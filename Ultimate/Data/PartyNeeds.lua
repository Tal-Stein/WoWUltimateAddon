local ADDON, ns = ...

-- What party members still need for their quests, as shared by Questie between group members
-- (QuestieComms.remoteQuestLogs[questId][playerName][objIndex] = { id, type, fulfilled,
-- required, finished }). Only members who run Questie share their progress. This reads
-- Questie's internal module table, so every step is guarded: a missing or reshaped table
-- just means no party needs.
local PN = { signature = nil }
ns.PartyNeeds = PN

local KINDS = { m = "monster", i = "item" }

local function remoteLogs()
  local loader = QuestieLoader
  local mods = type(loader) == "table" and type(loader._modules) == "table" and loader._modules or nil
  local comms = mods and mods.QuestieComms
  local logs = type(comms) == "table" and comms.remoteQuestLogs or nil
  return type(logs) == "table" and logs or nil
end

local function present(name)
  if type(name) ~= "string" then return false end
  local inGroup = ns.Safe.read(UnitInParty, name) or ns.Safe.read(UnitInRaid, name)
  return inGroup and ns.Safe.read(UnitIsConnected, name) and true or false
end

function PN.Enabled()
  local o = ns.db and ns.db.questTargeting
  return o ~= nil and o.partyNeeds == true
end

-- Unfinished objectives of group members who are present:
-- { questID, player, objIndex, kind ("monster"|"item"), id, have, need }
function PN:Needs()
  local list = {}
  local logs = remoteLogs()
  if not logs then return list end
  for questID, players in pairs(logs) do
    if type(questID) == "number" and type(players) == "table" then
      for player, objectives in pairs(players) do
        if type(objectives) == "table" and present(player) then
          for objIndex, o in pairs(objectives) do
            local kind = type(o) == "table" and KINDS[o.type]
            if kind and type(o.id) == "number" and not o.finished then
              list[#list + 1] = { questID = questID, player = player, objIndex = objIndex, kind = kind,
                id = o.id, have = tonumber(o.fulfilled) or 0, need = tonumber(o.required) or 0 }
            end
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if a.questID ~= b.questID then return a.questID < b.questID end
    if a.objIndex ~= b.objIndex then return a.objIndex < b.objIndex end
    return a.player < b.player
  end)
  return list
end

-- True when the party's needs differ from the last call.
function PN:Changed()
  local parts = {}
  for _, n in ipairs(self:Needs()) do
    parts[#parts + 1] = table.concat({ n.questID, n.player, n.objIndex, n.id, n.have, n.need }, ":")
  end
  local sig = table.concat(parts, ";")
  local changed = sig ~= self.signature
  self.signature = sig
  return changed
end

-- Questie updates its party logs from addon messages without an event we can hear, so poll
-- while grouped; only a real change rebuilds the index.
local function tick()
  if not PN.Enabled() then return end
  if PN:Changed() then ns.QuestIndex:RequestRebuild() end
end

local function rebuild() PN.signature = nil; ns.QuestIndex:RequestRebuild() end
ns:On("PLAYER_LOGIN", PN, function() C_Timer.NewTicker(2, tick) end)
ns:On("GROUP_ROSTER_UPDATE", PN, rebuild)
ns:On("ULT_SETTING_CHANGED", PN, function(_, path)
  if path == "questTargeting.partyNeeds" then rebuild() end
end)
