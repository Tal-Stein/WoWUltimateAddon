local ADDON, ns = ...
local L = ns.L

-- Long-range scan (the technique RestedXP and unit scanners use): for each wanted name, call
-- TargetUnit(name). Add-ons may not target, so the game always refuses; it reports the refusal
-- (ADDON_ACTION_FORBIDDEN, synchronously) only when a unit with that name is in the client's
-- view range, far beyond nameplates. A refusal therefore means "it's nearby". Nothing is ever
-- targeted. Found names feed the target bar until their nameplate shows; then the normal
-- nameplate path (levels, filters, markers) takes over.
local LR = { found = {}, scanning = false }
ns.LongRange = LR

local HOLD = 10      -- seconds a find stays valid without a new answer (and between re-pings)
local POPUP_WINDOW = 1 -- seconds after a ping in which "Ultimate was blocked" is our own scan

local function o() return ns.db.targeting end
function LR.Enabled() return ns.db ~= nil and o().detection == "longRange" end

function LR:Reset()
  self.found, self.visible, self.lastScan, self.lastPingAt = {}, nil, nil, nil
end

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
  now = now or self.lastScan or GetTime()
  return at ~= nil and now - at <= HOLD
end

-- One pass: ping every wanted name that no nameplate shows and that wasn't found recently.
function LR:Scan(now)
  if not self.Enabled() or InCombatLockdown() or type(TargetUnit) ~= "function" then return end
  now = now or GetTime()
  self.lastScan = now
  local visible = self.visible or plateNames()
  local before = {}
  for name in pairs(self.found) do before[name] = self:Found(name, now) end
  for name in pairs(wantedNames()) do
    if not visible[name] and not self:Found(name, now) then
      self.current, self.scanning, self.lastPingAt = name, true, GetTime()
      pcall(TargetUnit, name, true)
      self.scanning, self.current = false, nil
    end
  end
  local changed = false
  for name in pairs(self.found) do
    if (before[name] or false) ~= self:Found(name, now) then changed = true end
  end
  if changed and ns.Targeting and ns.Targeting.RequestRefresh then ns.Targeting:RequestRefresh() end
end

ns:On("ADDON_ACTION_FORBIDDEN", LR, function(_, addon, func)
  if LR.scanning and addon == ADDON and string.find(tostring(func), "TargetUnit", 1, true) then
    LR.found[LR.current] = LR.lastScan or GetTime()
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
        if not (LR.lastPingAt and GetTime() - LR.lastPingAt <= POPUP_WINDOW) then return end
        local text = self.text or self.Text
        local mine = ADDON_ACTION_FORBIDDEN and string.format(ADDON_ACTION_FORBIDDEN, ADDON)
        if mine and text and text.GetText and text:GetText() == mine then
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
  C_Timer.NewTicker(0.25, function()
    local now = GetTime()
    if now - last >= (o().scanInterval or 1) then
      last = now
      ns.SafeCall(LR.Scan, LR, now)
    end
  end)
end)
