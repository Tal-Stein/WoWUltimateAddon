local ns = __ns

UnitLevel = function(unit) if unit == "player" then return 11 end end
__boot(nil, {})

local S = ns.GradeSurfaces
local QG = ns.QuestGradesModule

-- Grades come from the module; these tests only check where they land.
QG.Badge = function(_, questId, _, opts)
  if not questId then return nil end
  return (opts and opts.short and "short" or "badge") .. questId
end

local function strip(fs) return fs and fs:GetText() end

describe("Grade surfaces", function()
  it("shows the grade on the quest dialog", function()
    QuestFrame = CreateFrame("Frame", "QuestFrame", UIParent)
    GetQuestID = function() return 418 end
    GetNumQuestChoices = function() return 0 end
    GetNumQuestRewards = function() return 0 end
    S:Install()
    __fire("QUEST_DETAIL")
    assertEq(strip(S.dialog.text), "badge418")
    assertTrue(S.dialog.shown)
    __fire("QUEST_FINISHED")
    assertFalse(S.dialog.shown)
  end)
  it("remembers the dialog's rewards for the quest, but only when all of them are known", function()
    QuestFrame = QuestFrame or CreateFrame("Frame", "QuestFrame", UIParent)
    GetQuestID = function() return 418 end
    GetNumQuestChoices = function() return 1 end
    GetNumQuestRewards = function() return 0 end
    GetQuestItemLink = function() return nil end -- still loading
    ns.global.questRewards = {}
    S:Install()
    __fire("QUEST_DETAIL")
    assertNil(ns.global.questRewards[418])
    GetQuestItemLink = function() return "|Hitem:100|h[Gloves]|h" end
    __fire("QUEST_DETAIL")
    assertEq(ns.global.questRewards[418][1], "|Hitem:100|h[Gloves]|h")
    GetNumQuestChoices = function() return 0 end
    __fire("QUEST_FINISHED")
  end)
  it("adds the grade to quest log titles after Blizzard updates them", function()
    local title = CreateFrame("Button", nil, UIParent)
    title.questID = 33
    title.Text = title:CreateFontString()
    local active = { [title] = true }
    QuestScrollFrame = { titleFramePool = { EnumerateActive = function() return pairs(active) end } }
    QuestLogQuests_Update = function() end
    S:Install()
    QuestLogQuests_Update()
    assertEq(strip(title.ultGrade.text), "badge33")
  end)
  it("adds the grade to Questie's tracker titles", function()
    local line = CreateFrame("Button", nil, UIParent)
    line.label = line:CreateFontString()
    line.mode, line.Quest = "quest", { Id = 418 }
    local tracker = { Update = function() end }
    QuestieLoader = { _modules = {
      QuestieTracker = tracker,
      TrackerLinePool = { ForEachQuestTitleLine = function(cb) cb(line) end },
    } }
    S:Install()
    tracker.Update()
    assertEq(strip(line.ultGrade.text), "badge418")
    assertTrue(line.ultGrade.shown)
    ns.db.questGrades.surfaces.tracker = false
    ns:Fire("ULT_SETTING_CHANGED", "questGrades.surfaces.tracker")
    assertFalse(line.ultGrade.shown)
    ns.db.questGrades.surfaces.tracker = true
    line.Quest = nil
    tracker.Update()
    assertFalse(line.ultGrade.shown, "recycled line without a quest")
  end)
  it("clears badges on tracker lines reused for other things, and sits after the title text", function()
    local line = CreateFrame("Button", nil, UIParent)
    line.label = line:CreateFontString()
    line.label.GetStringWidth = function() return 120 end
    line.mode, line.Quest = "quest", { Id = 418 }
    local tracker = { Update = function() end }
    QuestieLoader = { _modules = {
      QuestieTracker = tracker,
      TrackerLinePool = { GetHighestIndex = function() return 1 end, GetLine = function() return line end,
        ForEachQuestTitleLine = function(cb) if line.mode == "quest" then cb(line) end end },
    } }
    S.installed.tracker = nil
    S:Install()
    tracker.Update()
    assertTrue(line.ultGrade.shown)
    assertEq(line.ultGrade.point[4], 124, "just after the title text, not the label's full width")
    assertEq(line.ultGrade.mouseClickEnabled, false, "clicks go through to the line")
    line.mode = "objective"
    tracker.Update()
    assertFalse(line.ultGrade.shown)
  end)
  it("installs only once", function()
    local calls = 0
    QuestLogQuests_Update = function() end
    local title = CreateFrame("Button", nil, UIParent)
    title.questID = 1
    QuestScrollFrame = { titleFramePool = { EnumerateActive = function() calls = calls + 1; return pairs({ [title] = true }) end } }
    S.installed.questLog = nil
    S:Install(); S:Install()
    QuestLogQuests_Update()
    assertEq(calls, 1)
  end)
  it("does nothing, quietly, when the frames don't exist", function()
    local errors = ns.errorCount
    QuestFrame, QuestScrollFrame, QuestLogQuests_Update, QuestieLoader = nil, nil, nil, nil
    S.installed = {}
    S:Install()
    __fire("QUEST_DETAIL")
    ns:Fire("ULT_QUEST_GRADES_CHANGED")
    assertEq(ns.errorCount, errors, tostring(ns.lastError))
  end)
end)

describe("Grade surfaces on Questie's minimap icons", function()
  local created = 0
  local function newIcon()
    created = created + 1
    local f = CreateFrame("Button", "QuestieFrame" .. created, UIParent)
    f.UpdateTexture = function() end
    return f
  end
  it("labels quests you can pick up with a short grade", function()
    local early = newIcon() -- made before Ultimate hooked in
    QuestieLoader = { _modules = { QuestieFrame = { CreateIconFrame = function() return newIcon() end } } }
    S.installed.minimap = nil
    S:Install()
    local icon = QuestieLoader._modules.QuestieFrame.CreateIconFrame(created + 1)
    icon.miniMapIcon, icon.data = true, { Type = "available", Id = 33 }
    local graded = 0
    local badge = QG.Badge
    QG.Badge = function(...) graded = graded + 1; return badge(...) end
    icon:UpdateTexture()
    assertEq(graded, 0, "no grading inside Questie's own draw call")
    __advance(0.2)
    QG.Badge = badge
    assertEq(icon.ultGrade:GetText(), "short33")
    assertTrue(icon.ultGrade.shown)
    early.miniMapIcon, early.data = true, { Type = "available", Id = 34 }
    early:UpdateTexture()
    __advance(0.2)
    assertEq(early.ultGrade:GetText(), "short34", "icons made before the hook get labels too")
    icon.data = { Type = "complete", Id = 33 } -- recycled for a turn-in
    icon:UpdateTexture()
    assertFalse(icon.ultGrade.shown, "a recycled icon loses its label at once")
    icon.miniMapIcon, icon.data = nil, { Type = "available", Id = 33 } -- world map icon
    icon:UpdateTexture()
    __advance(0.2)
    assertTrue(icon.ultGrade.shown, "the world map too")
    ns.db.questGrades.surfaces.worldMap = false
    icon:UpdateTexture()
    assertFalse(icon.ultGrade.shown, "world map has its own switch")
    early:UpdateTexture()
    __advance(0.2)
    assertTrue(early.ultGrade.shown, "minimap unaffected")
    ns.db.questGrades.surfaces.worldMap = true
  end)
  it("follows the setting", function()
    local icon = _G["QuestieFrame1"]
    icon.miniMapIcon, icon.data = true, { Type = "available", Id = 34 }
    ns.db.questGrades.surfaces.minimap = false
    ns:Fire("ULT_SETTING_CHANGED", "questGrades.surfaces.minimap")
    assertFalse(icon.ultGrade.shown)
    ns.db.questGrades.surfaces.minimap = true
    ns:Fire("ULT_SETTING_CHANGED", "questGrades.surfaces.minimap")
    __advance(0.2)
    assertTrue(icon.ultGrade.shown)
  end)
end)

describe("Grade surfaces: map hooks are optional", function()
  it("doesn't hook Questie's icons at all while both map labels are off", function()
    local qf = { CreateIconFrame = function() end }
    local original = qf.CreateIconFrame
    QuestieLoader = { _modules = { QuestieFrame = qf } }
    ns.db.questGrades.surfaces.minimap, ns.db.questGrades.surfaces.worldMap = false, false
    S.installed.minimap = nil
    S:Install()
    assertTrue(qf.CreateIconFrame == original, "Questie's function left untouched")
    assertNil(S.installed.minimap)
    ns.db.questGrades.surfaces.minimap, ns.db.questGrades.surfaces.worldMap = true, true
  end)
end)
