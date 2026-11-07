local ADDON, ns = ...

-- Difficulty buckets mirroring Blizzard's creature difficulty colors
-- (red / orange / yellow / green / grey). Pure; greyLevel comes from the client in-game.
local Levels = {}
ns.Levels = Levels

function Levels.bucket(mobLevel, playerLevel, greyLevel)
  if mobLevel == nil or mobLevel < 0 then return "impossible" end
  local diff = mobLevel - playerLevel
  if diff >= 5 then return "impossible" end
  if diff >= 3 then return "hard" end
  if diff >= -2 then return "normal" end
  if mobLevel > greyLevel then return "easy" end
  return "trivial"
end

function Levels.isDangerous(bucket) return bucket == "hard" or bucket == "impossible" end

function Levels.isBoss(level, classification)
  return level == -1 or classification == "worldboss"
end

-- Highest level that gives no XP ("grey"), Classic formula.
function Levels.greyLevel(playerLevel)
  if playerLevel <= 5 then return 0 end
  if playerLevel <= 39 then return playerLevel - math.floor(playerLevel / 10) - 5 end
  if playerLevel <= 59 then return playerLevel - math.floor(playerLevel / 5) - 1 end
  return playerLevel - 9
end
