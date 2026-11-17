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

local rates = { [3172] = { [1190] = 31, [1191] = 36 } }
local available = {}
local tags = {}
local function modules()
  return {
    QuestXP = { GetQuestLogRewardXP = function(_, id) return id == 418 and 1150 or 0 end },
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
    assertEq(f.objectives[1].count, 1, "count 1 when the quest isn't in the log")
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
