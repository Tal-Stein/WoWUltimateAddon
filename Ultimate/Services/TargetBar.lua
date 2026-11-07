local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

-- Target bar: a fixed, movable, frameless bar (same look as the quest item bar) holding one
-- secure action-style button per ranked mob name. Clicking a button targets that name; right-click
-- opens the shared menu. It stays up while enabled (saying when nothing is nearby) and grows into
-- rows for many targets. Layout only changes out of combat (queued through ns.Combat).
local Bar = { buttons = {}, names = {} }
ns.TargetBar = Bar

local MAX_BUTTONS = 24
local SIZE = 36 -- design size of a button; all spacing below is in the same units
local LABEL_W, LABEL_H = 12, 14 -- extra cell width for name labels, label band under a button
local GAP_X, GAP_Y = 4, 4
local DEFAULT_POINT = { "CENTER", "CENTER", 0, -200 }

local frame = CreateFrame("Frame", "UltimateTargetBar", UIParent)
frame:SetSize(SIZE + LABEL_W, SIZE + LABEL_H)
frame:Hide()
Bar.frame = frame

-- Title strip above the bar, shown while unlocked; it is the drag handle.
local handle = CreateFrame("Frame", nil, frame)
handle:SetHeight(16)
handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT")
title:SetText(L.TARGET_BAR_TITLE)
Bar.title, Bar.handle = title, handle

-- Shown in place of the buttons when nothing is nearby; also takes the right-click.
local emptyArea = CreateFrame("Frame", nil, frame)
emptyArea:SetPoint("TOPLEFT")
emptyArea:EnableMouse(true)
Bar.emptyArea = emptyArea
Bar.empty = emptyArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
Bar.empty:SetPoint("LEFT", 2, 0)
Bar.empty:SetJustifyH("LEFT")
Bar.empty:SetText(L.TARGET_BAR_EMPTY)

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

-- Right-click menu (shared ns.Menu). On a mob button it also offers "Never target <name>".
function Bar.ShowMenu(owner)
  local name = owner and owner.candidateName
  ns.Menu.Show(owner, {
    title = L.TARGET_BAR_TITLE,
    items = function(root)
      if name then
        root:CreateButton(string.format(L.TARGET_MENU_NEVER, name), function()
          ns.db.questTargeting.filters.exclude[name] = true
          ns:Fire("ULT_SETTING_CHANGED", "questTargeting.filters.exclude")
          ns.Targeting:RequestRefresh()
        end)
      end
      local function isOrientation(v) return opts().orientation == v end
      local function setOrientation(v) ns.Menu.Set("targeting.bar.orientation", v) end
      root:CreateRadio(L.HORIZONTAL, isOrientation, setOrientation, "HORIZONTAL")
      root:CreateRadio(L.VERTICAL, isOrientation, setOrientation, "VERTICAL")
    end,
    lock = { get = function() return opts().locked end, set = function(v) ns.Menu.Set("targeting.bar.locked", v) end },
    hide = { label = L.TARGET_MENU_HIDE, fn = function()
      ns.Menu.Set("targeting.bar.enabled", false)
      ns:Print(L.TARGET_BAR_HIDDEN)
    end },
  })
end

local function onMouseUp(self, button) if button == "RightButton" then Bar.ShowMenu(self) end end
handle:SetScript("OnMouseUp", onMouseUp)
emptyArea:SetScript("OnMouseUp", onMouseUp)

for i = 1, MAX_BUTTONS do
  -- Kept at the template's own size (see UI.NativeButtonSize); the bar is scaled instead.
  local b = CreateFrame("Button", "UltimateTargetBarButton" .. i, frame, "SecureActionButtonTemplate, ActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  b:SetAttribute("useOnKeyDown", false)
  -- Right-click opens the menu instead of targeting.
  b:SetAttribute("type2", "macro")
  b:SetAttribute("macrotext2", "")
  b:HookScript("OnClick", function(self, button, down)
    if button == "RightButton" and not down then Bar.ShowMenu(self) end
  end)
  b.level = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.level:SetPoint("TOPLEFT", 2, -2)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b.label:SetWidth(SIZE + LABEL_W)
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
  local signature = table.concat(names, "\001") .. "|" .. tostring(o.enabled) .. tostring(o.orientation)
    .. tostring(o.perRow) .. tostring(o.scale) .. tostring(locked())
  if not force and signature == self.signature then
    self:UpdateVisuals()
    return
  end
  self.signature = signature
  -- Buttons keep the template's own size (see UI.NativeButtonSize); spacing scales with it and
  -- the whole panel is scaled back to the design size.
  self.native = self.native or UI.NativeButtonSize(self.buttons[1], SIZE)
  local size = self.native
  local k = size / SIZE
  local cellW, cellH = size + LABEL_W * k, size + LABEL_H * k
  local grid = ns.Grid.layout(#names, {
    perRow = o.perRow or 6, vertical = o.orientation == "VERTICAL",
    cellW = cellW, cellH = cellH, gapX = GAP_X * k, gapY = GAP_Y * k,
    pad = 0, top = 0, minWidth = 0,
  })
  self.grid = grid
  ns.Combat:Run("targetbar.layout", function()
    for i, b in ipairs(Bar.buttons) do
      local name = names[i] and ns.Units.sanitizeName(names[i])
      local cell = grid.cells[i]
      if name and cell then
        b:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. name)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", cell.x + (cellW - size) / 2, cell.y)
        b.label:SetWidth(cellW)
        b.candidateName = names[i]
        b:Show()
      else
        b.candidateName = nil
        b:Hide()
      end
    end
    emptyArea:SetSize(cellW * 3, cellH / 2)
    emptyArea:SetShown(#names == 0)
    Bar.empty:SetShown(#names == 0)
    handle:SetShown(not locked())
    frame:SetSize(grid.width, grid.height)
    Bar.barScale = (o.scale or 1) / k
    frame:SetScale(Bar.barScale)
    place()
    frame:SetShown(o.enabled and true or false)
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

-- Put the (empty) panel up at login rather than waiting for the first target.
ns:On("ULT_MODULES_STARTED", Bar, function()
  Bar.ranked = Bar.ranked or {}
  Bar:Layout(true)
end)
