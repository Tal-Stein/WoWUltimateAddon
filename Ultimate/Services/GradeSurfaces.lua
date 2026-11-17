local ADDON, ns = ...

-- Draws quest grades onto the quest dialog, the quest log (map-style) and Questie's tracker.
-- Only post-hooks (hooksecurefunc), events, and frames of our own parented to theirs; nothing
-- of Blizzard's or Questie's is replaced. Each surface installs once, when its frames exist.
local S = { installed = {} }
ns.GradeSurfaces = S

local function opts() return ns.db and ns.db.questGrades end
local function active() return ns.Modules:IsActive("questGrades") end
local function surfaceOn(name)
  local o = opts()
  return active() and o and o.surfaces and o.surfaces[name] ~= false
end

-- A small hoverable badge: own frame + fontstring, tooltip lines from the grades module.
local function makeBadge(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(80, 14)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
  f:EnableMouse(true)
  -- Hover shows the grade tooltip; clicks go through to the quest row underneath.
  if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
  f:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.questId) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for _, line in ipairs(ns.QuestGradesModule:TooltipLines(self.questId, self.ctx)) do
      GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return f
end

-- Right after the text itself: Blizzard's and Questie's title strings span the whole row.
local function placeAfterText(badge, fontString)
  local width = fontString and fontString.GetStringWidth and fontString:GetStringWidth() or 0
  badge:ClearAllPoints()
  badge:SetPoint("LEFT", fontString, "LEFT", (tonumber(width) or 0) + 4, 0)
end

local function setBadge(badge, questId, ctx, on)
  local text = on and questId and ns.QuestGradesModule:Badge(questId, ctx) or nil
  badge.questId, badge.ctx = questId, ctx
  if text then
    badge.text:SetText(text)
    badge:Show()
  else
    badge:Hide()
  end
end

-- Quest dialog -------------------------------------------------------------------------------
-- The dialog's reward links; links = nil (unknown) while any of them is still loading.
local function dialogContext()
  local links = {}
  for _, kind in ipairs({ "choice", "reward" }) do
    local count = ns.Safe.read(kind == "choice" and GetNumQuestChoices or GetNumQuestRewards) or 0
    for i = 1, count do
      local link = ns.Safe.read(GetQuestItemLink, kind, i)
      if not link then return { key = "dlg" } end
      links[#links + 1] = link
    end
  end
  return { key = "dlg", links = links }
end

function S:RefreshDialog()
  if not self.dialog then return end
  local questId = self.dialogOpen and ns.Safe.read(GetQuestID) or nil
  if not questId or questId == 0 then self.dialog:Hide(); return end
  local ctx = dialogContext()
  if ctx.links then ns.QuestGradesModule:RememberRewards(questId, ctx.links) end
  setBadge(self.dialog, questId, ctx, surfaceOn("dialog"))
end

local function installDialog()
  if S.installed.dialog or not QuestFrame then return end
  S.installed.dialog = true
  S.dialog = makeBadge(QuestFrame)
  S.dialog:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", -40, -30)
  S.dialog:Hide()
end

-- Quest log ----------------------------------------------------------------------------------
function S:RefreshQuestLog()
  local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
  if not (pool and pool.EnumerateActive) then return end
  local on = surfaceOn("questLog")
  for title in pool:EnumerateActive() do
    if type(title) == "table" and title.questID then
      if not title.ultGrade then title.ultGrade = makeBadge(title) end
      placeAfterText(title.ultGrade, title.Text or title)
      setBadge(title.ultGrade, title.questID, nil, on)
    end
  end
end

local function installQuestLog()
  if S.installed.questLog or type(QuestLogQuests_Update) ~= "function" then return end
  S.installed.questLog = true
  hooksecurefunc("QuestLogQuests_Update", function() ns.SafeCall(S.RefreshQuestLog, S) end)
end

-- Questie tracker ----------------------------------------------------------------------------
local function questie(name)
  local mods = type(QuestieLoader) == "table" and type(QuestieLoader._modules) == "table" and QuestieLoader._modules
  local m = mods and mods[name]
  return type(m) == "table" and m or nil
end

function S:RefreshTracker()
  local pool = questie("TrackerLinePool")
  if not (pool and type(pool.ForEachQuestTitleLine) == "function") then return end
  local on = surfaceOn("tracker")
  local function visit(line)
    if type(line) ~= "table" then return end
    local questId = line.mode == "quest" and type(line.Quest) == "table" and line.Quest.Id or nil
    if not line.ultGrade then
      if not questId then return end
      line.ultGrade = makeBadge(line)
    end
    if questId then placeAfterText(line.ultGrade, line.label or line) end
    setBadge(line.ultGrade, questId, nil, on)
  end
  -- Lines are pooled and reused for objectives and zones, so visit every line, not only titles.
  if type(pool.GetHighestIndex) == "function" and type(pool.GetLine) == "function" then
    for i = 1, tonumber(pool.GetHighestIndex()) or 0 do visit(pool.GetLine(i)) end
  else
    pool.ForEachQuestTitleLine(visit)
  end
end

local function installTracker()
  local tracker = questie("QuestieTracker")
  if S.installed.tracker or not (tracker and type(tracker.Update) == "function") then return end
  S.installed.tracker = true
  hooksecurefunc(tracker, "Update", function() ns.SafeCall(S.RefreshTracker, S) end)
end

function S:Install()
  installDialog()
  installQuestLog()
  installTracker()
end

function S:RefreshAll()
  self:RefreshDialog()
  self:RefreshQuestLog()
  self:RefreshTracker()
end

ns:On("PLAYER_LOGIN", S, function() S:Install() end)
ns:On("ADDON_LOADED", S, function() S:Install() end) -- the map/quest log may load later
ns:On("QUEST_DETAIL", S, function() S.dialogOpen = true; S:RefreshDialog() end)
ns:On("QUEST_COMPLETE", S, function() S.dialogOpen = true; S:RefreshDialog() end)
ns:On("QUEST_FINISHED", S, function()
  S.dialogOpen = false
  if S.dialog then S.dialog:Hide() end
end)
ns:On("ULT_QUEST_GRADES_CHANGED", S, function() S:RefreshAll() end)
ns:On("ULT_SETTING_CHANGED", S, function(_, path)
  if path and path:find("^questGrades") then S:RefreshAll() end
end)
ns:On("ULT_MODULE_TOGGLED", S, function() S:RefreshAll() end)
