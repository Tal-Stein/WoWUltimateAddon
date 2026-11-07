local ADDON, ns = ...

-- Which mobs matter for the player's open quests.
-- Sources: the live quest log (truth for what's unfinished) + LibQuestieDB (which NPCs satisfy
-- each objective, including item droppers) + tooltip-learned names for DB gaps.
local QI = {
  byNpc = {}, byName = {}, quests = {}, learned = {},
  dbOk = nil, dbChecked = nil, pending = false,
}
ns.QuestIndex = QI

local CONTRACT = 4

local function norm(s)
  if type(s) ~= "string" then return nil end
  return string.lower((string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")))
end

local function db()
  if not QI.dbChecked then
    QI.dbChecked = true
    local lib = LibQuestieDB
    if type(lib) == "table" and type(lib.RequireContract) == "function" then
      local ok, msg = lib.RequireContract(CONTRACT)
      QI.dbOk = ok and true or false
      QI.dbMessage = msg
    else
      QI.dbOk = false
      QI.dbMessage = "QuestieDB not loaded"
    end
    if not QI.dbOk then ns:Fire("ULT_QUESTIEDB_UNAVAILABLE", QI.dbMessage) end
  end
  return QI.dbOk and LibQuestieDB or nil
end

local function dbGet(entity, id, field)
  local lib = db()
  if not lib or not lib[entity] then return nil end
  local ok, v = pcall(lib[entity].Get, id, field)
  if ok then return v end
  return nil
end

-- Read the live quest log: { [questID] = { questID, title, header, logIndex, objectives = {...} } }
local function readLog()
  local quests = {}
  if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return quests end
  local header
  local n = ns.Safe.read(C_QuestLog.GetNumQuestLogEntries) or 0
  for i = 1, n do
    local info = ns.Safe.read(C_QuestLog.GetInfo, i)
    if info then
      if info.isHeader then
        header = info.title
      elseif info.questID and info.title then
        local objectives = ns.Safe.read(C_QuestLog.GetQuestObjectives, info.questID) or {}
        quests[info.questID] = { questID = info.questID, title = info.title, header = header,
          logIndex = i, objectives = objectives }
      end
    end
  end
  return quests
end

-- Find which live objectives a DB objective refers to. QuestieDB tuples carry no objective index
-- (the third/fourth slot is an icon), so match by text: the DB objective text when present,
-- else the NPC/item name, against the live objective text. Only if nothing matches, tie it to
-- every objective of that type.
local function matchObjectives(quest, kind, ...)
  local result = {}
  for i = 1, select("#", ...) do
    local needle = norm((select(i, ...)))
    if needle and needle ~= "" then
      for idx, o in ipairs(quest.objectives) do
        if o.type == kind and norm(o.text) and string.find(norm(o.text), needle, 1, true) then
          result[#result + 1] = { idx, o }
        end
      end
      if #result > 0 then return result end
    end
  end
  for idx, o in ipairs(quest.objectives) do
    if o.type == kind then result[#result + 1] = { idx, o } end
  end
  return result
end

local function addNpc(npcId, quest, objIndex, objective)
  if objective.finished then return end
  local entry = QI.byNpc[npcId]
  if not entry then
    local name = dbGet("Npc", npcId, "name")
    entry = { name = name, npcIds = { [npcId] = true }, quests = {} }
    QI.byNpc[npcId] = entry
    if name and not QI.byName[name] then QI.byName[name] = entry end
  end
  for _, q in ipairs(entry.quests) do
    if q.questID == quest.questID and q.objIndex == objIndex then return end
  end
  entry.quests[#entry.quests + 1] = {
    questID = quest.questID, title = quest.title, objIndex = objIndex, text = objective.text,
    have = objective.numFulfilled or 0, need = objective.numRequired or 0,
  }
  quest.npcNames = quest.npcNames or {}
  if entry.name then quest.npcNames[entry.name] = true end
end

local function droppers(itemId)
  local npcs = {}
  for _, id in ipairs(dbGet("Item", itemId, "npcDrops") or {}) do npcs[#npcs + 1] = id end
  for _, container in ipairs(dbGet("Item", itemId, "itemDrops") or {}) do
    for _, id in ipairs(dbGet("Item", container, "npcDrops") or {}) do npcs[#npcs + 1] = id end
  end
  return npcs
end

local function indexQuest(quest)
  if not db() then return end
  local dbName = dbGet("Quest", quest.questID, "name")
  if not dbName or norm(dbName) ~= norm(quest.title) then return end -- Forever ID drift guard
  local objectives = dbGet("Quest", quest.questID, "objectives")
  if type(objectives) ~= "table" then return end

  for _, t in ipairs(objectives[1] or {}) do -- creatures {npcId, text, icon}
    for _, m in ipairs(matchObjectives(quest, "monster", t[2], dbGet("Npc", t[1], "name"))) do
      addNpc(t[1], quest, m[1], m[2])
    end
  end
  for _, t in ipairs(objectives[5] or {}) do -- kill credit {npcIds, creditNpc, text, icon}
    for _, m in ipairs(matchObjectives(quest, "monster", t[3], dbGet("Npc", t[2], "name"))) do
      for _, id in ipairs(t[1] or {}) do addNpc(id, quest, m[1], m[2]) end
    end
  end
  for _, t in ipairs(objectives[3] or {}) do -- items {itemId, text, icon}
    local matches = matchObjectives(quest, "item", t[2], dbGet("Item", t[1], "name"))
    for _, npcId in ipairs(droppers(t[1])) do
      for _, m in ipairs(matches) do addNpc(npcId, quest, m[1], m[2]) end
    end
  end
end

local function learnedEntry(name, quest)
  local entry = { name = name, npcIds = {}, quests = {}, learned = true }
  for i, o in ipairs(quest.objectives) do
    if not o.finished and (o.type == "monster" or o.type == "item") then
      entry.quests[#entry.quests + 1] = { questID = quest.questID, title = quest.title, objIndex = i,
        text = o.text, have = o.numFulfilled or 0, need = o.numRequired or 0 }
    end
  end
  return entry
end

function QI:Rebuild()
  self.pending = false
  self.byNpc, self.byName = {}, {}
  self.quests = readLog()
  for _, quest in pairs(self.quests) do indexQuest(quest) end
  -- Re-apply tooltip-learned names for quests that are still open with unfinished objectives.
  for name, questID in pairs(self.learned) do
    local quest = self.quests[questID]
    if not quest then
      self.learned[name] = nil
    elseif not self.byName[name] then
      local entry = learnedEntry(name, quest)
      if #entry.quests > 0 then
        self.byName[name] = entry
        quest.npcNames = quest.npcNames or {}
        quest.npcNames[name] = true
      end
    end
  end
  ns:Fire("ULT_QUEST_INDEX_CHANGED")
end

function QI:RequestRebuild()
  if self.pending then return end
  self.pending = true
  C_Timer.After(0.5, function() QI:Rebuild() end)
end

function QI:ByNpcId(npcId) return npcId and self.byNpc[npcId] or nil end
function QI:ByName(name) return name and self.byName[name] or nil end
function QI:QuestInfo(questID) return self.quests[questID] end
function QI:Quests() return self.quests end

-- Every indexed entry once (DB entries plus tooltip-learned ones).
function QI:Entries()
  local out, seen = {}, {}
  for _, e in pairs(self.byNpc) do
    if not seen[e] then seen[e] = true; out[#out + 1] = e end
  end
  for _, e in pairs(self.byName) do
    if not seen[e] then seen[e] = true; out[#out + 1] = e end
  end
  return out
end

-- Level range across a set of NPC ids, from QuestieDB. Returns nil when unknown.
function QI:NpcLevels(npcIds)
  local lo, hi
  for id in pairs(npcIds or {}) do
    local a, b = dbGet("Npc", id, "minLevel"), dbGet("Npc", id, "maxLevel")
    if type(a) == "number" and a > 0 then lo = lo and math.min(lo, a) or a end
    if type(b) == "number" and b > 0 then hi = hi and math.max(hi, b) or b end
  end
  if lo and not hi then hi = lo elseif hi and not lo then lo = hi end
  return lo, hi
end

function QI:QuestNpcNames(questID)
  local q = self.quests[questID]
  return q and q.npcNames or {}
end

-- Record a mob seen with a quest objective in its tooltip (session only).
function QI:Learn(name, questID)
  local quest = self.quests[questID]
  if not name or not quest or self.byName[name] then return false end
  local entry = learnedEntry(name, quest)
  if #entry.quests == 0 then return false end
  self.learned[name] = questID
  self.byName[name] = entry
  quest.npcNames = quest.npcNames or {}
  quest.npcNames[name] = true
  ns:Fire("ULT_QUEST_INDEX_CHANGED")
  return true
end

-- Find an open quest by its title (tooltip lines give titles, not IDs).
function QI:QuestIdByTitle(title)
  local t = norm(title)
  for id, q in pairs(self.quests) do
    if norm(q.title) == t then return id end
  end
end

local function request() QI:RequestRebuild() end
ns:On("PLAYER_LOGIN", QI, request)
ns:On("QUEST_LOG_UPDATE", QI, request)
ns:On("QUEST_ACCEPTED", QI, request)
ns:On("QUEST_REMOVED", QI, request)
ns:On("UNIT_QUEST_LOG_CHANGED", QI, function(_, unit) if unit == "player" then request() end end)
