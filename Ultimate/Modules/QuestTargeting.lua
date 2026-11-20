local ADDON, ns = ...
local L = ns.L

-- Quest Targeting: feeds quest-relevant nearby mobs to the Targeting service (key, bar,
-- markers) and plays an alert when a new one comes into view.
local QT = {}
ns.QuestTargetingModule = QT

local QI = ns.QuestIndex

local function o() return ns.db.questTargeting end

local function relevantQuests(mob)
  local entry = QI:ByNpcId(mob.npcId) or QI:ByName(mob.name)
  if not entry then return nil end
  local ignored = o().ignored
  local quests = {}
  for _, q in ipairs(entry.quests) do
    if not ignored[q.questID] then quests[#quests + 1] = q end
  end
  if #quests == 0 then return nil end
  return quests
end

local function tooltipFor(quests)
  return function(tt)
    for _, q in ipairs(quests) do
      tt:AddLine(q.title, 1, 0.82, 0)
      tt:AddLine("  " .. (q.party and (q.party .. ": ") or "") .. (q.text or ""), 1, 1, 1)
    end
  end
end

-- Candidates for the Targeting service (one per mob; Targeting merges by name).
function QT.Candidates(mobs)
  local level, grey = ns.Alerts.PlayerLevels()
  local filters = o().filters
  local pinned = o().pinned
  local list = {}
  for _, mob in ipairs(mobs) do
    local quests = relevantQuests(mob)
    if quests and ns.Filters.passes(mob, level, grey, filters) and not mob.tapped then
      local remaining, isPinned
      for _, q in ipairs(quests) do
        local r = (q.need or 0) - (q.have or 0)
        if not remaining or r < remaining then remaining = r end
        if pinned[q.questID] then isPinned = true end
      end
      list[#list + 1] = {
        name = mob.name, level = mob.level, remaining = remaining, healthPct = mob.healthPct,
        pinned = isPinned or false, count = 1, mobs = { mob }, kind = "quest", tooltip = tooltipFor(quests),
      }
    end
  end
  return list
end

-- Which sound a newly seen quest mob plays.
function QT.AlertSound(mob, playerLevel)
  local a = o().alerts
  if ns.Levels.isBoss(mob.level, mob.classification) then return a.sounds.boss end
  if mob.classification == "elite" or mob.classification == "rareelite" then return a.sounds.elite end
  if a.levelSounds.enabled then
    local grey = ns.Levels.greyLevel(playerLevel)
    local bucket = ns.Levels.bucket(mob.level, playerLevel, grey)
    return ns.Levels.isDangerous(bucket) and a.levelSounds.dangerous or a.levelSounds.easy
  end
  return a.sounds.regular
end

function QT.OnMobAdded(mob)
  if mob.tapped then return end
  local quests = relevantQuests(mob)
  if not quests then
    if o().tooltipLearning then QT.LearnFromTooltip(mob) end
    return
  end
  local a = o().alerts
  if not a.enabled then return end
  local level, grey = ns.Alerts.PlayerLevels()
  if not ns.Filters.passes(mob, level, grey, o().filters) then return end
  QT.gate:configure(a)
  if not QT.gate:shouldAlert(mob.guid, mob.name, GetTime()) then return end
  ns.Alerts.Notify({
    soundKey = QT.AlertSound(mob, level),
    channel = a.channel,
    showText = a.showText,
    text = string.format(L.ALERT_QUEST_MOB, mob.name, ns.UI.LevelText(mob.level, mob.classification)),
    color = ns.UI.DifficultyColor(mob.level),
  })
end

-- Tooltip learning: a nameplate unit whose tooltip lists an unfinished objective of an open
-- quest is recorded as relevant for this session. Rate limited.
local learnBudget, learnWindow = 0, 0
function QT.LearnFromTooltip(mob)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit and Enum and Enum.TooltipDataLineType) then return end
  if not mob.unit or not mob.name or QI:ByName(mob.name) then return end
  local now = GetTime()
  if now - learnWindow >= 1 then learnWindow, learnBudget = now, 0 end
  if learnBudget >= 12 then return end
  learnBudget = learnBudget + 1
  local data = ns.Safe.read(C_TooltipInfo.GetUnit, mob.unit)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return end
  local types = Enum.TooltipDataLineType
  local questID
  for _, line in ipairs(data.lines) do
    local kind = ns.Safe.read(function() return line.type end)
    local text = ns.Safe.read(function() return line.leftText end)
    if kind == types.QuestTitle and type(text) == "string" then
      questID = QI:QuestIdByTitle(text)
    elseif kind == types.QuestObjective and questID and not ns.Safe.read(function() return line.completed end) then
      if QI:Learn(mob.name, questID) then return true end
    end
  end
end

local function scanReport()
  local level, grey = ns.Alerts.PlayerLevels()
  ns:Print(string.format(L.SCAN_HEADER, level, grey, QI.dbOk == false and L.SCAN_DB_OFF or L.SCAN_DB_ON))
  local n = 0
  for _, entry in pairs(QI.byName) do
    n = n + 1
    local q = entry.quests[1]
    ns:Print(string.format("  %s — %s (%s)", entry.name or "?", q and q.title or "?", q and q.text or ""))
  end
  if n == 0 then ns:Print("  " .. L.SCAN_NONE) end
  ns:Print(L.SCAN_NEARBY)
  for _, mob in ipairs(ns.Nameplates:All()) do
    if relevantQuests(mob) then
      local ok, reason = ns.Filters.passes(mob, level, grey, o().filters)
      ns:Print(string.format("  %s (%s): %s", mob.name, ns.UI.LevelText(mob.level, mob.classification),
        ok and (mob.tapped and L.TAGGED or L.OK) or (L["REASON_" .. reason] or reason)))
    end
  end
  if not ns.Nameplates:EnemyPlatesOn() then ns:Print(L.PLATES_OFF_WARNING) end
end

local function checkEnemyPlates()
  if ns.Nameplates:EnemyPlatesOn() or not o().prompts.enemyPlates or not StaticPopup_Show then return end
  StaticPopup_Show("ULTIMATE_ENEMY_PLATES")
end

if StaticPopupDialogs then
  StaticPopupDialogs.ULTIMATE_ENEMY_PLATES = {
    text = L.PLATES_PROMPT,
    button1 = L.ENABLE,
    button2 = L.NOT_NOW,
    button3 = L.DONT_ASK,
    OnAccept = function()
      ns.Combat:Run("cvar.plates", function() SetCVar("nameplateShowEnemies", "1") end)
    end,
    OnAlt = function() ns.db.questTargeting.prompts.enemyPlates = false end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopupDialogs.ULTIMATE_QUESTIEDB = {
    text = L.QUESTIEDB_PROMPT,
    button1 = OKAY or "Okay",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end

QT.def = ns.Modules:Register({
  key = "questTargeting",
  name = L.MODULE_QUEST_TARGETING,
  description = L.MODULE_QUEST_TARGETING_DESC,
  defaults = {
    filters = { minOffset = -10, maxOffset = 3, hideGrey = true, includeElites = true, includeBosses = false,
      hideTapped = true, exclude = {} },
    alerts = { enabled = true, showText = true, guidCooldown = 60, nameCooldown = 10, channel = "Master",
      sounds = { regular = "mapping", elite = "raidwarning", boss = "alarm" },
      levelSounds = { enabled = false, easy = "questadded", dangerous = "alarm" } },
    prompts = { enemyPlates = true },
    tooltipLearning = true,
    partyNeeds = true,
    pinned = {},
    ignored = {},
  },
  OnEnable = function()
    QT.gate = ns.AlertGate.new(o().alerts)
    ns.Targeting:RegisterProvider("quest", QT.Candidates)
    ns.Nameplates:AddListener("questTargeting", { onAdded = QT.OnMobAdded })
    ns:On("ULT_DEBUG_SCAN", QT, scanReport)
    ns:On("ULT_QUESTIEDB_UNAVAILABLE", QT, function()
      if StaticPopup_Show then StaticPopup_Show("ULTIMATE_QUESTIEDB") end
    end)
    C_Timer.After(5, checkEnemyPlates)
  end,
  OnDisable = function()
    ns.Targeting:UnregisterProvider("quest")
    ns.Nameplates:RemoveListener("questTargeting")
    ns:Off("ULT_DEBUG_SCAN", QT)
    ns:Off("ULT_QUESTIEDB_UNAVAILABLE", QT)
  end,
})

function QT.def.BuildSettings(ctx)
  local P = ns.SettingsPanel
  ctx:Header(L.SECTION_FILTERS)
  ctx:Slider("questTargeting.filters.minOffset", L.MIN_OFFSET, -20, 0, 1, P.fmt.levels, L.LEVEL_WINDOW_TIP)
  ctx:Slider("questTargeting.filters.maxOffset", L.MAX_OFFSET, 0, 10, 1, P.fmt.levels, L.LEVEL_WINDOW_TIP)
  ctx:Checkbox("questTargeting.filters.hideGrey", L.HIDE_GREY)
  ctx:Checkbox("questTargeting.filters.includeElites", L.INCLUDE_ELITES)
  ctx:Checkbox("questTargeting.filters.includeBosses", L.INCLUDE_BOSSES)

  ctx:Header(L.SECTION_ALERTS)
  ctx:Checkbox("questTargeting.alerts.enabled", L.ALERTS_ENABLED)
  ctx:Checkbox("questTargeting.alerts.showText", L.ALERTS_TEXT)
  ctx:Dropdown("questTargeting.alerts.channel", L.SOUND_CHANNEL, P.CHANNELS)
  local ch = "questTargeting.alerts.channel"
  P.SoundRow(ctx, "questTargeting.alerts.sounds.regular", L.SOUND_REGULAR, ch)
  P.SoundRow(ctx, "questTargeting.alerts.sounds.elite", L.SOUND_ELITE, ch)
  P.SoundRow(ctx, "questTargeting.alerts.sounds.boss", L.SOUND_BOSS, ch)
  ctx:Checkbox("questTargeting.alerts.levelSounds.enabled", L.LEVEL_SOUNDS, L.LEVEL_SOUNDS_TIP)
  P.SoundRow(ctx, "questTargeting.alerts.levelSounds.easy", L.SOUND_EASY, ch)
  P.SoundRow(ctx, "questTargeting.alerts.levelSounds.dangerous", L.SOUND_DANGEROUS, ch)
  ctx:Slider("questTargeting.alerts.guidCooldown", L.GUID_COOLDOWN, 10, 600, 10, P.fmt.int)
  ctx:Slider("questTargeting.alerts.nameCooldown", L.NAME_COOLDOWN, 0, 60, 1, P.fmt.int)

  ctx:Header(L.SECTION_MISC)
  ctx:Checkbox("questTargeting.tooltipLearning", L.TOOLTIP_LEARNING, L.TOOLTIP_LEARNING_TIP)
  ctx:Checkbox("questTargeting.partyNeeds", L.PARTY_NEEDS, L.PARTY_NEEDS_TIP)
  ctx:Checkbox("questTargeting.prompts.enemyPlates", L.PLATES_PROMPT_SETTING)
  ctx:Button(L.ENEMY_PLATES, L.TURN_ON, function()
    ns.Combat:Run("cvar.plates", function() SetCVar("nameplateShowEnemies", "1") end)
  end, L.ENEMY_PLATES_TIP)
end
