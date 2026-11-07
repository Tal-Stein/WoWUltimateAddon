local ADDON, ns = ...

-- Candidate ranking (pure). A candidate is one mob *name* (targeting is by name):
--   { name, level, remaining, healthPct, pinned, isRare, count, firstSeen }
local Ranking = {}
ns.Ranking = Ranking

function Ranking.defaultCriteria()
  return {
    { id = "pinned", enabled = true },
    { id = "level", enabled = true, desc = false },
    { id = "remaining", enabled = true },
    { id = "health", enabled = false },
    { id = "count", enabled = false, desc = true },
  }
end

local HUGE = math.huge

-- Each comparer returns -1 (a first), 1 (b first) or 0.
local function numeric(av, bv, desc)
  if av == bv then return 0 end
  if av == nil then return 1 end -- unknown values sort last regardless of direction
  if bv == nil then return -1 end
  if desc then return av > bv and -1 or 1 end
  return av < bv and -1 or 1
end

local comparers = {
  pinned = function(a, b)
    if (a.pinned and true) == (b.pinned and true) then return 0 end
    return a.pinned and -1 or 1
  end,
  level = function(a, b, crit) return numeric(a.level, b.level, crit.desc) end,
  remaining = function(a, b, crit) return numeric(a.remaining, b.remaining, crit.desc) end,
  health = function(a, b, crit) return numeric(a.healthPct, b.healthPct, crit.desc) end,
  count = function(a, b, crit) return numeric(a.count, b.count, crit.desc) end,
}

function Ranking.rank(candidates, opts)
  local items = {}
  for i, c in ipairs(candidates) do items[i] = { c = c, i = i } end
  local criteria = opts.criteria or Ranking.defaultCriteria()
  table.sort(items, function(x, y)
    local a, b = x.c, y.c
    if opts.rareFirst and (a.isRare and true) ~= (b.isRare and true) then return a.isRare and true or false end
    for _, crit in ipairs(criteria) do
      if crit.enabled and comparers[crit.id] then
        local r = comparers[crit.id](a, b, crit)
        if r ~= 0 then return r < 0 end
      end
    end
    local fa, fb = a.firstSeen or HUGE, b.firstSeen or HUGE
    if fa ~= fb then return fa < fb end
    return x.i < y.i
  end)
  local names = {}
  for i, item in ipairs(items) do names[i] = item.c.name end
  return names
end
