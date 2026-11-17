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
-- depend on the character). The quest log's own reward lookup is only used once it has proven
-- itself: right after accepting a quest, its answer must match what the dialog just showed.
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

-- Reward item IDs the quest log reports for a quest (questID-based API), or nil when unavailable.
local function logRewardIds(questId)
  if type(GetNumQuestLogChoices) ~= "function" or type(GetQuestLogChoiceInfo) ~= "function" then return nil end
  local ids = {}
  local okC, choices = pcall(GetNumQuestLogChoices, questId, true)
  if not okC then return nil end
  for i = 1, tonumber(choices) or 0 do
    local ok, _, _, _, _, _, itemId = pcall(GetQuestLogChoiceInfo, i, questId)
    if not (ok and itemId) then return nil end
    ids[#ids + 1] = itemId
  end
  if type(GetNumQuestLogRewards) == "function" and type(GetQuestLogRewardInfo) == "function" then
    local okR, rewards = pcall(GetNumQuestLogRewards, questId)
    for i = 1, okR and tonumber(rewards) or 0 do
      local ok, _, _, _, _, _, itemId = pcall(GetQuestLogRewardInfo, i, questId)
      if not (ok and itemId) then return nil end
      ids[#ids + 1] = itemId
    end
  end
  return ids
end

-- Log reward links for a quest, only once the lookup has been verified against a dialog.
function QG:LogRewardLinks(questId)
  if not (ns.global and ns.global.logRewardsTrusted == true) then return nil end
  if not (ns.QuestIndex and ns.QuestIndex:QuestInfo(questId)) then return nil end
  local ids = logRewardIds(questId)
  if not ids then return nil end
  local links = {}
  for i, id in ipairs(ids) do links[i] = "item:" .. id end
  return links
end

local function idOf(link) return tonumber(string.match(tostring(link), "item:(%d+)")) end

-- Right after accepting a quest, compare the log's answer with the dialog's. One mismatch and
-- the log lookup is never trusted; a match (with at least one item) trusts it.
function QG:VerifyLogRewards(questId)
  local g = ns.global
  local seen = rememberedRewards(questId)
  if not g or g.logRewardsTrusted == false or not seen or #seen == 0 then return end
  local ids = logRewardIds(questId)
  if not ids then return end
  local want = {}
  for _, link in ipairs(seen) do
    local id = idOf(link)
    if id then want[id] = (want[id] or 0) + 1 end
  end
  local same = #ids == #seen
  for _, id in ipairs(ids) do
    if not want[id] or want[id] == 0 then same = false; break end
    want[id] = want[id] - 1
  end
  g.logRewardsTrusted = same
  self:InvalidateGear()
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
    if ctx then links = ctx.links else links = rememberedRewards(questId) or QG:LogRewardLinks(questId) end
    r.gearWhy = links and nil or "dialog"
    if links then
      local best, why = ns.GearValue:BestUpgrade(links)
      r.gearBest, r.gearWhy = best, why
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
-- opts.short: grades only (no time, no warnings), for small spots like minimap icons.
function QG:Badge(questId, ctx, opts)
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
  local short = opts and opts.short
  if not short and o().show.time and r.seconds then parts[#parts + 1] = "~" .. minutes(r.seconds) .. "m" end
  if not short and o().show.warnings and #r.warnings > 0 then parts[#parts + 1] = "|cffff4040!|r" end
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
  else
    local why = rawFor(questId, ctx).gearWhy
    add(why == "noscorer" and L.GRADE_GEAR_NOSCORER or why == "loading" and L.GRADE_GEAR_LOADING
      or L.GRADE_GEAR_DIALOG, gold)
  end
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
    surfaces = { dialog = true, questLog = true, tracker = true, minimap = true, worldMap = true },
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
    ns:On("QUEST_ACCEPTED", QG, function(_, a, b)
      local questId = b or a
      C_Timer.After(1, function() ns.SafeCall(QG.VerifyLogRewards, QG, questId) end)
    end)
    ns:On("ULT_SETTING_CHANGED", QG, function(_, path)
      if path and path:find("^questGrades") then QG:Invalidate() end
    end)
    QG:Invalidate()
  end,
  OnDisable = function()
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "QUEST_ACCEPTED",
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
  ctx:Checkbox("questGrades.surfaces.minimap", L.GRADE_SURFACE_MINIMAP, L.GRADE_SURFACE_MINIMAP_TIP)
  ctx:Checkbox("questGrades.surfaces.worldMap", L.GRADE_SURFACE_WORLDMAP, L.GRADE_SURFACE_WORLDMAP_TIP)
  ctx:Checkbox("questGrades.learn", L.GRADE_LEARN, L.GRADE_LEARN_TIP)
  ctx:Button(L.GRADE_RESET_TIMES, L.RESET, function() ns.QuestTimes:Reset(); QG:Invalidate() end)
end
