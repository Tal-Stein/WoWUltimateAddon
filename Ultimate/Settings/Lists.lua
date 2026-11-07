local ADDON, ns = ...
local L = ns.L

-- "Lists & Priorities" canvas page: pin/ignore quests, mob exclusion list, rare watch list.
-- Built from Blizzard templates (UICheckButtonTemplate, InputBoxTemplate, UIPanelButtonTemplate,
-- UIPanelScrollFrameTemplate) so it matches the rest of the Settings panel.
local Lists = {}
ns.ListsPage = Lists

local ROW_H = 22

local function changed(path) ns:Fire("ULT_SETTING_CHANGED", path) end

local function scrollArea(parent, width, height)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetSize(width, height)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(width, height)
  scroll:SetScrollChild(content)
  local bg = scroll:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", 4, -4)
  bg:SetColorTexture(0, 0, 0, 0.25)
  return scroll, content
end

-- Quest table --------------------------------------------------------------

local function questRow(content, i)
  local row = CreateFrame("Frame", nil, content)
  row:SetSize(content:GetWidth(), ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row.pin = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.pin:SetSize(24, 24)
  row.pin:SetPoint("LEFT", 6, 0)
  row.ignore = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.ignore:SetSize(24, 24)
  row.ignore:SetPoint("LEFT", 62, 0)
  row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.title:SetPoint("LEFT", 118, 0)
  row.title:SetPoint("RIGHT", -6, 0)
  row.title:SetJustifyH("LEFT")
  row.pin:SetScript("OnClick", function(self)
    ns.db.questTargeting.pinned[row.questID] = self:GetChecked() and true or nil
    changed("questTargeting.pinned")
  end)
  row.ignore:SetScript("OnClick", function(self)
    ns.db.questTargeting.ignored[row.questID] = self:GetChecked() and true or nil
    ns.Targeting:RequestRefresh()
    changed("questTargeting.ignored")
  end)
  return row
end

function Lists:RefreshQuests()
  local quests = {}
  for id, q in pairs(ns.QuestIndex:Quests()) do quests[#quests + 1] = { id = id, title = q.title, header = q.header } end
  table.sort(quests, function(a, b) return (a.title or "") < (b.title or "") end)
  local content = self.questContent
  for i, q in ipairs(quests) do
    local row = self.questRows[i] or questRow(content, i)
    self.questRows[i] = row
    row.questID = q.id
    row.title:SetText(q.title .. (q.header and ("  |cff808080" .. q.header .. "|r") or ""))
    row.pin:SetChecked(ns.db.questTargeting.pinned[q.id] == true)
    row.ignore:SetChecked(ns.db.questTargeting.ignored[q.id] == true)
    row:Show()
  end
  for i = #quests + 1, #self.questRows do self.questRows[i]:Hide() end
  content:SetHeight(math.max(#quests * ROW_H, 1))
  self.noQuests:SetShown(#quests == 0)
end

-- Name list editor ---------------------------------------------------------

local function nameList(parent, label, path, width)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(width, 200)
  local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT")
  title:SetText(label)
  local input = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
  input:SetSize(width - 150, 22)
  input:SetPoint("TOPLEFT", 6, -20)
  input:SetAutoFocus(false)
  local add = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  add:SetSize(60, 22)
  add:SetPoint("LEFT", input, "RIGHT", 6, 0)
  add:SetText(L.ADD)
  local addTarget = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  addTarget:SetSize(80, 22)
  addTarget:SetPoint("LEFT", add, "RIGHT", 4, 0)
  addTarget:SetText(L.ADD_TARGET)
  local scroll, content = scrollArea(box, width - 30, 140)
  scroll:SetPoint("TOPLEFT", 4, -50)
  box.rows = {}

  local function store() return (ns.Tables.getPath(ns.db, path)) end
  function box:Refresh()
    local names = {}
    for name in pairs(store()) do names[#names + 1] = name end
    table.sort(names)
    for i, name in ipairs(names) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, content)
        row:SetSize(width - 40, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", 4, 0)
        row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.remove:SetSize(70, 20)
        row.remove:SetPoint("RIGHT")
        row.remove:SetText(L.REMOVE)
        row.remove:SetScript("OnClick", function()
          store()[row.name] = nil
          changed(path)
          box:Refresh()
        end)
        self.rows[i] = row
      end
      row.name = name
      row.text:SetText(name)
      row:Show()
    end
    for i = #names + 1, #self.rows do self.rows[i]:Hide() end
    content:SetHeight(math.max(#names * ROW_H, 1))
  end

  local function addName(name)
    name = ns.Units.sanitizeName(name)
    if not name then return end
    store()[name] = true
    changed(path)
    input:SetText("")
    box:Refresh()
  end
  add:SetScript("OnClick", function() addName(input:GetText()) end)
  input:SetScript("OnEnterPressed", function(self) addName(self:GetText()); self:ClearFocus() end)
  input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  addTarget:SetScript("OnClick", function() addName(ns.Safe.read(UnitName, "target")) end)
  return box
end

-- Page ----------------------------------------------------------------------

function Lists:Build(frame)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
  title:SetPoint("TOPLEFT", 10, -10)
  title:SetText(L.LISTS)

  local qTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qTitle:SetPoint("TOPLEFT", 10, -48)
  qTitle:SetText(L.LISTS_QUESTS)
  local qTip = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  qTip:SetPoint("TOPLEFT", qTitle, "BOTTOMLEFT", 0, -4)
  qTip:SetText(L.LISTS_QUESTS_TIP)
  local pinLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pinLabel:SetPoint("TOPLEFT", qTip, "BOTTOMLEFT", 8, -8)
  pinLabel:SetText(L.PIN)
  local ignoreLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ignoreLabel:SetPoint("LEFT", pinLabel, "LEFT", 56, 0)
  ignoreLabel:SetText(L.IGNORE)

  local scroll, content = scrollArea(frame, 560, 200)
  scroll:SetPoint("TOPLEFT", qTip, "BOTTOMLEFT", 0, -26)
  self.questContent, self.questRows = content, {}
  self.noQuests = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  self.noQuests:SetPoint("TOPLEFT", 8, -6)
  self.noQuests:SetText(L.NO_QUESTS)

  self.exclude = nameList(frame, L.LISTS_EXCLUDE, "questTargeting.filters.exclude", 290)
  self.exclude:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -20)
  self.watch = nameList(frame, L.LISTS_WATCH, "rareScanner.watch", 290)
  self.watch:SetPoint("LEFT", self.exclude, "RIGHT", 10, 0)
end

function Lists:Refresh()
  self:RefreshQuests()
  self.exclude:Refresh()
  self.watch:Refresh()
end

function Lists:Register(root)
  if not Settings.RegisterCanvasLayoutSubcategory then return end
  local frame = CreateFrame("Frame", "UltimateListsPanel")
  self.frame = frame
  self:Build(frame)
  frame:SetScript("OnShow", function() Lists:Refresh() end)
  ns:On("ULT_QUEST_INDEX_CHANGED", Lists, function()
    if frame:IsVisible() then Lists:RefreshQuests() end
  end)
  self.category = Settings.RegisterCanvasLayoutSubcategory(root, frame, L.LISTS)
end
