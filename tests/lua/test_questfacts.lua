local ns = __ns

UnitLevel = function(unit) if unit == "player" then return 11 end end
__boot(nil, {})

local QF = ns.QuestFacts
local QI = ns.QuestIndex

local db = { quest = {}, npc = {}, item = {} }
local function getter(tbl) return { Get = function(id, field) return tbl[id] and tbl[id][field] end } end
LibQuestieDB = {
  RequireContract = function() return true end,
  Quest = getter(db.quest), Npc = getter(db.npc), Item = getter(db.item),
}

local rates = { [3172] = { [1190] = 31, [1191] = 36 }, [5000] = { [1190] = 3 } }
local bags = {}
GetItemCount = function(id) return bags[id] or 0 end
local available = {}
local tags = {}
local function modules()
  return {
    QuestXP = { db = { [418] = { 11, 1150 }, [33] = { 6, 400 } },
      GetQuestLogRewardXP = function(_, id) return id == 418 and 1150 or 0 end },
    DropDB = { GetItemDroprate = function(item, npc)
      local r = rates[item] and rates[item][npc]
      return r and { r, "Wowhead" } or nil
    end },
    AvailableQuests = { __availableQuests = available },
    QuestieDB = { GetQuestTagInfo = function(id) return tags[id] end },
  }
end

local function setup()
  QuestieLoader = { _modules = modules() }
  for k in pairs(available) do available[k] = nil end
  for k in pairs(tags) do tags[k] = nil end
  QI.dbChecked = nil
  QI.quests = {
    [418] = { questID = 418, title = "Thelsamar Blood Sausages", objectives = {
      { text = "Boar Intestines: 0/3", type = "item", finished = false, numFulfilled = 0, numRequired = 3 },
    } },
  }
  db.quest[418] = { name = "Thelsamar Blood Sausages", questLevel = 11,
    startedBy = { { 1963 } }, finishedBy = { { 1963 } }, objectives = { [3] = { { 3172, nil, 0 } } } }
  db.quest[33] = { name = "Wolves Across the Border", questLevel = 6,
    startedBy = { { 197 } }, finishedBy = { { 197 } }, objectives = { [1] = { { 299, nil, 0 } } },
    nextQuestInChain = 34 }
  db.quest[90] = { name = "Far Away", questLevel = 18, objectives = {} }
  db.quest[91] = { name = "Escort Me", questLevel = 12, objectives = {} }
  db.item[3172] = { name = "Boar Intestines", npcDrops = { 1190, 1191 } }
  db.npc[1190] = { name = "Mountain Boar", maxLevel = 11, rank = 0, zoneID = 38 }
  db.npc[1191] = { name = "Mangy Mountain Boar", maxLevel = 15, rank = 0, zoneID = 38 }
  db.npc[1963] = { name = "Vidra Hearthstove", zoneID = 38 }
  db.npc[197] = { name = "Marshal McBride", zoneID = 12 }
  db.npc[299] = { name = "Young Wolf", maxLevel = 3, rank = 0, zoneID = 12 }
  QF:Invalidate()
end

describe("QuestFacts", function()
  it("costs the drop that starts a quest", function()
    setup()
    bags = {}
    db.item[5000] = { name = "Torn Note", npcDrops = { 1190 } }
    db.quest[60] = { name = "A Torn Note", questLevel = 11, startedBy = { nil, nil, { 5000 } }, objectives = {} }
    local f = QF:Get(60)
    assertEq(f.starterRate, 3)
    local starter = f.objectives[1]
    assertEq(starter.kind, "drop"); assertEq(starter.count, 1); assertEq(starter.rate, 3)
    -- 34 kills of level-11 boars at 25 s + 90 s travel
    assertEq(ns.Grades.estimateSeconds(f, 11), 34 * 25 + 90)
  end)
  it("doesn't cost the starter once you have it or the quest", function()
    setup()
    db.item[5000] = { name = "Torn Note", npcDrops = { 1190 } }
    db.quest[60] = { name = "A Torn Note", questLevel = 11, startedBy = { nil, nil, { 5000 } }, objectives = {} }
    bags = { [5000] = 1 }
    assertEq(#QF:Get(60).objectives, 0)
    bags = {}
    QF:Invalidate()
    QI.quests[60] = { questID = 60, title = "A Torn Note", objectives = {} }
    assertEq(#QF:Get(60).objectives, 0)
  end)
  it("knows when a starter's chance is unknown, and when it's simply handed over", function()
    setup()
    bags = {}
    db.item[5001] = { name = "Strange Rune", npcDrops = { 299 } } -- no drop rate known
    db.item[5002] = { name = "Old Chest Key", objectDrops = { 77 } }
    db.item[5003] = { name = "Sealed Letter" } -- a quest reward / vendor item
    db.quest[61] = { name = "Rune", questLevel = 11, startedBy = { nil, nil, { 5001 } }, objectives = {} }
    db.quest[62] = { name = "Key", questLevel = 11, startedBy = { nil, nil, { 5002 } }, objectives = {} }
    db.quest[63] = { name = "Letter", questLevel = 11, startedBy = { nil, nil, { 5003 } }, objectives = {} }
    assertNil(ns.Grades.estimateSeconds(QF:Get(61), 11))
    assertNil(ns.Grades.estimateSeconds(QF:Get(62), 11))
    assertEq(ns.Grades.estimateSeconds(QF:Get(63), 11), 90)
  end)
  it("reads counts from the quest text when the quest isn't in the log", function()
    setup()
    db.quest[33].objectivesText = { "Kill 8 Young Wolves for Marshal McBride." }
    QF:Invalidate()
    assertEq(QF:Get(33).objectives[1].count, 8)
    QI.quests = {}
    db.quest[418].objectivesText = { "Bring 3 pieces of Bear Meat, 4 Boar Intestines, and 3 Spider Ichor." }
    QF:Invalidate()
    assertEq(QF:Get(418).objectives[1].count, 4)
  end)
  it("knows the difference between no XP data and zero XP", function()
    setup()
    db.quest[34] = { name = "No Data", questLevel = 5, objectives = {} }
    assertNil(QF:Get(34).xp, "no XP row: unknown")
    assertEq(QF:Get(33).xp, nil, "0 from Questie below max level means unknown")
    GetMaxPlayerLevel = function() return 11 end
    QF:Invalidate()
    assertEq(QF:Get(33).xp, 0, "0 at max level is real")
    GetMaxPlayerLevel = nil
  end)
  it("doesn't cost objectives it can't model", function()
    setup()
    db.quest[35] = { name = "Use The Totem", questLevel = 10, objectives = { [5] = { { { 1190 }, 1190, "Totem used" } } } }
    local f = QF:Get(35)
    assertNil(ns.Grades.estimateSeconds(f, 11))
  end)
  it("turns an item objective into a drop with the mean known rate and the log count", function()
    setup()
    local f = QF:Get(418)
    assertEq(f.xp, 1150)
    assertEq(f.level, 11)
    assertEq(#f.objectives, 1)
    local o = f.objectives[1]
    assertEq(o.kind, "drop"); assertEq(o.count, 3); assertEq(o.rate, 33.5)
    assertEq(o.level, 15, "the toughest dropper sets the level")
    assertEq(f.zones, 1)
  end)
  it("reads kill objectives, chains and zones", function()
    setup()
    local f = QF:Get(33)
    assertEq(f.objectives[1].kind, "kill")
    assertEq(f.objectives[1].level, 3)
    assertNil(f.objectives[1].count, "no count is guessed for a quest outside the log")
    assertTrue(f.chain)
  end)
  it("has no drop rate when Questie's drop data is missing", function()
    setup()
    QuestieLoader._modules.DropDB = nil
    QF:Invalidate()
    assertNil(QF:Get(418).objectives[1].rate)
  end)
  it("flags elite, group and escort quests from the quest tag", function()
    setup()
    tags[91] = 84
    tags[90] = 1
    assertTrue(QF:Get(91).escort)
    assertTrue(QF:Get(90).group)
    assertFalse(QF:Get(418).escort)
  end)
  it("compares log quests plus available quests within range", function()
    setup()
    available[33] = true -- level 6: 5 below 11
    available[90] = true -- level 18: 7 above
    local ids = {}
    for _, id in ipairs(QF:Candidates(5)) do ids[id] = true end
    assertTrue(ids[418]); assertTrue(ids[33]); assertNil(ids[90])
  end)
  it("works without Questie's modules", function()
    setup()
    QuestieLoader = nil
    QF:Invalidate()
    local f = QF:Get(418)
    assertNil(f.xp)
    assertEq(#QF:Candidates(5), 1)
  end)
end)
