local ADDON, ns = ...
local L = ns.L

-- Targeting service: modules feed candidates (one per mob name), this ranks them and arms one
-- secure macro button ("UltimateTargetButton") bound to a key. Targeting itself always happens
-- on the player's key press or click; the add-on only decides which name the macro targets.
local T = {
  providers = {}, providerOrder = {}, ranked = {}, byName = {}, firstSeen = {},
  cursor = ns.Macro.Cursor.new(), started = false,
}
ns.Targeting = T

ns.DB:RegisterDefaults("targeting", {
  autoArm = true,
  stopInCombat = true,
  fallbacks = 2,
  marker = 0, -- raid target icon index 1-8, 0 = off
  markerSoloOnly = true,
  rareFirst = true,
  ranking = ns.Ranking.defaultCriteria(),
  bar = { enabled = true, max = 6, orientation = "HORIZONTAL", scale = 1, locked = false },
  markers = { enabled = true, size = 40, offset = 10, colorMode = "difficulty", anim = "bob", topOnly = false },
})

local button = CreateFrame("Button", "UltimateTargetButton", UIParent, "SecureActionButtonTemplate")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "/cleartarget [dead]")
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute("useOnKeyDown", false)
button:Hide() -- clicked through its key binding or /click; never shown
T.button = button

local function opts() return ns.db.targeting end

local function markerAllowed()
  local o = opts()
  if (o.marker or 0) <= 0 then return false end
  if o.markerSoloOnly and IsInGroup and ns.Safe.read(IsInGroup) then return false end
  return true
end

function T:BuildMacroText()
  local o = opts()
  return ns.Macro.build(self.ranked, self.cursor:current(), {
    stopInCombat = o.stopInCombat, fallbacks = o.fallbacks, marker = markerAllowed() and o.marker or 0,
  })
end

function T:ApplyMacro()
  local text = self:BuildMacroText()
  if text == self.armedText and not ns.Combat:IsPending("targeting.macro") then return end
  ns.Combat:Run("targeting.macro", function()
    button:SetAttribute("macrotext", text)
    T.armedText = text
  end)
end

function T:RegisterProvider(key, fn)
  if not self.providers[key] then self.providerOrder[#self.providerOrder + 1] = key end
  self.providers[key] = fn
  self:Start()
  self:RequestRefresh()
end

function T:UnregisterProvider(key)
  if not self.providers[key] then return end
  self.providers[key] = nil
  for i = #self.providerOrder, 1, -1 do
    if self.providerOrder[i] == key then table.remove(self.providerOrder, i) end
  end
  self:Refresh()
  if #self.providerOrder == 0 then self:Stop() end
end

local function mergeInto(base, c)
  base.isRare = base.isRare or c.isRare
  base.pinned = base.pinned or c.pinned
  base.count = (base.count or 0) + (c.count or 0)
  if c.level and (not base.level or c.level < base.level) then base.level = c.level end
  if c.remaining and (not base.remaining or c.remaining < base.remaining) then base.remaining = c.remaining end
  if c.healthPct and (not base.healthPct or c.healthPct < base.healthPct) then base.healthPct = c.healthPct end
  for _, m in ipairs(c.mobs or {}) do base.mobs[#base.mobs + 1] = m end
  if c.tooltip then base.tooltips[#base.tooltips + 1] = c.tooltip end
  if c.kind == "rare" then base.kind = "rare" end
end

-- Collect, merge and rank candidates. `force` arms the macro even when auto-arm is off.
function T:Refresh(force)
  local mobs = ns.Nameplates:All()
  local byName, list = {}, {}
  for _, key in ipairs(self.providerOrder) do
    local ok, candidates = ns.SafeCall(self.providers[key], mobs)
    if ok and type(candidates) == "table" then
      for _, c in ipairs(candidates) do
        if c.name then
          local base = byName[c.name]
          if not base then
            base = { name = c.name, count = 0, mobs = {}, tooltips = {}, kind = c.kind }
            byName[c.name] = base
            list[#list + 1] = base
          end
          mergeInto(base, c)
        end
      end
    end
  end
  local now = GetTime()
  local seen = {}
  for _, c in ipairs(list) do
    self.firstSeen[c.name] = self.firstSeen[c.name] or now
    c.firstSeen = self.firstSeen[c.name]
    seen[c.name] = true
  end
  for name in pairs(self.firstSeen) do if not seen[name] then self.firstSeen[name] = nil end end

  local o = opts()
  self.ranked = ns.Ranking.rank(list, { rareFirst = o.rareFirst, criteria = o.ranking })
  self.byName = byName
  self.cursor:set(self.ranked)
  -- With auto-arm off the key still never keeps targeting a name that is no longer a candidate.
  if o.autoArm or force or #self.ranked == 0 then self:ApplyMacro() end
  ns:Fire("ULT_TARGETS_CHANGED", self.ranked, self.byName)
end

function T:RequestRefresh()
  if self.refreshQueued then return end
  self.refreshQueued = true
  C_Timer.After(0.25, function()
    T.refreshQueued = false
    if T.started then T:Refresh() end
  end)
end

function T:OnTargetChanged()
  local name = ns.Safe.read(UnitName, "target")
  if name and self.cursor:onTargetName(name) then
    if opts().autoArm then self:ApplyMacro() end
  end
end

function T:Start()
  if self.started then return end
  self.started = true
  local function request() T:RequestRefresh() end
  ns.Nameplates:AddListener(T, { onAdded = request, onRemoved = request, onRefresh = request })
  ns:On("ULT_QUEST_INDEX_CHANGED", T, request)
  ns:On("ULT_SETTING_CHANGED", T, request)
  ns:On("GROUP_ROSTER_UPDATE", T, request)
  ns:On("PLAYER_TARGET_CHANGED", T, function() T:OnTargetChanged() end)
end

function T:Stop()
  if not self.started then return end
  self.started = false
  ns.Nameplates:RemoveListener(T)
  ns:Off("ULT_QUEST_INDEX_CHANGED", T)
  ns:Off("ULT_SETTING_CHANGED", T)
  ns:Off("GROUP_ROSTER_UPDATE", T)
  ns:Off("PLAYER_TARGET_CHANGED", T)
end

-- Creates or updates the account macro "UltTarget" (/click UltimateTargetButton) for action bars.
function T:CreateActionBarMacro()
  if InCombatLockdown() then
    ns:Print(L.MACRO_IN_COMBAT)
    return false, L.MACRO_IN_COMBAT
  end
  local body = "/click UltimateTargetButton"
  local index = GetMacroIndexByName and GetMacroIndexByName("UltTarget") or 0
  local ok
  if index and index > 0 then
    ok = pcall(EditMacro, index, "UltTarget", 134400, body)
  else
    ok = pcall(CreateMacro, "UltTarget", 134400, body, nil)
  end
  local msg = ok and L.MACRO_CREATED or L.MACRO_FAILED
  ns:Print(msg)
  return ok, msg
end

-- Bindings.xml entry point for "Refresh quest targets".
function Ultimate_Refresh() T:Refresh(true) end

ns:On("ULT_DEBUG_SCAN", T, function() T:Refresh(true) end)
