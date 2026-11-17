local ns = __ns

local afk = false
UnitIsAFK = function() return afk end
__boot(nil, {})

local QT = ns.QuestTimes

local function setup()
  afk = false
  ns.db.questGrades = ns.db.questGrades or {}
  ns.db.questGrades.learn = true
  QT:Reset()
  QT.estimateFor = function() return 100 end
end

describe("QuestTimes", function()
  it("splits online time between the quests active together", function()
    setup()
    __fire("QUEST_ACCEPTED", 1); __fire("QUEST_ACCEPTED", 2)
    QT:Tick(10)
    assertEq(QT:Spent(1), 5); assertEq(QT:Spent(2), 5)
  end)
  it("doesn't count AFK time", function()
    setup()
    __fire("QUEST_ACCEPTED", 1)
    afk = true
    QT:Tick(10)
    assertEq(QT:Spent(1), 0)
  end)
  it("records time and estimate at turn-in", function()
    setup()
    __fire("QUEST_ACCEPTED", 1)
    QT:Tick(30)
    __fire("QUEST_TURNED_IN", 1, 500, 0)
    __fire("QUEST_REMOVED", 1)
    assertEq(QT:Took(1), 30)
    assertEq(ns.global.questTimes[1].estimate, 100)
    assertNil(QT:Spent(1))
  end)
  it("forgets abandoned quests and ignores quests accepted before tracking", function()
    setup()
    __fire("QUEST_ACCEPTED", 1)
    __fire("QUEST_REMOVED", 1)
    assertNil(QT:Spent(1))
    __fire("QUEST_TURNED_IN", 7, 100, 0)
    assertNil(QT:Took(7))
  end)
  it("learns a personal multiplier once there are five finished quests", function()
    setup()
    for id = 1, 4 do ns.global.questTimes[id] = { spent = 200, estimate = 100 } end
    assertEq(QT:Multiplier(), 1)
    ns.global.questTimes[5] = { spent = 200, estimate = 100 }
    assertEq(QT:Multiplier(), 2)
    for id = 1, 5 do ns.global.questTimes[id] = { spent = 1000, estimate = 100 } end
    assertEq(QT:Multiplier(), 3, "clamped")
  end)
  it("does nothing when learning is off, and resets", function()
    setup()
    __fire("QUEST_ACCEPTED", 1)
    ns.db.questGrades.learn = false
    QT:Tick(10)
    assertEq(QT:Spent(1), 0)
    ns.db.questGrades.learn = true
    QT:Reset()
    assertNil(QT:Spent(1))
  end)
end)
