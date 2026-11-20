local ns = __ns

-- The game refuses TargetUnit from add-ons and, during the call, reports the refusal
-- (ADDON_ACTION_FORBIDDEN "TargetUnit()") and shows its warning popup, only when a unit with
-- that name is around. This stub does the same.
local nearby, calls = {}, {}
local withPopup = false
ADDON_ACTION_FORBIDDEN = "%s has been blocked from an action only available to the Blizzard UI."
local popup
local nextHandle, stopped = 100, {}
local function play() nextHandle = nextHandle + 1; return true, nextHandle end
SOUNDKIT = { IG_MAINMENU_CLOSE = 851, IG_MAINMENU_OPEN = 850 }
PlaySound = function() return play() end
StopSound = function(h) stopped[h] = true end

local function showPopup()
  popup.text:SetText(string.format(ADDON_ACTION_FORBIDDEN, "Ultimate"))
  popup:Show()
  play() -- its open sound
  local onShow = popup:GetScript("OnShow")
  if onShow then onShow(popup) end
end
local hasTarget = false
local muted = {}
MuteSoundFile = function(id) muted[id] = true end
UnmuteSoundFile = function(id) muted[id] = nil end
local function stubTargetUnit(name)
  calls[#calls + 1] = name
  -- With a target, a name that matches nothing would clear it: the game refuses (and answers) for every name.
  if not nearby[name] and not hasTarget then return end
  __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "TargetUnit()")
  if withPopup then showPopup() end
end
TargetUnit = stubTargetUnit
UnitLevel = function(unit) if unit == "player" then return 10 end end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
time = time or os.time

__boot(nil, {})
popup = CreateFrame("Frame", "StaticPopup1", UIParent)
popup.text = popup:CreateFontString()
-- Hiding the popup plays its close sound.
local frameHide = popup.Hide
popup.Hide = function(self) frameHide(self); play() end

local LR = ns.LongRange
local QI = ns.QuestIndex
QI.Rebuild = function() end -- these tests set the quest mobs directly

local function entry(name)
  return { name = name, npcIds = {}, quests = { { questID = 99128, title = "Slimy Menace", objIndex = 1,
    text = name .. " slain: 2/4", have = 2, need = 4 } } }
end

local function setup()
  nearby, calls, withPopup, stopped, hasTarget, muted = {}, {}, false, {}, false, {}
  UnitExists = function(u) return u == "target" and hasTarget end
  TargetUnit = stubTargetUnit
  IsInRaid, UnitOnTaxi = nil, nil
  QI.byName = { ["Murloc Streamrunner"] = entry("Murloc Streamrunner"), ["Murloc"] = entry("Murloc") }
  ns.db.rareScanner.watch = { ["Mother Fang"] = true }
  ns.db.targeting.detection = "longRange"
  LR:Reset()
  LR:InstallPopupGuard()
end

local function asked(name)
  for _, n in ipairs(calls) do if n == name then return true end end
  return false
end

describe("Long-range scan (RestedXP's way)", function()
  it("is the default way of finding mobs; nameplates-only stays available", function()
    assertEq(ns.db.targeting.detection, "longRange")
  end)
  it("asks about every wanted name on each scan", function()
    setup()
    LR:Scan(100)
    assertTrue(asked("Murloc Streamrunner") and asked("Murloc") and asked("Mother Fang"))
    assertEq(#calls, 3)
  end)
  it("a name answered during its own call is nearby, and lands on the bar", function()
    setup()
    nearby["Mother Fang"] = true
    LR:Scan(GetTime())
    assertTrue(LR:Found("Mother Fang"))
    assertFalse(LR:Found("Murloc"))
    local c = LR.Candidates({})
    assertEq(#c, 1)
    assertEq(c[1].name, "Mother Fang")
    assertTrue(c[1].farAway)
  end)
  it("accepts the notice even when the client names the function UNKNOWN()", function()
    setup()
    TargetUnit = function(name) if name == "Murloc" then __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "UNKNOWN()") end end
    LR:Scan(GetTime())
    assertTrue(LR:Found("Murloc"))
  end)
  it("ignores notices outside its own calls", function()
    setup()
    LR:Scan(GetTime())
    __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "TargetUnit()")
    assertEq(#LR.Candidates({}), 0)
  end)
  it("stays listed while it keeps answering, and leaves 5 s after it stops", function()
    setup()
    nearby["Murloc"] = true
    for _ = 1, 20 do LR:Scan(GetTime()); __advance(0.25) end
    assertTrue(LR:Found("Murloc"))
    nearby["Murloc"] = nil
    __advance(4); LR:Scan(GetTime())
    assertTrue(LR:Found("Murloc"), "still within 5 s")
    __advance(1.5); LR:Scan(GetTime())
    assertFalse(LR:Found("Murloc"), "gone after 5 s of silence")
  end)
  it("calls TargetUnit by name, so the game reports TargetUnit() rather than UNKNOWN()", function()
    setup()
    local seen
    TargetUnit = function() seen = debug.getinfo(1, "n").name end
    LR:Scan(GetTime())
    assertEq(seen, "TargetUnit")
  end)
  it("doesn't scan in a raid or on a flight path (as RestedXP)", function()
    setup()
    IsInRaid = function() return true end
    LR:Scan(GetTime())
    assertEq(#calls, 0)
    IsInRaid = nil
    UnitOnTaxi = function() return true end
    LR:Scan(GetTime())
    assertEq(#calls, 0)
  end)
  it("does nothing with nameplates only", function()
    setup()
    ns.db.targeting.detection = "nameplates"
    LR:Scan(GetTime())
    assertEq(#calls, 0)
    ns.db.targeting.detection = "longRange"
  end)
  it("leaves out names a nameplate already shows", function()
    setup()
    nearby["Murloc"] = true
    LR:Scan(GetTime())
    assertEq(#LR.Candidates({ { name = "Murloc" } }), 0)
  end)
end)

describe("Long-range scan popup", function()
  it("hides the warning popup, with its sounds muted only during the scan", function()
    setup()
    withPopup = true
    nearby["Murloc"] = true
    local mutedDuring
    local stub = TargetUnit
    TargetUnit = function(n) mutedDuring = muted[567490] and muted[567464]; return stub(n) end
    LR:Scan(GetTime())
    assertTrue(LR:Found("Murloc"))
    assertFalse(popup.shown, "popup hidden")
    assertTrue(mutedDuring, "open and close sounds muted while asking")
    assertNil(muted[567490]); assertNil(muted[567464])
    assertEq(next(stopped), nil, "no other sound is stopped")
  end)
  it("leaves other add-ons' warnings alone", function()
    setup()
    popup.text:SetText(string.format(ADDON_ACTION_FORBIDDEN, "SomeOtherAddon"))
    popup:Show()
    popup:GetScript("OnShow")(popup)
    assertTrue(popup.shown)
  end)
  it("leaves its own warning alone outside a scan", function()
    setup()
    popup.text:SetText(string.format(ADDON_ACTION_FORBIDDEN, "Ultimate"))
    popup:Show()
    popup:GetScript("OnShow")(popup)
    assertTrue(popup.shown)
  end)
end)

describe("Long-range scan and the error log", function()
  it("keeps its own refusals out of the error log", function()
    setup()
    ns.ErrorLog:Clear()
    nearby["Murloc Streamrunner"] = true
    LR:Scan(GetTime())
    assertEq(#(ns.global.errorLog or {}), 0)
  end)
  it("logs Ultimate's other blocked actions", function()
    setup()
    ns.ErrorLog:Clear()
    __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "SomethingElse()")
    assertEq(#(ns.global.errorLog or {}), 1)
  end)
end)

describe("Long-range scan report and diary", function()
  it("reports what it saw in /ult scan", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    LR:Scan(GetTime())
    local lines = {}
    local print = ns.Print
    ns.Print = function(_, fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    ns:Fire("ULT_DEBUG_SCAN")
    ns.Print = print
    local all = table.concat(lines, " | ")
    assertTrue(string.find(all, "Long-range", 1, true) ~= nil, all)
    assertTrue(string.find(all, "Murloc Streamrunner", 1, true) ~= nil, all)
  end)
  it("records each new find, and whether its nameplate showed up", function()
    setup()
    ns.global.scanDiary = {}
    nearby["Mother Fang"] = true
    LR:Scan(GetTime()); __advance(0.25); LR:Scan(GetTime())
    local d = ns.global.scanDiary
    assertEq(#d, 1, "one entry per new find, not per answer")
    assertEq(d[1].name, "Mother Fang")
    LR:NoteNameplate("Mother Fang")
    assertTrue(d[1].confirmed)
  end)
  it("keeps at most 100 entries", function()
    setup()
    ns.global.scanDiary = {}
    for i = 1, 105 do LR:Diary("Mob " .. i, "events") end
    assertEq(#ns.global.scanDiary, 100)
    assertEq(ns.global.scanDiary[1].name, "Mob 6")
  end)
end)

describe("Long-range scan self-test (/ult scan test)", function()
  it("reports whether the game answered for a name no creature has, and leaves no find", function()
    setup()
    local answered = LR:SelfTest()
    assertFalse(answered)
    nearby[LR.TEST_NAME] = true -- a client that answers for anything
    withPopup = true
    answered = LR:SelfTest()
    assertTrue(answered)
    assertFalse(LR:Found(LR.TEST_NAME), "a test is never a find")
    assertFalse(popup.shown, "its popup is hidden too")
  end)
  it("doesn't scan while you have a target (every name would answer), and keeps its finds", function()
    setup()
    nearby["Murloc"] = true
    LR:Scan(GetTime())
    hasTarget = true
    calls = {}
    for _ = 1, 40 do __advance(0.25); LR:Scan(GetTime()) end -- 10 s with a target
    assertEq(#calls, 0)
    assertEq(#LR.Candidates({}), 1, "only Murloc, kept while targeting")
    hasTarget = false
    nearby["Murloc"] = nil
    for _ = 1, 22 do __advance(0.25); LR:Scan(GetTime()) end
    assertFalse(LR:Found("Murloc"), "dropped 5 s after it can be asked again and doesn't answer")
  end)
end)
