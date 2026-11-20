local ns = __ns

-- The game refuses TargetUnit from add-ons and signals the refusal only when a unit with that
-- name is around: by ADDON_ACTION_FORBIDDEN and/or its warning popup, during the call or just
-- after. This stub can do any of those.
local nearby, calls, mode = {}, {}, "event"
local pendingLate
stopped, lastSound = {}, nil
ADDON_ACTION_FORBIDDEN = "%s has been blocked from an action only available to the Blizzard UI."
local popup
local function showPopup()
  popup.text:SetText(string.format(ADDON_ACTION_FORBIDDEN, "Ultimate"))
  popup:Show()
  local onShow = popup:GetScript("OnShow")
  if onShow then onShow(popup) end
end
TargetUnit = function(name)
  calls[#calls + 1] = name
  if not nearby[name] then return end
  if mode == "event" then __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "TargetUnit()")
  elseif mode == "popup" then showPopup()
  elseif mode == "late" then pendingLate = true
  elseif mode == "both" then -- the notice now, the popup a moment later
    __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "TargetUnit()")
    C_Timer.After(0.6, showPopup)
  end
end
UnitLevel = function(unit) if unit == "player" then return 10 end end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
time = time or os.time

__boot(nil, {})
popup = CreateFrame("Frame", "StaticPopup1", UIParent)
popup.text = popup:CreateFontString()

local LR = ns.LongRange
local QI = ns.QuestIndex
QI.Rebuild = function() end -- these tests set the quest mobs directly; no quest log to rebuild from

local function entry(name)
  return { name = name, npcIds = {}, quests = { { questID = 99128, title = "Slimy Menace", objIndex = 1,
    text = name .. " slain: 2/4", have = 2, need = 4 } } }
end

local function setup()
  nearby, calls, mode, pendingLate = {}, {}, "event", nil
  __inCombat = false
  QI.byName = { ["Murloc Streamrunner"] = entry("Murloc Streamrunner"), ["Murloc"] = entry("Murloc") }
  ns.db.rareScanner.watch = { ["Mother Fang"] = true }
  ns.db.targeting.detection = "longRange"
  LR:Reset()
  LR:InstallPopupGuard()
end

-- Ping every eligible name once (one per call, as the ticker does), letting each answer window
-- close before the next ping.
local function sweep(now)
  for _ = 1, 5 do LR:Ping(now); __advance(1.1) end
end

describe("Long-range scan", function()
  it("is the default way of finding mobs; nameplates-only stays available", function()
    assertEq(ns.DB.defaults.targeting.detection, "longRange")
  end)
  it("pings one name at a time", function()
    setup()
    LR:Ping(100)
    assertEq(#calls, 1)
  end)
  it("finds quest mobs and watched rares from the game's notice", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    nearby["Mother Fang"] = true
    local now = GetTime()
    sweep(now)
    assertTrue(LR:Found("Murloc Streamrunner", now))
    assertTrue(LR:Found("Mother Fang", now))
    assertFalse(LR:Found("Murloc", now))
    local names = {}
    for _, c in ipairs(LR.Candidates({})) do names[c.name] = c end
    assertEq(names["Murloc Streamrunner"].kind, "quest")
    assertTrue(names["Murloc Streamrunner"].farAway)
    assertEq(names["Mother Fang"].kind, "rare")
  end)
  it("also counts the warning popup as an answer, and silences it", function()
    setup()
    mode = "popup"
    local nextHandle = 40
    stopped = {}
    SOUNDKIT = SOUNDKIT or {}
    SOUNDKIT.IG_MAINMENU_CLOSE = SOUNDKIT.IG_MAINMENU_CLOSE or 851
    PlaySound = function() nextHandle = nextHandle + 1; lastSound = nextHandle; return true, nextHandle end
    StopSound = function(h) stopped[h] = true end
    nearby["Murloc Streamrunner"] = true
    sweep(100)
    assertTrue(LR:Found("Murloc Streamrunner", 100))
    assertFalse(popup.shown, "popup hidden")
    assertTrue(stopped[lastSound] and stopped[lastSound - 1] and stopped[lastSound - 2], "its sounds stopped")
    assertEq(LR.stats.popups, 1)
  end)
  it("doesn't ask about the next name while the last answer may still come", function()
    setup()
    LR:Ping(100) -- nobody nearby: no answer yet
    LR:Ping(100)
    assertEq(#calls, 1, "waits for the answer window")
    __advance(1.1)
    LR:Ping(100)
    assertEq(#calls, 2)
  end)
  it("drops a name you clicked when nothing could be targeted, for a minute", function()
    setup()
    nearby["Murloc"] = true -- e.g. only corpses: the game still answers
    sweep(GetTime())
    assertTrue(LR:Found("Murloc"))
    LR:ClickFailed("Murloc")
    sweep(GetTime())
    assertFalse(LR:Found("Murloc"), "kept off the bar although it still answers")
    __advance(61)
    sweep(GetTime())
    assertTrue(LR:Found("Murloc"), "back after a minute if it still answers")
  end)
  it("a refusal reported twice (notice, then popup) counts once and never for the next name", function()
    setup()
    mode = "both"
    nearby["Mother Fang"] = true
    for _ = 1, 25 do
      LR:Ping(GetTime())
      __advance(0.5) -- the ticker's pace
    end
    assertTrue(LR:Found("Mother Fang"))
    assertFalse(LR:Found("Murloc"), "the trailing popup didn't make Murloc a find")
    assertFalse(LR:Found("Murloc Streamrunner"))
    assertFalse(LR.unreliable, "nor the made-up name")
  end)
  it("with a big quest log, a find stays listed continuously and leaves only after two missed answers", function()
    setup()
    for i = 1, 30 do QI.byName["Mob " .. string.format("%02d", i)] = entry("Mob " .. i) end
    nearby["Mob 15"] = true
    local firstSeen
    local gaps = 0
    for _ = 1, 120 do -- 60 s of the ticker
      LR:Ping(GetTime())
      __advance(0.5)
      if LR:Found("Mob 15") then firstSeen = firstSeen or GetTime()
      elseif firstSeen then gaps = gaps + 1 end
    end
    assertTrue(firstSeen ~= nil, "found")
    assertEq(gaps, 0, "never dropped while it keeps answering")
    nearby["Mob 15"] = nil -- it's gone
    local goneAt
    for _ = 1, 60 do
      LR:Ping(GetTime())
      __advance(0.5)
      if not LR:Found("Mob 15") then goneAt = goneAt or GetTime() end
    end
    assertTrue(goneAt ~= nil, "removed once it stops answering")
  end)
  it("checks itself with a made-up name, and stops trusting answers if even that answers", function()
    setup()
    nearby["Murloc"] = true
    local canary
    for _ = 1, 30 do
      LR:Ping(GetTime())
      if calls[#calls] and string.find(calls[#calls], "Ultimate", 1, true) then canary = calls[#calls] end
      __advance(1.1)
    end
    assertTrue(canary ~= nil, "a made-up name gets asked now and then")
    assertTrue(LR:Found("Murloc"))
    assertFalse(LR.unreliable)
    nearby[canary] = true -- this game answers for anything
    for _ = 1, 30 do LR:Ping(GetTime()); __advance(1.1) end
    assertTrue(LR.unreliable)
    assertEq(#LR.Candidates({}), 0, "no finds shown when answers prove nothing")
  end)
  it("credits an answer that arrives just after the ping to the name just pinged", function()
    setup()
    mode = "late"
    nearby["Mother Fang"] = true
    for _ = 1, 5 do
      LR:Ping(100)
      if pendingLate then
        pendingLate = nil
        __fire("ADDON_ACTION_FORBIDDEN", "Ultimate", "TargetUnit()") -- delivered after the call
      end
      __advance(1.1)
    end
    assertTrue(LR:Found("Mother Fang", 100))
    assertFalse(LR:Found("Murloc", 100))
    assertEq(LR.stats.lateEvents, 1)
  end)
  it("doesn't ping what nameplates show, or what it found in the last 10 s", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    LR.visible = { ["Murloc"] = true }
    sweep(100)
    for _, n in ipairs(calls) do assertTrue(n ~= "Murloc", "visible mobs aren't pinged") end
    calls = {}
    sweep(104)
    for _, n in ipairs(calls) do assertTrue(n ~= "Murloc Streamrunner", "found recently: not pinged again") end
  end)
  it("keeps a find listed without gaps by asking again before it runs out", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    sweep(100)
    calls = {}
    sweep(107) -- older than 6 s: asked again, still answers
    local asked = false
    for _, n in ipairs(calls) do if n == "Murloc Streamrunner" then asked = true end end
    assertTrue(asked, "re-asked before it expires")
    assertTrue(LR:Found("Murloc Streamrunner", 120), "listed continuously")
    nearby["Murloc Streamrunner"] = nil
    LR:Ping(114); __advance(1.1)
    LR:Ping(114) -- settles the first re-ask: one miss
    assertTrue(LR:Found("Murloc Streamrunner", 114), "one missed answer doesn't drop it")
    __advance(1.1)
    LR:Ping(114) -- settles the second: two misses in a row
    assertFalse(LR:Found("Murloc Streamrunner", 114), "gone after two missed answers")
  end)
  it("forgets a find once it stops answering", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    sweep(100)
    nearby["Murloc Streamrunner"] = nil
    sweep(111)
    assertFalse(LR:Found("Murloc Streamrunner", 116))
  end)
  it("does nothing with nameplates only, or in combat", function()
    setup()
    ns.db.targeting.detection = "nameplates"
    sweep(100)
    assertEq(#calls, 0)
    ns.db.targeting.detection = "longRange"
    __inCombat = true
    sweep(100)
    assertEq(#calls, 0)
    __inCombat = false
  end)
  it("keeps its own answers out of the error log", function()
    setup()
    ns.ErrorLog:Clear()
    nearby["Murloc Streamrunner"] = true
    sweep(100)
    assertEq(#(ns.global.errorLog or {}), 0)
  end)
  it("leaves other add-ons' warnings alone", function()
    setup()
    popup.text:SetText(string.format(ADDON_ACTION_FORBIDDEN, "SomeOtherAddon"))
    popup:Show()
    popup:GetScript("OnShow")(popup)
    assertTrue(popup.shown)
  end)
  it("reports what it saw in /ult scan", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    sweep(100)
    local lines = {}
    local print = ns.Print
    ns.Print = function(_, fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    ns:Fire("ULT_DEBUG_SCAN")
    ns.Print = print
    local all = table.concat(lines, " | ")
    assertTrue(string.find(all, "Long-range", 1, true) ~= nil, all)
    assertTrue(string.find(all, "Murloc Streamrunner", 1, true) ~= nil, all)
  end)
end)

describe("Long-range scan diary", function()
  it("records each new find with how it was answered, and what happened next", function()
    setup()
    ns.global.scanDiary = {}
    nearby["Mother Fang"] = true
    sweep(GetTime())
    local d = ns.global.scanDiary
    assertEq(#d, 1)
    assertEq(d[1].name, "Mother Fang")
    assertEq(d[1].source, "events")
    assertNil(d[1].confirmed)
    -- its nameplate shows up: confirmed real
    __fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    LR:NoteNameplate("Mother Fang")
    assertTrue(d[1].confirmed)
    LR:ClickFailed("Mother Fang")
    assertTrue(d[1].clickFailed)
  end)
  it("keeps at most 100 entries", function()
    setup()
    ns.global.scanDiary = {}
    for i = 1, 105 do LR:Diary("Mob " .. i, "events") end
    assertEq(#ns.global.scanDiary, 100)
    assertEq(ns.global.scanDiary[1].name, "Mob 6")
  end)
end)
