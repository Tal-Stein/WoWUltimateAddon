local ADDON, ns = ...
local L = ns.L

-- Round minimap button in Blizzard's tracking-button style (same art LibDBIcon buttons use).
-- Left-click: show/hide the target list. Right-click: settings. Drag: move around the edge.
local MB = {}
ns.MinimapButton = MB

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

local function o() return ns.db.core.minimap end

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

function MB:Place()
  local b = self.button
  if not b then return end
  local rad = math.rad(o().angle or 200)
  local w = Minimap.GetWidth and Minimap:GetWidth()
  local radius = (type(w) == "number" and w > 0) and (w / 2 + 10) or 80
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function onUpdateDrag(self)
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not (mx and px and scale) then return end
  o().angle = math.deg(atan2(py / scale - my, px / scale - mx)) % 360
  MB:Place()
end

local function onClick(_, button)
  if button == "RightButton" then
    if ns.OpenSettings then ns.OpenSettings() end
  elseif ns.Modules:IsActive("targetList") then
    ns:Fire("ULT_TOGGLE_TARGET_LIST")
  elseif ns.OpenSettings then
    ns.OpenSettings()
  end
end

local function onEnter(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(L.ADDON_TITLE)
  local TL = ns.TargetListModule
  if TL and ns.Modules:IsActive("targetList") and (TL.total or 0) > 0 then
    GameTooltip:AddLine(string.format(L.TARGET_LIST_COUNT, TL.nearbyTotal or 0, TL.total), 1, 1, 1)
  end
  GameTooltip:AddDoubleLine(L.MINIMAP_LEFT, L.MINIMAP_TOGGLE_LIST, 0, 1, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.MINIMAP_RIGHT, L.MINIMAP_SETTINGS, 0, 1, 0, 1, 1, 1)
  GameTooltip:Show()
end

function MB:Create()
  if self.button or not Minimap then return end
  local b = CreateFrame("Button", "UltimateMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local overlay = b:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", 7, -6)
  b.icon = icon
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnDragStart", function(self)
    if ns.db.core.lockAll then return end
    self:SetScript("OnUpdate", onUpdateDrag)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  self.button = b
  self:Place()
  b:SetShown(not o().hide)
end

ns:On("ULT_MODULES_STARTED", MB, function() MB:Create() end)
ns:On("ULT_SETTING_CHANGED", MB, function(_, path)
  if MB.button and path and path:find("^core%.minimap") then
    MB.button:SetShown(not o().hide)
    MB:Place()
  end
end)
ns:On("ULT_RESET_POSITIONS", MB, function()
  o().angle = 200
  MB:Place()
end)
