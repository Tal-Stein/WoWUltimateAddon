local ADDON, ns = ...

-- Farming arithmetic: which gathering nodes a character can work, what each zone's nodes are
-- worth at today's prices, and how the zones grade against each other. No game calls here; the
-- data comes from Services/FarmSources.lua.
local FM = {}
ns.Farming = FM

-- "yes", "skill" (profession known, skill too low), "unknown" (the node's required skill isn't
-- known, e.g. a Forever-only node) or nil (you don't have the profession).
function FM.CanGather(node, skills)
  local rank = node and skills and skills[node.prof]
  if not rank then return nil end
  if not node.skill then return "unknown" end
  return rank >= node.skill and "yes" or "skill"
end

FM.MIN_KILLS = 5  -- kills of a mob before its value per kill counts
FM.MIN_PACE = 10  -- timed kills before gold per hour is shown

local function itemsValue(items, price)
  local total = 0
  for id, qty in pairs(items or {}) do
    local p = price(id)
    if p then total = total + p * qty end
  end
  return total
end

-- What one kill of a mob is worth, from your own kills of it (stat: { kills, copper,
-- items = { [itemID] = qty }, skins = { [itemID] = qty } }): { perKill, coin, loot, skin, kills }
-- in copper per kill, or nil with no kills. Skinning counts only for skinners.
function FM.MobValue(stat, price, skills)
  local kills = stat and stat.kills or 0
  if kills <= 0 then return nil end
  local coin = (stat.copper or 0) / kills
  local loot = itemsValue(stat.items, price) / kills
  local skin = (skills and skills.skinning) and itemsValue(stat.skins, price) / kills or 0
  return { perKill = coin + loot + skin, coin = coin, loot = loot, skin = skin, kills = kills }
end

-- Copper per hour at your own pace (pace: { sum = seconds between kills, n = timed kills }).
function FM.PerHour(perKill, pace)
  if not perKill or not pace or (pace.n or 0) < FM.MIN_PACE or (pace.sum or 0) <= 0 then return nil end
  return perKill * 3600 / (pace.sum / pace.n)
end

-- zones: { [uiMapID] = { [node name] = spawn count } }, nodes: Data/GatherNodes, skills:
-- { herbalism = rank, ... }, price(itemID) -> copper, source ("auction"/"vendor"), age (days),
-- area(uiMapID) -> size (optional), mobs (optional): { zones = { [uiMapID] = { [npcID] = spawns } },
-- values = { [npcID] = FM.MobValue(...) }, names = { [npcID] = name } }. Returns the zones with
-- something for you, most valuable first: { mapID, value, density, entries = { { kind ("node" or
-- "mob"), name, count, price (per node or per kill), ... } } }
function FM.ScoreZones(zones, nodes, skills, price, area, mobs)
  local list = {}
  local all = {}
  for mapID in pairs(zones) do all[mapID] = true end
  for mapID in pairs(mobs and mobs.zones or {}) do all[mapID] = true end
  for mapID in pairs(all) do
    local counts = zones[mapID] or {}
    local entries, value = {}, 0
    for npcID, spawns in pairs(mobs and mobs.zones[mapID] or {}) do
      local v = mobs.values[npcID]
      if v and v.kills >= FM.MIN_KILLS and v.perKill > 0 then
        entries[#entries + 1] = { kind = "mob", npcID = npcID, name = mobs.names[npcID] or tostring(npcID),
          count = spawns, price = v.perKill, kills = v.kills, value = v, status = "yes" }
        value = value + spawns * v.perKill
      end
    end
    for name, count in pairs(counts) do
      local node = nodes[name]
      local status = FM.CanGather(node, skills)
      if status == "yes" or status == "unknown" then
        local p, source, age
        if node.item then p, source, age = price(node.item) end
        entries[#entries + 1] = { kind = "node", name = name, count = count, itemID = node.item, price = p,
          source = source, age = age, skill = node.skill, status = status, prof = node.prof }
        if p then value = value + p * count end
      end
    end
    if #entries > 0 then
      table.sort(entries, function(a, b)
        local va, vb = (a.price or 0) * a.count, (b.price or 0) * b.count
        if va ~= vb then return va > vb end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
      end)
      local size = area and area(mapID)
      local density = (size and size > 0) and value / size or value
      list[#list + 1] = { mapID = mapID, value = value, density = density, entries = entries }
    end
  end
  table.sort(list, function(a, b)
    if a.density ~= b.density then return a.density > b.density end
    return a.mapID < b.mapID
  end)
  FM.Grade(list)
  return list
end

FM.GRADES = { "excellent", "good", "fair", "poor" }

-- Grade valued zones against the best one (list is sorted best first): within 75% of it is
-- excellent, 40% good, 15% fair, below that poor. Zones worth nothing (no prices yet) get none.
FM.THRESHOLDS = { 0.75, 0.4, 0.15 }

function FM.Grade(list)
  local best = 0
  for _, z in ipairs(list) do
    if (z.value or 0) > 0 and z.density > best then best = z.density end
  end
  for _, z in ipairs(list) do
    if (z.value or 0) > 0 and best > 0 then
      local r = z.density / best
      local grade = FM.GRADES[4]
      for i, t in ipairs(FM.THRESHOLDS) do
        if r >= t then grade = FM.GRADES[i]; break end
      end
      z.grade = grade
    else
      z.grade = nil
    end
  end
  return list
end

FM.VIEWS = { "best", "near", "level" }
FM.NEAR_MINUTES = { 10, 20 } -- how far "near" looks, then further when under NEAR_MIN zones are that close
FM.NEAR_MIN = 3
FM.LEVEL_SLACK = 2           -- levels either side of a zone's range that still suit you

local function copy(z, extra)
  local c = {}
  for k, v in pairs(z) do c[k] = v end
  for k, v in pairs(extra) do c[k] = v end
  return c
end

-- The graded zones (list: FM.ScoreZones, best first) for one view:
--   "best"   all of them
--   "near"   within NEAR_MINUTES of travel (ctx.minutes(mapID) -> minutes or nil), with .minutes
--   "level"  whose level range (ctx.levels(mapID) -> min, max) suits ctx.level, with .minLevel/.maxLevel
-- Order stays most valuable first.
function FM.View(list, view, ctx)
  local out = {}
  if view == "near" then
    for _, limit in ipairs(FM.NEAR_MINUTES) do
      out = {}
      for _, z in ipairs(list) do
        local m = z.grade and ctx.minutes and ctx.minutes(z.mapID)
        if m and m <= limit then out[#out + 1] = copy(z, { minutes = m }) end
      end
      if #out >= FM.NEAR_MIN then break end
    end
  elseif view == "level" then
    for _, z in ipairs(list) do
      local lo, hi
      if z.grade and ctx.levels then lo, hi = ctx.levels(z.mapID) end
      if lo and hi and ctx.level and ctx.level >= lo - FM.LEVEL_SLACK and ctx.level <= hi + FM.LEVEL_SLACK then
        out[#out + 1] = copy(z, { minLevel = lo, maxLevel = hi })
      end
    end
  else
    for _, z in ipairs(list) do
      if z.grade then out[#out + 1] = z end
    end
  end
  return out
end

-- A gold goal (copper) against the money you have: { left, reached, hours } (hours only when a
-- gold-per-hour rate is known).
function FM.Goal(goal, money, perHour)
  local left = math.max(0, (goal or 0) - (money or 0))
  local hours = (perHour and perHour > 0 and left > 0) and left / perHour or nil
  return { left = left, reached = left == 0, hours = hours }
end

-- "3h", "1h 30m", "15m"; at least a minute.
function FM.FormatHours(hours)
  local mins = math.max(1, math.floor(hours * 60 + 0.5))
  local h, m = math.floor(mins / 60), mins % 60
  if h > 0 and m > 0 then return string.format("%dh %dm", h, m) end
  if h > 0 then return string.format("%dh", h) end
  return string.format("%dm", m)
end
