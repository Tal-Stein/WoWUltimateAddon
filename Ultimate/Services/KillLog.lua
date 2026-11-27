local ADDON, ns = ...

-- Records what your kills actually give, per mob (by NPC ID), shared by all your characters in
-- UltimateDB.farmMobs:
--   { kills, copper, items = { [itemID] = qty }, skinned, skins = { [itemID] = qty }, maps = { [uiMapID] = kills } }
-- A kill is any corpse you loot, a PARTY_KILL of yours in the combat log (when the game allows it),
-- or a mob you fought (on your or your pet's threat list) dying as your target or under its
-- nameplate; each counts once per GUID.
-- Coin and items come from the loot window's own sources (GetLootSourceInfo), so area loot is
-- split correctly. Loot right after you start a Skinning cast counts as skinning; after Pick
-- Pocket it's ignored (casts are noted when sent, before their loot window opens). Your pace (seconds
-- between kills, breaks over BREAK seconds left out) is kept per character for gold per hour.
local KL = {}
ns.KillLog = KL

local BREAK = 90         -- seconds; longer gaps between kills aren't farming
local CAST_WINDOW = 3    -- seconds between a gathering cast and its loot window
local PICK_POCKET = 921
local SEEN_LIMIT = 5000  -- GUIDs remembered per set before starting it over
local WINDOW_RESET = 2   -- seconds after which a loot window that never closed stops blocking

local seen, looted, skinned, fought = {}, {}, {}, {}
local sizes = {}
local lastKill, lastCast, windowAt

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

-- Each set starts over on its own when full, so a reset of `seen` never forgets which corpses
-- were already looted.
local function remember(set, guid)
  if set[guid] then return end
  sizes[set] = (sizes[set] or 0) + 1
  if sizes[set] > SEEN_LIMIT then wipe(set); sizes[set] = 1 end
  set[guid] = true
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
  if ns.FarmSources then ns.FarmSources.Bump() end
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
  if not on() then return end
  -- One window fires LOOT_READY and LOOT_OPENED; a window that never closed stops blocking.
  if windowAt and GetTime() - windowAt < WINDOW_RESET then return end
  windowAt = GetTime()
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
  if next(counted) then if ns.FarmSources then ns.FarmSources.Bump() end end
end

local function onCombatLog()
  if not CombatLogGetCurrentEventInfo then return end
  local ok, _, sub, _, source, _, _, _, dest = pcall(CombatLogGetCurrentEventInfo)
  if not ok or sub ~= "PARTY_KILL" or ns.Safe.isSecret(source) or ns.Safe.isSecret(dest) then return end
  if source == read(UnitGUID, "player") or source == read(UnitGUID, "pet") then KL.RecordKill(dest) end
end

local function onThreatList(unit)
  if not UnitThreatSituation then return false end
  return read(UnitThreatSituation, "player", unit) ~= nil or read(UnitThreatSituation, "pet", unit) ~= nil
end

-- Mobs you fight are noted while alive (on your or your pet's threat list); one of them dead as
-- your target or under its nameplate is a kill. Mobs others killed never were on your list.
local function onHealth(_, unit)
  if type(unit) ~= "string" or not (unit == "target" or unit:find("^nameplate%d")) then return end
  local guid = read(UnitGUID, unit)
  if not guid or not ns.Units.npcIdFromGuid(guid) then return end
  if read(UnitIsDead, unit) then
    if fought[guid] and not read(UnitIsTapDenied, unit) then KL.RecordKill(guid) end
  elseif onThreatList(unit) then
    remember(fought, guid)
  end
end

function KL.Start()
  ns:On("LOOT_READY", KL, function() KL.OnLoot() end)
  ns:On("LOOT_OPENED", KL, function() KL.OnLoot() end)
  ns:On("LOOT_CLOSED", KL, function() windowAt = nil end)
  -- Casts are noted as early as possible: a Pick Pocket or Skinning loot window can open before
  -- UNIT_SPELLCAST_SUCCEEDED arrives.
  local function cast(spellID) lastCast = { spellID = spellID, at = GetTime() } end
  ns:On("UNIT_SPELLCAST_SENT", KL, function(_, unit, _, _, spellID) if unit == "player" then cast(spellID) end end)
  ns:On("UNIT_SPELLCAST_START", KL, function(_, unit, _, spellID) if unit == "player" then cast(spellID) end end)
  ns:On("UNIT_SPELLCAST_SUCCEEDED", KL, function(_, unit, _, spellID) if unit == "player" then cast(spellID) end end)
  -- The combat log may be closed to add-ons (C_CombatLog.IsCombatLogRestricted); kills still
  -- count from loot, targets and nameplates then.
  local restricted = C_CombatLog and C_CombatLog.IsCombatLogRestricted and read(C_CombatLog.IsCombatLogRestricted)
  if not restricted then pcall(ns.On, ns, "COMBAT_LOG_EVENT_UNFILTERED", KL, onCombatLog) end
  ns:On("UNIT_HEALTH", KL, onHealth)
end

function KL.Stop()
  ns:OffAll(KL)
end
