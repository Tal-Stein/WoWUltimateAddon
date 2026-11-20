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

local HOLD = 10   -- seconds a find stays valid without a new answer (and between re-pings)
local WINDOW = 1  -- seconds after a ping in which an answer (notice or popup) belongs to it

local function o() return ns.db.targeting end
function LR.Enabled() return ns.db ~= nil and o().detection == "longRange" end

function LR:Reset()
  self.found, self.visible, self.pending, self.lastName = {}, nil, nil, nil
  self.stats = { pings = 0, events = 0, lateEvents = 0, popups = 0 }
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
  return at ~= nil and now - at <= HOLD
end

-- The ping in flight, if its answer window is still open.
local function pending()
  local p = LR.pending
  if p and GetTime() - p.at <= WINDOW then return p end
  return nil
end

local function answer(source)
  local p = pending()
  if not p then return false end
  if not LR:Found(p.name, p.now) and ns.Targeting and ns.Targeting.RequestRefresh then
    ns.Targeting:RequestRefresh()
  end
  LR.found[p.name] = p.now
  LR.stats[source] = (LR.stats[source] or 0) + 1
  return true
end

-- Is this forbidden-action notice the answer to our own ping? (The error log skips those.)
function LR.IsOwnAnswer(addon, func)
  return addon == ADDON and string.find(tostring(func), "TargetUnit", 1, true) ~= nil and pending() ~= nil
end

-- Ping the next name that no nameplate shows and that wasn't found recently: one per call, so
-- any answer, during the call or just after, belongs to it.
function LR:Ping(now)
  if not self.Enabled() or InCombatLockdown() or type(TargetUnit) ~= "function" then return end
  now = now or GetTime()
  local visible = self.visible or plateNames()
  local names = {}
  for name in pairs(wantedNames()) do
    if not visible[name] and not self:Found(name, now) then names[#names + 1] = name end
  end
  if #names == 0 then return end
  table.sort(names)
  local pick = names[1]
  for _, name in ipairs(names) do
    if self.lastName and name > self.lastName then pick = name; break end
  end
  self.lastName = pick
  self.pending = { name = pick, at = GetTime(), now = now }
  self.stats.pings = self.stats.pings + 1
  self.scanning = true
  pcall(TargetUnit, pick, true)
  self.scanning = false
end

ns:On("ADDON_ACTION_FORBIDDEN", LR, function(_, addon, func)
  if addon == ADDON and string.find(tostring(func), "TargetUnit", 1, true) then
    answer(LR.scanning and "events" or "lateEvents")
  end
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

-- Showing and hiding the popup plays the menu open/close sounds, all within our ping. Sound
-- handles are sequential, so play a probe sound and stop it plus the two before it (the
-- popup's open and close) before they're heard. Same approach as RestedXP's scanner.
function LR.SilenceLastSounds()
  if type(PlaySound) ~= "function" or type(StopSound) ~= "function" or not SOUNDKIT then return end
  local ok, _, handle = pcall(PlaySound, SOUNDKIT.IG_MAINMENU_CLOSE, "SFX")
  if not (ok and type(handle) == "number") then return end
  for h = handle - 2, handle do pcall(StopSound, h) end
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
          answer("popups")
          self:Hide()
          LR.SilenceLastSounds()
        end
      end)
    end
  end
end

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
    st.events or 0, st.lateEvents or 0, st.popups or 0))
  local names = {}
  for name in pairs(LR.found) do if LR:Found(name) then names[#names + 1] = name end end
  table.sort(names)
  ns:Print("  " .. (#names > 0 and table.concat(names, ", ") or L.LONG_RANGE_NONE))
end)
