local ADDON, ns = ...
local L = ns.L

-- Farming mode for the targeting system: besides quest mobs, the target bar offers grinding mobs
-- around you (hostile, non-elite, within FM.MOB_BELOW..FM.MOB_ABOVE levels of you), rated by the
-- gold per kill your own kills recorded (Services/KillLog.lua), best first. Quest mobs keep their
-- level rating; grinding mobs show a gold rating. On while ns.db.farming.targetMode is set.
local FT = {}
ns.FarmTargeting = FT

local FM = ns.Farming
local TRIVIAL = { minus = true, trivial = true }

local function farmOpts() return ns.db.farming end

function FT.Active()
  local o = farmOpts()
  return o and o.targetMode and ns.Modules:IsActive("farming") or false
end

-- What one kill of this NPC has been worth to you, once you've killed it often enough to trust.
function FT.Value(npcID)
  local stat = npcID and ns.KillLog.Stats()[npcID]
  local v = stat and FM.MobValue(stat, ns.FarmSources.Price, ns.FarmSources.Skills())
  if v and v.kills >= FM.MIN_KILLS and v.perKill > 0 then return v end
end

-- The best gold per kill among all the mobs you've farmed: the yardstick for ratings.
function FT.BestKnown()
  local best = 0
  local skills = ns.FarmSources.Skills()
  for _, stat in pairs(ns.KillLog.Stats()) do
    local v = FM.MobValue(stat, ns.FarmSources.Price, skills)
    if v and v.kills >= FM.MIN_KILLS and v.perKill > best then best = v.perKill end
  end
  return best > 0 and best or nil
end

-- "31s", "1g 20s", "45c": the bar's short gold.
function FT.ShortMoney(copper)
  copper = math.floor((copper or 0) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return s > 0 and string.format("%dg %ds", g, s) or string.format("%dg", g) end
  if s > 0 then return string.format("%ds", s) end
  return string.format("%dc", c)
end

function FT.Farmable(mob, level)
  return mob.npcId and mob.attackable and not mob.isPlayer and not mob.dead and not mob.tapped
    and not TRIVIAL[mob.classification or ""] and (mob.classification == nil or mob.classification == "normal")
    and type(mob.level) == "number" and mob.level > 0
    and mob.level >= level - FM.MOB_BELOW and mob.level <= level + FM.MOB_ABOVE
end

-- The farming line for a tooltip: "Grinding: Good · 31s per kill (24 kills)", or a prompt to farm it.
function FT.TooltipLine(npcID)
  local v = FT.Value(npcID)
  if not v then return L.FARM_TIP_UNRATED, 0.6, 0.6, 0.6 end
  local grade = FM.RatioGrade(v.perKill, FT.BestKnown())
  local c = ns.GoldFarming.COLORS[grade]
  return string.format(L.FARM_TIP_RATED, L["FARM_GRADE_" .. grade], ns.GoldFarming.MobValueText(v.perKill, v.kills)),
    c[1], c[2], c[3]
end

-- Targeting provider: grinding candidates among the nameplates.
function FT.Candidates(mobs)
  local level = ns.Safe.read(UnitLevel, "player") or 1
  local exclude = ns.db.questTargeting and ns.db.questTargeting.filters.exclude or {}
  local best = FT.BestKnown()
  local list = {}
  for _, mob in ipairs(mobs) do
    if FT.Farmable(mob, level) and not exclude[mob.name] then
      local v = FT.Value(mob.npcId)
      local npcID = mob.npcId
      list[#list + 1] = {
        name = mob.name, level = mob.level, healthPct = mob.healthPct, count = 1, mobs = { mob },
        kind = "farm", gold = v and v.perKill or nil,
        goldGrade = v and FM.RatioGrade(v.perKill, best) or nil,
        tooltip = function(tt)
          local text, r, g, b = FT.TooltipLine(npcID)
          tt:AddLine(text, r, g, b)
        end,
      }
    end
  end
  return list
end

-- In farming mode the bar ranks by gold first (after pinned quests).
function FT.Criteria(criteria)
  if not FT.Active() then return criteria end
  local out = {}
  for i, c in ipairs(criteria) do
    out[#out + 1] = c
    if i == 1 then out[#out + 1] = { id = "gold", enabled = true, desc = true } end
  end
  if #out == 0 then out[1] = { id = "gold", enabled = true, desc = true } end
  return out
end

-- Register or drop the provider to match the setting.
function FT.Apply()
  if FT.Active() then
    ns.Targeting:RegisterProvider("farm", FT.Candidates)
  else
    ns.Targeting:UnregisterProvider("farm")
  end
  ns.Targeting:RequestRefresh()
end

function FT.SetMode(on)
  ns.Menu.Set("farming.targetMode", on and true or false)
  FT.Apply()
  ns:Print(on and L.FARM_MODE_ON or L.FARM_MODE_OFF)
end
