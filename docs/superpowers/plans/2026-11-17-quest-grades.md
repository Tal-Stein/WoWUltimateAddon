# Quest Grades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grade quests for Leveling (1–5) and Gear (1–5 / "–" / "?"), or as one unified grade from
a playing style, with a time estimate and warnings. Show the grades on the quest dialog, the quest
log and Questie's tracker.

**Architecture:**
- **Pure grading math** in `Logic/QuestGrades.lua`, fed by "facts" gathered per quest from
  LibQuestieDB, Questie's internals (XP, drop rates, available quests) and the live client.
- **A module** (`Modules/QuestGrades.lua`) owns settings and a cache.
- **One service** (`Services/GradeSurfaces.lua`) draws the grades onto three surfaces via
  `hooksecurefunc`/events only.

**Tech Stack:** Lua 5.1 (WoW 12.x API, Interface 16001), lupa test harness (`python tests/run.py`),
`python scripts/check.py`.

**Spec:** `docs/superpowers/specs/2026-11-17-quest-grades-design.md`

## Global Constraints

- Questie and LibQuestieDB (contract 4) are required.
  - Read Questie internals only through `QuestieLoader._modules.<Name>`, never `ImportModule`
    (which creates empty modules).
  - Every read is guarded; a failed read means "no data", shown as "?" or "–", never a made-up
    number.
- If Blizzard blocks something, don't work around it. Only `hooksecurefunc`, events, and own child
  frames/fontstrings; no overwriting Blizzard functions.
- Native look: Blizzard fonts (`GameFontNormalSmall`/`GameFontHighlightSmall`) and colors
  (`ns.UI` helpers).
- No per-frame work. Grades are cached and invalidated on QUEST_LOG_UPDATE, PLAYER_LEVEL_UP,
  PLAYER_EQUIPMENT_CHANGED and ULT_SETTING_CHANGED (`questGrades.*`).
- Every new Lua file is listed in `Ultimate/Ultimate.toc`.
- Feature branch, then `--no-ff` merge into main, then push. Commit trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Rulings made while planning (from research, 2026-11-17)

- **Route badge dropped from v1.** RXP/Guidelime/FlowUp keep parsed guides private, and the only
  path is copying guide files, which the spec forbids and FlowUp's license disallows. The
  "routes" factor is removed from the unified weights. Cost if wrong: one factor missing; can be
  added later.
- **Gear grade only where the client shows rewards:** quests in the log
  (`GetNumQuestLogChoices`/`GetQuestLogItemLink` by log index) and the open quest dialog
  (`GetNumQuestChoices`/`GetNumQuestRewards`/`GetQuestItemLink`). Otherwise "?". Questie has no
  quest→reward field. Cost if wrong: available-but-not-accepted quests show "?" for gear.
- **Travel is a zone-count estimate** (90 s + 120 s per extra zone among giver, objective areas
  and turn-in), not a distance calculation. The personal multiplier corrects it over time. Cost if
  wrong: rougher time estimates within one zone.
- **Map pins are not in v1** (spec allows dropping them).

## Review Focus

1. A quest with no XP data or no objective data: shows "?" for Leveling and time, never 0 or 5.
2. Item drops whose drop rate is unknown for every dropper: time "?" (not infinite, not a guess).
3. GearQuestForever not loaded, or reward items not cached yet (score 0): Gear "?", and the grade
   updates when GET_ITEM_INFO_RECEIVED arrives.
4. Questie's tracker or the quest log not present (other client UI, Questie tracker disabled):
   that surface is skipped without errors.
5. Max-level player (Questie XP returns 0): Leveling shows "–" (no XP), not 1.

---

### Task 1: Pure grading math

**Files:**
- Create: `Ultimate/Logic/QuestGrades.lua`
- Modify: `Ultimate/Ultimate.toc` (after `Logic\Levels.lua`)
- Test: `tests/lua/test_questgrades_logic.lua`

**Interfaces:**
- Produces `ns.Grades` with:
  - `Grades.estimateSeconds(facts, consts) -> number|nil`
    - `facts = { objectives = { {kind="kill", count, level?, elite?}, {kind="drop", count, rate?,
      level?, elite?}, {kind="object", count} }, zones = n }`
    - Returns nil when any objective lacks what it needs.
  - `Grades.CONSTS = { killSeconds = 25, perLevelAbove = 5, eliteFactor = 3, objectSeconds = 10,
    travelBase = 90, travelPerZone = 120 }`
  - `Grades.levelingFixed(xpPerMin, baselineXpPerMin) -> 1..5|nil`
    - Ratio bands: `<0.5`→1, `<0.8`→2, `<1.2`→3, `<1.8`→4, else 5.
    - nil if either input is nil or ≤ 0.
  - `Grades.gearFixed(newScore, oldScore) -> 1..5 | "none" | nil`
    - gain = new/old − 1; old ≤ 0 (empty slot) and new > 0 → 5.
    - Bands: gain ≤ 0 → "none"; `<0.03`→1, `<0.08`→2, `<0.15`→3, `<0.30`→4, else 5.
    - nil if newScore is nil.
  - `Grades.relative(value, values) -> 1..5|nil`
    - Percentile p = (count of values strictly below value) / (#values − 1).
    - Grade = `math.min(5, 1 + math.floor(p * 5))`. A single-element set → 3.
  - `Grades.PRESETS = { balanced = {speed=60, gear=40, chain=30, travel=30, difficulty=40,
    rep=10}, speed = {speed=100, gear=10, chain=40, travel=50, difficulty=50, rep=0}, gear =
    {speed=40, gear=100, chain=20, travel=20, difficulty=30, rep=10} }`
  - `Grades.unifiedScore(factors, weights) -> 0..1|nil`
    - Weighted average over factors whose value is non-nil and whose weight > 0.
    - nil when no factor counts.
  - `Grades.unifiedFixed(score) -> 1..5` = `1 + math.floor(score * 4 + 0.5)`

- [ ] **Step 1: Write the failing tests** (`describe("Grades")`):
  - **estimateSeconds**
    - `{objectives={{kind="kill",count=10,level=10}}, zones=1}` at player level 10 = 10×25 + 90
      = 340.
    - A drop `{kind="drop",count=10,rate=31}` = ceil(10/0.31)=33 kills → 33×25 + 90 = 915.
    - `rate=nil` → nil.
    - Elite kill count 2 at level 12 for player 10 → 2×(25+10)×3 + 90 = 300.
    - zones=3 → +240.
  - **levelingFixed:** ratios 0.4→1, 0.79→2, 1.0→3, 1.5→4, 2.0→5; nil input → nil.
  - **gearFixed:** (110,100)→3 [gain .10], (100,100)→"none", (50,0)→5, (nil,100)→nil, (102,100)→1.
  - **relative:** `relative(5, {1,5,9})`=3; `relative(9,{1,5,9})`=5; `relative(1,{1,5,9})`=1;
    `relative(4,{4})`=3.
  - **unifiedScore:** `({speed=1, gear=0}, {speed=50, gear=50})`=0.5; gear=nil is skipped →
    `({speed=1, gear=nil},{speed=50,gear=50})`=1; all weights 0 → nil.
  - **unifiedFixed:** 0→1, 0.5→3, 1→5.
- [ ] **Step 2:** Run `python tests/run.py` → the new tests FAIL (ns.Grades nil).
- [ ] **Step 3:** Implement as specified; add the TOC line.
- [ ] **Step 4:** `python tests/run.py` → all pass; `python scripts/check.py` → OK.
- [ ] **Step 5:** Commit `feat(grades): grading math`.

### Task 2: Quest facts from QuestieDB and Questie

**Files:**
- Create: `Ultimate/Data/QuestFacts.lua`
- Modify: TOC (after `Data\PartyNeeds.lua`)
- Test: `tests/lua/test_questfacts.lua`

**Interfaces:**
- Consumes: LibQuestieDB getters (as in `Data/QuestIndex.lua`) and
  `QuestieLoader._modules`:
  - `.QuestXP:GetQuestLogRewardXP(questId)`
  - `.DropDB.GetItemDroprate(itemId, npcId)` → table, rate = `tonumber(t[1])`
  - `.AvailableQuests.__availableQuests` (`[questId]=true`)
- Produces `ns.QuestFacts` with:
  - `QuestFacts:Get(questId) -> facts|nil` (cached; `QuestFacts:Invalidate()` clears)
    - `facts = { questId, name, level, xp (number|nil), objectives = {...as Task 1},
      zones = n, elite = bool, group = bool, escort = bool, timed = bool, chain = bool,
      rep = bool }`
  - `QuestFacts:Candidates(range) -> { questId, ... }`
    - Quests in the log (`ns.QuestIndex:Quests()`) plus available quests whose level is within
      ±range of the player.
- Field rules:
  - Kills: from `objectives[1]`, level = the npc's `maxLevel`, elite = npc `rank` ≥ 1.
  - Drops: from `objectives[3]` via `npcDrops`.
    - rate = the mean of the known rates across droppers; nil when none is known.
    - Count comes from the live log objective's `numRequired` when the quest is in the log,
      else 1.
  - Objects: `objectives[2]` → kind "object".
  - zones = distinct npc `zoneID`s among `startedBy[1]`, kill/drop npcs and `finishedBy[1]`
    (min 1).
  - group/elite/escort/timed:
    - escort = `triggerEnd` present.
    - timed = `specialFlags` bit 1 (value 1).
    - group = quest flag `questFlags` bit 1 (value 1, "group").
    - elite = any kill/drop npc elite.
  - chain = `nextQuestInChain` non-nil and non-zero; rep = `reputationReward` non-empty.

- [ ] **Step 1: Write failing tests**
  - Use the stub style of `tests/lua/test_partyneeds.lua`: LibQuestieDB getters plus a stub
    `QuestieLoader._modules` with QuestXP, DropDB and AvailableQuests.
  - Quest 418-style: an item objective with droppers 1190 (31%) and 1191 (36%) → one drop
    objective with rate 33.5 and count 3 from the log.
  - Kill quest → kill objective with level/elite.
  - xp from the QuestXP stub.
  - No DropDB module → drop rate nil.
  - `Candidates(5)` includes log quests and in-range available quests, and excludes an available
    quest 7 levels away.
  - QuestieLoader nil → `Get` still returns facts with xp nil, and `Candidates` returns the log
    quests only.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → pass; check.py OK.
- [ ] **Step 5:** Commit `feat(grades): quest facts`.

### Task 3: Personal quest times

**Files:**
- Create: `Ultimate/Data/QuestTimes.lua`
- Modify: TOC
- Test: `tests/lua/test_questtimes.lua`

**Interfaces:**
- Produces `ns.QuestTimes` with:
  - `QuestTimes:Tick(dt)`: adds dt/n seconds to each of the n active log quests, only when not
    AFK (`UnitIsAFK("player")`) and when the feature is enabled (`ns.db.questGrades.learn`).
    Driven by a 1 s ticker.
  - On QUEST_TURNED_IN(questId), records
    `ns.global.questTimes[questId] = { spent = s, estimate = e }` when the quest was tracked from
    accept.
    - e comes from a `QuestTimes.estimateFor(questId)` hook that the module sets.
    - Untracked quests (accepted before install) are not recorded.
  - `QuestTimes:Spent(questId) -> seconds|nil` (current, in-progress)
  - `QuestTimes:Took(questId) -> seconds|nil` (finished)
  - `QuestTimes:Multiplier() -> number`
    - The median of spent/estimate over finished records with an estimate, clamped 0.5..3.
    - 1 when fewer than 5 records.
  - `QuestTimes:Reset()`
- Accepted quests are tracked via QUEST_ACCEPTED (`[questId] = 0` in
  `ns.global.questTimesActive`); abandoned (QUEST_REMOVED without turn-in) are dropped.

- [ ] **Step 1: Failing tests**
  - Two active quests, `Tick(10)` → each +5.
  - AFK → no change.
  - Turn-in records spent and estimate.
  - Multiplier is 1 with 4 records; with 5 records of ratio 2 → 2; with ratios capped → 3.
  - Reset clears.
  - Disabled → Tick does nothing.
- [ ] **Step 2–4:** fail → implement → pass.
- [ ] **Step 5:** Commit `feat(grades): learn personal quest times`.

### Task 4: Gear value adapter

**Files:**
- Create: `Ultimate/Data/GearValue.lua`
- Modify: TOC
- Test: `tests/lua/test_gearvalue.lua`

**Interfaces:**
- Consumes `_G.GearQuest.Compare:ScoreItemStats({ itemId = id }) -> number` (0 = not cached).
- Produces `ns.GearValue` with:
  - `GearValue:BestUpgrade(itemLinks) -> { link, newScore, oldScore } | nil`
    - For each link: slot via `C_Item.GetItemInventoryTypeByID` / `select(9, GetItemInfo)`
      mapped to inventory slot IDs (two-slot types use the lower-scored equipped item).
    - Score new and equipped; return the link with the largest new/old.
    - nil when GearQuest is missing or any score is 0 (not cached).
  - `GearValue.available() -> bool`

- [ ] **Step 1: Failing tests**
  - Stub GearQuest scores: item 100 → 50, equipped 10 → 40 ⇒ best `{newScore=50, oldScore=40}`.
  - Two links → picks the higher ratio.
  - Empty slot → oldScore 0.
  - Score 0 → nil.
  - No GearQuest → nil and `available()` false.
- [ ] **Steps 2–5:** fail → implement → pass → commit `feat(grades): gear value via GearQuestForever`.

### Task 5: QuestGrades module (settings, cache, tooltip text)

**Files:**
- Create: `Ultimate/Modules/QuestGrades.lua`
- Modify: TOC (after `Modules\QuestTargeting.lua`), `Ultimate/Locale/enUS.lua`
- Test: `tests/lua/test_questgrades.lua`

**Interfaces:**
- Consumes Tasks 1–4.
- Registers a module `key = "questGrades"` via `ns.Modules:Register` (pattern:
  `Modules/QuestTargeting.lua`), defaults:
  ```lua
  { mode = "separate", style = "balanced", weights = <copy of PRESETS.balanced>,
    scale = "fixed", range = 5, learn = true,
    show = { time = true, warnings = true },
    surfaces = { dialog = true, questLog = true, tracker = true } }
  ```
- Produces `ns.QuestGradesModule`:
  - `QG:Grade(questId, ctx?) -> result|nil`, where
    `result = { leveling = 1..5|"none"|nil, gear = 1..5|"none"|nil, unified = 1..5|nil,
    seconds = number|nil, xp = number|nil, took = number|nil, warnings = {"elite"|"group"|
    "escort"|"timed"|"travel"} }`.
    - ctx carries reward links for the quest dialog.
    - leveling: xp = 0 → "none"; xp nil or seconds nil → nil.
    - Fixed scale:
      - baselineXpPerMin = median base XP of `QuestXP.db` entries with quest level = player
        level, ÷ 10 (cached per level).
      - Gear via `Grades.gearFixed`.
    - Relative scale: `Grades.relative` over the `Candidates(range)` values of the same axis.
    - unified (mode "unified" only):
      - factors: speed = leveling grade mapped (g−1)/4; gear = (g−1)/4 with "none" → 0 and
        nil → skipped; chain 1/0; travel = 1 − min((zones−1)/3, 1); difficulty = 0 if
        elite/group/escort else 1; rep 1/0.
      - weights = PRESETS[style], or `weights` when style is "custom".
      - Turned into 1–5 by `unifiedFixed` (fixed) or `relative` (relative).
    - seconds = `estimateSeconds × QuestTimes:Multiplier()` when learn is on.
    - warnings: "travel" when zones ≥ 3.
  - `QG:TooltipLines(questId, ctx?) -> { {text, r, g, b}, ... }`
    - Lines: "Leveling 4 — ≈ 1,150 XP in ~8 min (≈ 8,600 XP/hour)"; "Gear 5 — <item link>
      (+14%)"; "Time: ~8 min" or "Time: ?"; "Took you 12 min (est. 8)"; warnings.
    - All strings come from `L`.
  - `QG:Badge(questId, ctx?) -> string`
    - Separate mode: "|cff..L4|r |cff..G5|r ~8m" (colors from grade: 1 red, 2 orange, 3 yellow,
      4 green, 5 blue).
    - Unified mode: "★4 ~8m".
    - "?" for nil, "–" for "none". Time and warnings honor `show`.
  - Cache: `QG:Invalidate()` on the Global Constraints events; fires `ULT_QUEST_GRADES_CHANGED`.
- Settings (`QG.def.BuildSettings(ctx)`, pattern from `QuestTargeting`):
  - Dropdowns: mode (separate/unified), style (balanced/speed/gear/custom), scale (fixed/relative).
  - Six weight sliders `questGrades.weights.<f>` (0–100, step 5); they apply when style is custom.
  - Range slider (1–10).
  - Checkboxes: show.time, show.warnings, surfaces.dialog/questLog/tracker, learn.
  - Button "Reset my quest times".

- [ ] **Step 1: Failing tests**
  - Fixed-scale leveling for a stubbed quest with xp 1150 and an estimate of 480 s and a baseline
    → expected band.
  - max level (xp 0) → "none".
  - No data → nil, and the badge shows "?".
  - Unified "speed" vs "gear" presets give different grades for a high-XP, no-gear quest.
  - Relative scale ranks within candidates.
  - Badge in separate mode contains "L" and "G" with grades.
  - Tooltip line contains "XP".
  - ULT_SETTING_CHANGED "questGrades.mode" invalidates the cache.
  - Defaults as above.
- [ ] **Steps 2–5:** fail → implement → pass → commit `feat(grades): module, settings and tooltip`.

### Task 6: Surfaces — quest dialog, quest log, Questie tracker

**Files:**
- Create: `Ultimate/Services/GradeSurfaces.lua`
- Modify: TOC (after `Modules\QuestGrades.lua`)
- Test: `tests/lua/test_gradesurfaces.lua`

**Interfaces:**
- Consumes `ns.QuestGradesModule:Badge/TooltipLines`.
- **Dialog:**
  - On QUEST_DETAIL / QUEST_COMPLETE, when `QuestFrame` exists, show one own fontstring
    anchored to `QuestFrame`'s title area, text = `Badge(GetQuestID(), ctx)`.
    - ctx = reward links from `GetQuestItemLink("choice"/"reward", i)`.
  - The fontstring sits on an own frame child of QuestFrame with OnEnter tooltip lines. Hide it
    on QUEST_FINISHED.
- **Quest log:**
  - If `QuestLogQuests_Update` exists, `hooksecurefunc` it.
  - Walk `QuestScrollFrame.titleFramePool:EnumerateActive()`; for each title frame with
    `.questID`, add or update an own fontstring `frame.ultGrade` right of the title text.
  - Tooltip via `HookScript("OnEnter")` once per frame (guard flag).
- **Tracker:**
  - If `QuestieLoader._modules.QuestieTracker` and `TrackerLinePool` exist,
    `hooksecurefunc(QuestieTracker, "Update", fn)`.
  - fn calls `TrackerLinePool.ForEachQuestTitleLine(function(line) ... end)`, reading
    `line.Quest and line.Quest.Id`.
  - Add or update `line.ultGrade` anchored LEFT to `line.label`'s RIGHT; hide it when
    `line.Quest` is nil.
- Every surface honors `surfaces.*` and refreshes on `ULT_QUEST_GRADES_CHANGED`. All hooks are
  installed once, after ADDON_LOADED of Questie and `PLAYER_LOGIN`, inside `ns.SafeCall`.

- [ ] **Step 1: Failing tests** with stub frames:
  - QUEST_DETAIL sets the dialog badge text.
  - Quest log hook: calling the stubbed `QuestLogQuests_Update` after install sets
    `frame.ultGrade` text for a pooled frame with questID.
  - Tracker hook: calling `QuestieTracker.Update` sets the `line.ultGrade` text.
  - Disabling `surfaces.tracker` hides it.
  - Missing QuestScrollFrame/QuestieTracker → no errors (`ns.errorCount` unchanged).
- [ ] **Steps 2–5:** fail → implement → pass → commit `feat(grades): show grades on dialog, quest log and tracker`.

### Task 7: Finish

- [ ] Run the full suite and check.py.
- [ ] Add a "Quest grades" section to `docs/testing.md` (in-game checks: dialog badge, quest-log
  badge, tracker badge, tooltip, unified mode, relative scale, learn/reset).
- [ ] Merge `--no-ff` into main and push.
