local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

-- Quest Items: a bar of secure item buttons for quest items you need to use, shown either
-- always or only when relevant (quest zone / quest area / targeting the quest's mob / pinned).
local QIt = { buttons = {}, items = {} }
ns.QuestItemsModule = QIt

local QI = ns.QuestIndex
local MAX_BUTTONS = 8
local SIZE, GAP = 36, 4
local DEFAULT_POINT = { "CENTER", "CENTER", 0, -260 }

local function o() return ns.db.questItems end
local function locked() return o().locked or ns.db.core.lockAll end
local read = ns.Safe.read

local function itemIdFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(string.match(link, "item:(%d+)"))
end

local function usable(itemID)
  return C_Item and C_Item.GetItemSpell and read(C_Item.GetItemSpell, itemID) ~= nil
end

function QIt.Collect()
  local byId, list = {}, {}
  local zone = GetZoneText and read(GetZoneText) or nil
  local function add(itemID, questID)
    if not itemID then return end
    local existing = byId[itemID]
    if existing then
      if not existing.questID and questID then existing.questID = questID end
      return
    end
    local entry = { itemID = itemID, questID = questID }
    byId[itemID] = entry
    list[#list + 1] = entry
  end
  -- 1) Quest log special items (the same source as Blizzard's objective tracker buttons).
  if GetQuestLogSpecialItemInfo then
    for questID, q in pairs(QI:Quests()) do
      if q.logIndex then add(itemIdFromLink(read(GetQuestLogSpecialItemInfo, q.logIndex)), questID) end
    end
  end
  -- 2) Usable quest items in bags.
  if C_Container and C_Container.GetContainerNumSlots then
    for bag = 0, (NUM_BAG_SLOTS or 4) do
      for slot = 1, read(C_Container.GetContainerNumSlots, bag) or 0 do
        local info = read(C_Container.GetContainerItemInfo, bag, slot)
        local itemID = type(info) == "table" and info.itemID or nil
        if itemID then
          local q = read(C_Container.GetContainerItemQuestInfo, bag, slot)
          if type(q) == "table" and (q.isQuestItem or q.questID) and usable(itemID) then
            add(itemID, q.questID)
          end
        end
      end
    end
  end
  for _, e in ipairs(list) do
    local q = e.questID and QI:QuestInfo(e.questID)
    e.title = q and q.title
    e.pinned = o().pinned[e.itemID] == true
    e.npcNames = e.questID and QI:QuestNpcNames(e.questID) or {}
    e.questZoneMatch = q ~= nil and zone ~= nil and q.header == zone
  end
  return list
end

-- Frames ------------------------------------------------------------------

local frame = CreateFrame("Frame", "UltimateQuestItemBar", UIParent)
frame:SetSize(SIZE, SIZE)
frame:Hide()
local handle = CreateFrame("Frame", nil, frame)
handle:SetHeight(14)
handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
local title = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("LEFT")
title:SetText(L.QUEST_ITEM_BAR_TITLE)

local place = UI.MakeMovable(frame, handle, setmetatable({}, {
  __index = function(_, k) return o()[k] end,
  __newindex = function(_, k, v) o()[k] = v end,
}), locked, DEFAULT_POINT)

local function onEnter(self)
  if not self.itemID or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(self.itemID)
  if self.questTitle then GameTooltip:AddLine(self.questTitle, 1, 0.82, 0) end
  GameTooltip:AddLine(self.pinned and L.ITEM_UNPIN_HINT or L.ITEM_PIN_HINT, 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

for i = 1, MAX_BUTTONS do
  local b = CreateFrame("Button", "UltimateQuestItem" .. i, frame, "SecureActionButtonTemplate, ActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:RegisterForDrag("LeftButton")
  b:SetAttribute("type", "item")
  b:SetAttribute("useOnKeyDown", false)
  -- Shift-click pins instead of using the item.
  b:SetAttribute("shift-type1", "macro")
  b:SetAttribute("shift-macrotext1", "")
  b:HookScript("OnClick", function(self)
    if IsShiftKeyDown and IsShiftKeyDown() and self.itemID and not InCombatLockdown() then
      o().pinned[self.itemID] = (not o().pinned[self.itemID]) or nil
      QIt.Update()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    if self.itemID and not InCombatLockdown() and C_Item and C_Item.PickupItem then C_Item.PickupItem(self.itemID) end
  end)
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b.countText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.countText:SetPoint("BOTTOMRIGHT", -2, 2)
  b.pinMark = b:CreateTexture(nil, "OVERLAY")
  b.pinMark:SetSize(12, 12)
  b.pinMark:SetPoint("TOPRIGHT", -1, -1)
  b.pinMark:SetTexture("Interface\\COMMON\\FavoritesIcon")
  b.pinMark:Hide()
  b:Hide()
  QIt.buttons[i] = b
end

-- Non-protected visuals: icon, count, cooldown, pin mark, binding text. Safe in combat.
function QIt.UpdateVisuals()
  for i, b in ipairs(QIt.buttons) do
    if b.itemID then
      local icon = b.icon or _G[b:GetName() .. "Icon"]
      if icon and C_Item and C_Item.GetItemIconByID then icon:SetTexture(read(C_Item.GetItemIconByID, b.itemID)) end
      local count = C_Item and C_Item.GetItemCount and read(C_Item.GetItemCount, b.itemID) or 0
      b.countText:SetText(count and count > 1 and tostring(count) or "")
      local cd = b.cooldown or _G[b:GetName() .. "Cooldown"]
      if cd and CooldownFrame_Set and C_Container and C_Container.GetItemCooldown then
        local start, duration, enable = C_Container.GetItemCooldown(b.itemID)
        if not ns.Safe.isSecret(start) then pcall(CooldownFrame_Set, cd, start, duration, enable) end
      end
      if b.pinned then b.pinMark:Show() else b.pinMark:Hide() end
      local hotkey = b.HotKey or _G[b:GetName() .. "HotKey"]
      if hotkey and GetBindingKey then
        local key = i <= 4 and read(GetBindingKey, "CLICK UltimateQuestItem" .. i .. ":LeftButton")
        hotkey:SetText(key and GetBindingText and GetBindingText(key, true) or "")
      end
    end
  end
end

function QIt.Update()
  if not ns.Modules:IsActive("questItems") then return end
  local opts = o()
  local items = QIt.Collect()
  local target = read(UnitName, "target")
  local shown = {}
  for _, item in ipairs(items) do
    local inArea = item.questID and C_QuestLog and C_QuestLog.IsOnMap and read(C_QuestLog.IsOnMap, item.questID) or false
    if ns.ItemRelevance.shouldShow(item, { targetName = target, inQuestArea = inArea and true or false }, opts.mode) then
      shown[#shown + 1] = item
    end
  end
  table.sort(shown, function(a, b)
    if a.pinned ~= b.pinned then return a.pinned end
    return a.itemID < b.itemID
  end)
  local max = math.min(opts.max or 4, MAX_BUTTONS)
  ns.Combat:Run("questitems.layout", function()
    local horizontal = opts.orientation ~= "VERTICAL"
    local n = 0
    for i, b in ipairs(QIt.buttons) do
      local item = i <= max and shown[i] or nil
      if item then
        n = n + 1
        b:SetAttribute("item", "item:" .. item.itemID)
        b.itemID, b.questTitle, b.pinned = item.itemID, item.title, item.pinned
        b:ClearAllPoints()
        if horizontal then
          b:SetPoint("LEFT", frame, "LEFT", (i - 1) * (SIZE + GAP), 0)
        else
          b:SetPoint("TOP", frame, "TOP", 0, -(i - 1) * (SIZE + GAP))
        end
        b:Show()
      else
        b.itemID, b.questTitle, b.pinned = nil, nil, nil
        b:SetAttribute("item", nil)
        b:Hide()
      end
    end
    local count = math.max(n, 1)
    if horizontal then frame:SetSize(count * SIZE + (count - 1) * GAP, SIZE)
    else frame:SetSize(SIZE, count * SIZE + (count - 1) * GAP) end
    frame:SetScale(opts.scale or 1)
    place()
    frame:SetShown(n > 0)
    handle:SetShown(not locked())
    QIt.UpdateVisuals()
  end)
end

local pending = false
local function requestUpdate()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function() pending = false; QIt.Update() end)
end

local EVENTS = { "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "PLAYER_TARGET_CHANGED", "ZONE_CHANGED",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "ULT_QUEST_INDEX_CHANGED", "UPDATE_BINDINGS" }

QIt.def = ns.Modules:Register({
  key = "questItems",
  name = L.MODULE_QUEST_ITEMS,
  description = L.MODULE_QUEST_ITEMS_DESC,
  defaults = { mode = "relevant", max = 4, orientation = "HORIZONTAL", scale = 1, locked = false, pinned = {} },
  OnEnable = function()
    for _, e in ipairs(EVENTS) do ns:On(e, QIt, requestUpdate) end
    ns:On("BAG_UPDATE_COOLDOWN", QIt, QIt.UpdateVisuals)
    ns:On("SPELL_UPDATE_COOLDOWN", QIt, QIt.UpdateVisuals)
    ns:On("ULT_RESET_POSITIONS", QIt, function() o().point = nil; QIt.Update() end)
    ns:On("ULT_SETTING_CHANGED", QIt, function(_, path)
      if path and (path:find("^questItems") or path == "core.lockAll") then QIt.Update() end
    end)
    QIt.Update()
  end,
  OnDisable = function()
    ns:OffAll(QIt)
    ns.Combat:Run("questitems.layout", function()
      for _, b in ipairs(QIt.buttons) do b.itemID = nil; b:Hide() end
      frame:Hide()
    end)
  end,
})

function QIt.def.BuildSettings(ctx)
  local P = ns.SettingsPanel
  ctx:Dropdown("questItems.mode", L.ITEM_MODE, {
    { value = "relevant", label = L.ITEM_MODE_RELEVANT }, { value = "always", label = L.ITEM_MODE_ALWAYS } }, L.ITEM_MODE_TIP)
  ctx:Slider("questItems.max", L.ITEM_MAX, 1, 8, 1, P.fmt.int)
  ctx:Dropdown("questItems.orientation", L.ORIENTATION, P.ORIENTATIONS)
  ctx:Slider("questItems.scale", L.SCALE, 0.5, 2, 0.05, P.fmt.percent)
  ctx:Checkbox("questItems.locked", L.LOCK_BAR, L.LOCK_BAR_TIP)
end
