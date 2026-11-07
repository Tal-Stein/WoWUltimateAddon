local ADDON, ns = ...

-- All user-visible strings. Unknown keys fall back to the key itself.
ns.L = setmetatable({}, { __index = function(_, k) return k end })
local L = ns.L

L.ADDON_TITLE = "Ultimate"
L.ON = "on"
L.OFF = "off"
L.DEBUG_MODE = "Debug output"
L.POSITIONS_RESET = "Bar positions reset."
L.SLASH_HELP = "/ult — open settings;  /ult scan — show detected quest mobs;  /ult reset — reset bar positions;  /ult debug — toggle debug output"
