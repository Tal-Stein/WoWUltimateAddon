local ns = __ns
local QI = ns.QuestIndex
local PN = ns.PartyNeeds

UnitLevel = function(unit) if unit == "player" then return 12 end end
__boot(nil, {})

-- Local quest log: one quest whose item objective the player has already finished.
local log = {}
C_QuestLog = {
  GetNumQuestLogEntries = function() return #log end,
  GetInfo = function(i) return log[i] end,
  GetQuestObjectives = function(id)
    for _, e in ipairs(log) do if e.questID == id then return e.objectives end end
  end,
}

local db = { quest = {}, npc = {}, item = {} }
local function getter(tbl) return { Get = function(id, field) return tbl[id] and tbl[id][field] end } end
LibQuestieDB = {
  RequireContract = function() return true end,
  Quest = getter(db.quest), Npc = getter(db.npc), Item = getter(db.item),
}

-- Questie's shared party quest logs: remoteQuestLogs[questId][playerName][objIndex].
local remote = {}
QuestieLoader = { _modules = { QuestieComms = { remoteQuestLogs = remote } } }
local inGroup = {}
UnitInParty = function(name) return inGroup[name] == true end
UnitInRaid = function() return nil end
UnitIsConnected = function(name) return inGroup[name] == true end

local function setup()
  QI.dbChecked = nil
  for k in pairs(remote) do remote[k] = nil end
  inGroup = { Bob = true }
  log = {
    { title = "Thelsamar Blood Sausages", questID = 418, isHeader = false, objectives = {
      { text = "Boar Intestines: 3/3", type = "item", finished = true, numFulfilled = 3, numRequired = 3 },
    } },
  }
  db.quest[418] = { name = "Thelsamar Blood Sausages", objectives = { [3] = { { 3172, nil, 0 } } } }
  db.quest[33] = { name = "Wolves Across the Border", objectives = { [1] = { { 299, nil, 0 } } } }
  db.item[3172] = { name = "Boar Intestines", npcDrops = { 1190, 1191 } }
  db.npc[1190] = { name = "Mountain Boar" }
  db.npc[1191] = { name = "Mangy Mountain Boar" }
  db.npc[299] = { name = "Young Wolf" }
  ns.db.questTargeting.partyNeeds = true
end

local function needItem(player, fulfilled)
  remote[418] = remote[418] or {}
  remote[418][player] = { [1] = { index = 1, id = 3172, type = "i", fulfilled = fulfilled, required = 3,
    finished = fulfilled == 3 } }
end

describe("Party needs", function()
  it("is on by default", function()
    assertEq(ns.db.questTargeting.partyNeeds, true)
  end)
  it("names the party member in the target's tooltip", function()
    setup()
    needItem("Bob", 1)
    QI:Rebuild()
    local list = ns.QuestTargetingModule.Candidates({ { unit = "nameplate1", guid = "g1", npcId = 1190,
      name = "Mountain Boar", level = 11, classification = "normal", attackable = true } })
    assertEq(#list, 1)
    local lines = {}
    list[1].tooltip({ AddLine = function(_, text) lines[#lines + 1] = text end })
    assertEq(lines[1], "Thelsamar Blood Sausages")
    assertEq(lines[2], "  Bob: Boar Intestines: 1/3")
  end)
  it("targets droppers of an item a party member still needs, though I have mine", function()
    setup()
    needItem("Bob", 1)
    QI:Rebuild()
    local e = QI:ByNpcId(1190)
    assertTrue(e ~= nil, "Mountain Boar indexed for Bob")
    assertTrue(QI:ByNpcId(1191) ~= nil)
    local q = e.quests[1]
    assertEq(q.questID, 418)
    assertEq(q.party, "Bob")
    assertEq(q.have, 1); assertEq(q.need, 3)
    assertEq(q.text, "Boar Intestines: 1/3")
  end)
  it("targets a mob for a quest only the party member has", function()
    setup()
    remote[33] = { Bob = { [1] = { index = 1, id = 299, type = "m", fulfilled = 2, required = 8, finished = false } } }
    QI:Rebuild()
    local e = QI:ByNpcId(299)
    assertTrue(e ~= nil)
    assertEq(e.quests[1].title, "Wolves Across the Border")
    assertEq(e.quests[1].text, "Young Wolf: 2/8")
  end)
  it("skips objectives the party member has finished", function()
    setup()
    needItem("Bob", 3)
    QI:Rebuild()
    assertNil(QI:ByNpcId(1190))
  end)
  it("ignores people who left the group or went offline", function()
    setup()
    needItem("Carl", 0)
    QI:Rebuild()
    assertNil(QI:ByNpcId(1190))
  end)
  it("does nothing when turned off", function()
    setup()
    needItem("Bob", 1)
    ns.db.questTargeting.partyNeeds = false
    QI:Rebuild()
    assertNil(QI:ByNpcId(1190))
  end)
  it("doesn't list my own unfinished objective twice", function()
    setup()
    log[1].objectives[1] = { text = "Boar Intestines: 1/3", type = "item", finished = false, numFulfilled = 1, numRequired = 3 }
    needItem("Bob", 0)
    QI:Rebuild()
    local e = QI:ByNpcId(1190)
    assertEq(#e.quests, 1)
    assertNil(e.quests[1].party, "my own entry wins")
  end)
  it("works without Questie's party data", function()
    setup()
    local saved = QuestieLoader
    QuestieLoader = nil
    QI:Rebuild()
    assertNil(QI:ByNpcId(1190))
    QuestieLoader = saved
  end)
  it("rebuilds when a party member's progress changes", function()
    setup()
    PN:Changed() -- prime the signature
    assertEq(PN:Changed(), false)
    needItem("Bob", 1)
    assertEq(PN:Changed(), true)
    needItem("Bob", 2)
    assertEq(PN:Changed(), true)
    assertEq(PN:Changed(), false)
  end)
end)
