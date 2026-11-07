local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

-- Target List: a collapsible, movable window listing the mobs the open quests need, grouped by
-- quest, with a portrait, level range and progress per mob. Mobs whose nameplates are in view
-- are highlighted. Display only: no secure frames, so it updates and collapses freely in combat.
local TL = { rows = {}, nearby = {}, total = 0, nearbyTotal = 0 }
ns.TargetListModule = TL

local WIDTH = 230
local HEADER_H = 24
local QUEST_H, MOB_H = 18, 28
local PORTRAIT = 24
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -220, -260 }
local BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function o() return ns.db.targetList end
local function locked() return o().locked or ns.db.core.lockAll end

-- Frame ---------------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "UltimateTargetList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(WIDTH, HEADER_H + 8)
frame:SetFrameStrata("MEDIUM")
if frame.SetBackdrop then
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(0, 0, 0, 0.6)
  local c = TOOLTIP_DEFAULT_COLOR
  if c then frame:SetBackdropBorderColor(c.r, c.g, c.b) end
end
frame:Hide()
TL.frame = frame

local header = CreateFrame("Button", nil, frame)
header:SetPoint("TOPLEFT", 4, -4)
header:SetPoint("TOPRIGHT", -4, -4)
header:SetHeight(HEADER_H - 4)
header:RegisterForClicks("LeftButtonUp")
TL.header = header

local toggle = header:CreateTexture(nil, "ARTWORK")
toggle:SetSize(14, 14)
toggle:SetPoint("LEFT", 4, 0)
TL.toggleIcon = toggle

TL.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
TL.title:SetPoint("LEFT", toggle, "RIGHT", 6, 0)
TL.title:SetText(L.TARGET_LIST_TITLE)

TL.count = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
TL.count:SetPoint("RIGHT", -6, 0)

local body = CreateFrame("Frame", nil, frame)
body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
body:SetHeight(1)
TL.body = body

TL.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
TL.empty:SetPoint("TOPLEFT", 6, -4)
TL.empty:SetText(L.TARGET_LIST_EMPTY)

TL.more = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
TL.more:SetJustifyH("LEFT")

local place = UI.MakeMovable(frame, header, setmetatable({}, {
  __index = function(_, k) return o()[k] end,
  __newindex = function(_, k, v) o()[k] = v end,
}), locked, DEFAULT_POINT)

header:SetScript("OnClick", function() TL:Toggle() end)
header:SetScript("OnEnter", function(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(L.TARGET_LIST_TITLE)
  GameTooltip:AddLine(L.TARGET_LIST_TOGGLE_HINT, 1, 1, 1, true)
  GameTooltip:Show()
end)
header:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

-- Rows ----------------------------------------------------------------------------------------

local function rowEnter(self)
  if not GameTooltip or self.kind ~= "mob" or not self.mob then return end
  local m = self.mob
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  local color = UI.DifficultyColor(m.maxLevel)
  GameTooltip:SetText(m.name, color.r, color.g, color.b)
  if m.minLevel then
    local lv = m.minLevel == m.maxLevel and tostring(m.minLevel) or (m.minLevel .. "-" .. m.maxLevel)
    GameTooltip:AddLine(string.format(L.TARGET_LIST_LEVEL, lv), 1, 1, 1)
  end
  if m.text then GameTooltip:AddLine(m.text, 0.75, 0.75, 0.75, true) end
  if m.nearby then GameTooltip:AddLine(L.TARGET_LIST_IN_VIEW, 0.1, 1, 0.1, true) end
  GameTooltip:Show()
end

local function rowLeave() if GameTooltip then GameTooltip:Hide() end end

local function newRow(i)
  local r = CreateFrame("Button", nil, body)
  r.nearbyGlow = r:CreateTexture(nil, "BACKGROUND")
  r.nearbyGlow:SetAllPoints()
  r.nearbyGlow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  r.nearbyGlow:SetBlendMode("ADD")
  r.nearbyGlow:SetVertexColor(0.2, 1, 0.2, 0.6)
  r.nearbyGlow:Hide()
  r.fallback = r:CreateTexture(nil, "ARTWORK")
  r.fallback:SetSize(PORTRAIT - 6, PORTRAIT - 6)
  r.fallback:SetPoint("LEFT", 6, 0)
  r.fallback:SetTexture(UI.ICON_QUEST)
  r.portrait = CreateFrame("PlayerModel", nil, r)
  r.portrait:SetSize(PORTRAIT, PORTRAIT)
  r.portrait:SetPoint("LEFT", 3, 0)
  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.label:SetJustifyH("LEFT")
  r.label:SetWordWrap(false)
  r.level = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.level:SetJustifyH("LEFT")
  r.level:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", PORTRAIT + 8, 2)
  r.progress = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.progress:SetPoint("RIGHT", -6, 0)
  r.label:SetPoint("RIGHT", r.progress, "LEFT", -4, 0)
  r:SetScript("OnEnter", rowEnter)
  r:SetScript("OnLeave", rowLeave)
  TL.rows[i] = r
  return r
end

local function setPortrait(r, npcId)
  local show = o().portraits and npcId ~= nil
  if show and r.npcId ~= npcId then
    if r.portrait.ClearModel then r.portrait:ClearModel() end
    if r.portrait.SetCreature then pcall(r.portrait.SetCreature, r.portrait, npcId) end
    if r.portrait.SetPortraitZoom then r.portrait:SetPortraitZoom(1) end
  end
  r.npcId = npcId
  r.portrait:SetShown(show)
end

local function layoutQuestRow(r, g, y)
  r.kind, r.mob = "quest", nil
  r:SetHeight(QUEST_H)
  r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
  r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
  r.label:ClearAllPoints()
  r.label:SetPoint("LEFT", 6, 0)
  r.label:SetPoint("RIGHT", r.progress, "LEFT", -4, 0)
  r.label:SetFontObject(GameFontNormalSmall or "GameFontNormalSmall")
  r.label:SetText(g.title or "")
  r.label:SetTextColor(1, 0.82, 0)
  r.level:SetText("")
  r.progress:SetText(g.nearbyCount > 0 and ("|cff20ff20" .. g.nearbyCount .. "|r") or "")
  r.nearbyGlow:Hide()
  r.fallback:Hide()
  r.npcId = nil
  r.portrait:Hide()
  r:Show()
  return QUEST_H
end

local function layoutMobRow(r, m, y)
  r.kind, r.mob = "mob", m
  r:SetHeight(MOB_H)
  r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
  r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
  r.label:ClearAllPoints()
  r.label:SetPoint("TOPLEFT", r, "TOPLEFT", PORTRAIT + 8, -3)
  r.label:SetPoint("RIGHT", r.progress, "LEFT", -4, 0)
  r.label:SetFontObject(GameFontHighlight or "GameFontHighlight")
  r.label:SetText(m.name)
  local color = m.maxLevel and UI.DifficultyColor(m.maxLevel) or UI.NormalColor()
  r.label:SetTextColor(color.r, color.g, color.b)
  if m.minLevel then
    local lv = m.minLevel == m.maxLevel and tostring(m.minLevel) or (m.minLevel .. "-" .. m.maxLevel)
    r.level:SetText(string.format(L.TARGET_LIST_LEVEL, lv))
  else
    r.level:SetText("")
  end
  local need = m.need or 0
  r.progress:SetText(need > 0 and string.format("%d/%d", m.have or 0, need) or "")
  r.nearbyGlow:SetShown(m.nearby == true)
  r.fallback:Show()
  setPortrait(r, m.npcId)
  r:Show()
  return MOB_H
end

-- Render --------------------------------------------------------------------------------------

function TL:Build()
  local QI = ns.QuestIndex
  local groups, total, nearby = ns.Watchlist.build(QI:Entries(), {
    quests = QI:Quests(), nearby = self.nearby,
    pinned = ns.db.questTargeting and ns.db.questTargeting.pinned,
    ignored = ns.db.questTargeting and ns.db.questTargeting.ignored,
    levelOf = function(ids) return QI:NpcLevels(ids) end,
  })
  if o().nearbyOnly then
    local kept = {}
    for _, g in ipairs(groups) do
      local mobs = {}
      for _, m in ipairs(g.mobs) do if m.nearby then mobs[#mobs + 1] = m end end
      if #mobs > 0 then g.mobs = mobs; kept[#kept + 1] = g end
    end
    groups = kept
  end
  return groups, total, nearby
end

function TL:Render()
  if not ns.Modules:IsActive("targetList") then return end
  local groups, total, nearbyTotal = self:Build()
  self.total, self.nearbyTotal = total, nearbyTotal
  self.count:SetText(total > 0 and string.format(L.TARGET_LIST_COUNT, nearbyTotal, total) or "")

  local collapsed = o().collapsed
  self.toggleIcon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")

  local maxRows = o().maxRows or 20
  local n, y, hidden = 0, 0, 0
  for _, g in ipairs(groups) do
    for i = 0, #g.mobs do
      if n >= maxRows then
        hidden = hidden + 1
      else
        n = n + 1
        local r = self.rows[n] or newRow(n)
        if i == 0 then y = y + layoutQuestRow(r, g, y) else y = y + layoutMobRow(r, g.mobs[i], y) end
      end
    end
  end
  for i = n + 1, #self.rows do self.rows[i]:Hide() end

  self.empty:SetShown(#groups == 0)
  if #groups == 0 then y = 18 end
  self.more:ClearAllPoints()
  self.more:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -y - 2)
  self.more:SetText(string.format(L.TARGET_LIST_MORE, hidden))
  self.more:SetShown(hidden > 0)
  if hidden > 0 then y = y + 16 end

  body:SetHeight(math.max(y, 1))
  body:SetShown(not collapsed)
  frame:SetHeight(HEADER_H + 6 + (collapsed and 0 or y + 4))
  frame:SetScale(o().scale or 1)
  ns:Fire("ULT_TARGET_LIST_UPDATED", total, nearbyTotal)
end

function TL:Toggle()
  o().collapsed = not o().collapsed
  self:Render()
end

function Ultimate_ToggleTargetList() ns:Fire("ULT_TOGGLE_TARGET_LIST") end

-- Nearby names come from the targeting service, which already applies the filters.
ns:On("ULT_TARGETS_CHANGED", TL, function(_, _, byName)
  local set = {}
  for name in pairs(byName or {}) do set[name] = true end
  TL.nearby = set
  TL:Render()
end)

TL.def = ns.Modules:Register({
  key = "targetList",
  name = L.MODULE_TARGET_LIST,
  description = L.MODULE_TARGET_LIST_DESC,
  defaults = { collapsed = false, portraits = true, nearbyOnly = false, maxRows = 20, scale = 1, locked = false },
  OnEnable = function()
    place()
    frame:Show()
    ns:On("ULT_QUEST_INDEX_CHANGED", TL, function() TL:Render() end)
    ns:On("ULT_TOGGLE_TARGET_LIST", TL, function() TL:Toggle() end)
    ns:On("ULT_SETTING_CHANGED", TL, function(_, path)
      if path and (path:find("^targetList%.") or path:find("^questTargeting%.pinned")
        or path:find("^questTargeting%.ignored") or path == "core.lockAll") then
        if path == "targetList.portraits" then for _, r in ipairs(TL.rows) do r.npcId = nil end end
        TL:Render()
      end
    end)
    ns:On("ULT_RESET_POSITIONS", TL, function() o().point = nil; place() end)
    TL:Render()
  end,
  OnDisable = function()
    ns:Off("ULT_QUEST_INDEX_CHANGED", TL)
    ns:Off("ULT_TOGGLE_TARGET_LIST", TL)
    ns:Off("ULT_SETTING_CHANGED", TL)
    ns:Off("ULT_RESET_POSITIONS", TL)
    frame:Hide()
  end,
})

function TL.def.BuildSettings(ctx)
  local P = ns.SettingsPanel
  ctx:Checkbox("targetList.collapsed", L.TARGET_LIST_COLLAPSED)
  ctx:Checkbox("targetList.portraits", L.TARGET_LIST_PORTRAITS, L.TARGET_LIST_PORTRAITS_TIP)
  ctx:Checkbox("targetList.nearbyOnly", L.TARGET_LIST_NEARBY_ONLY, L.TARGET_LIST_NEARBY_ONLY_TIP)
  ctx:Slider("targetList.maxRows", L.TARGET_LIST_MAX_ROWS, 5, 40, 1, P.fmt.int)
  ctx:Slider("targetList.scale", L.SCALE, 0.5, 2, 0.05, P.fmt.percent)
  ctx:Checkbox("targetList.locked", L.TARGET_LIST_LOCK, L.TARGET_LIST_LOCK_TIP)
end
