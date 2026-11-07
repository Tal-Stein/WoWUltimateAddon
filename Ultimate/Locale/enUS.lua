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
L.MACRO_IN_COMBAT = "Can't change macros in combat. Try again after combat."
L.MACRO_CREATED = "Macro \"UltTarget\" is ready. Find it under General Macros (/macro) and drag it to an action bar."
L.MACRO_FAILED = "Couldn't create the \"UltTarget\" macro. Your general macro slots may be full."
L.TARGET_BAR_TITLE = "Ultimate Targets"
L.RARE = "Rare"
L.CLICK_TO_TARGET = "Click to target"

-- Key Bindings UI (Options > Keybindings > AddOns)
BINDING_HEADER_ULTIMATE = "Ultimate"
_G["BINDING_NAME_CLICK UltimateTargetButton:LeftButton"] = "Target next quest mob"
BINDING_NAME_ULTIMATE_REFRESH = "Refresh quest targets"
for i = 1, 4 do
  _G["BINDING_NAME_CLICK UltimateQuestItem" .. i .. ":LeftButton"] = "Use quest item " .. i
end
