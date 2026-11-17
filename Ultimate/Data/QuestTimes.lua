local ADDON, ns = ...

-- How long quests actually take the player: online, not-AFK time while a quest is in the log,
-- split evenly between the quests active at that moment. Kept account-wide in UltimateDB.
-- Only quests accepted while this runs are measured, so a record is always a full one.
local QT = {}
ns.QuestTimes = QT

-- Set by the grades module: returns the estimate (seconds) for a quest at turn-in, or nil.
QT.estimateFor = nil

local MIN_RECORDS, MIN_MULT, MAX_MULT = 5, 0.5, 3

local function enabled()
  local o = ns.db and ns.db.questGrades
  return o ~= nil and o.learn ~= false
end

local function store()
  local g = ns.global
  if not g then return nil end
  g.questTimes = g.questTimes or {}
  g.questTimesActive = g.questTimesActive or {}
  return g
end

function QT:Tick(dt)
  if not enabled() or ns.Safe.read(UnitIsAFK, "player") then return end
  local g = store()
  if not g then return end
  local n = 0
  for _ in pairs(g.questTimesActive) do n = n + 1 end
  if n == 0 then return end
  local share = dt / n
  for id, spent in pairs(g.questTimesActive) do g.questTimesActive[id] = spent + share end
end

function QT:Spent(questId)
  local g = store()
  return g and g.questTimesActive[questId] or nil
end

function QT:Took(questId)
  local g = store()
  local r = g and g.questTimes[questId]
  return r and r.spent or nil
end

function QT:Multiplier()
  local g = store()
  local ratios = {}
  for _, r in pairs(g and g.questTimes or {}) do
    if r.spent and r.estimate and r.estimate > 0 then ratios[#ratios + 1] = r.spent / r.estimate end
  end
  if #ratios < MIN_RECORDS then return 1 end
  table.sort(ratios)
  local mid = (#ratios + 1) / 2
  local median = (ratios[math.floor(mid)] + ratios[math.ceil(mid)]) / 2
  return math.max(MIN_MULT, math.min(MAX_MULT, median))
end

function QT:Reset()
  local g = ns.global
  if not g then return end
  g.questTimes, g.questTimesActive = {}, {}
end

ns:On("QUEST_ACCEPTED", QT, function(_, a, b)
  local questId = b or a -- (questId) on modern clients, (logIndex, questId) on older ones
  local g = store()
  if g and type(questId) == "number" and enabled() and g.questTimesActive[questId] == nil then
    g.questTimesActive[questId] = 0
  end
end)

ns:On("QUEST_TURNED_IN", QT, function(_, questId)
  local g = store()
  local spent = g and g.questTimesActive[questId]
  if not spent then return end
  local estimate = QT.estimateFor and ns.Safe.read(QT.estimateFor, questId) or nil
  g.questTimes[questId] = { spent = spent, estimate = estimate }
  g.questTimesActive[questId] = nil
end)

ns:On("QUEST_REMOVED", QT, function(_, questId)
  local g = store()
  if g then g.questTimesActive[questId] = nil end
end)

ns:On("PLAYER_LOGIN", QT, function()
  C_Timer.NewTicker(1, function() QT:Tick(1) end)
end)
