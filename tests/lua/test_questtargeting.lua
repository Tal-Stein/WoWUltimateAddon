local ns = __ns

UnitLevel = function(unit) if unit == "player" then return 10 end end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
GetCVarBool = function() return true end
local played, notices = {}, {}
PlaySound = function(kit, channel) played[#played + 1] = { kit = kit, channel = channel } end
RaidWarningFrame = {}
RaidNotice_AddMessage = function(_, text) notices[#notices + 1] = text end
SOUNDKIT = { RAID_WARNING = 8959, MAP_PING = 3175, ALARM_CLOCK_WARNING_3 = 12889, IG_QUEST_LIST_OPEN = 875 }

__boot(nil, {})
local QT = ns.QuestTargetingModule
local QI = ns.QuestIndex

local function entry(name, have, need, questID)
  return { name = name, npcIds = {}, quests = { { questID = questID or 100, title = "Kobold Camp", objIndex = 1,
    text = name .. " slain", have = have, need = need } } }
end

local function mob(over)
  local m = { unit = "nameplate1", guid = "Creature-0-1-0-1-40-01", npcId = 40, name = "Kobold", level = 9,
    classification = "normal", dead = false, tapped = false, attackable = true, isPlayer = false }
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end

local function reset()
  QI.byNpc, QI.byName = {}, {}
  played, notices = {}, {}
  QT.gate = ns.AlertGate.new(ns.db.questTargeting.alerts)
end

describe("QuestTargeting provider", function()
  it("is registered as an enabled-by-default module", function()
    assertTrue(ns.Modules:IsEnabled("questTargeting"))
    assertTrue(ns.Targeting.providers.quest ~= nil, "provider registered on enable")
  end)
  it("test_provider_builds_candidates", function()
    reset()
    QI.byNpc[40] = entry("Kobold", 4, 10)
    local list = QT.Candidates({ mob(), mob({ guid = "Creature-0-1-0-1-40-02", tapped = true }), mob({ npcId = 99, name = "Wolf" }) })
    assertEq(#list, 1, "tapped and irrelevant mobs excluded")
    assertEq(list[1].name, "Kobold")
    assertEq(list[1].remaining, 6)
    assertEq(list[1].kind, "quest")
    assertFalse(list[1].pinned)
  end)
  it("falls back to name lookup and honours pins and ignores", function()
    reset()
    QI.byName.Kobold = entry("Kobold", 1, 2, 7)
    ns.db.questTargeting.pinned[7] = true
    local list = QT.Candidates({ mob({ npcId = nil }) })
    assertTrue(list[1].pinned)
    ns.db.questTargeting.pinned[7] = nil
    ns.db.questTargeting.ignored[7] = true
    assertEq(#QT.Candidates({ mob({ npcId = nil }) }), 0, "ignored quest contributes nothing")
    ns.db.questTargeting.ignored[7] = nil
  end)
end)

describe("QuestTargeting alerts", function()
  it("test_alert_category_selection", function()
    local o = ns.db.questTargeting.alerts
    assertEq(QT.AlertSound(mob({ level = -1 }), 10), o.sounds.boss)
    assertEq(QT.AlertSound(mob({ classification = "worldboss", level = 20 }), 10), o.sounds.boss)
    assertEq(QT.AlertSound(mob({ classification = "elite" }), 10), o.sounds.elite)
    assertEq(QT.AlertSound(mob(), 10), o.sounds.regular)
    o.levelSounds.enabled = true
    assertEq(QT.AlertSound(mob({ level = 13 }), 10), o.levelSounds.dangerous)
    assertEq(QT.AlertSound(mob({ level = 9 }), 10), o.levelSounds.easy)
    o.levelSounds.enabled = false
  end)
  it("plays a sound and shows text for a new quest mob", function()
    reset()
    QI.byNpc[40] = entry("Kobold", 4, 10)
    QT.OnMobAdded(mob())
    assertEq(#played, 1)
    assertEq(played[1].kit, 3175, "regular = map ping")
    assertEq(played[1].channel, "Master")
    assertTrue(notices[1]:find("Kobold", 1, true) ~= nil)
  end)
  it("test_alert_suppressed_for_tapped_and_cooldown", function()
    reset()
    QI.byNpc[40] = entry("Kobold", 4, 10)
    ns.db.questTargeting.filters.hideTapped = false
    QT.OnMobAdded(mob({ tapped = true }))
    assertEq(#played, 0, "tapped never alerts")
    ns.db.questTargeting.filters.hideTapped = true
    QT.OnMobAdded(mob())
    QT.OnMobAdded(mob())
    QT.OnMobAdded(mob({ guid = "Creature-0-1-0-1-40-09" }))
    assertEq(#played, 1, "GUID and name cooldowns")
    reset()
    ns.db.questTargeting.alerts.enabled = false
    QI.byNpc[40] = entry("Kobold", 4, 10)
    QT.OnMobAdded(mob())
    assertEq(#played, 0, "alerts disabled")
    ns.db.questTargeting.alerts.enabled = true
  end)
  it("does not alert for filtered or irrelevant mobs", function()
    reset()
    QI.byNpc[40] = entry("Kobold", 4, 10)
    QT.OnMobAdded(mob({ level = 30 }))
    QT.OnMobAdded(mob({ npcId = 5, name = "Other" }))
    assertEq(#played, 0)
  end)
end)

describe("QuestTargeting tooltip learning", function()
  it("learns a mob whose tooltip shows an unfinished objective of an open quest", function()
    reset()
    QI.quests = { [100] = { questID = 100, title = "Kobold Camp", objectives = {
      { text = "Candles: 1/8", type = "item", finished = false, numFulfilled = 1, numRequired = 8 } } } }
    Enum = { TooltipDataLineType = { QuestTitle = 17, QuestObjective = 8, QuestPlayer = 18 } }
    C_TooltipInfo = { GetUnit = function() return { lines = {
      { type = 0, leftText = "Tunnel Rat" },
      { type = 17, leftText = "Kobold Camp" },
      { type = 8, leftText = "Candles: 1/8", completed = false },
    } } end }
    QT.LearnFromTooltip(mob({ npcId = 77, name = "Tunnel Rat" }))
    assertTrue(QI:ByName("Tunnel Rat") ~= nil)
  end)
end)

describe("QuestTargeting disable", function()
  it("unregisters its provider", function()
    ns.Modules:SetEnabled("questTargeting", false)
    assertNil(ns.Targeting.providers.quest)
    ns.Modules:SetEnabled("questTargeting", true)
    assertTrue(ns.Targeting.providers.quest ~= nil)
  end)
end)
