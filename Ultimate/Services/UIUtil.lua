local ADDON, ns = ...

-- Small helpers shared by the add-on's frames. Everything reuses Blizzard colors and art.
local UI = {}
ns.UI = UI

UI.ICON_QUEST = "Interface\\GossipFrame\\AvailableQuestIcon"
UI.ICON_RARE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
UI.ICON_BOSS = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local RED = { r = 1, g = 0.1, b = 0.1 }
local GOLD = { r = 1, g = 0.82, b = 0 }

-- Blizzard creature difficulty color for a level (red/orange/yellow/green/grey).
function UI.DifficultyColor(level)
  if type(level) ~= "number" or level < 0 then return RED end
  if GetCreatureDifficultyColor then
    local ok, a, g, b = pcall(GetCreatureDifficultyColor, level)
    if ok and type(a) == "table" then return a end
    if ok and type(a) == "number" then return { r = a, g = g, b = b } end
  end
  return GOLD
end

function UI.NormalColor()
  local c = NORMAL_FONT_COLOR
  if c then return { r = c.r, g = c.g, b = c.b } end
  return GOLD
end

function UI.ColorHex(c)
  return string.format("ff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

function UI.LevelText(level, classification)
  if type(level) ~= "number" or level < 0 then return "??" end
  local suffix = ""
  if classification == "elite" or classification == "rareelite" or classification == "worldboss" then suffix = "+" end
  return tostring(level) .. suffix
end

-- Make `frame` draggable through `handle`, persisting its anchor into store.point.
-- isLocked() is checked on every drag; moving never happens in combat.
function UI.MakeMovable(frame, handle, store, isLocked, defaultPoint)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle:SetScript("OnDragStart", function()
    if isLocked() or InCombatLockdown() then return end
    frame:StartMoving()
  end)
  handle:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = frame:GetPoint()
    store.point = { point, relPoint, x, y }
  end)
  local function place()
    frame:ClearAllPoints()
    local p = store.point or defaultPoint
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  end
  return place
end
