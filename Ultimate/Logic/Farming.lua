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

-- zones: { [uiMapID] = { [node name] = spawn count } }, nodes: Data/GatherNodes, skills:
-- { herbalism = rank, ... }, price(itemID) -> copper, source ("auction"/"vendor"), age (days),
-- area(uiMapID) -> size (optional). Returns the zones you can gather in, most valuable first:
-- { mapID, value, density, entries = { { name, count, itemID, price, source, age, skill, status } } }
function FM.ScoreZones(zones, nodes, skills, price, area)
  local list = {}
  for mapID, counts in pairs(zones) do
    local entries, value = {}, 0
    for name, count in pairs(counts) do
      local node = nodes[name]
      local status = FM.CanGather(node, skills)
      if status == "yes" or status == "unknown" then
        local p, source, age
        if node.item then p, source, age = price(node.item) end
        entries[#entries + 1] = { name = name, count = count, itemID = node.item, price = p,
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
