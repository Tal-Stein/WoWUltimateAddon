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

-- A value's grade against the best one (FM.THRESHOLDS); nil without a value or a best.
function FM.RatioGrade(value, best)
  if not value or value <= 0 or not best or best <= 0 then return nil end
  local r = value / best
  for i, t in ipairs(FM.THRESHOLDS) do
    if r >= t then return FM.GRADES[i] end
  end
  return FM.GRADES[4]
end

function FM.Grade(list)
  local best = 0
  for _, z in ipairs(list) do
    if (z.value or 0) > 0 and z.density > best then best = z.density end
  end
  for _, z in ipairs(list) do
    z.grade = (z.value or 0) > 0 and FM.RatioGrade(z.density, best) or nil
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

FM.MOB_BELOW = 5 -- mobs up to this many levels below you still pay (coin, loot, some experience)
FM.MOB_ABOVE = 3 -- and up to this many above are still safe to farm

-- Zones by the mobs at your level that live there (index: { [uiMapID] = { [npcID] = spawns } },
-- levels: { [npcID] = { min, max } } from Questie; values: { [npcID] = FM.MobValue } from your own
-- kills; names(npcID) -> name). Graded by how many suitable mobs live there; each entry carries
-- its gold per kill once you've farmed it (price, kills), farmed mobs listed first.
function FM.MobZones(index, levels, level, values, names, area)
  local list = {}
  for mapID, mobs in pairs(index) do
    local entries, count = {}, 0
    for npcID, spawns in pairs(mobs) do
      local l = levels[npcID]
      if l and l[1] <= level + FM.MOB_ABOVE and l[2] >= level - FM.MOB_BELOW then
        local v = values and values[npcID]
        local known = v and v.kills >= FM.MIN_KILLS and v.perKill > 0
        entries[#entries + 1] = { kind = "mob", npcID = npcID, name = names(npcID), count = spawns,
          minLevel = l[1], maxLevel = l[2], price = known and v.perKill or nil,
          kills = known and v.kills or nil, value = known and v or nil, status = "yes" }
        count = count + spawns
      end
    end
    if #entries > 0 then
      table.sort(entries, function(a, b)
        local va, vb = (a.price or 0) * a.count, (b.price or 0) * b.count
        if va ~= vb then return va > vb end
        if a.count ~= b.count then return a.count > b.count end
        return a.npcID < b.npcID
      end)
      local size = area and area(mapID)
      list[#list + 1] = { mapID = mapID, value = count, density = (size and size > 0) and count / size or count,
        entries = entries }
    end
  end
  table.sort(list, function(a, b)
    if a.density ~= b.density then return a.density > b.density end
    return a.mapID < b.mapID
  end)
  FM.Grade(list)
  return list
end

-- Spawn points (0-1) grouped into areas: points in the same or neighbouring grid cells (cell wide)
-- join one area. Each area: center (x, y, the middle of the points' extent), radii (rx, ry: half the points' extent
-- plus half a cell, so a lone spawn still gets a small area) and n points.
function FM.Clusters(points, cell)
  local grid = {}
  local function key(cx, cy) return cx * 100000 + cy end
  for _, p in ipairs(points) do
    local cx, cy = math.floor(p.x / cell), math.floor(p.y / cell)
    local k = key(cx, cy)
    local c = grid[k]
    if not c then c = { cx = cx, cy = cy, pts = {} }; grid[k] = c end
    c.pts[#c.pts + 1] = p
  end
  local areas, seen = {}, {}
  for k, start in pairs(grid) do
    if not seen[k] then
      seen[k] = true
      local stack, pts = { start }, {}
      while #stack > 0 do
        local c = table.remove(stack)
        for _, p in ipairs(c.pts) do pts[#pts + 1] = p end
        for dx = -1, 1 do
          for dy = -1, 1 do
            local nk = key(c.cx + dx, c.cy + dy)
            if grid[nk] and not seen[nk] then seen[nk] = true; stack[#stack + 1] = grid[nk] end
          end
        end
      end
      local minX, maxX, minY, maxY = 1, 0, 1, 0
      for _, p in ipairs(pts) do
        if p.x < minX then minX = p.x end
        if p.x > maxX then maxX = p.x end
        if p.y < minY then minY = p.y end
        if p.y > maxY then maxY = p.y end
      end
      areas[#areas + 1] = { x = (minX + maxX) / 2, y = (minY + maxY) / 2, n = #pts,
        rx = (maxX - minX) / 2 + cell / 2, ry = (maxY - minY) / 2 + cell / 2 }
    end
  end
  return areas
end
