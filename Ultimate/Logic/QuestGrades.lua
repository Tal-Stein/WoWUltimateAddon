local ADDON, ns = ...

-- Quest grading math (pure). Grades are 1..5; "none" means "nothing here for you" (no XP, no
-- upgrade); nil means "not enough data to say" and is shown as "?".
local Grades = {}
ns.Grades = Grades

Grades.CONSTS = { killSeconds = 25, perLevelAbove = 5, eliteFactor = 3, objectSeconds = 10,
  travelBase = 90, travelPerZone = 120 }

Grades.PRESETS = {
  balanced = { speed = 60, gear = 40, chain = 30, travel = 30, difficulty = 40, rep = 10 },
  speed = { speed = 100, gear = 10, chain = 40, travel = 50, difficulty = 50, rep = 0 },
  gear = { speed = 40, gear = 100, chain = 20, travel = 20, difficulty = 30, rep = 10 },
}
Grades.FACTORS = { "speed", "gear", "chain", "travel", "difficulty", "rep" }

local function killCost(o, playerLevel, c)
  local secs = c.killSeconds
  if o.level and playerLevel and o.level > playerLevel then
    secs = secs + (o.level - playerLevel) * c.perLevelAbove
  end
  if o.elite then secs = secs * c.eliteFactor end
  return secs
end

-- Estimated seconds to finish: objectives plus travel. nil when an objective can't be costed.
function Grades.estimateSeconds(facts, playerLevel, consts)
  local c = consts or Grades.CONSTS
  if type(facts) ~= "table" or type(facts.objectives) ~= "table" then return nil end
  local total = 0
  for _, o in ipairs(facts.objectives) do
    local count = o.count or 1
    if o.kind == "kill" then
      total = total + count * killCost(o, playerLevel, c)
    elseif o.kind == "drop" then
      if not o.rate or o.rate <= 0 then return nil end
      local kills = math.ceil(count / (math.min(o.rate, 100) / 100))
      total = total + kills * killCost(o, playerLevel, c)
    elseif o.kind == "object" then
      total = total + count * c.objectSeconds
    else
      return nil
    end
  end
  local zones = math.max(1, facts.zones or 1)
  return total + c.travelBase + (zones - 1) * c.travelPerZone
end

local function band(x, cuts)
  for i, cut in ipairs(cuts) do
    if x < cut then return i end
  end
  return #cuts + 1
end

function Grades.levelingFixed(xpPerMin, baseline)
  if not xpPerMin or not baseline or xpPerMin <= 0 or baseline <= 0 then return nil end
  return band(xpPerMin / baseline, { 0.5, 0.8, 1.2, 1.8 })
end

function Grades.gearFixed(newScore, oldScore)
  if not newScore then return nil end
  if not oldScore or oldScore <= 0 then return newScore > 0 and 5 or "none" end
  local gain = newScore / oldScore - 1
  if gain <= 0 then return "none" end
  return band(gain, { 0.03, 0.08, 0.15, 0.30 })
end

function Grades.relative(value, values)
  if value == nil or type(values) ~= "table" or #values == 0 then return nil end
  if #values == 1 then return 3 end
  local below = 0
  for _, v in ipairs(values) do
    if v < value then below = below + 1 end
  end
  local p = below / (#values - 1)
  return math.min(5, 1 + math.floor(p * 5))
end

function Grades.unifiedScore(factors, weights)
  local sum, wsum = 0, 0
  for _, k in ipairs(Grades.FACTORS) do
    local v, w = factors[k], weights[k] or 0
    if v ~= nil and w > 0 then
      sum = sum + v * w
      wsum = wsum + w
    end
  end
  if wsum == 0 then return nil end
  return sum / wsum
end

function Grades.unifiedFixed(score)
  return 1 + math.floor(score * 4 + 0.5)
end
