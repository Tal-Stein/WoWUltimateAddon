local ADDON, ns = ...

-- All user-visible strings. Unknown keys fall back to the key itself.
ns.L = setmetatable({}, { __index = function(_, k) return k end })
local L = ns.L

L.ADDON_TITLE = "Ultimate"
