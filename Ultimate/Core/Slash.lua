local ADDON, ns = ...
local L = ns.L

SLASH_ULTIMATE1 = "/ult"
SLASH_ULTIMATE2 = "/ultimate"

-- Recalculate everything Ultimate derives from Questie's data, now. Databases themselves are read
-- fresh each login; remembered quest rewards and quest times are kept.
function ns.Rescan()
  if ns.QuestIndex then ns.QuestIndex:Rebuild() end
  if ns.QuestGradesModule then ns.QuestGradesModule:Invalidate() end
  if ns.Targeting and ns.Targeting.Refresh then ns.Targeting:Refresh(true) end
  ns:Print(L.RESCANNED)
end

local commands = {
  [""] = function()
    if ns.OpenSettings then ns.OpenSettings() else ns:Print(L.SLASH_HELP) end
  end,
  debug = function()
    ns.db.core.debug = not ns.db.core.debug
    ns:Print(L.DEBUG_MODE, ns.db.core.debug and L.ON or L.OFF)
  end,
  reset = function()
    ns:Fire("ULT_RESET_POSITIONS")
    ns:Print(L.POSITIONS_RESET)
  end,
  scan = function(arg)
    if arg == "test" and ns.LongRange then ns.LongRange:SelfTest() else ns:Fire("ULT_DEBUG_SCAN") end
  end,
  rescan = function() ns.Rescan() end,
  grades = function()
    if ns.QuestGradesModule and ns.Modules:IsActive("questGrades") then
      ns.QuestGradesModule:Report()
    else
      ns:Print(L.GRADES_OFF)
    end
  end,
  errors = function(arg)
    if arg == "clear" then
      ns.ErrorLog:Clear()
      ns:Print(L.ERRORS_CLEARED)
    else
      ns.ErrorLog:Report()
    end
  end,
  help = function() ns:Print(L.SLASH_HELP) end,
}

SlashCmdList.ULTIMATE = function(msg)
  local text = string.lower(strtrim(msg or ""))
  local cmd, arg = string.match(text, "^(%S*)%s*(.-)$")
  local fn = commands[cmd or ""] or commands.help
  fn(arg)
end
