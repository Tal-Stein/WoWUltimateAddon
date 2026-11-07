local ADDON, ns = ...

-- Mob filter (pure). Returns ok, reason. Reasons: dead, player, friendly, tapped, excluded,
-- boss, elite, level, grey.
local Filters = {}
ns.Filters = Filters

function Filters.passes(mob, playerLevel, greyLevel, opts)
  if mob.dead then return false, "dead" end
  if mob.isPlayer then return false, "player" end
  if not mob.attackable then return false, "friendly" end
  if opts.hideTapped and mob.tapped then return false, "tapped" end
  if opts.exclude and mob.name and opts.exclude[mob.name] then return false, "excluded" end

  if ns.Levels.isBoss(mob.level, mob.classification) then
    if not opts.includeBosses then return false, "boss" end
    return true, nil
  end

  local c = mob.classification
  if (c == "elite" or c == "rareelite") and not opts.includeElites then return false, "elite" end

  local level = mob.level
  if level == nil then return false, "level" end
  local diff = level - playerLevel
  if diff < opts.minOffset or diff > opts.maxOffset then return false, "level" end
  if opts.hideGrey and ns.Levels.bucket(level, playerLevel, greyLevel) == "trivial" then
    return false, "grey"
  end
  return true, nil
end
