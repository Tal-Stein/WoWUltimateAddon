local ADDON, ns = ...
local L = ns.L

-- Rare Scanner: always-on detection of rare, rare-elite and world-boss mobs (quest or not),
-- plus a personal watch list. Feeds the target bar/key and plays its own alert.
local RS = { history = {} }
ns.RareScannerModule = RS

local RARE = { rare = true, rareelite = true, worldboss = true }
local HISTORY_MAX = 20

local function o() return ns.db.rareScanner end

function RS.IsRare(mob)
  return RARE[mob.classification] == true or (mob.name ~= nil and o().watch[mob.name] == true)
end

local function kindLabel(c)
  if c == "rareelite" then return L.RARE_ELITE end
  if c == "worldboss" then return L.BOSS end
  if c == "rare" then return L.RARE end
  return L.WATCHED
end

function RS.Candidates(mobs)
  local mode = o().barMode
  if mode == "hidden" then return {} end
  local list = {}
  for _, mob in ipairs(mobs) do
    if RS.IsRare(mob) and not mob.dead and mob.attackable and not mob.tapped and not mob.isPlayer then
      list[#list + 1] = {
        name = mob.name, level = mob.level, healthPct = mob.healthPct, count = 1, mobs = { mob },
        kind = "rare", isRare = mode == "first",
        tooltip = function(tt) tt:AddLine(kindLabel(mob.classification), 0.75, 0.75, 0.75) end,
      }
    end
  end
  return list
end

function RS.OnMobAdded(mob)
  if not RS.IsRare(mob) or mob.dead or not mob.attackable or mob.isPlayer then return end
  local opts = o()
  if mob.tapped and not opts.alertTagged then return end
  RS.gate:configure({ guidCooldown = opts.cooldown, nameCooldown = opts.cooldown })
  if not RS.gate:shouldAlert(mob.guid, mob.name, GetTime()) then return end
  local text = string.format(L.ALERT_RARE, mob.name, ns.UI.LevelText(mob.level, mob.classification),
    kindLabel(mob.classification))
  if mob.tapped then text = text .. " " .. L.TAGGED_SUFFIX end
  ns.Alerts.Notify({ soundKey = opts.sound, channel = opts.channel, showText = opts.showText, text = text,
    color = { r = 0.85, g = 0.85, b = 0.95 } })
  table.insert(RS.history, 1, { name = mob.name, level = mob.level, classification = mob.classification,
    zone = GetZoneText and ns.Safe.read(GetZoneText) or "", time = time and time() or 0 })
  while #RS.history > HISTORY_MAX do table.remove(RS.history) end
end

local function report()
  ns:Print(L.RARE_HISTORY)
  if #RS.history == 0 then ns:Print("  " .. L.RARE_HISTORY_NONE) end
  for _, h in ipairs(RS.history) do
    ns:Print(string.format("  %s (%s) — %s, %s", h.name, ns.UI.LevelText(h.level, h.classification), h.zone,
      date and date("%H:%M", h.time) or ""))
  end
end

RS.def = ns.Modules:Register({
  key = "rareScanner",
  name = L.MODULE_RARES,
  description = L.MODULE_RARES_DESC,
  defaults = { sound = "raidwarning", channel = "Master", showText = true, alertTagged = true,
    barMode = "first", watch = {}, cooldown = 300 },
  OnEnable = function()
    RS.gate = ns.AlertGate.new({ guidCooldown = o().cooldown, nameCooldown = o().cooldown })
    ns.Targeting:RegisterProvider("rare", RS.Candidates)
    ns.Nameplates:AddListener("rareScanner", { onAdded = RS.OnMobAdded })
    ns:On("ULT_DEBUG_SCAN", RS, report)
  end,
  OnDisable = function()
    ns.Targeting:UnregisterProvider("rare")
    ns.Nameplates:RemoveListener("rareScanner")
    ns:Off("ULT_DEBUG_SCAN", RS)
  end,
})

L.MODULE_RARES = "Rare Scanner"
L.MODULE_RARES_DESC = "Always watches nameplates for rare, rare-elite and world-boss mobs, and anything on your watch list."
L.ALERT_RARE = "RARE: %s (%s %s)"
L.RARE_ELITE = "Rare Elite"
L.BOSS = "Boss"
L.WATCHED = "Watched"
L.TAGGED_SUFFIX = "(tagged)"
L.RARE_HISTORY = "Rares seen this session:"
L.RARE_HISTORY_NONE = "none yet"
