local ADDON, ns = ...

-- Facts about a quest for grading: XP at the player's level, objectives costed as kills, drops
-- and object uses, zones touched, and warnings. Sources: LibQuestieDB, Questie's own modules
-- (QuestXP, DropDB, AvailableQuests, QuestieDB tags; read through QuestieLoader._modules) and
-- the live quest log. Any missing source leaves its fact nil rather than guessed.
local QF = { cache = {} }
ns.QuestFacts = QF

local TAG = { ELITE = 1, RAID = 62, DUNGEON = 81, ESCORT = 84 }

local function dbGet(entity, id, field)
  local lib = LibQuestieDB
  if type(lib) ~= "table" or type(lib[entity]) ~= "table" or type(lib[entity].Get) ~= "function" then
    return nil
  end
  local ok, v = pcall(lib[entity].Get, id, field)
  if ok then return v end
  return nil
end

local function questie(name)
  local loader = QuestieLoader
  local mods = type(loader) == "table" and type(loader._modules) == "table" and loader._modules or nil
  local m = mods and mods[name]
  return type(m) == "table" and m or nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil
end

local function xpFor(questId)
  local qxp = questie("QuestXP")
  local xp = qxp and call(qxp.GetQuestLogRewardXP, qxp, questId)
  return type(xp) == "number" and xp or nil
end

local function dropRate(itemId, npcId)
  local drops = questie("DropDB")
  local r = drops and call(drops.GetItemDroprate, itemId, npcId)
  local rate = type(r) == "table" and tonumber(r[1]) or tonumber(r)
  return rate and rate > 0 and rate or nil
end

local function tagOf(questId)
  local qdb = questie("QuestieDB")
  return qdb and call(qdb.GetQuestTagInfo, questId) or nil
end

-- Live objectives of a type, in log order.
local function liveOfType(questId, kind)
  local q = ns.QuestIndex and ns.QuestIndex:QuestInfo(questId)
  local list = {}
  for _, o in ipairs(q and q.objectives or {}) do
    if o.type == kind then list[#list + 1] = o end
  end
  return list
end

local function firstNpc(field)
  return type(field) == "table" and type(field[1]) == "table" and field[1][1] or nil
end

local function build(questId)
  local name = dbGet("Quest", questId, "name")
  if not name then return nil end
  local f = { questId = questId, name = name, level = dbGet("Quest", questId, "questLevel"),
    xp = xpFor(questId), objectives = {}, elite = false }
  local zones, zoneCount = {}, 0
  local function addZone(npcId)
    local z = npcId and dbGet("Npc", npcId, "zoneID")
    if z and not zones[z] then zones[z] = true; zoneCount = zoneCount + 1 end
  end
  local function npcInfo(npcId)
    local rank = dbGet("Npc", npcId, "rank") or 0
    if rank >= 1 then f.elite = true end
    return dbGet("Npc", npcId, "maxLevel"), rank >= 1
  end

  addZone(firstNpc(dbGet("Quest", questId, "startedBy")))
  local objectives = dbGet("Quest", questId, "objectives")
  objectives = type(objectives) == "table" and objectives or {}

  local liveKills = liveOfType(questId, "monster")
  for i, t in ipairs(objectives[1] or {}) do
    local level, elite = npcInfo(t[1])
    addZone(t[1])
    local live = liveKills[i]
    f.objectives[#f.objectives + 1] = { kind = "kill", count = live and live.numRequired or 1,
      level = level, elite = elite }
  end
  for _ , t in ipairs(objectives[2] or {}) do
    f.objectives[#f.objectives + 1] = { kind = "object", count = 1 }
  end
  local liveItems = liveOfType(questId, "item")
  for i, t in ipairs(objectives[3] or {}) do
    local droppers = dbGet("Item", t[1], "npcDrops") or {}
    local sum, known, level, elite = 0, 0, nil, false
    for _, npcId in ipairs(droppers) do
      local r = dropRate(t[1], npcId)
      if r then sum, known = sum + r, known + 1 end
      local l, e = npcInfo(npcId)
      if l and (not level or l > level) then level = l end
      elite = elite or e
      addZone(npcId)
    end
    local live = liveItems[i]
    if #droppers > 0 then
      f.objectives[#f.objectives + 1] = { kind = "drop", count = live and live.numRequired or 1,
        rate = known > 0 and sum / known or nil, level = level, elite = elite }
    else
      f.objectives[#f.objectives + 1] = { kind = "object", count = live and live.numRequired or 1 }
    end
  end
  addZone(firstNpc(dbGet("Quest", questId, "finishedBy")))
  f.zones = math.max(1, zoneCount)

  local tag = tagOf(questId)
  f.escort = tag == TAG.ESCORT
  f.group = tag == TAG.ELITE or tag == TAG.DUNGEON or tag == TAG.RAID
  f.elite = f.elite or tag == TAG.ELITE
  f.timed = false
  if C_QuestLog and C_QuestLog.GetTimeAllowed and ns.QuestIndex and ns.QuestIndex:QuestInfo(questId) then
    local allowed = ns.Safe.read(C_QuestLog.GetTimeAllowed, questId)
    f.timed = type(allowed) == "number" and allowed > 0
  end
  local nextQ = dbGet("Quest", questId, "nextQuestInChain")
  f.chain = type(nextQ) == "number" and nextQ > 0
  local rep = dbGet("Quest", questId, "reputationReward")
  f.rep = type(rep) == "table" and next(rep) ~= nil
  return f
end

function QF:Get(questId)
  if not questId then return nil end
  local hit = self.cache[questId]
  if hit == nil then
    hit = build(questId) or false
    self.cache[questId] = hit
  end
  return hit or nil
end

function QF:Invalidate() self.cache = {} end

-- Quests to compare against: the log, plus Questie's available quests within ±range levels.
function QF:Candidates(range)
  local ids, seen = {}, {}
  for id in pairs(ns.QuestIndex and ns.QuestIndex:Quests() or {}) do
    ids[#ids + 1] = id; seen[id] = true
  end
  local aq = questie("AvailableQuests")
  local avail = aq and aq.__availableQuests
  local player = ns.Safe.read(UnitLevel, "player")
  if type(avail) == "table" and player then
    for id in pairs(avail) do
      local lvl = not seen[id] and dbGet("Quest", id, "questLevel")
      if type(lvl) == "number" and math.abs(lvl - player) <= (range or 5) then
        ids[#ids + 1] = id; seen[id] = true
      end
    end
  end
  table.sort(ids)
  return ids
end
