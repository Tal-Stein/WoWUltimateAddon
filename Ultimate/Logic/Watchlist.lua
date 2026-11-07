local ADDON, ns = ...

-- Pure: turn quest-index entries into the "Looking for" list.
-- build(entries, opts) -> groups, totalMobs, nearbyMobs
--   entries: { { name, npcIds = {[id]=true}, quests = { {questID, title, objIndex, text, have, need} } } }
--   opts: { quests = {[questID] = {title, logIndex}}, nearby = {[name]=true},
--           pinned = {[questID]=true}, ignored = {[questID]=true}, levelOf = fn(npcIds) -> min, max }
--   groups: { { questID, title, pinned, nearbyCount, mobs = { {name, npcId, have, need, text,
--             nearby, minLevel, maxLevel} } } }  pinned first, then quest log order.
local W = {}
ns.Watchlist = W

local function firstId(set)
  local best
  for id in pairs(set or {}) do
    if not best or id < best then best = id end
  end
  return best
end

function W.build(entries, opts)
  opts = opts or {}
  local nearby, pinned, ignored = opts.nearby or {}, opts.pinned or {}, opts.ignored or {}
  local questInfo = opts.quests or {}
  local groups, byQuest = {}, {}
  local seenNames, seenNearby = {}, {}
  local total, nearbyTotal = 0, 0

  for _, e in ipairs(entries) do
    if e.name then
      for _, q in ipairs(e.quests or {}) do
        if not ignored[q.questID] then
          local g = byQuest[q.questID]
          if not g then
            local info = questInfo[q.questID] or {}
            g = { questID = q.questID, title = info.title or q.title, logIndex = info.logIndex or math.huge,
              pinned = pinned[q.questID] == true, nearbyCount = 0, mobs = {}, names = {} }
            byQuest[q.questID] = g
            groups[#groups + 1] = g
          end
          if not g.names[e.name] then
            g.names[e.name] = true
            local minL, maxL
            if opts.levelOf then minL, maxL = opts.levelOf(e.npcIds or {}) end
            local isNear = nearby[e.name] == true
            g.mobs[#g.mobs + 1] = { name = e.name, npcId = firstId(e.npcIds), have = q.have, need = q.need,
              text = q.text, nearby = isNear, minLevel = minL, maxLevel = maxL }
            if isNear then g.nearbyCount = g.nearbyCount + 1 end
            if not seenNames[e.name] then
              seenNames[e.name] = true
              total = total + 1
              if isNear then nearbyTotal = nearbyTotal + 1 end
            end
          end
        end
      end
    end
  end

  for _, g in ipairs(groups) do
    g.names = nil
    table.sort(g.mobs, function(a, b)
      if a.nearby ~= b.nearby then return a.nearby end
      return a.name < b.name
    end)
  end
  table.sort(groups, function(a, b)
    if a.pinned ~= b.pinned then return a.pinned end
    if a.logIndex ~= b.logIndex then return a.logIndex < b.logIndex end
    return (a.title or "") < (b.title or "")
  end)
  return groups, total, nearbyTotal
end
