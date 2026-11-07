local ADDON, ns = ...

-- Sound + on-screen alert, Blizzard style (RaidWarningFrame text). Gating is the caller's job.
local Alerts = {}
ns.Alerts = Alerts

-- a = { soundKey, channel, text, color = {r,g,b}, showText }
function Alerts.Notify(a)
  if a.soundKey and a.soundKey ~= "none" then ns.Sounds.Play(a.soundKey, a.channel) end
  if a.showText and a.text and RaidNotice_AddMessage and RaidWarningFrame then
    local c = a.color or ns.UI.NormalColor()
    ns.SafeCall(RaidNotice_AddMessage, RaidWarningFrame, a.text, { r = c.r, g = c.g, b = c.b })
  end
end

-- Player level and the highest "grey" (no XP) level, from the client when available.
function Alerts.PlayerLevels()
  local level = ns.Safe.read(UnitLevel, "player") or 1
  local grey = ns.Levels.greyLevel(level)
  return level, grey
end
