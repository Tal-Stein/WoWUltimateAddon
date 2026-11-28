local ADDON, ns = ...

-- Where the farming numbers come from. Everything is read at runtime from the add-ons that own
-- it, so updating those add-ons updates the map; nothing third-party is copied into Ultimate.
--   Professions  C_SkillInfo (the game)
--   Nodes        GatherMate2 (with GatherMate2_Data) or Questie's Forever database, whichever
--                covers more (see FS.Zones)
--   Prices       Auctionator's scans of your realm, else the vendor price
-- Questie's node counts are cached in UltimateDB.farmNodes under the versions they were read
-- from, and read again when Questie, QuestieDB or Data/GatherNodes.lua changes.
local FS = {}
ns.FarmSources = FS

local CALLER = "Ultimate"
local GM_TYPES = { herbalism = "Herb Gathering", mining = "Mining" }

local function meta(addon, key)
  local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  return get and ns.Safe.read(get, addon, key) or nil
end

------------------------------------------------------------------------------
-- Professions
------------------------------------------------------------------------------
function FS.Skills()
  local skills = {}
  local get = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
  for prof, id in pairs(ns.GatherSkillLines) do
    local info = get and ns.Safe.read(get, id)
    if type(info) == "table" and (info.rank or 0) > 0 then skills[prof] = info.rank end
  end
  return skills
end

------------------------------------------------------------------------------
-- Nodes
------------------------------------------------------------------------------
local function questieObjects()
  local lib = LibQuestieDB
  if type(lib) ~= "table" or type(lib.Object) ~= "table" or type(lib.Object.IdsByName) ~= "function" then return nil end
  return lib.Object
end

local function zoneDB()
  local mods = type(QuestieLoader) == "table" and type(QuestieLoader._modules) == "table" and QuestieLoader._modules
  return mods and mods.ZoneDB
end

local function names()
  local list = {}
  for name in pairs(ns.GatherNodes) do list[#list + 1] = name end
  table.sort(list)
  return list
end

-- Calls fn(name, uiMapID, x, y) for every spawn Questie knows (x, y in Questie's 0-100), only
-- for the area `onlyArea` when given.
local function eachQuestieSpawn(fn, onlyArea)
  local objects, zones = questieObjects(), zoneDB()
  if not objects or not zones then return false end
  for _, name in ipairs(names()) do
    for _, id in ipairs(ns.Safe.read(objects.IdsByName, name) or {}) do
      local spawns = ns.Safe.read(objects.Get, id, "spawns")
      for area, points in pairs(type(spawns) == "table" and spawns or {}) do
        if not onlyArea or area == onlyArea then
          local mapID = ns.Safe.read(zones.GetUiMapIdByAreaId, zones, area)
          if mapID and mapID > 0 then
            for _, p in ipairs(points) do
              -- Questie marks spawns it can't place with negative coordinates.
              if type(p[1]) == "number" and type(p[2]) == "number" and p[1] >= 0 and p[2] >= 0 then
                fn(name, mapID, p[1], p[2])
              end
            end
          end
        end
      end
    end
  end
  return true
end

-- Questie's name lookup (IdsByName) builds an index over every object the first time; done in one
-- go that can stall the game ("script ran too long"). Start it in small batches early instead.
function FS.Prepare()
  FS.Watch()
  local objects = questieObjects()
  local cached = ns.global and ns.global.farmNodes and ns.global.farmNodes.key == FS.SourceKey()
  if not cached and objects and type(objects.BuildNameIndexAsync) == "function" then
    pcall(objects.BuildNameIndexAsync) -- only needed to count Questie's nodes again
  end
  -- Start reading which mobs live where once Questie has settled in.
  if C_Timer then
    C_Timer.After(10, function() FS.MobIndex() end)
    C_Timer.After(20, function() FS.Forever() end)
    C_Timer.After(40, function() FS.PrefetchPrices() end) -- after ForeverDB has been read
  end
end

function FS.SourceKey()
  return table.concat({ meta("Questie", "Version") or "-", meta("QuestieDB", "Version") or "-",
    tostring(ns.GatherNodesVersion) }, "|")
end

local function questieCounts()
  local g = ns.global
  local key = FS.SourceKey()
  local cache = g and g.farmNodes
  if cache and cache.key == key and cache.zones then return cache.zones end
  local zones = {}
  local ok = eachQuestieSpawn(function(name, mapID)
    zones[mapID] = zones[mapID] or {}
    zones[mapID][name] = (zones[mapID][name] or 0) + 1
  end)
  -- Nothing found means Questie's data isn't ready yet: try again next time, don't keep it.
  if ok and g and next(zones) then g.farmNodes = { key = key, zones = zones } end
  return zones
end

local function gatherMate()
  if not (C_AddOns and ns.Safe.read(C_AddOns.IsAddOnLoaded, "GatherMate2")) then return nil end
  local ace = type(LibStub) == "function" and ns.Safe.read(LibStub, "AceAddon-3.0", true)
  return ace and ns.Safe.read(ace.GetAddon, ace, "GatherMate2", true) or nil
end

-- GatherMate2's nodes on every zone map: { [uiMapID] = { [name] = count } }.
local function gatherMateZones(gm)
  local zones = {}
  local types = Enum and Enum.UIMapType
  local all = C_Map and ns.Safe.read(C_Map.GetMapChildrenInfo, 947, types and types.Zone or 3, true) or {}
  for _, info in ipairs(all) do
    for prof, nodeType in pairs(GM_TYPES) do
      local ok, iter, state, start = pcall(gm.GetNodesForZone, gm, info.mapID, nodeType, true)
      if ok and type(iter) == "function" then
        for _, nodeID in iter, state, start do
          local name = ns.Safe.read(gm.GetNameForNode, gm, nodeType, nodeID)
          local node = name and ns.GatherNodes[name]
          if node and node.prof == prof then
            zones[info.mapID] = zones[info.mapID] or {}
            zones[info.mapID][name] = (zones[info.mapID][name] or 0) + 1
          end
        end
      end
    end
  end
  return zones
end

-- { [uiMapID] = { [node name] = count } } and where it came from ("questie", "gathermate" or
-- "none"): whichever source covers more nodes. Questie's database only holds the nodes quests
-- use (on Forever: no Iron, Mithril or Thorium at all); GatherMate2 with GatherMate2_Data
-- imported holds them all. One source at a time: mixing would skew zones against each other.
local function total(zones)
  local n = 0
  for _, counts in pairs(zones) do for _, c in pairs(counts) do n = n + c end end
  return n
end

local gmCache = { gen = -1 }
function FS.Zones()
  local base = questieCounts()
  local gm = gatherMate()
  if gm then
    if gmCache.gen ~= FS.generation or gmCache.gm ~= gm then
      gmCache = { gen = FS.generation, gm = gm, zones = gatherMateZones(gm) }
    end
    local zones = gmCache.zones
    if total(zones) > total(base) then FS.source = "gathermate"; return zones, FS.source end
  end
  FS.source = next(base) and "questie" or "none"
  return base, FS.source
end

-- Node positions on one map, for its pins: { { name, x, y } } with x, y in 0-1. Kept per map
-- until the sources change.
local spawnCache = {}
local function gatherMateSpawns(gm, mapID)
  local list = {}
  for prof, nodeType in pairs(GM_TYPES) do
    local ok, iter, state, start = pcall(gm.GetNodesForZone, gm, mapID, nodeType, true)
    if ok and type(iter) == "function" then
      for coord, nodeID in iter, state, start do
        local name = ns.Safe.read(gm.GetNameForNode, gm, nodeType, nodeID)
        local node = name and ns.GatherNodes[name]
        if node and node.prof == prof then
          local okd, x, y = pcall(gm.DecodeLoc, gm, coord)
          if okd and type(x) == "number" and type(y) == "number" then
            list[#list + 1] = { name = name, x = x, y = y }
          end
        end
      end
    end
  end
  return list
end

function FS.Spawns(mapID)
  local source = FS.source or select(2, FS.Zones()) -- decided by the last FS.Zones
  if source == "gathermate" then return gatherMateSpawns(gatherMate(), mapID) end
  local key = FS.SourceKey()
  if spawnCache.key ~= key then spawnCache = { key = key } end
  if spawnCache[mapID] then return spawnCache[mapID] end
  local zones = zoneDB()
  local area = zones and ns.Safe.read(zones.GetAreaIdByUiMapId, zones, mapID)
  local list = {}
  if not area then return list end
  eachQuestieSpawn(function(name, m, x, y)
    if m == mapID then list[#list + 1] = { name = name, x = x / 100, y = y / 100 } end
  end, area)
  if #list > 0 then spawnCache[mapID] = list end
  return list
end

------------------------------------------------------------------------------
-- Mobs (your own kills, Services/KillLog.lua, placed with Questie's NPC spawns)
------------------------------------------------------------------------------
local ABOVE_LEVEL = 3 -- mobs further above you than this aren't farming
local mobSpawns = {}  -- [npcID] = { [uiMapID] = spawns }, per session
local npcFields = {}  -- [npcID] = { name, rank, minLevel }, per session

local function npc(id, field)
  local lib = LibQuestieDB
  if type(lib) ~= "table" or type(lib.Npc) ~= "table" then return nil end
  if field == "spawns" then return ns.Safe.read(lib.Npc.Get, id, field) end
  local f = npcFields[id]
  if not f then
    f = { name = ns.Safe.read(lib.Npc.Get, id, "name"), rank = ns.Safe.read(lib.Npc.Get, id, "rank"),
      minLevel = ns.Safe.read(lib.Npc.Get, id, "minLevel") }
    npcFields[id] = f
  end
  return f[field]
end

local function spawnsByMap(npcID)
  if mobSpawns[npcID] then return mobSpawns[npcID] end
  local zones, byMap = zoneDB(), {}
  local spawns = npc(npcID, "spawns")
  for area, points in pairs(type(spawns) == "table" and spawns or {}) do
    local mapID = zones and ns.Safe.read(zones.GetUiMapIdByAreaId, zones, area)
    if mapID and mapID > 0 then byMap[mapID] = (byMap[mapID] or 0) + #points end
  end
  mobSpawns[npcID] = byMap
  return byMap
end

-- For FM.ScoreZones: { zones = { [uiMapID] = { [npcID] = spawns } }, values = { [npcID] = value },
-- names = { [npcID] = name } } for the mobs you've killed that suit you (not elite or rare, not
-- more than ABOVE_LEVEL above your level).
function FS.Mobs(skills)
  local mobs = { zones = {}, values = {}, names = {} }
  local level = ns.Safe.read(UnitLevel, "player") or 1
  for npcID, stat in pairs(ns.KillLog.Stats()) do
    local rank = npc(npcID, "rank") or 0
    local minLevel = npc(npcID, "minLevel") or 0
    local value = rank == 0 and minLevel <= level + ABOVE_LEVEL and FS.MobValue(npcID, skills)
    if value then
      mobs.values[npcID] = value
      mobs.names[npcID] = npc(npcID, "name")
      for mapID, n in pairs(spawnsByMap(npcID)) do
        mobs.zones[mapID] = mobs.zones[mapID] or {}
        mobs.zones[mapID][npcID] = n
      end
    end
  end
  return mobs
end

------------------------------------------------------------------------------
-- Which mobs live where (Questie's Forever NPCs): hostile, non-elite creatures with spawns.
-- Built a batch at a time (there are thousands of NPCs) and kept in UltimateDB.farmMobIndex under
-- the Questie versions and your faction; ULT_FARM_DATA fires when it's ready.
------------------------------------------------------------------------------
local INDEX_BATCH = 300
local AMBIENT = { [188] = true } -- critters' faction template
local building

local function factionLetter()
  local f = ns.Safe.read(UnitFactionGroup, "player")
  return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

local function farmable(id, letter)
  local lib = LibQuestieDB.Npc
  local get = function(field) return ns.Safe.read(lib.Get, id, field) end
  if (get("rank") or 0) ~= 0 then return nil end
  local friendly = get("friendlyToFaction")
  if type(friendly) == "string" and letter and friendly:find(letter, 1, true) then return nil end
  if (get("npcFlags") or 0) ~= 0 or get("questStarts") or get("questEnds") then return nil end
  if AMBIENT[get("factionID") or 0] then return nil end
  local lo, hi = get("minLevel"), get("maxLevel")
  if not lo or lo <= 0 then return nil end
  local spawns = get("spawns")
  if type(spawns) ~= "table" or next(spawns) == nil then return nil end
  return spawns, lo, hi or lo
end

-- index ({ [uiMapID] = { [npcID] = spawns } }), levels ({ [npcID] = { min, max } }), or nil while
-- it's being built.
function FS.MobIndex()
  local g = ns.global
  local key = FS.SourceKey() .. "|" .. tostring(factionLetter())
  local cache = g and g.farmMobIndex
  if cache and cache.key == key then return cache.maps, cache.levels end
  local lib = LibQuestieDB
  if building or type(lib) ~= "table" or type(lib.Npc) ~= "table" or type(lib.Npc.GetAllIds) ~= "function" then
    return nil
  end
  local ids = ns.Safe.read(lib.Npc.GetAllIds)
  local zones, letter = zoneDB(), factionLetter()
  if type(ids) ~= "table" or not zones then return nil end -- Questie not ready yet
  local maps, levels, i = {}, {}, 1
  building = true
  local step
  local function batch()
    local stop = math.min(i + INDEX_BATCH - 1, #ids)
    for n = i, stop do
      local id = ids[n]
      local spawns, lo, hi = farmable(id, letter)
      if spawns then
        for area, points in pairs(spawns) do
          local mapID = zones and ns.Safe.read(zones.GetUiMapIdByAreaId, zones, area)
          if mapID and mapID > 0 and type(points) == "table" and #points > 0 then
            maps[mapID] = maps[mapID] or {}
            maps[mapID][id] = (maps[mapID][id] or 0) + #points
            levels[id] = { lo, hi }
          end
        end
      end
    end
    i = stop + 1
    if i <= #ids then
      C_Timer.After(0, step)
    else
      building = false
      -- An empty result means Questie wasn't ready: build again next time instead of keeping it.
      if g and next(maps) then g.farmMobIndex = { key = key, maps = maps, levels = levels } end
      ns:Fire("ULT_FARM_DATA")
    end
  end
  step = function()
    local ok = pcall(batch)
    if not ok then building = false end -- try again on the next request
  end
  C_Timer.After(0, step)
  return nil
end

function FS.NpcName(npcID) return npc(npcID, "name") end

-- Where one mob spawns on a map: { { x, y } } in 0-1 (Questie's spawns for the map's area). Kept
-- per map and mob: reading spawns from Questie's compressed store isn't free.
local pointCache = {}
function FS.MobPoints(mapID, npcID)
  local ck = FS.SourceKey()
  if pointCache.key ~= ck then pointCache = { key = ck } end
  local cacheKey = mapID * 1000000 + npcID
  if pointCache[cacheKey] then return pointCache[cacheKey] end
  local list = FS.ReadMobPoints(mapID, npcID)
  pointCache[cacheKey] = list
  return list
end

function FS.ReadMobPoints(mapID, npcID)
  local zones = zoneDB()
  local area = zones and ns.Safe.read(zones.GetAreaIdByUiMapId, zones, mapID)
  local spawns = area and npc(npcID, "spawns")
  local list = {}
  for _, p in ipairs(type(spawns) == "table" and spawns[area] or {}) do
    if type(p[1]) == "number" and type(p[2]) == "number" and p[1] >= 0 and p[2] >= 0 then
      list[#list + 1] = { x = p[1] / 100, y = p[2] / 100 }
    end
  end
  return list
end

------------------------------------------------------------------------------
-- ForeverDB (a shared Forever database add-on, GPL, read at runtime): coin per mob from recorded
-- Forever kills, and drop and skinning chances (Forever counts where enough kills exist, else
-- the median of VMaNGOS, cMaNGOS and pfQuest). Loaded whole it's ~90 MB, so it's loaded only when
-- its version changes (at most once a day), out of combat; what farming needs is kept compact in
-- UltimateDB.farmForeverDB and every other session reads only that.
------------------------------------------------------------------------------
local MIN_CHANCE = 20     -- drops rarer than 0.2% (chances per 10000) aren't worth carrying
local CONVERT_BATCH = 2000
local forever, foreverBuilding
FS.generation = 0         -- goes up when farming data changes (ForeverDB, prices, items, kills)
local FOREVER_MAX_AGE = 7 * 86400 -- ForeverDB updates daily; re-read it at most weekly (it's ~90 MB)
local BUMP_DELAY = 2      -- seconds: many changes in a row (items arriving, kills) bump once

-- Everything worked out from the data (prices, values, ratings) is kept until this goes up.
local bumpQueued
function FS.Bump(now)
  local function bump()
    bumpQueued = false
    FS.itemsWaiting = false
    FS.generation = FS.generation + 1
    ns:Fire("ULT_FARM_DATA")
  end
  if now then bump(); return end
  if bumpQueued then return end
  bumpQueued = true
  C_Timer.After(BUMP_DELAY, bump)
end

function FS.ForeverVersion() return meta("ForeverDB", "Version") end

local function foreverDone(data)
  foreverBuilding = false
  data.builtAt = time()
  if ns.global then ns.global.farmForeverDB = data end
  forever = data
  FS.Bump(true)
end

local function convertForever(version)
  local db = _G.ForeverDB
  if type(db) ~= "table" or type(db.drop) ~= "table" then foreverBuilding = false; return end
  local data = { version = version, gold = {}, drops = {}, skins = {} }
  for npcID, g in pairs(db.gold or {}) do
    if type(g) == "table" and g[1] then data.gold[npcID] = { g[1], g[2], g[3], g[4] } end
  end
  local function addTo(into, item, list)
    for i = 1, #list, 2 do
      local npcID, chance = list[i], list[i + 1]
      if type(npcID) == "number" and type(chance) == "number" and chance >= MIN_CHANCE then
        local t = into[npcID]
        if not t then t = {}; into[npcID] = t end
        t[#t + 1] = item
        t[#t + 1] = chance
      end
    end
  end
  for item, list in pairs(db.skin or {}) do addTo(data.skins, item, list) end
  local key
  local function step()
    local n = 0
    local list
    key, list = next(db.drop, key)
    while key ~= nil do
      addTo(data.drops, key, list)
      n = n + 1
      if n >= CONVERT_BATCH then C_Timer.After(0, step); return end
      key, list = next(db.drop, key)
    end
    foreverDone(data)
  end
  step()
end

-- ForeverDB's farming data: { version, gold = { [npcID] = { avg, min, max, kills } },
-- drops/skins = { [npcID] = { itemID, chance, ... } } }, or nil when it isn't installed (or is
-- still being read: ULT_FARM_DATA fires when it's ready).
function FS.Forever()
  local version = FS.ForeverVersion()
  if not version then return nil end
  if forever and forever.version == version then return forever end
  local cache = ns.global and ns.global.farmForeverDB
  if cache and cache.version == version then forever = cache; return forever end
  -- A newer ForeverDB: keep the copy we have until it's a week old (loading it is the cost).
  if cache and cache.builtAt and time() - cache.builtAt < FOREVER_MAX_AGE then forever = cache; return forever end
  if not foreverBuilding and not ns.Safe.read(InCombatLockdown) then
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if load then
      foreverBuilding = true
      local ok = pcall(load, "ForeverDB")
      if ok and type(_G.ForeverDB) == "table" then
        C_Timer.After(0, function() convertForever(version) end)
      else
        foreverBuilding = false
      end
    end
  end
  return cache -- the previous version's meanwhile, if any
end

local function foreverEntry(npcID)
  local d = FS.Forever()
  if not d then return nil end
  local g = d.gold[npcID]
  local drops, skins = d.drops[npcID], d.skins[npcID]
  if not g and not drops and not skins then return nil end
  return { coin = g and g[1], kills = g and g[4], drops = drops, skins = skins }
end

-- What one kill of a mob is worth to you: your own kills (Services/KillLog.lua) or ForeverDB,
-- whichever FM.PickValue trusts; nil when neither knows.
-- Worked out once per mob until the data changes (FS.generation).
local valueCache = { gen = -1 }
function FS.MobValue(npcID, skills)
  if valueCache.gen ~= FS.generation then valueCache = { gen = FS.generation } end
  local hit = valueCache[npcID]
  if hit ~= nil then return hit or nil end
  skills = skills or FS.Skills()
  local stat = ns.KillLog.Stats()[npcID]
  local own = stat and ns.Farming.MobValue(stat, FS.Price, skills)
  local data = ns.Farming.DataMobValue(foreverEntry(npcID), FS.Price, skills)
  local v = ns.Farming.PickValue(own, data)
  -- Your own few kills shown beside the crowd's figure, to compare.
  if v and v == data and own and own.kills > 0 then v.own = own end
  valueCache[npcID] = v or false
  return v
end

-- A mob's most valuable drops: { { itemID, chance (0-1), value (copper per kill) } }, best first.
function FS.TopDrops(npcID, n)
  local e = foreverEntry(npcID)
  local list = {}
  for i = 1, #(e and e.drops or {}), 2 do
    local item, chance = e.drops[i], e.drops[i + 1] / 10000
    local p = FS.Price(item)
    if p then list[#list + 1] = { itemID = item, chance = chance, value = p * chance } end
  end
  table.sort(list, function(a, b) return a.value > b.value end)
  while #list > (n or 3) do table.remove(list) end
  return list
end

------------------------------------------------------------------------------
-- Prices
------------------------------------------------------------------------------
local function auctionator()
  local api = type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
  return type(api) == "table" and api or nil
end

-- Vendor prices never change: once read they're kept in UltimateDB.farmSellPrices, so the next
-- session needn't wait for the game's item cache. Items it hasn't seen yet are asked for; when they
-- arrive, the data is bumped once (BUMP_DELAY) and the ratings follow.
local pending = {}
local function sellPrice(itemID)
  local g = ns.global
  local known = g and g.farmSellPrices and g.farmSellPrices[itemID]
  if known then return known > 0 and known or nil end
  local info = C_Item and C_Item.GetItemInfo or GetItemInfo
  if info then
    local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(info, itemID)
    if ok and name and type(sell) == "number" and not ns.Safe.isSecret(sell) then
      if g then g.farmSellPrices = g.farmSellPrices or {}; g.farmSellPrices[itemID] = sell end
      return sell > 0 and sell or nil
    end
  end
  if not pending[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
    pending[itemID] = true
    pcall(C_Item.RequestLoadItemDataByID, itemID)
  end
  return nil
end

-- Items arriving don't redo the ratings while the map is open (they arrive by the hundred, and
-- each redo is felt there): they're taken in the next time it opens, or once it's closed.
FS.itemsWaiting = false
function FS.IsMapOpen() return false end -- (Modules/GoldFarming.lua says)
function FS.OnItemInfo(itemID)
  if not pending[itemID] then return end
  pending[itemID] = nil
  if sellPrice(itemID) then
    FS.itemsWaiting = true
    if not FS.IsMapOpen() and not FS.Prefetching() then FS.Bump() end
  end
end

------------------------------------------------------------------------------
-- Fetching prices: a drop counts toward a mob's value only once its price is known, and the game
-- tells an item's vendor price only after it's been asked for. So every item ForeverDB lists as a
-- drop or a skin is asked for once in the background, PREFETCH_BATCH every PREFETCH_EVERY seconds
-- out of combat, those that make up a typical kill first (FM.RARE_CHANCE), and kept for good
-- (UltimateDB.farmSellPrices): later sessions ask only for what's still missing. The ratings are
-- redone every PREFETCH_BUMP seconds while it runs and once at the end, not per item.
------------------------------------------------------------------------------
FS.PREFETCH_BATCH = 50
FS.PREFETCH_EVERY = 1
FS.PREFETCH_BUMP = 30
FS.PREFETCH_SETTLE = 5 -- seconds after the last batch for the answers to arrive

-- The item IDs in d (ForeverDB's drops and skins) without a known price: common drops and skins,
-- then rare drops; each once.
function FS.PriceQueue(d, known)
  local queue, seen = {}, {}
  local rare = ns.Farming.RARE_CHANCE * 10000
  local function add(lists, test)
    for _, list in pairs(lists or {}) do
      for i = 1, #list, 2 do
        local id = list[i]
        if not seen[id] and known[id] == nil and test(list[i + 1]) then
          seen[id] = true
          queue[#queue + 1] = id
        end
      end
    end
  end
  add(d.drops, function(chance) return chance >= rare end)
  add(d.skins, function() return true end)
  add(d.drops, function() return true end)
  return queue
end

local fetching
function FS.Prefetching() return fetching ~= nil end
function FS.PrefetchProgress()
  if not fetching then return nil end
  return fetching.i - 1, #fetching.queue
end

function FS.PrefetchPrices()
  if fetching or not (C_Timer and C_Item and C_Item.RequestLoadItemDataByID) then return end
  local d = FS.Forever()
  if not d then return end
  local g = ns.global
  local queue = FS.PriceQueue(d, g and g.farmSellPrices or {})
  if #queue == 0 then return end
  fetching = { queue = queue, i = 1, bumpAt = GetTime() + FS.PREFETCH_BUMP }
  local function step()
    local f = fetching
    if not f then return end
    if not ns.Safe.read(InCombatLockdown) then
      for _ = 1, FS.PREFETCH_BATCH do
        local id = f.queue[f.i]
        if not id then break end
        f.i = f.i + 1
        -- Asks for it when it isn't known; again if an earlier ask was never answered.
        local asked = pending[id]
        if not sellPrice(id) and asked then pcall(C_Item.RequestLoadItemDataByID, id) end
      end
      if FS.itemsWaiting and GetTime() >= f.bumpAt and not FS.IsMapOpen() then
        f.bumpAt = GetTime() + FS.PREFETCH_BUMP
        FS.Bump()
      end
    end
    if f.i > #f.queue then
      C_Timer.After(FS.PREFETCH_SETTLE, function()
        fetching = nil
        if FS.itemsWaiting and not FS.IsMapOpen() then FS.Bump() end
      end)
    else
      C_Timer.After(FS.PREFETCH_EVERY, step)
    end
  end
  step()
end

function FS.PendingItems()
  local n = 0
  for _ in pairs(pending) do n = n + 1 end
  return n
end

-- copper, "auction"/"vendor", age in days (auction only); nil when nothing is known. Kept until
-- the data changes (an Auctionator scan bumps it).
local priceCache = { gen = -1 }
function FS.Price(itemID)
  if priceCache.gen ~= FS.generation then priceCache = { gen = FS.generation } end
  local hit = priceCache[itemID]
  if hit ~= nil then
    if hit then return hit[1], hit[2], hit[3] end
    return nil
  end
  local p, source, age
  local api = auctionator()
  if api and api.GetAuctionPriceByItemID then
    local a = ns.Safe.read(api.GetAuctionPriceByItemID, CALLER, itemID)
    if type(a) == "number" and a > 0 then
      p, source = a, "auction"
      age = api.GetAuctionAgeByItemID and ns.Safe.read(api.GetAuctionAgeByItemID, CALLER, itemID)
    end
  end
  if not p then
    p = sellPrice(itemID)
    source = p and "vendor" or nil
  end
  priceCache[itemID] = p and { p, source, age } or false
  return p, source, age
end

-- Calls fn when Auctionator finishes a scan (its prices changed).
function FS.OnPricesChanged(fn)
  local api = auctionator()
  if api and api.RegisterForDBUpdate then pcall(api.RegisterForDBUpdate, CALLER, fn) end
end

local watching = false
function FS.Watch()
  if watching then return end
  watching = true
  ns:On("GET_ITEM_INFO_RECEIVED", FS, function(_, itemID) FS.OnItemInfo(itemID) end)
  FS.OnPricesChanged(function() FS.Bump() end)
end

function FS.Status()
  return {
    questie = meta("Questie", "Version"),
    questieDB = meta("QuestieDB", "Version"),
    foreverDB = FS.ForeverVersion(),
    gathermate = gatherMate() ~= nil,
    auctionator = auctionator() ~= nil,
  }
end
