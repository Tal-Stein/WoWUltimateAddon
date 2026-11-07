local ADDON, ns = ...
local L = ns.L

SLASH_ULTIMATE1 = "/ult"
SLASH_ULTIMATE2 = "/ultimate"

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
  scan = function() ns:Fire("ULT_DEBUG_SCAN") end,
  list = function() ns:Fire("ULT_TOGGLE_TARGET_LIST") end,
  help = function() ns:Print(L.SLASH_HELP) end,
}

SlashCmdList.ULTIMATE = function(msg)
  local cmd = string.lower(strtrim(msg or ""))
  local fn = commands[cmd] or commands.help
  fn()
end
