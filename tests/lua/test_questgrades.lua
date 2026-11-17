local ns = __ns

UnitLevel = function(unit) if unit == "player" then return 11 end end
__boot(nil, {})

local QG = ns.QuestGradesModule
local QI = ns.QuestIndex

local db = { quest = {}, npc = {}, item = {} }
local function getter(tbl) return { Get = function(id, field) return tbl[id] and tbl[id][field] end } end
LibQuestieDB = {
  RequireContract = function() return true end,
  Quest = getter(db.quest), Npc = getter(db.npc), Item = getter(db.item),
}

local xp = {}
local available = {}
local function setup()
  xp = { [418] = 1150, [33] = 400, [77] = 900 }
  for k in pairs(available) do available[k] = nil end
  QuestieLoader = { _modules = {
    QuestXP = { db = { [418] = { 11, 1150 }, [500] = { 11, 1000 }, [501] = { 11, 1200 }, [33] = { 6, 400 } },
      GetQuestLogRewardXP = function(_, id) return xp[id] end },
    DropDB = { GetItemDroprate = function(item, npc)
      local r = ({ [1190] = 31, [1191] = 36 })[npc]
      return item == 3172 and r and { r } or nil
    end },
    AvailableQuests = { __availableQuests = available },
  } }
  GearQuest = nil
  QI.dbChecked = nil
  QI.quests = { [418] = { questID = 418, title = "Thelsamar Blood Sausages", objectives = {
    { text = "Boar Intestines: 0/3", type = "item", finished = false, numFulfilled = 0, numRequired = 3 } } } }
  db.quest[418] = { name = "Thelsamar Blood Sausages", questLevel = 11, objectives = { [3] = { { 3172, nil, 0 } } } }
  db.quest[33] = { name = "Wolves", questLevel = 9, startedBy = { { 197 } }, objectives = { [1] = { { 299, nil, 0 } } },
    objectivesText = { "Kill 1 Young Wolf." } }
  db.quest[77] = { name = "Unknown Drops", questLevel = 11, objectives = { [3] = { { 9999, nil, 0 } } } }
  db.item[3172] = { name = "Boar Intestines", npcDrops = { 1190, 1191 } }
  db.item[9999] = { name = "Mystery", npcDrops = { 1190 } }
  db.npc[1190] = { name = "Mountain Boar", maxLevel = 11, zoneID = 38 }
  db.npc[1191] = { name = "Mangy Mountain Boar", maxLevel = 15, zoneID = 38 }
  db.npc[197] = { name = "Marshal", zoneID = 12 }
  db.npc[299] = { name = "Young Wolf", maxLevel = 3, zoneID = 12 }
  local o = ns.db.questGrades
  o.mode, o.style, o.scale, o.learn = "separate", "balanced", "fixed", false
  QG:Invalidate()
end

describe("QuestGrades module", function()
  it("has the agreed defaults", function()
    local o = ns.db.questGrades
    assertEq(o.mode, "separate"); assertEq(o.scale, "fixed"); assertEq(o.style, "balanced")
    assertEq(o.range, 5); assertTrue(o.learn)
    assertTrue(o.surfaces.tracker); assertTrue(o.surfaces.questLog); assertTrue(o.surfaces.dialog)
  end)
  it("grades leveling on fixed bands", function()
    setup()
    local r = QG:Grade(418)
    -- 9 kills of level-15 boars at 45 s + 90 s travel = 495 s; 1150 XP / 8.25 min = 139 XP/min;
    -- baseline = median level-11 XP 1150 / 10 = 115 → ratio 1.21 → 4
    assertEq(r.seconds, 495)
    assertEq(r.leveling, 4)
    assertNil(r.gear, "no GearQuestForever: unknown")
  end)
  it("says '–' when the quest gives no XP at your level", function()
    setup()
    xp[418] = 0
    assertNil(QG:Grade(418).leveling, "0 below max level is missing data, not 'nothing for you'")
    GetMaxPlayerLevel = function() return 11 end
    QG:Invalidate()
    assertEq(QG:Grade(418).leveling, "none")
    GetMaxPlayerLevel = nil
  end)
  it("says '?' rather than guessing", function()
    setup()
    local r = QG:Grade(77)
    assertNil(r.seconds); assertNil(r.leveling)
    assertTrue(string.find(QG:Badge(77), "?", 1, true) ~= nil)
  end)
  it("ranks relative to other options when asked", function()
    setup()
    available[33] = true
    ns.db.questGrades.scale = "relative"
    QG:Invalidate()
    assertEq(QG:Grade(33).leveling, 5)
    assertEq(QG:Grade(418).leveling, 1)
  end)
  it("gives one grade from a playing style in unified mode", function()
    setup()
    QG:RememberRewards(418, {}) -- the dialog showed no rewards: Gear "none"
    ns.db.questGrades.mode = "unified"
    ns.db.questGrades.style = "speed"
    ns:Fire("ULT_SETTING_CHANGED", "questGrades.style")
    local speedy = QG:Grade(418).unified
    ns.db.questGrades.style = "gear"
    ns:Fire("ULT_SETTING_CHANGED", "questGrades.style")
    local geary = QG:Grade(418).unified
    assertTrue(speedy and geary and speedy > geary, tostring(speedy) .. " vs " .. tostring(geary))
    assertEq(QG:Grade(418).gear, "none")
    ns.global.questRewards[418] = nil
  end)
  it("uses the custom weights", function()
    setup()
    ns.db.questGrades.mode = "unified"
    ns.db.questGrades.style = "custom"
    for k in pairs(ns.db.questGrades.weights) do ns.db.questGrades.weights[k] = 0 end
    ns.db.questGrades.weights.difficulty = 100
    ns:Fire("ULT_SETTING_CHANGED", "questGrades.weights.difficulty")
    assertEq(QG:Grade(418).unified, 5, "solo-friendly is all that counts")
  end)
  it("shows a compact badge and a tooltip", function()
    setup()
    local badge = string.gsub(string.gsub(QG:Badge(418), "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
    assertTrue(string.find(badge, "L4", 1, true) ~= nil, badge)
    assertTrue(string.find(badge, "G?", 1, true) ~= nil, badge)
    assertTrue(string.find(badge, "8m", 1, true) ~= nil, badge)
    local found
    for _, line in ipairs(QG:TooltipLines(418)) do
      if string.find(line[1], "XP", 1, true) then found = true end
    end
    assertTrue(found)
  end)
  it("shows '?' for a past estimate it doesn't have", function()
    setup()
    ns.global.questTimes = { [418] = { spent = 600 } }
    local found
    for _, line in ipairs(QG:TooltipLines(418)) do
      if string.find(line[1], "est. ?", 1, true) then found = true end
    end
    assertTrue(found)
    ns.global.questTimes = {}
  end)
  it("works out the comparison set once per refresh", function()
    setup()
    available[33] = true
    ns.db.questGrades.scale = "relative"
    ns.db.questGrades.mode = "unified"
    QG:Invalidate()
    local orig, calls = ns.QuestFacts.Candidates, 0
    ns.QuestFacts.Candidates = function(...) calls = calls + 1; return orig(...) end
    QG:Grade(418); QG:Grade(33); QG:Badge(418); QG:TooltipLines(33)
    ns.QuestFacts.Candidates = orig
    assertEq(calls, 1)
  end)
  it("re-checks only gear when an item finishes loading", function()
    setup()
    QG:Grade(418)
    local orig, wiped = ns.QuestFacts.Invalidate, false
    ns.QuestFacts.Invalidate = function(...) wiped = true; return orig(...) end
    __fire("GET_ITEM_INFO_RECEIVED", 100, true)
    __advance(0.6)
    ns.QuestFacts.Invalidate = orig
    assertFalse(wiped, "quest facts kept")
  end)
  it("uses only characters the game's fonts have", function()
    setup()
    local function plain(text)
      return not string.find((string.gsub(text, "|T.-|t", "")), "[\128-\255]")
    end
    xp[418] = 0
    GetMaxPlayerLevel = function() return 11 end
    QG:Invalidate()
    for _, mode in ipairs({ "separate", "unified" }) do
      ns.db.questGrades.mode = mode
      QG:Invalidate()
      for _, id in ipairs({ 418, 77 }) do
        assertTrue(plain(QG:Badge(id)), mode .. " badge: " .. QG:Badge(id))
        for _, line in ipairs(QG:TooltipLines(id)) do assertTrue(plain(line[1]), line[1]) end
      end
    end
    GetMaxPlayerLevel = nil
  end)
  it("says why gear is unknown", function()
    setup()
    local function gearLine(id)
      for _, line in ipairs(QG:TooltipLines(id)) do
        if string.find(line[1], "Gear", 1, true) then return line[1] end
      end
    end
    assertTrue(string.find(gearLine(418), "quest dialog", 1, true) ~= nil, gearLine(418))
  end)
  it("trusts the quest log's rewards only after they match what the dialog showed", function()
    setup()
    ns.global.questRewards, ns.global.logRewardsTrusted = {}, nil
    local logItems = { [418] = { 100 }, [33] = { 200 } }
    GetNumQuestLogChoices = function(questID) return #(logItems[questID] or {}) end
    GetNumQuestLogRewards = function() return 0 end
    GetQuestLogChoiceInfo = function(i, questID)
      local id = logItems[questID] and logItems[questID][i]
      return "Item", 0, 1, 2, true, id
    end
    QG:RememberRewards(418, { "|cff1eff00|Hitem:100::::|h[Gloves]|h|r" })
    QI.quests[33] = { questID = 33, title = "Wolves", objectives = {} }
    assertNil(QG:LogRewardLinks(33), "not trusted yet")
    __fire("QUEST_ACCEPTED", 418)
    __advance(1.1)
    assertTrue(ns.global.logRewardsTrusted)
    QI.quests = { [33] = { questID = 33, title = "Wolves", objectives = {} } } -- the rebuilt log
    assertEq(QG:LogRewardLinks(33)[1], "item:200")
    logItems[418] = { 999 } -- disagrees with the dialog
    ns.global.logRewardsTrusted = nil
    __fire("QUEST_ACCEPTED", 418)
    __advance(1.1)
    assertEq(ns.global.logRewardsTrusted, false)
    assertNil(QG:LogRewardLinks(33))
    GetNumQuestLogChoices, GetNumQuestLogRewards, GetQuestLogChoiceInfo = nil, nil, nil
    ns.global.logRewardsTrusted = nil
  end)
  it("has a short badge for the minimap: grades only", function()
    setup()
    assertTrue(ns.db.questGrades.surfaces.minimap, "minimap on by default")
    local short = QG:Badge(418, nil, { short = true })
    assertTrue(string.find(short, "m", 1, true) == nil, short)
    assertTrue(string.find(short, "L", 1, true) ~= nil, short)
  end)
  it("hides time when asked", function()
    setup()
    ns.db.questGrades.show.time = false
    ns:Fire("ULT_SETTING_CHANGED", "questGrades.show.time")
    assertTrue(string.find(QG:Badge(418), "m", 1, true) == nil)
    ns.db.questGrades.show.time = true
  end)
end)
