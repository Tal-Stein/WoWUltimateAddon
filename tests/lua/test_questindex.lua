local ns = __ns
local QI = ns.QuestIndex

-- Stub quest log: entries are { title, questID, isHeader, objectives = {...} }
local log = {}
C_QuestLog = {
  GetNumQuestLogEntries = function() return #log end,
  GetInfo = function(i) return log[i] end,
  GetQuestObjectives = function(id)
    for _, e in ipairs(log) do if e.questID == id then return e.objectives end end
  end,
}

local db = { quest = {}, npc = {}, item = {} }
local contractOk = true
local function getter(tbl) return { Get = function(id, field) return tbl[id] and tbl[id][field] end } end
LibQuestieDB = {
  RequireContract = function(n) if contractOk then return true end return false, "mismatch" end,
  Quest = getter(db.quest), Npc = getter(db.npc), Item = getter(db.item),
}

local function setup()
  log = {
    { title = "Elwynn Forest", isHeader = true },
    { title = "Kobold Camp", questID = 100, isHeader = false, objectives = {
      { text = "Kobold Vermin slain: 4/10", type = "monster", finished = false, numFulfilled = 4, numRequired = 10 },
      { text = "Gold Dust: 1/8", type = "item", finished = false, numFulfilled = 1, numRequired = 8 },
      { text = "Done Mob slain: 1/1", type = "monster", finished = true, numFulfilled = 1, numRequired = 1 },
    } },
  }
  -- Real QuestieDB shape: creature/item {id, text, icon}, icon padded to 0, text usually nil.
  db.quest[100] = { name = "Kobold Camp", objectives = {
    [1] = { { 40, nil, 0 }, { 42, nil, 0 } },
    [3] = { { 500, nil, 0 } },
  } }
  db.npc[40] = { name = "Kobold Vermin", minLevel = 2, maxLevel = 3 }
  db.npc[41] = { name = "Kobold Laborer" }
  db.npc[42] = { name = "Done Mob" }
  db.npc[43] = { name = "Kobold Worker" }
  db.item[500] = { name = "Gold Dust", npcDrops = { 41 }, itemDrops = { 501 } }
  db.item[501] = { npcDrops = { 43 } }
  contractOk = true
end

describe("QuestIndex", function()
  it("test_index_maps_creature_and_drops", function()
    setup()
    QI:Rebuild()
    local e40 = QI:ByNpcId(40)
    assertTrue(e40 ~= nil, "creature objective indexed")
    assertEq(e40.name, "Kobold Vermin")
    assertEq(e40.quests[1].questID, 100)
    assertEq(e40.quests[1].have, 4)
    assertEq(e40.quests[1].need, 10)
    local e41 = QI:ByNpcId(41)
    assertTrue(e41 ~= nil, "item dropper indexed")
    assertEq(e41.quests[1].text, "Gold Dust: 1/8")
    assertTrue(QI:ByNpcId(43) ~= nil, "itemDrops followed one level")
    assertTrue(QI:ByName("Kobold Laborer") == e41, "by name")
    local names = QI:QuestNpcNames(100)
    assertTrue(names["Kobold Vermin"] and names["Kobold Laborer"])
    assertEq(QI:QuestInfo(100).header, "Elwynn Forest")
  end)
  it("test_index_skips_finished", function()
    setup()
    QI:Rebuild()
    assertNil(QI:ByNpcId(42))
  end)
  it("test_index_rejects_name_mismatch", function()
    setup()
    db.quest[100].name = "Other Quest"
    QI:Rebuild()
    assertNil(QI:ByNpcId(40))
    assertNil(QI:ByNpcId(41))
  end)
  it("test_index_contract_fail", function()
    setup()
    contractOk = false
    QI.dbChecked = nil
    QI:Rebuild()
    assertNil(QI:ByNpcId(40))
    assertEq(QI.dbOk, false)
    QI.dbChecked = nil
  end)
  it("matches objectives by NPC name, not the icon slot", function()
    setup()
    QI:Rebuild()
    local e40 = QI:ByNpcId(40)
    assertEq(#e40.quests, 1, "Kobold Vermin tied only to its own objective")
    assertEq(e40.quests[1].objIndex, 1)
    assertNil(QI:ByNpcId(42), "finished objective's mob is not relevant even with icon 0")
  end)
  it("uses DB objective text when present", function()
    setup()
    log[2].objectives[1].text = "Tunnel Rats slain: 4/10"
    db.quest[100].objectives[1] = { { 40, "Tunnel Rats", 0 } }
    QI:Rebuild()
    assertEq(QI:ByNpcId(40).quests[1].objIndex, 1)
  end)
  it("falls back to every objective of the type when nothing matches", function()
    setup()
    db.npc[40].name = "Renamed"
    QI:Rebuild()
    assertEq(#QI:ByNpcId(40).quests, 1, "only unfinished monster objectives")
  end)
  it("learns tooltip mobs for open quests only", function()
    setup()
    QI:Rebuild()
    QI:Learn("Mystery Mob", 100)
    local e = QI:ByName("Mystery Mob")
    assertTrue(e ~= nil)
    assertEq(e.quests[1].questID, 100)
    QI:Learn("Ghost", 999)
    assertNil(QI:ByName("Ghost"))
    QI:Rebuild()
    assertTrue(QI:ByName("Mystery Mob") ~= nil, "learned entries survive rebuilds while quest open")
  end)
  it("debounces rebuild requests and fires a change event", function()
    setup()
    local fired = 0
    ns:On("ULT_QUEST_INDEX_CHANGED", "t", function() fired = fired + 1 end)
    QI:RequestRebuild(); QI:RequestRebuild()
    __advance(0.6)
    assertEq(fired, 1)
    ns:Off("ULT_QUEST_INDEX_CHANGED", "t")
  end)
end)
