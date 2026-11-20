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
  elseif mode == "late" then pendingLate = true end
end
UnitLevel = function(unit) if unit == "player" then return 10 end end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
time = time or os.time

__boot(nil, {})
popup = CreateFrame("Frame", "StaticPopup1", UIParent)
popup.text = popup:CreateFontString()

local LR = ns.LongRange
local QI = ns.QuestIndex

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

-- Ping every eligible name once (one per call, as the ticker does).
local function sweep(now)
  for _ = 1, 5 do LR:Ping(now) end
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
    sweep(105)
    for _, n in ipairs(calls) do assertTrue(n ~= "Murloc Streamrunner", "found recently: not pinged again") end
  end)
  it("forgets a find once it stops answering", function()
    setup()
    nearby["Murloc Streamrunner"] = true
    sweep(100)
    nearby["Murloc Streamrunner"] = nil
    sweep(111)
    assertFalse(LR:Found("Murloc Streamrunner", 111))
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
