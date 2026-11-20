local ns = __ns

-- The game refuses TargetUnit from add-ons, and reports the refusal (synchronously) only when a
-- unit with that name is around. This stub does the same.
local nearby, calls = {}, {}
TargetUnit = function(name)
  calls[#calls + 1] = name
  if nearby[name] then __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "TargetUnit()") end
end
UnitLevel = function(unit) if unit == "player" then return 10 end end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
time = time or os.time

__boot(nil, {})

local LR = ns.LongRange
local QI = ns.QuestIndex

local function entry(name)
  return { name = name, npcIds = {}, quests = { { questID = 99128, title = "Slimy Menace", objIndex = 1,
    text = name .. " slain: 2/4", have = 2, need = 4 } } }
end

local function setup()
  nearby, calls = {}, {}
  __inCombat = false
  QI.byName = { ["Murloc Streamrunner"] = entry("Murloc Streamrunner"), ["Murloc"] = entry("Murloc") }
  ns.db.rareScanner.watch = { ["Mother Fang"] = true }
  ns.db.targeting.detection = "longRange"
  LR:Reset()
end

describe("Long-range scan", function()
  it("is the default way of finding mobs; nameplates-only stays available", function()
    assertEq(ns.DB.defaults.targeting.detection, "longRange")
  end)
  it("finds quest mobs and watched rares by name before their nameplate shows", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    nearby["Mother Fang"] = true
    LR:Scan(100)
    assertTrue(LR:Found("Murloc Streamrunner"))
    assertTrue(LR:Found("Mother Fang"))
    assertFalse(LR:Found("Murloc"))
    local list = LR.Candidates({})
    local names = {}
    for _, c in ipairs(list) do names[c.name] = c end
    assertTrue(names["Murloc Streamrunner"] ~= nil)
    assertEq(names["Murloc Streamrunner"].kind, "quest")
    assertTrue(names["Murloc Streamrunner"].farAway)
    assertEq(names["Mother Fang"].kind, "rare")
  end)
  it("doesn't scan what nameplates already show, and leaves found names alone for a while", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    LR.visible = { ["Murloc"] = true }
    LR:Scan(100)
    for _, n in ipairs(calls) do assertTrue(n ~= "Murloc", "visible mobs aren't pinged") end
    calls = {}
    LR:Scan(105)
    for _, n in ipairs(calls) do assertTrue(n ~= "Murloc Streamrunner", "found within the last 10 s: not pinged again") end
    assertTrue(LR:Found("Murloc Streamrunner", 105))
  end)
  it("forgets a find once it stops answering", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    LR:Scan(100)
    nearby["Murloc Streamrunner"] = nil
    LR:Scan(111)
    assertFalse(LR:Found("Murloc Streamrunner", 111))
  end)
  it("does nothing with nameplates only, or in combat", function()
    setup()
    ns.db.targeting.detection = "nameplates"
    LR:Scan(100)
    assertEq(#calls, 0)
    ns.db.targeting.detection = "longRange"
    __inCombat = true
    LR:Scan(100)
    assertEq(#calls, 0)
    __inCombat = false
  end)
  it("keeps its own refusals out of the error log", function()
    setup()
    ns.ErrorLog:Clear()
    nearby["Murloc Streamrunner"] = true
    LR:Scan(100)
    assertEq(#(ns.global.errorLog or {}), 0)
    __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "TargetUnit()") -- not during a scan: real problem
    assertEq(#ns.global.errorLog, 1)
  end)
  it("hides only the game's popup about its own scan", function()
    setup()
    ADDON_ACTION_FORBIDDEN = "%s has been blocked from an action only available to the Blizzard UI."
    local popup = CreateFrame("Frame", "StaticPopup1", UIParent)
    popup.text = popup:CreateFontString()
    LR:InstallPopupGuard()
    nearby["Murloc"] = true
    LR:Scan(100) -- a ping just happened
    popup.text:SetText(string.format(ADDON_ACTION_FORBIDDEN, "Ultimate"))
    popup:Show()
    popup:GetScript("OnShow")(popup)
    assertFalse(popup.shown, "our scan's popup hidden")
    popup.text:SetText(string.format(ADDON_ACTION_FORBIDDEN, "SomeOtherAddon"))
    popup:Show()
    popup:GetScript("OnShow")(popup)
    assertTrue(popup.shown, "other add-ons' warnings still show")
  end)
end)
