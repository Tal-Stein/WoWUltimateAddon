local ns = __ns

UnitLevel = function(unit) if unit == "player" then return 11 end end
__boot(nil, {})

local S = ns.GradeSurfaces
local QG = ns.QuestGradesModule

-- Grades come from the module; these tests only check where they land.
QG.Badge = function(_, questId) return questId and ("badge" .. questId) or nil end

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
    line.Quest = { Id = 418 }
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
