local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

-- Target bar: one secure action-style button per ranked mob name. Clicking targets that name.
-- Layout and visibility only change out of combat (queued through ns.Combat).
local Bar = { buttons = {}, names = {} }
ns.TargetBar = Bar

local MAX_BUTTONS = 12
local SIZE, GAP = 36, 6
local DEFAULT_POINT = { "CENTER", "CENTER", 0, -200 }

local frame = CreateFrame("Frame", "UltimateTargetBar", UIParent)
frame:SetSize(SIZE, SIZE)
frame:Hide()
Bar.frame = frame

local handle = CreateFrame("Frame", nil, frame)
handle:SetHeight(14)
handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("LEFT")
title:SetText(L.TARGET_BAR_TITLE)
Bar.title = title

local function opts() return ns.db.targeting.bar end
local function locked() return opts().locked or ns.db.core.lockAll end

local place = UI.MakeMovable(frame, handle, setmetatable({}, {
  __index = function(_, k) return opts()[k] end,
  __newindex = function(_, k, v) opts()[k] = v end,
}), locked, DEFAULT_POINT)

local function onEnter(self)
  local c = Bar.byName and self.candidateName and Bar.byName[self.candidateName]
  if not c or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local color = UI.DifficultyColor(c.level)
  GameTooltip:SetText(c.name, color.r, color.g, color.b)
  if c.kind == "rare" then GameTooltip:AddLine(L.RARE, 0.75, 0.75, 0.75) end
  for _, fn in ipairs(c.tooltips or {}) do pcall(fn, GameTooltip) end
  GameTooltip:AddLine(L.CLICK_TO_TARGET, 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function onLeave() if GameTooltip then GameTooltip:Hide() end end

for i = 1, MAX_BUTTONS do
  -- Kept at the template's own size (see UI.NativeButtonSize); the bar is scaled instead.
  local b = CreateFrame("Button", "UltimateTargetBarButton" .. i, frame, "SecureActionButtonTemplate, ActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  b:SetAttribute("useOnKeyDown", false)
  b.level = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.level:SetPoint("TOPLEFT", 2, -2)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b.label:SetWidth(SIZE + GAP * 2)
  b.label:SetWordWrap(false)
  b.countText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.countText:SetPoint("BOTTOMRIGHT", -2, 2)
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", onLeave)
  b:Hide()
  Bar.buttons[i] = b
end

local function iconFor(c)
  if c.kind == "rare" or c.isRare then return UI.ICON_RARE end
  if c.level == -1 then return UI.ICON_BOSS end
  for _, m in ipairs(c.mobs or {}) do
    if m.classification == "worldboss" then return UI.ICON_BOSS end
  end
  return UI.ICON_QUEST
end

-- Non-protected visuals (icon, labels, counts). Safe in combat.
function Bar:UpdateVisuals()
  for _, b in ipairs(self.buttons) do
    local c = b.candidateName and self.byName and self.byName[b.candidateName]
    if c then
      local icon = b.icon or _G[b:GetName() .. "Icon"]
      if icon then icon:SetTexture(iconFor(c)) end
      local color = UI.DifficultyColor(c.level)
      b.level:SetText(UI.LevelText(c.level, c.mobs and c.mobs[1] and c.mobs[1].classification))
      b.level:SetTextColor(color.r, color.g, color.b)
      b.label:SetText(c.name)
      b.countText:SetText((c.count or 0) > 1 and tostring(c.count) or "")
      if icon and icon.SetDesaturated then icon:SetDesaturated(false) end
    elseif b.candidateName then
      -- Name left the ranking during combat: keep the (frozen) button but grey it out.
      local icon = b.icon or _G[b:GetName() .. "Icon"]
      if icon and icon.SetDesaturated then icon:SetDesaturated(true) end
      b.countText:SetText("")
    end
  end
end

function Bar:Layout(force)
  local o = opts()
  local names = {}
  for i = 1, math.min(o.max or 6, MAX_BUTTONS) do
    if self.ranked[i] then names[#names + 1] = self.ranked[i] end
  end
  local signature = table.concat(names, "") .. "|" .. tostring(o.enabled) .. tostring(o.orientation)
    .. tostring(o.scale) .. tostring(locked())
  if not force and signature == self.signature then
    self:UpdateVisuals()
    return
  end
  self.signature = signature
  self.native = self.native or UI.NativeButtonSize(self.buttons[1], SIZE)
  local size = self.native
  local gap = GAP * size / SIZE
  ns.Combat:Run("targetbar.layout", function()
    local horizontal = o.orientation ~= "VERTICAL"
    for i, b in ipairs(Bar.buttons) do
      local name = names[i] and ns.Units.sanitizeName(names[i])
      if name then
        b:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. name)
        b:ClearAllPoints()
        b.label:SetWidth(size + gap * 2)
        if horizontal then
          b:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + gap * 2), 0)
        else
          b:SetPoint("TOP", frame, "TOP", 0, -(i - 1) * (size + gap * 3))
        end
        b.candidateName = names[i]
        b:Show()
      else
        b.candidateName = nil
        b:Hide()
      end
    end
    Bar.barScale = (o.scale or 1) * SIZE / size
    frame:SetScale(Bar.barScale)
    local n = math.max(#names, 1)
    if horizontal then
      frame:SetSize(n * size + (n - 1) * gap * 2, size)
    else
      frame:SetSize(size, n * size + (n - 1) * gap * 3)
    end
    place()
    frame:SetShown(o.enabled and #names > 0)
    handle:SetShown(not locked())
    Bar:UpdateVisuals()
  end)
  self:UpdateVisuals()
end

ns:On("ULT_TARGETS_CHANGED", Bar, function(_, ranked, byName)
  Bar.ranked, Bar.byName = ranked or {}, byName or {}
  Bar:Layout()
end)

ns:On("ULT_RESET_POSITIONS", Bar, function()
  opts().point = nil
  Bar.ranked = Bar.ranked or {}
  Bar:Layout(true)
end)

ns:On("ULT_SETTING_CHANGED", Bar, function(_, path)
  if path and (path:find("^targeting%.bar") or path == "core.lockAll") then
    Bar.ranked = Bar.ranked or {}
    Bar:Layout(true)
  end
end)
