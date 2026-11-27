local ADDON, ns = ...

-- Records what your kills actually give, per mob (by NPC ID), shared by all your characters in
-- UltimateDB.farmMobs:
--   { kills, copper, items = { [itemID] = qty }, skinned, skins = { [itemID] = qty }, maps = { [uiMapID] = kills } }
-- A kill is any corpse you loot, a PARTY_KILL of yours in the combat log (when the game allows it),
-- or a mob you tagged dying as your target or with its nameplate up; each counts once per GUID.
-- Coin and items come from the loot window's own sources (GetLootSourceInfo), so area loot is
-- split correctly. Loot right after your Skinning cast counts as skinning. Your pace (seconds
-- between kills, breaks over BREAK seconds left out) is kept per character for gold per hour.
local KL = {}
ns.KillLog = KL

local BREAK = 90         -- seconds; longer gaps between kills aren't farming
local CAST_WINDOW = 3    -- seconds between a gathering cast and its loot window
local PICK_POCKET = 921
local SEEN_LIMIT = 5000  -- GUIDs remembered per session before starting over

local seen, looted, skinned = {}, {}, {}
local seenCount = 0
local lastKill, lastCast, windowDone

local function on() return ns.db.farming and ns.db.farming.recordKills ~= false end
local function read(fn, ...) return ns.Safe.read(fn, ...) end

function KL.Stats()
  local g = ns.global
  if not g then return {} end
  g.farmMobs = g.farmMobs or {}
  return g.farmMobs
end

function KL.Pace()
  if type(UltimateCharDB) ~= "table" then return { sum = 0, n = 0 } end
  UltimateCharDB.farmPace = UltimateCharDB.farmPace or { sum = 0, n = 0 }
  return UltimateCharDB.farmPace
end

local function stat(npcID)
  local all = KL.Stats()
  local s = all[npcID]
  if not s then
    s = { kills = 0, copper = 0, items = {}, skinned = 0, skins = {}, maps = {} }
    all[npcID] = s
  end
  return s
end

local function remember(set, guid)
  if seenCount > SEEN_LIMIT then wipe(seen); wipe(looted); wipe(skinned); seenCount = 0 end
  set[guid] = true
  seenCount = seenCount + 1
end

-- Count one kill of the creature `guid` (once per GUID).
function KL.RecordKill(guid)
  if not on() then return end
  local npcID = ns.Units.npcIdFromGuid(guid)
  if not npcID or seen[guid] then return end
  remember(seen, guid)
  local s = stat(npcID)
  s.kills = s.kills + 1
  local mapID = C_Map and read(C_Map.GetBestMapForUnit, "player")
  if mapID then s.maps[mapID] = (s.maps[mapID] or 0) + 1 end
  local now = GetTime()
  if lastKill and now - lastKill <= BREAK then
    local pace = KL.Pace()
    pace.sum, pace.n = pace.sum + (now - lastKill), pace.n + 1
  end
  lastKill = now
end

local function skinningName()
  local info = C_SkillInfo and read(C_SkillInfo.GetSkillLineInfoByID, ns.GatherSkillLines.skinning)
  return type(info) == "table" and info.name or nil
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return read(C_Spell.GetSpellName, id) end
  if GetSpellInfo then return read(GetSpellInfo, id) end
end

-- What this loot window is: "kill", "skin" or nil (pick-pocketing: not a kill).
local function windowKind()
  if lastCast and GetTime() - lastCast.at <= CAST_WINDOW then
    if lastCast.spellID == PICK_POCKET then return nil end
    local skin = skinningName()
    if skin and spellName(lastCast.spellID) == skin then return "skin" end
  end
  return "kill"
end

local function itemID(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

function KL.OnLoot()
  if windowDone or not on() then return end
  windowDone = true
  local kind = windowKind()
  lastCast = nil
  if not kind then return end
  local money = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2
  local counted = {}
  for slot = 1, read(GetNumLootItems) or 0 do
    local slotType = read(GetLootSlotType, slot)
    local id = slotType ~= money and itemID(read(GetLootSlotLink, slot)) or nil
    local sources = { pcall(GetLootSourceInfo, slot) }
    for i = 2, #sources, 2 do
      local guid, qty = sources[i], sources[i + 1]
      local npcID = not ns.Safe.isSecret(guid) and ns.Units.npcIdFromGuid(guid)
      if npcID and type(qty) == "number" and not ns.Safe.isSecret(qty) then
        local s = stat(npcID)
        if kind == "kill" and not looted[guid] then
          counted[guid] = true
          KL.RecordKill(guid)
          if slotType == money then s.copper = s.copper + qty
          elseif id then s.items[id] = (s.items[id] or 0) + qty end
        elseif kind == "skin" and not skinned[guid] then
          counted[guid] = "skin"
          if id then s.skins[id] = (s.skins[id] or 0) + qty end
        end
      end
    end
  end
  for guid, how in pairs(counted) do
    if how == "skin" then
      remember(skinned, guid)
      local s = stat(ns.Units.npcIdFromGuid(guid))
      s.skinned = s.skinned + 1
    else
      remember(looted, guid)
    end
  end
end

local function onCombatLog()
  if not CombatLogGetCurrentEventInfo then return end
  local ok, _, sub, _, source, _, _, _, dest = pcall(CombatLogGetCurrentEventInfo)
  if not ok or sub ~= "PARTY_KILL" or ns.Safe.isSecret(source) or ns.Safe.isSecret(dest) then return end
  if source == read(UnitGUID, "player") or source == read(UnitGUID, "pet") then KL.RecordKill(dest) end
end

-- A mob you tagged, dead as your target or under its nameplate.
local function onHealth(_, unit)
  if type(unit) ~= "string" or not (unit == "target" or unit:find("^nameplate%d")) then return end
  if read(UnitIsDead, unit) and not read(UnitIsTapDenied, unit) and read(UnitCanAttack, "player", unit) then
    KL.RecordKill(read(UnitGUID, unit))
  end
end

function KL.Start()
  ns:On("LOOT_READY", KL, function() KL.OnLoot() end)
  ns:On("LOOT_OPENED", KL, function() KL.OnLoot() end)
  ns:On("LOOT_CLOSED", KL, function() windowDone = false end)
  ns:On("UNIT_SPELLCAST_SUCCEEDED", KL, function(_, unit, _, spellID)
    if unit == "player" then lastCast = { spellID = spellID, at = GetTime() } end
  end)
  -- The combat log may be closed to add-ons (C_CombatLog.IsCombatLogRestricted); kills still
  -- count from loot, targets and nameplates then.
  local restricted = C_CombatLog and C_CombatLog.IsCombatLogRestricted and read(C_CombatLog.IsCombatLogRestricted)
  if not restricted then pcall(ns.On, ns, "COMBAT_LOG_EVENT_UNFILTERED", KL, onCombatLog) end
  ns:On("UNIT_HEALTH", KL, onHealth)
end

function KL.Stop()
  ns:OffAll(KL)
end
