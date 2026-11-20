local ADDON, ns = ...
local L = ns.L

-- Long-range scan (the technique RestedXP and unit scanners use): for each wanted name, call
-- TargetUnit(name). Add-ons may not target, so the game always refuses; it reports the refusal
-- (ADDON_ACTION_FORBIDDEN, synchronously) only when a unit with that name is in the client's
-- view range, far beyond nameplates. A refusal therefore means "it's nearby". Nothing is ever
-- targeted. Found names feed the target bar until their nameplate shows; then the normal
-- nameplate path (levels, filters, markers) takes over.
local LR = { found = {}, scanning = false, stats = {} }
ns.LongRange = LR

local HOLD = 60   -- safety limit: a find never re-asked leaves after this long
local REFRESH = 6 -- a find is re-asked after this long, ahead of the round of unfound names
local MISSES = 2  -- a find leaves after this many unanswered re-asks in a row
local FAILED_HOLD = 60 -- a name you clicked that targeted nothing stays off the list this long
-- Self-check: every CANARY_EVERY-th question is about a name no unit can have. If the game
-- answers that, its answers prove nothing, and the scan stops showing finds.
local CANARY, CANARY_EVERY = "Ultimate Probe Qzxv", 10
LR.CANARY = CANARY
-- Answers only count during the call itself; the window just keeps one question at a time.
local WINDOW = 0.05
-- Right after a reload or zoning the game answers for any name, made-up ones included, for a
-- while. So: no questions for WARMUP seconds, then nothing is shown until PASSES self-checks in a
-- row stayed silent. A self-check that answers hides and forgets every find; the scan then
-- checks itself more often (every RECHECK_EVERY-th question) until it's quiet again.
local WARMUP, PASSES, RECHECK_EVERY = 10, 2, 3

local function o() return ns.db.targeting end
function LR.Enabled() return ns.db ~= nil and o().detection == "longRange" end

function LR:Reset()
  self.found, self.visible, self.pending, self.lastName, self.failed, self.misses = {}, nil, nil, nil, {}, {}
  self.stats = { pings = 0, events = 0, lateEvents = 0, popups = 0, canaries = 0 }
  self.unreliable = false
  self.verified, self.passes, self.warmUntil, self.sinceCheck = false, 0, nil, 0
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

local function plateNames()
  local set = {}
  for _, mob in ipairs(ns.Nameplates and ns.Nameplates:All() or {}) do
    if mob.name then set[mob.name] = true end
  end
  return set
end

function LR:Found(name, now)
  local at = self.found[name]
  now = now or GetTime()
  local failedAt = self.failed[name]
  if failedAt and GetTime() - failedAt < FAILED_HOLD then return false end
  return at ~= nil and now - at <= HOLD
end

-- After a click that tried to target `name` (a long-range find): did a living one get targeted?
function LR.AfterClick(name)
  if not name then return end
  -- Failed: nothing got targeted, or only a dead one of that name. Some other mob being targeted
  -- (e.g. the main button's fallback names) says nothing about this find.
  local has = ns.Safe.read(UnitExists, "target")
  local same = has and ns.Safe.read(UnitName, "target") == name
  if not has or (same and ns.Safe.read(UnitIsDead, "target")) then LR:ClickFailed(name) end
end

-- You clicked a long-range find and nothing (alive) got targeted: the answers were probably from
-- corpses or a mob out of reach. Keep that name off the list for a minute.
function LR:ClickFailed(name)
  if not name then return end
  if self.openDiary[name] then self.openDiary[name].clickFailed = true end
  self.failed[name] = GetTime()
  self.found[name] = nil
  if ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
end

-- The ping in flight, if its answer window is still open.
local function pending()
  local p = LR.pending
  if p and GetTime() - p.at <= WINDOW then return p end
  return nil
end

-- Diary of new finds (UltimateDB.scanDiary, saved on /reload): how each was answered and what
-- happened next, so false finds can be told apart from real mobs out of sight.
local DIARY_MAX, CONFIRM_WITHIN = 100, 60
LR.openDiary = {}

function LR:Diary(name, source)
  if not ns.global then return end
  ns.global.scanDiary = ns.global.scanDiary or {}
  local d = ns.global.scanDiary
  local e = { name = name, at = (time and time()) or 0, source = source, selfCheckOk = not self.unreliable,
    pings = self.stats.pings, verified = self.verified }
  e.t = GetTime()
  if self.enteredAt then e.sinceWorld = math.floor(e.t - self.enteredAt + 0.5) end
  local p = self.pending
  if p and p.eventFunc then e.eventFunc = p.eventFunc end
  d[#d + 1] = e
  while #d > DIARY_MAX do table.remove(d, 1) end
  self.openDiary[name] = e
  return e
end

-- A nameplate with this name appeared: the latest find of it, if recent, was a real mob.
function LR:NoteNameplate(name)
  local e = name and self.openDiary[name]
  if e and not e.confirmed and GetTime() - (e.t or 0) <= CONFIRM_WITHIN then
    e.confirmed = true
    e.confirmedAfter = math.floor(GetTime() - e.t + 0.5)
  end
end

local function answer(source)
  local p = pending()
  if not p then return false end
  -- One refusal can be reported twice (the notice, then the popup a moment later): the second
  -- belongs to the same question and is only counted as a duplicate.
  if p.answered then
    LR.stats.duplicates = (LR.stats.duplicates or 0) + 1
    return true
  end
  p.answered = true
  LR.misses[p.name] = nil
  if p.name ~= CANARY and not LR.found[p.name] then LR:Diary(p.name, source) end
  if p.name == CANARY then
    LR.passes = 0
    -- Every find so far came from the same untrustworthy answers: forget them all.
    LR.found, LR.misses = {}, {}
    if not LR.unreliable then
      LR.unreliable = true
      if ns.ErrorLog then ns.ErrorLog:Record("scan", "canary", "The game answered for a made-up name; long-range finds are hidden.") end
    end
    if ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
    return true
  end
  if not LR:Found(p.name, p.now) and ns.Targeting and ns.Targeting.RequestRefresh then
    ns.Targeting:RequestRefresh()
  end
  LR.found[p.name] = p.now
  LR.stats[source] = (LR.stats[source] or 0) + 1
  return true
end

-- Is this forbidden-action notice the answer to our own ping? (The error log skips those.) The
-- client may name the function "UNKNOWN()", so any Ultimate notice inside a ping's window counts.
function LR.IsOwnAnswer(addon, func)
  return addon == ADDON and LR.scanning == true
end

-- Ping the next name that no nameplate shows and that wasn't found recently: one per call, so
-- any answer, during the call or just after, belongs to it.
-- The last question's window has closed: if a find didn't answer its re-ask, count a miss;
-- after MISSES in a row it leaves the list.
function LR:Settle()
  local p = self.pending
  if not p or p.settled or pending() then return end
  p.settled = true
  if p.name == CANARY then
    if not p.answered then
      -- A silent self-check: after PASSES in a row, answers are trusted (again).
      self.passes = self.passes + 1
      if self.passes >= PASSES and (self.unreliable or not self.verified) then
        self.unreliable, self.verified = false, true
        if ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
      end
    end
    return
  end
  if p.answered or not self.found[p.name] then return end
  self.misses[p.name] = (self.misses[p.name] or 0) + 1
  if self.misses[p.name] >= MISSES then
    self.found[p.name], self.misses[p.name] = nil, nil
    if ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
  end
end

function LR:Ping(now)
  if not self.Enabled() or InCombatLockdown() or type(TargetUnit) ~= "function" then return end
  now = now or GetTime()
  if self.warmUntil and GetTime() < self.warmUntil then return end
  -- One question at a time, each with its full answer window, even once answered: a late or
  -- repeated signal then still lands on its own question, never on the next name.
  if pending() then return end
  self:Settle()
  local visible = self.visible or plateNames()
  local due, unfound = {}, {}
  for name in pairs(wantedNames()) do
    local at = self.found[name]
    local failedAt = self.failed[name]
    local suppressed = failedAt and GetTime() - failedAt < FAILED_HOLD
    if not visible[name] and not suppressed then
      if at and now - at >= REFRESH then due[#due + 1] = name
      elseif not at then unfound[#unfound + 1] = name end
    end
  end
  local pick
  local checkEvery = (self.unreliable or not self.verified) and RECHECK_EVERY or CANARY_EVERY
  if #due + #unfound == 0 and self.verified and not self.unreliable then return end
  -- Until trusted, the self-check comes first and often; afterwards every CANARY_EVERY-th time.
  if self.sinceCheck + 1 >= checkEvery or (not self.verified and self.passes == 0 and self.sinceCheck == 0) then
    pick = CANARY
    self.stats.canaries = self.stats.canaries + 1
    self.sinceCheck = 0
  elseif #due > 0 and not (#unfound > 0 and self.newTurn) then
    -- Re-ask the find that's been waiting longest, so the list follows the game's answers.
    table.sort(due, function(a, b) return self.found[a] < self.found[b] end)
    pick = due[1]
  elseif #unfound > 0 then
    table.sort(unfound)
    pick = unfound[1]
    for _, name in ipairs(unfound) do
      if self.lastName and name > self.lastName then pick = name; break end
    end
    self.lastName = pick
  else
    return
  end
  -- Re-asks and new names take turns, so a long list of finds never stops new ones being found.
  if pick ~= CANARY then self.newTurn = not self.newTurn end
  if pick ~= CANARY then self.sinceCheck = self.sinceCheck + 1 end
  self.pending = { name = pick, at = GetTime(), now = now }
  self.stats.pings = self.stats.pings + 1
  -- The refusal is reported during the call (as RestedXP relies on). Only answers that arrive
  -- while the call runs count, so nothing late can be credited to the wrong name.
  -- TargetUnit is called from a Lua function, not handed to pcall directly: called from pcall
  -- the client can't name it and reports "UNKNOWN()". While the call runs, the other frames
  -- listening for the refusal (the game's warning popup among them) are switched off, so our
  -- own refusal shows no popup and plays no sound; they're switched back on right after, so
  -- every other warning still shows. No Blizzard table is written (that would spread taint).
  local muted = LR.MuteOthers()
  self.scanning = true
  pcall(function() TargetUnit(pick, true) end)
  self.scanning = false
  LR.Unmute(muted)
end

-- Frames other than ours registered for ADDON_ACTION_FORBIDDEN, switched off for one call.
function LR.MuteOthers()
  local frames = {}
  if type(GetFramesRegisteredForEvent) == "function" then
    local list = { pcall(GetFramesRegisteredForEvent, "ADDON_ACTION_FORBIDDEN") }
    if list[1] then for i = 2, #list do frames[#frames + 1] = list[i] end end
  elseif UIParent then
    frames[1] = UIParent
  end
  local muted = {}
  for _, f in ipairs(frames) do
    if f ~= ns.eventFrame and type(f) == "table" and f.UnregisterEvent
        and (not f.IsEventRegistered or f:IsEventRegistered("ADDON_ACTION_FORBIDDEN")) then
      if pcall(f.UnregisterEvent, f, "ADDON_ACTION_FORBIDDEN") then muted[#muted + 1] = f end
    end
  end
  return muted
end

function LR.Unmute(muted)
  for _, f in ipairs(muted or {}) do pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN") end
end

ns:On("NAME_PLATE_UNIT_ADDED", LR, function(_, unit)
  local name = ns.Safe.read(UnitName, unit)
  if name then LR:NoteNameplate(name) end
end)

ns:On("ADDON_ACTION_FORBIDDEN", LR, function(_, addon, func)
  local p = pending()
  if addon == ADDON and p and not p.eventFunc then
    p.eventFunc = (LR.scanning and "" or "late:") .. tostring(func) -- for the diary
  end
  -- Only a notice that arrives during our own call is an answer. "UNKNOWN()" is accepted too,
  -- in case the client can't name the function.
  local f = tostring(func)
  if addon == ADDON and (string.find(f, "TargetUnit", 1, true) or f == "UNKNOWN()") then
    if LR.scanning then answer("events") else LR.stats.lateEvents = (LR.stats.lateEvents or 0) + 1 end
  end
end)

-- Target bar candidates for found names that no nameplate shows yet.
function LR.Candidates(mobs)
  if not LR.Enabled() or LR.unreliable or not LR.verified then return {} end
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

-- Showing and hiding the popup plays the menu open/close sounds. Sound handles are
-- sequential, so a silent probe (a sound started and stopped at once) marks where the count
-- stands. Only handles proven to be the popup's are stopped: those started between two probes
-- with nothing but the popup's own code running in between. Stopping "the last few" blindly
-- also cut off other add-ons' sounds, like Spoken's voice clips.
function LR.Probe()
  if type(PlaySound) ~= "function" or type(StopSound) ~= "function" or not SOUNDKIT then return nil end
  local ok, _, handle = pcall(PlaySound, SOUNDKIT.IG_MAINMENU_CLOSE, "SFX")
  if not (ok and type(handle) == "number") then return nil end
  pcall(StopSound, handle)
  return handle
end

local function stopBetween(from, to)
  if not (from and to) or to - from > 6 then return end -- never a wide sweep
  for h = from + 1, to - 1 do pcall(StopSound, h) end
end

-- Hide the popup and silence it. `self` is the popup, shown during our ping.
function LR.HideQuietly(popup)
  local before = LR.Probe()
  popup:Hide()
  local after = LR.Probe()
  stopBetween(before, after) -- the close sound
  -- The open sound: only when the popup came up inside our own TargetUnit call, so nothing
  -- else could have started a sound since the probe taken just before it.
  local p = LR.pending
  if LR.scanning and p and p.handle then stopBetween(p.handle, before) end
end

-- The game shows "Ultimate has been blocked..." for every refusal. Hide that popup only right
-- after one of our own pings; any other Ultimate problem (and every other add-on's) still shows,
-- and Blizzard's handler stays registered.
function LR:InstallPopupGuard()
  for i = 1, 4 do
    local popup = _G["StaticPopup" .. i]
    if popup and not popup.ultLongRangeGuard and popup.HookScript then
      popup.ultLongRangeGuard = true
      popup:HookScript("OnShow", function(self)
        if not pending() then return end
        local text = self.text or self.Text
        local mine = ADDON_ACTION_FORBIDDEN and string.format(ADDON_ACTION_FORBIDDEN, ADDON)
        if mine and text and text.GetText and text:GetText() == mine then
          -- Normally switched off during our call (see Ping); if it shows anyway it's ours, but
          -- only one shown during the call itself counts as an answer.
          if LR.scanning then answer("popups") else LR.stats.latePopups = (LR.stats.latePopups or 0) + 1 end
          LR.HideQuietly(self)
        end
      end)
    end
  end
end

-- Each reload or zone change starts a quiet warm-up and a fresh self-check.
ns:On("PLAYER_ENTERING_WORLD", LR, function()
  LR.enteredAt = GetTime()
  LR.warmUntil = GetTime() + WARMUP
  LR.found, LR.misses, LR.pending = {}, {}, nil
  LR.verified, LR.passes, LR.sinceCheck = false, 0, 0
  if ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
end)

ns:On("PLAYER_LOGIN", LR, function()
  LR:InstallPopupGuard()
  ns.Targeting:RegisterProvider("longRange", LR.Candidates)
  local last = 0
  C_Timer.NewTicker(0.1, function()
    local now = GetTime()
    if now - last >= (o().pingInterval or 0.5) then
      last = now
      ns.SafeCall(LR.Ping, LR, now)
    end
  end)
end)

ns:On("ULT_DEBUG_SCAN", LR, function()
  local st = LR.stats
  ns:Print(string.format(L.LONG_RANGE_REPORT, LR.Enabled() and L.ON or L.OFF, st.pings or 0,
    st.events or 0, st.lateEvents or 0, st.popups or 0, st.duplicates or 0))
  ns:Print(string.format(LR.unreliable and L.LONG_RANGE_UNRELIABLE or L.LONG_RANGE_SELFCHECK, st.canaries or 0))
  local names = {}
  for name in pairs(LR.found) do if LR:Found(name) then names[#names + 1] = name end end
  table.sort(names)
  ns:Print("  " .. (#names > 0 and table.concat(names, ", ") or L.LONG_RANGE_NONE))
  local dropped = {}
  for name, at in pairs(LR.failed) do
    if GetTime() - at < 60 then dropped[#dropped + 1] = name end
  end
  table.sort(dropped)
  if #dropped > 0 then ns:Print(string.format(L.LONG_RANGE_DROPPED, table.concat(dropped, ", "))) end
end)
