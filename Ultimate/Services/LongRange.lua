local ADDON, ns = ...
local L = ns.L

-- Long-range scan, the way RestedXP's guide targeting does it (RXPGuides/Targeting.lua:
-- CheckTargetProximity and its ADDON_ACTION_FORBIDDEN handler), so it behaves the same:
--   * on a short ticker, call TargetUnit(name, true) for every wanted name;
--   * add-ons may not target, so the game refuses, and it reports the refusal
--     (ADDON_ACTION_FORBIDDEN, func "TargetUnit()") during the call only when a unit with that
--     name is in the area around you, far beyond nameplate range;
--   * a name answered during its own call is "nearby"; it stays listed while it keeps answering
--     and drops after MATCH_TIMEOUT seconds without an answer;
--   * the "has been blocked" popup the refusal brings up is hidden and its sounds stopped.
-- Nothing is ever targeted. Found names feed the target bar until their nameplate shows; then
-- the normal nameplate path (levels, filters, markers) takes over.
local LR = { found = {}, scanning = nil, stats = {} }
ns.LongRange = LR

local MATCH_TIMEOUT = 5 -- RestedXP's matchTimeout

local function o() return ns.db.targeting end
function LR.Enabled() return ns.db ~= nil and o().detection == "longRange" end

function LR:Reset()
  self.found, self.scanning = {}, nil
  self.stats = { scans = 0, calls = 0, answers = 0 }
end
LR:Reset()

-- Names worth looking for: quest mobs still needed (not on ignored quests) and watched rares.
local function wantedNames()
  local names = {}
  if ns.Modules:IsActive("questTargeting") then
    local ignored = ns.db.questTargeting.ignored or {}
    for name, entry in pairs(ns.QuestIndex.byName or {}) do
      for _, q in ipairs(entry.quests or {}) do
        if not ignored[q.questID] then names[name] = "quest"; break end
      end
    end
  end
  if ns.Modules:IsActive("rareScanner") then
    for name, on in pairs(ns.db.rareScanner.watch or {}) do
      if on and not names[name] then names[name] = "rare" end
    end
  end
  return names
end
LR.wantedNames = wantedNames

-- Answered within the last MATCH_TIMEOUT seconds?
function LR:Found(name, now)
  local at = self.found[name]
  return at ~= nil and (now or GetTime()) - at <= MATCH_TIMEOUT
end

-- RestedXP's shouldTargetCheck: not in a raid or on a flight path.
local function shouldScan()
  if ns.Safe.read(IsInRaid) then return false end
  if ns.Safe.read(UnitOnTaxi, "player") then return false end
  return true
end

-- Sound handles are sequential. A probe (started and stopped at once, never heard) marks
-- where the count stands, so the popup's own sounds can be stopped and nothing else.
function LR.Probe()
  if type(PlaySound) ~= "function" or type(StopSound) ~= "function" or not SOUNDKIT then return nil end
  local ok, _, handle = pcall(PlaySound, SOUNDKIT.IG_MAINMENU_CLOSE, "SFX")
  if not (ok and type(handle) == "number") then return nil end
  pcall(StopSound, handle)
  return handle
end

-- One scan: ask about every wanted name. Calls are synchronous, so the refusal (and the popup
-- it brings up) for each name arrives while LR.scanning holds that name.
function LR:Scan(now)
  if not self.Enabled() or type(TargetUnit) ~= "function" or not shouldScan() then return end
  now = now or GetTime()
  local names = {}
  for name in pairs(wantedNames()) do names[#names + 1] = name end
  if #names > 0 then
    table.sort(names)
    self.stats.scans = self.stats.scans + 1
    self.mark = self.Probe() -- sounds after this, during the scan, are the popup's
    for _, name in ipairs(names) do
      self.scanning = name
      self.stats.calls = self.stats.calls + 1
      -- Called from a Lua function, never handed to pcall directly: called from pcall the
      -- client can't name it and reports "UNKNOWN()" instead of "TargetUnit()".
      pcall(function() TargetUnit(name, true) end)
    end
    self.scanning, self.mark = nil, nil
  end
  -- Drop names that stopped answering.
  local changed = false
  for name, at in pairs(self.found) do
    if now - at > MATCH_TIMEOUT then self.found[name] = nil; changed = true end
  end
  if changed and ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
end

-- A refusal for the name being asked right now: it's nearby.
function LR:Answer(source)
  local name = self.scanning
  if not name then return false end
  if self.testing then
    self.testing[source] = true
    return true
  end
  local new = not self:Found(name)
  self.found[name] = GetTime()
  self.stats.answers = self.stats.answers + 1
  if new then
    self:Diary(name, source)
    if ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
  end
  return true
end

-- Is this forbidden-action notice the answer to our own scan? (The error log skips those.)
function LR.IsOwnAnswer(addon, func)
  return addon == ADDON and LR.scanning ~= nil
end

ns:On("ADDON_ACTION_FORBIDDEN", LR, function(_, addon, func)
  if addon ~= ADDON or not LR.scanning then return end
  local f = tostring(func)
  if LR.testing then LR.testing.func = f end
  if f == "TargetUnit()" or f == "UNKNOWN()" then LR:Answer("events") end
end)

-- Diary of new finds (UltimateDB.scanDiary, saved on /reload), for diagnosing: when each was
-- found, and whether its nameplate turned up afterwards.
local DIARY_MAX, CONFIRM_WITHIN = 100, 60
LR.openDiary = {}

function LR:Diary(name, source)
  if not ns.global then return end
  ns.global.scanDiary = ns.global.scanDiary or {}
  local d = ns.global.scanDiary
  local e = { name = name, at = (time and time()) or 0, source = source, t = GetTime(),
    hadTarget = ns.Safe.read(UnitExists, "target") and true or false }
  d[#d + 1] = e
  while #d > DIARY_MAX do table.remove(d, 1) end
  self.openDiary[name] = e
  return e
end

function LR:NoteNameplate(name)
  local e = name and self.openDiary[name]
  if e and not e.confirmed and GetTime() - (e.t or 0) <= CONFIRM_WITHIN then
    e.confirmed = true
    e.confirmedAfter = math.floor(GetTime() - e.t + 0.5)
  end
end

ns:On("NAME_PLATE_UNIT_ADDED", LR, function(_, unit)
  local name = ns.Safe.read(UnitName, unit)
  if name then LR:NoteNameplate(name) end
end)

-- Target bar candidates for found names that no nameplate shows yet.
function LR.Candidates(mobs)
  if not LR.Enabled() then return {} end
  local shown = {}
  for _, mob in ipairs(mobs or {}) do if mob.name then shown[mob.name] = true end end
  local list = {}
  for name, kind in pairs(wantedNames()) do
    if not shown[name] and LR:Found(name) then
      local remaining
      local entry = kind == "quest" and ns.QuestIndex.byName[name]
      for _, q in ipairs(entry and entry.quests or {}) do
        local r = (q.need or 0) - (q.have or 0)
        if not remaining or r < remaining then remaining = r end
      end
      list[#list + 1] = { name = name, count = 1, mobs = {}, kind = kind, isRare = kind == "rare",
        remaining = remaining, farAway = true,
        tooltip = function(tt) tt:AddLine(L.LONG_RANGE_FOUND, 0.75, 0.75, 0.75) end }
    end
  end
  return list
end

-- The popup ("Ultimate has been blocked...") comes up during our call. Hide it then, and stop
-- the sounds started since the scan's mark: only the popup's own code ran in between.
function LR.HideQuietly(popup)
  popup:Hide()
  local after = LR.Probe()
  if LR.mark and after and after - LR.mark <= 8 then
    for h = LR.mark + 1, after - 1 do pcall(StopSound, h) end
  end
  LR.mark = after
end

function LR:InstallPopupGuard()
  for i = 1, 4 do
    local popup = _G["StaticPopup" .. i]
    if popup and not popup.ultLongRangeGuard and popup.HookScript then
      popup.ultLongRangeGuard = true
      popup:HookScript("OnShow", function(self)
        if not LR.scanning then return end
        local text = self.text or self.Text
        local mine = ADDON_ACTION_FORBIDDEN and string.format(ADDON_ACTION_FORBIDDEN, ADDON)
        if mine and text and text.GetText and text:GetText() == mine then
          LR:Answer("popups") -- normally the notice already counted it; same name, same time
          LR.HideQuietly(self)
        end
      end)
    end
  end
end

ns:On("PLAYER_LOGIN", LR, function()
  LR:InstallPopupGuard()
  ns.Targeting:RegisterProvider("longRange", LR.Candidates)
  local last = 0
  C_Timer.NewTicker(0.05, function()
    local now = GetTime()
    if now - last >= (o().scanInterval or 0.25) then
      last = now
      ns.SafeCall(LR.Scan, LR, now)
    end
  end)
end)

-- /ult scan test: ask the game about a name no creature has, and report whether it answered
-- and whether you had a target. Run it once with a target and once without.
LR.TEST_NAME = "Nobody Here Qzxv"
function LR:SelfTest()
  local hasTarget = ns.Safe.read(UnitExists, "target") and true or false
  local result = {}
  self.testing = result
  self.mark = self.Probe()
  self.scanning = self.TEST_NAME
  pcall(function() TargetUnit(LR.TEST_NAME, true) end)
  self.scanning, self.testing, self.mark = nil, nil, nil
  local answered = result.events or result.popups
  ns:Print(string.format(L.LONG_RANGE_TEST, hasTarget and L.YES or L.NO,
    answered and L.YES or L.NO, tostring(result.func or "-"), result.popups and L.YES or L.NO))
  return answered and true or false, hasTarget, result
end

ns:On("ULT_DEBUG_SCAN", LR, function()
  local st = LR.stats
  ns:Print(string.format(L.LONG_RANGE_REPORT, LR.Enabled() and L.ON or L.OFF, st.scans or 0,
    st.calls or 0, st.answers or 0))
  local names = {}
  for name in pairs(LR.found) do if LR:Found(name) then names[#names + 1] = name end end
  table.sort(names)
  ns:Print("  " .. (#names > 0 and table.concat(names, ", ") or L.LONG_RANGE_NONE))
end)
