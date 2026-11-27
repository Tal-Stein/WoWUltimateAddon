local ADDON, ns = ...

-- Where the farming numbers come from. Everything is read at runtime from the add-ons that own
-- it, so updating those add-ons updates the map; nothing third-party is copied into Ultimate.
--   Professions  C_SkillInfo (the game)
--   Nodes        Questie's Forever database (required); GatherMate2's only if Questie has none
--                (GatherMate2 counts nodes you've seen, Questie every spawn point: mixing them
--                would grade the zones you've farmed below the ones you haven't)
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

-- { [uiMapID] = { [node name] = count } }: Questie's, else GatherMate2's; and which ("questie",
-- "gathermate" or "none").
function FS.Zones()
  local base = questieCounts()
  if next(base) then return base, "questie" end
  local gm = gatherMate()
  if gm then
    local zones = gatherMateZones(gm)
    if next(zones) then return zones, "gathermate" end
  end
  return base, "none"
end

-- Node positions on one map, for its pins: { { name, x, y } } with x, y in 0-1. Kept per map
-- until the sources change.
local spawnCache = {}
function FS.Spawns(mapID)
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
    local value = rank == 0 and minLevel <= level + ABOVE_LEVEL and ns.Farming.MobValue(stat, FS.Price, skills)
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
-- Prices
------------------------------------------------------------------------------
local function auctionator()
  local api = type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
  return type(api) == "table" and api or nil
end

-- copper, "auction"/"vendor", age in days (auction only); nil when nothing is known.
function FS.Price(itemID)
  local api = auctionator()
  if api and api.GetAuctionPriceByItemID then
    local p = ns.Safe.read(api.GetAuctionPriceByItemID, CALLER, itemID)
    if type(p) == "number" and p > 0 then
      local age = api.GetAuctionAgeByItemID and ns.Safe.read(api.GetAuctionAgeByItemID, CALLER, itemID)
      return p, "auction", age
    end
  end
  local info = C_Item and C_Item.GetItemInfo or GetItemInfo
  if info then
    local ok, sell = pcall(function() return (select(11, info(itemID))) end)
    if ok and type(sell) == "number" and sell > 0 and not ns.Safe.isSecret(sell) then return sell, "vendor" end
  end
  return nil
end

-- Calls fn when Auctionator finishes a scan (its prices changed).
function FS.OnPricesChanged(fn)
  local api = auctionator()
  if api and api.RegisterForDBUpdate then pcall(api.RegisterForDBUpdate, CALLER, fn) end
end

function FS.Status()
  return {
    questie = meta("Questie", "Version"),
    questieDB = meta("QuestieDB", "Version"),
    gathermate = gatherMate() ~= nil,
    auctionator = auctionator() ~= nil,
  }
end
