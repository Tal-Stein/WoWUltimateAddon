local ADDON, ns = ...
local L = ns.L

-- Quest Grades: how a quest pays off for leveling and for gear, or one grade from a playing
-- style, with a time estimate and warnings. Facts come from ns.QuestFacts / ns.GearValue /
-- ns.QuestTimes; the math lives in ns.Grades. Results are cached until something changes.
local QG = { cache = {}, raw = {} }
ns.QuestGradesModule = QG

local G = ns.Grades

local function o() return ns.db.questGrades end

local COLORS = { "ff4040", "ff8020", "ffd100", "40ff40", "4080ff" }

local function playerLevel() return ns.Safe.read(UnitLevel, "player") end

-- Median base XP of quests at the player's level, ÷ 10 minutes. Cached per level.
local baselines = {}
local function baseline(level)
  if not level then return nil end
  if baselines[level] ~= nil then return baselines[level] or nil end
  local mods = type(QuestieLoader) == "table" and type(QuestieLoader._modules) == "table" and QuestieLoader._modules
  local qxp = mods and type(mods.QuestXP) == "table" and mods.QuestXP
  local values = {}
  for _, row in pairs(qxp and type(qxp.db) == "table" and qxp.db or {}) do
    if type(row) == "table" and row[1] == level and type(row[2]) == "number" and row[2] > 0 then
      values[#values + 1] = row[2]
    end
  end
  if #values == 0 then baselines[level] = false; return nil end
  table.sort(values)
  local mid = (#values + 1) / 2
  local median = (values[math.floor(mid)] + values[math.ceil(mid)]) / 2
  baselines[level] = median / 10
  return baselines[level]
end

-- Rewards seen on the quest dialog, remembered per quest (account-wide; quest rewards don't
-- depend on the character). The log's own reward API can't be trusted to take a quest ID on
-- this client, so quests only get a gear grade once their dialog has been seen.
function QG:RememberRewards(questId, links)
  if not questId or type(links) ~= "table" or not ns.global then return end
  ns.global.questRewards = ns.global.questRewards or {}
  ns.global.questRewards[questId] = links
  self.cache = {}
  for key, r in pairs(self.raw) do
    if key == tostring(questId) then r.gearDone = nil end
  end
end

local function rememberedRewards(questId)
  local store = ns.global and ns.global.questRewards
  return store and store[questId] or nil
end

-- Raw numbers for one quest: facts, estimate (with and without the personal multiplier), XP per
-- minute, gear result.
-- Worked out once per refresh: the comparison set and the personal pace multiplier.
local function candidates()
  if not QG.cands then QG.cands = ns.QuestFacts:Candidates(o().range) end
  return QG.cands
end

local function multiplier()
  if not QG.mult then
    QG.mult = (o().learn and ns.QuestTimes) and ns.QuestTimes:Multiplier() or 1
  end
  return QG.mult
end

local function rawFor(questId, ctx)
  local key = questId .. (ctx and ctx.key or "")
  local r = QG.raw[key]
  if not r then
    local facts = ns.QuestFacts:Get(questId)
    r = { facts = facts }
    if facts then
      r.estimate = G.estimateSeconds(facts, playerLevel())
      r.seconds = r.estimate and math.floor(r.estimate * multiplier() + 0.5) or nil
      r.xp = facts.xp
      if r.xp and r.xp > 0 and r.seconds and r.seconds > 0 then r.xpm = r.xp / (r.seconds / 60) end
    end
    QG.raw[key] = r
  end
  -- Gear is redone on its own when items load or equipment changes.
  if not r.gearDone then
    r.gearDone, r.gear, r.gearBest = true, nil, nil
    local links
    if ctx then links = ctx.links else links = rememberedRewards(questId) end
    if links then
      local best = ns.GearValue:BestUpgrade(links)
      r.gearBest = best
      if best == false then r.gear = "none"
      elseif best then r.gear = G.gearFixed(best.newScore, best.oldScore) end
    end
  end
  return r
end

local function relativeOf(questId, ctx, field)
  local mine = rawFor(questId, ctx)[field]
  if mine == nil then return nil end
  local values = {}
  for _, id in ipairs(candidates()) do
    local v = (id == questId) and mine or rawFor(id)[field]
    if v ~= nil then values[#values + 1] = v end
  end
  return G.relative(mine, values)
end

local function weights()
  local opts = o()
  if opts.style == "custom" then return opts.weights end
  return G.PRESETS[opts.style] or G.PRESETS.balanced
end

local function unifiedScoreOf(questId, ctx, leveling, gear)
  local r = rawFor(questId, ctx)
  local f = r.facts
  if not f then return nil end
  local factors = {
    speed = type(leveling) == "number" and (leveling - 1) / 4 or (leveling == "none" and 0 or nil),
    gear = type(gear) == "number" and (gear - 1) / 4 or (gear == "none" and 0 or nil),
    chain = f.chain and 1 or 0,
    travel = 1 - math.min((f.zones - 1) / 3, 1),
    difficulty = (f.elite or f.group or f.escort) and 0 or 1,
    rep = f.rep and 1 or 0,
  }
  return G.unifiedScore(factors, weights())
end

local function levelingOf(questId, ctx)
  local r = rawFor(questId, ctx)
  if r.xp == 0 then return "none" end
  if not r.xpm then return nil end
  if o().scale == "relative" then return relativeOf(questId, ctx, "xpm") end
  return G.levelingFixed(r.xpm, baseline(playerLevel()))
end

function QG:Grade(questId, ctx)
  if not questId then return nil end
  local key = questId .. (ctx and ctx.key or "")
  if self.cache[key] then return self.cache[key] end
  local r = rawFor(questId, ctx)
  local res = { seconds = r.seconds, estimate = r.estimate, xp = r.xp, gearBest = r.gearBest,
    took = ns.QuestTimes and ns.QuestTimes:Took(questId) or nil, warnings = {} }
  res.leveling = levelingOf(questId, ctx)
  res.gear = r.gear
  if o().mode == "unified" then
    local score = unifiedScoreOf(questId, ctx, res.leveling, res.gear)
    if score then
      if o().scale == "relative" then
        local values = {}
        for _, id in ipairs(candidates()) do
          local s = id == questId and score or unifiedScoreOf(id, nil, levelingOf(id), rawFor(id).gear)
          if s then values[#values + 1] = s end
        end
        res.unified = G.relative(score, values)
      else
        res.unified = G.unifiedFixed(score)
      end
    end
  end
  local f = r.facts
  if f then
    if f.elite then res.warnings[#res.warnings + 1] = "elite" end
    if f.group then res.warnings[#res.warnings + 1] = "group" end
    if f.escort then res.warnings[#res.warnings + 1] = "escort" end
    if f.timed then res.warnings[#res.warnings + 1] = "timed" end
    if f.zones >= 3 then res.warnings[#res.warnings + 1] = "travel" end
  end
  self.cache[key] = res
  return res
end

local function gradeText(g)
  if g == nil then return "?" end
  if g == "none" then return "-" end
  return "|cff" .. COLORS[g] .. g .. "|r"
end

local function minutes(secs) return math.max(1, math.floor(secs / 60 + 0.5)) end

local WARN = { elite = "WARN_ELITE", group = "WARN_GROUP", escort = "WARN_ESCORT", timed = "WARN_TIMED",
  travel = "WARN_TRAVEL" }

-- Compact text for a quest title: "L4 G2 ~8m" or "★4 ~8m", with "!" when there are warnings.
function QG:Badge(questId, ctx)
  local r = self:Grade(questId, ctx)
  if not r then return nil end
  local parts = {}
  if o().mode == "unified" then
    -- Blizzard's star raid marker; the game's fonts have no star character.
    parts[#parts + 1] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t" .. gradeText(r.unified)
  else
    parts[#parts + 1] = "L" .. gradeText(r.leveling)
    parts[#parts + 1] = "G" .. gradeText(r.gear)
  end
  if o().show.time and r.seconds then parts[#parts + 1] = "~" .. minutes(r.seconds) .. "m" end
  if o().show.warnings and #r.warnings > 0 then parts[#parts + 1] = "|cffff4040!|r" end
  return table.concat(parts, " ")
end

local function num(n)
  if type(BreakUpLargeNumbers) == "function" then return BreakUpLargeNumbers(n) end
  return tostring(n)
end

function QG:TooltipLines(questId, ctx)
  local r = self:Grade(questId, ctx)
  if not r then return {} end
  local lines = {}
  local function add(text, c) lines[#lines + 1] = { text, c and c[1] or 1, c and c[2] or 1, c and c[3] or 1 } end
  local gold = { 1, 0.82, 0 }
  if o().mode == "unified" then
    add(string.format(L.GRADE_UNIFIED_LINE, gradeText(r.unified), L["GRADE_STYLE_" .. string.upper(o().style)] or o().style), gold)
  end
  if r.leveling == "none" then add(L.GRADE_LEVELING_NONE, gold)
  elseif r.leveling and r.xp and r.seconds then
    local mins = minutes(r.seconds)
    add(string.format(L.GRADE_LEVELING_LINE, gradeText(r.leveling), num(r.xp), mins,
      num(math.floor(r.xp / (r.seconds / 3600) + 0.5))), gold)
  else add(L.GRADE_LEVELING_UNKNOWN, gold) end
  if r.gear == "none" then add(L.GRADE_GEAR_NONE, gold)
  elseif r.gear and r.gearBest then
    local pct = r.gearBest.oldScore > 0 and math.floor((r.gearBest.newScore / r.gearBest.oldScore - 1) * 100 + 0.5) or 100
    add(string.format(L.GRADE_GEAR_LINE, gradeText(r.gear), r.gearBest.link, pct), gold)
  else add(L.GRADE_GEAR_UNKNOWN, gold) end
  if r.seconds then add(string.format(L.GRADE_TIME, minutes(r.seconds))) else add(L.GRADE_TIME_UNKNOWN) end
  if r.took then
    local rec = ns.global and ns.global.questTimes and ns.global.questTimes[questId]
    local est = rec and rec.estimate
    add(string.format(L.GRADE_TOOK, minutes(r.took), est and tostring(minutes(est)) or "?"))
  else
    local spent = ns.QuestTimes and ns.QuestTimes:Spent(questId)
    if spent and spent >= 60 then add(string.format(L.GRADE_SPENT, minutes(spent))) end
  end
  for _, w in ipairs(r.warnings) do add(L[WARN[w]], { 1, 0.3, 0.3 }) end
  return lines
end

-- Everything: quest facts, estimates, comparison set. (Baselines are per level and stay.)
function QG:Invalidate()
  self.cache, self.raw, self.cands, self.mult = {}, {}, nil, nil
  if ns.QuestFacts then ns.QuestFacts:Invalidate() end
  ns:Fire("ULT_QUEST_GRADES_CHANGED")
end

-- Only gear: items finished loading or equipment changed.
function QG:InvalidateGear()
  self.cache = {}
  for _, r in pairs(self.raw) do r.gearDone = nil end
  ns:Fire("ULT_QUEST_GRADES_CHANGED")
end

-- Coalesce bursts (QUEST_LOG_UPDATE, item info arriving) into one refresh after 0.5 s.
local pending
function QG:RequestInvalidate(kind)
  local wasPending = pending
  if kind == "full" or pending == "full" then pending = "full" else pending = "gear" end
  if wasPending then return end
  C_Timer.After(0.5, function()
    local what = pending
    pending = nil
    if what == "full" then QG:Invalidate() else QG:InvalidateGear() end
  end)
end

local STYLES = {
  { value = "balanced", label = L.GRADE_STYLE_BALANCED },
  { value = "speed", label = L.GRADE_STYLE_SPEED },
  { value = "gear", label = L.GRADE_STYLE_GEAR },
  { value = "custom", label = L.GRADE_STYLE_CUSTOM },
}

local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

QG.def = ns.Modules:Register({
  key = "questGrades",
  name = L.MODULE_QUEST_GRADES,
  description = L.MODULE_QUEST_GRADES_DESC,
  defaults = {
    mode = "separate", style = "balanced", weights = copy(G.PRESETS.balanced),
    scale = "fixed", range = 5, learn = true,
    show = { time = true, warnings = true },
    surfaces = { dialog = true, questLog = true, tracker = true },
  },
  OnEnable = function()
    ns.QuestTimes.estimateFor = function(questId)
      local r = QG:Grade(questId)
      return r and r.estimate or nil
    end
    local function full() QG:RequestInvalidate("full") end
    local function gear() QG:RequestInvalidate("gear") end
    ns:On("QUEST_LOG_UPDATE", QG, full)
    ns:On("PLAYER_LEVEL_UP", QG, full)
    ns:On("PLAYER_EQUIPMENT_CHANGED", QG, gear)
    ns:On("GET_ITEM_INFO_RECEIVED", QG, gear)
    ns:On("ULT_SETTING_CHANGED", QG, function(_, path)
      if path and path:find("^questGrades") then QG:Invalidate() end
    end)
    QG:Invalidate()
  end,
  OnDisable = function()
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED",
      "GET_ITEM_INFO_RECEIVED", "ULT_SETTING_CHANGED" }) do
      ns:Off(e, QG)
    end
    ns.QuestTimes.estimateFor = nil
    QG:Invalidate()
  end,
})

function QG.def.BuildSettings(ctx)
  local P = ns.SettingsPanel
  ctx:Header(L.SECTION_GRADES)
  ctx:Dropdown("questGrades.mode", L.GRADE_MODE, {
    { value = "separate", label = L.GRADE_MODE_SEPARATE },
    { value = "unified", label = L.GRADE_MODE_UNIFIED },
  }, L.GRADE_MODE_TIP)
  ctx:Dropdown("questGrades.scale", L.GRADE_SCALE, {
    { value = "fixed", label = L.GRADE_SCALE_FIXED },
    { value = "relative", label = L.GRADE_SCALE_RELATIVE },
  }, L.GRADE_SCALE_TIP)
  ctx:Slider("questGrades.range", L.GRADE_RANGE, 1, 10, 1, P.fmt.levels, L.GRADE_RANGE_TIP)

  ctx:Header(L.SECTION_GRADE_STYLE)
  ctx:Dropdown("questGrades.style", L.GRADE_STYLE, STYLES, L.GRADE_STYLE_TIP)
  for _, f in ipairs(G.FACTORS) do
    ctx:Slider("questGrades.weights." .. f, L["GRADE_WEIGHT_" .. string.upper(f)], 0, 100, 5, P.fmt.int,
      L.GRADE_WEIGHT_TIP)
  end

  ctx:Header(L.SECTION_GRADE_SHOW)
  ctx:Checkbox("questGrades.show.time", L.GRADE_SHOW_TIME)
  ctx:Checkbox("questGrades.show.warnings", L.GRADE_SHOW_WARNINGS)
  ctx:Checkbox("questGrades.surfaces.dialog", L.GRADE_SURFACE_DIALOG)
  ctx:Checkbox("questGrades.surfaces.questLog", L.GRADE_SURFACE_LOG)
  ctx:Checkbox("questGrades.surfaces.tracker", L.GRADE_SURFACE_TRACKER, L.GRADE_SURFACE_TRACKER_TIP)
  ctx:Checkbox("questGrades.learn", L.GRADE_LEARN, L.GRADE_LEARN_TIP)
  ctx:Button(L.GRADE_RESET_TIMES, L.RESET, function() ns.QuestTimes:Reset(); QG:Invalidate() end)
end
