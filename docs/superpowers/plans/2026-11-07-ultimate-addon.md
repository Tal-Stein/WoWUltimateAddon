# Ultimate Add-on Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build "Ultimate", a modular WoW Forever add-on. It has three features: Quest Targeting (quest-mob detection, a target key and bar, overhead markers, sound alerts), Rare Scanner, and a Quest Item bar. Every option is editable in Blizzard's own Settings panel.

**Architecture:**
- **Pure logic** lives in `Ultimate/Logic/*.lua`: filters, ranking, macro building, alert gating and item relevance. These files use no WoW globals and are unit-tested offline under LuaJIT, run through Python `lupa`.
- **WoW glue** lives in Core, Services, Data, Modules and Settings. Its pieces:
  - nameplate scanner
  - quest index reading LibQuestieDB
  - a secure targeting button with a macrotext cursor
  - a combat-safe queue for every secure change
- **Features** are modules registered with a core registry. Targeting is a shared service that modules feed candidates into.

**Tech Stack:**
- Lua 5.1, the WoW Forever client API (Interface 16001, 12.x Midnight-style restrictions).
- Blizzard Settings API and SecureActionButtonTemplate.
- LibQuestieDB, contract 4.
- Dev tools: Python 3.12 + `lupa` (LuaJIT 2.1) for tests, PowerShell deploy script.

**Spec:** `docs/superpowers/specs/2026-11-07-ultimate-addon-design.md`

## Global Constraints

- TOC header lines:
  - `## Interface: 16001`
  - `## Dependencies: Questie, QuestieDB`
  - `## SavedVariables: UltimateDB`
  - `## SavedVariablesPerCharacter: UltimateCharDB`
- Add-on folder and title `Ultimate`. Slash command `/ult`.
- No workarounds for Blizzard restrictions. Never call `SetAttribute`, `SetCVar`, `Show`/`Hide`/`SetPoint` on a secure frame, `CreateMacro` or `EditMacro` while `InCombatLockdown()` is true. Queue the change via `ns.Combat:Run(key, fn)` instead.
- Every unit or quest value read goes through `ns.Safe.read(fn, ...)`, which returns nil if the call errors or the value `issecretvalue`. If the value is nil, skip the unit.
- Targeting is by **name** only (`/targetexact`). Macro text is at most 255 bytes, and names are sanitised by removing `[%c%[%];/|]`.
- Identity is the NPC ID parsed from the GUID. The name inside a macro is the live `UnitName` from the nameplate.
- UI uses Blizzard fonts, colors and templates only: `GameFontNormal`, `GameFontHighlight`, `GameFontNormalSmall`, `GameFontDisable`, `NORMAL_FONT_COLOR`, `GetCreatureDifficultyColor`, `SecureActionButtonTemplate` + `ActionButtonTemplate`, `UIPanelButtonTemplate`, `InputBoxTemplate`, `GameTooltip`, `RaidNotice_AddMessage`, `StaticPopupDialogs`. No custom fonts or art files.
- Settings use `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterProxySetting`, `Settings.CreateCheckbox` / `CreateSlider` / `CreateDropdown` and `Settings.RegisterAddOnCategory`. There is one top category "Ultimate" plus one subcategory per module.
- Git:
  - Work on `feature/<area>` branches with small commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
  - Merge to `main` with `--no-ff` after `python tests/run.py` and `python scripts/check.py` pass.
  - Every commit ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - No remote, no push.

## Review Focus

1. **Entering combat mid-refresh.** When a quest log update or nameplate change arrives while in combat, the secure button and bar keep their last state with no "action blocked" error, and the change applies once combat ends. Tested in Task 2 (`test_combat_queue_defers_and_coalesces`).
2. **Secret or nil unit values on a nameplate.** If GUID, level or name is secret, that plate is skipped and nothing errors. Tested in Task 6 (`test_snapshot_skips_secret_values`).
3. **A long or odd mob name blowing the 255-byte macro budget, or injecting a macro line.** Fallback lines get dropped and the primary target line is always present. Tested in Task 4 (`test_macro_budget_and_sanitise`).
4. **A QuestieDB quest ID whose name doesn't match the live quest** (Forever ID drift). That DB entry is ignored and no wrong mobs are marked. Tested in Task 5 (`test_index_rejects_name_mismatch`).
5. **No candidates, or a disabled module.** The key's macrotext becomes an empty-but-valid `/cleartarget [dead]` no-op, the bar hides, and pressing does nothing harmful. Tested in Task 4 (`test_macro_empty_list`).

---

## File Structure

```
Ultimate/
  Ultimate.toc                 load order, deps, SavedVariables
  Bindings.xml                 key bindings (target key, refresh, quest items 1-4)
  Locale/enUS.lua              ns.L strings (all user-visible text)
  Logic/Tables.lua             ns.Tables.merge(defaults, saved), copy
  Logic/Levels.lua             ns.Levels.bucket(diff, greyLevel) -> "trivial"|"easy"|"normal"|"hard"|"impossible"
  Logic/Units.lua              ns.Units.npcIdFromGuid(guid), sanitizeName(name)
  Logic/Filters.lua            ns.Filters.passes(mob, playerLevel, opts, greyLevel)
  Logic/Ranking.lua            ns.Ranking.rank(candidates, opts) -> ordered names
  Logic/Macro.lua              ns.Macro.build(names, cursor, opts) -> text ; ns.Macro.Cursor
  Logic/AlertGate.lua          ns.AlertGate.new(opts):shouldAlert(guid, name, now)
  Logic/ItemRelevance.lua      ns.ItemRelevance.shouldShow(item, ctx, mode)
  Core/Init.lua                ns, event bus (ns:On/Off/Fire), guarded dispatch, debug print
  Core/Safe.lua                ns.Safe.read, ns.Safe.isSecret
  Core/Combat.lua              ns.Combat:Run(key, fn) queue, flush on PLAYER_REGEN_ENABLED
  Core/DB.lua                  profile load/merge, ns.db (char or account scope)
  Core/Modules.lua             ns.Modules:Register(def), SetEnabled(key, bool), Iterate()
  Core/Slash.lua               /ult, /ult scan, /ult debug, /ult reset
  Data/QuestIndex.lua          builds index from quest log + LibQuestieDB + tooltip learning
  Services/Nameplates.lua      plate snapshots, listeners, ticker
  Services/Sounds.lua          catalog of SOUNDKIT choices, play(key, channel)
  Services/Alerts.lua          sound + RaidNotice text, using AlertGate
  Services/Targeting.lua       candidate providers, ranking, secure key button + cursor, action-bar macro
  Services/TargetBar.lua       secure bar of name buttons
  Services/Markers.lua         overhead textures on nameplates
  Modules/QuestTargeting.lua   provider: quest mobs; alerts; enemy-nameplate prompt
  Modules/RareScanner.lua      provider: rares + watch list; alerts; history
  Modules/QuestItems.lua       quest item bar
  Settings/Builder.lua         helpers wrapping Settings API (checkbox/slider/dropdown/header/button/list)
  Settings/Panel.lua           root category + global options; each module's BuildSettings
tests/
  run.py                       lupa LuaJIT runner: loads Logic files with ("Ultimate", ns), runs tests/lua/test_*.lua
  lua/harness.lua              describe/it/assertEq/assertTrue + WoW stubs for glue tests
  lua/test_*.lua               one per logic/glue unit
scripts/
  check.py                     luajit syntax check of every .lua; every TOC-listed file exists; every .lua listed
  deploy.ps1                   junction Ultimate/ into ..._forever_\Interface\AddOns\Ultimate
docs/testing.md                in-game verification checklist
README.md
```

Every add-on file starts `local ADDON, ns = ...`. The test runner calls each chunk with `("Ultimate", ns)` so the same files load offline.

---

### Task 1: Scaffold, test runner, checks, deploy

Branch: `feature/scaffold`

**Files:**
- Create: `Ultimate/Ultimate.toc`, `Ultimate/Logic/Tables.lua`, `Ultimate/Locale/enUS.lua`, `tests/run.py`, `tests/lua/harness.lua`, `tests/lua/test_tables.lua`, `scripts/check.py`, `scripts/deploy.ps1`, `.gitattributes` (`* text=auto eol=lf`, `*.ps1 eol=crlf`), `README.md`

**Interfaces:**
- Produces:
  - `ns.Tables.merge(defaults, saved) -> saved`: recursively fills missing keys, never overwrites existing ones, and drops nothing.
  - `ns.Tables.copy(t)`.
  - The runner contract: test files call `describe(name, fn)`, `it(name, fn)`, `assertEq(a, b, msg)`, `assertTrue(v, msg)`, `assertNil(v)`. The runner exits non-zero on any failure and prints `N passed, M failed`.
  - `run.py` loads the TOC-listed files from `Ultimate/Logic/` and `Ultimate/Core/` in TOC order into a shared `ns` before the tests. It also exposes `loadAddonFile(path)` to tests that need glue files with stubs.

- [ ] **Step 1:** `pip install lupa`, then verify that `python -c "import lupa.luajit21"` succeeds. If that module is missing, use `lupa.lua51` and record the choice in README.
- [ ] **Step 2:** Write `test_tables.lua`:
  - `merge({a=1,b={c=2}}, {b={}})` → `{a=1,b={c=2}}`
  - an existing `saved.a=5` stays 5
  - `copy` gives a deep, non-aliased copy
- [ ] **Step 3:** Run `python tests/run.py`. Expected: FAIL, because `ns.Tables` is nil.
- [ ] **Step 4:** Implement `Logic/Tables.lua`. Write the TOC listing the Locale, Logic and Core files (the later files are added by their own tasks).
- [ ] **Step 5:** Run `python tests/run.py` and `python scripts/check.py`. Expected: all pass, and check prints `OK`.
- [ ] **Step 6:** Commit `chore: scaffold add-on, test runner and checks`, then merge `--no-ff` to main.

### Task 2: Core (events, safety, combat queue, DB, modules, slash)

Branch: `feature/core`

**Files:**
- Create: `Core/Init.lua`, `Core/Safe.lua`, `Core/Combat.lua`, `Core/DB.lua`, `Core/Modules.lua`, `Core/Slash.lua`
- Test: `tests/lua/test_core.lua`. Stubs in harness: `CreateFrame` returning a recorder frame, `InCombatLockdown`, `issecretvalue`, `C_Timer.After`/`NewTicker`, `GetTime`.

**Interfaces:**
- **Event bus:**
  - `ns:On(event, owner, fn)` and `ns:Off(event, owner)`. WoW events register on one hidden frame. Custom events use the `ULT_` prefix.
  - `ns:Fire(event, ...)`. Every handler runs in `xpcall`, and an error in one handler doesn't stop the others.
- **Safety:** `ns.Safe.read(fn, ...) -> value|nil` returns the first return value only. `ns.Safe.isSecret(v) -> bool`.
- **Combat queue:** `ns.Combat:Run(key, fn)` runs `fn` now when out of combat. In combat it stores `fn` under `key`, so the last call per key wins, and flushes on `PLAYER_REGEN_ENABLED` in insertion order.
- **Saved data:**
  - `ns.db` is the active profile table.
  - `ns.global` is `UltimateDB`.
  - `ns.DB:RegisterDefaults(path, defaults)`, where `path` is a module key or `"core"`.
  - Scope comes from `UltimateDB.scope`, `"char"` (the default) or `"account"`.
- **Modules:**
  - `ns.Modules:Register{ key, name, description, defaults, OnEnable, OnDisable, BuildSettings, defaultEnabled }`.
  - `ns.Modules:SetEnabled(key, bool)`, `IsEnabled(key)`, `Iterate()`.
  - Enabled state is stored at `ns.db.modules[key]`.
  - `OnEnable` runs on `PLAYER_LOGIN` for enabled modules.
- **Commands:**
  - `/ult` opens settings via `ns.OpenSettings()`, defined in Task 10. A stub prints until then.
  - `/ult debug` toggles debug printing.
  - `/ult reset` resets bar positions by firing `ULT_RESET_POSITIONS`.
  - `/ult scan` fires `ULT_DEBUG_SCAN`.

- [ ] **Step 1:** Write the tests:
  - `test_combat_queue_defers_and_coalesces`: in combat, `Run("a", f1)` then `Run("a", f2)` → nothing runs. Firing `PLAYER_REGEN_ENABLED` runs only f2. Out of combat, `Run` executes immediately.
  - `test_guarded_dispatch`: the first handler errors and the second still runs.
  - `test_safe_read_secret`: `issecretvalue` stub returns true for a sentinel → `read` returns nil, and `read` of an erroring fn returns nil.
  - `test_modules_enable_disable`: disabling calls `OnDisable` once and persists `false`, re-enabling calls `OnEnable`, and `defaultEnabled=false` stays off on first load.
  - `test_db_merge_defaults`.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement the Core files and add them to the TOC.
- [ ] **Step 4:** Run the tests and `check.py`, and confirm they PASS.
- [ ] **Step 5:** Commit `feat(core): event bus, combat queue, profiles, module registry, slash`, then merge.

### Task 3: Pure unit logic (levels, units, filters)

Branch: `feature/logic`

**Files:**
- Create: `Logic/Levels.lua`, `Logic/Units.lua`, `Logic/Filters.lua`
- Test: `tests/lua/test_filters.lua`

**Interfaces:**
- **`ns.Levels.bucket(mobLevel, playerLevel, greyLevel) -> bucket`**:
  - `mobLevel == -1` → `"impossible"`
  - `diff >= 5` → `"impossible"`
  - `diff >= 3` → `"hard"`
  - `diff >= -2` → `"normal"`
  - `mobLevel > greyLevel` → `"easy"`
  - otherwise → `"trivial"`
  - These thresholds match Blizzard's `GetCreatureDifficultyColor`. In-game, `greyLevel` comes from `GetQuestGreenRange`, or `UnitQuestTrivialLevelRange("player")` when present.
- **`ns.Levels.isDangerous(bucket) -> bool`**: true for `"hard"` and `"impossible"`.
- **`ns.Units.npcIdFromGuid(guid) -> number|nil`**: for `Creature-` or `Vehicle-` GUIDs, field 6 split by `-`. Anything else returns nil.
- **`ns.Units.sanitizeName(name) -> string|nil`**: strips `[%c%[%];/|]`, trims, and returns nil if the result is empty.
- **`ns.Filters.passes(mob, playerLevel, greyLevel, opts) -> bool, reason`**:
  - `mob` fields: `{ name, level, classification, dead, tapped, attackable, isPlayer }`.
  - `opts` fields: `{ minOffset=-10, maxOffset=3, hideGrey=true, includeElites=true, includeBosses=false, hideTapped=true, exclude={[name]=true} }`.
  - Bosses: `level == -1` or `classification == "worldboss"`. When `includeBosses` is true, bosses skip the level window.
  - Elites: `"elite"` or `"rareelite"`.

- [ ] **Step 1:** Write the tests:
  - `bucket(15,10,4)` = impossible
  - `bucket(13,10,4)` = hard
  - `bucket(8,10,4)` = normal
  - `bucket(5,10,4)` = easy
  - `bucket(4,10,4)` = trivial
  - `npcIdFromGuid("Creature-0-4372-0-1-1234-0000ABCD")` = 1234, `"Player-1-0ABC"` = nil
  - `sanitizeName("Bad;/Name|[x]")` = `"BadNamex"`
  - `passes` reasons:
    - tapped → false, `"tapped"`
    - level 20 with player 10 → false, `"level"`
    - grey with hideGrey → false, `"grey"`
    - elite with `includeElites=false` → false
    - boss with `includeBosses=false` → false, and with true → passes even when out of the window
    - excluded name → false
    - dead → false
    - player → false
    - not attackable → false
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement the three files and add them to the TOC.
- [ ] **Step 4:** Run the tests and confirm they PASS.
- [ ] **Step 5:** Commit `feat(logic): level buckets, GUID parsing, mob filters`. Stay on the branch.

### Task 4: Ranking and macro builder

Branch: `feature/logic` (continued, merged at the end of this task)

**Files:**
- Create: `Logic/Ranking.lua`, `Logic/Macro.lua`
- Test: `tests/lua/test_ranking.lua`, `tests/lua/test_macro.lua`

**Interfaces:**
- **`ns.Ranking.rank(candidates, opts) -> names[]`**:
  - Each candidate is `{ name, level, remaining, healthPct, pinned, isRare, count, firstSeen }`. One candidate is one name, already aggregated: `level` is the minimum visible level and `remaining` is the minimum over its objectives.
  - `opts` fields:
    - `rareFirst=true`.
    - `criteria`, an ordered list of `{id, enabled, desc}` with ids `"pinned"|"level"|"remaining"|"health"|"count"`.
    - Default criteria: pinned (enabled), level (enabled, asc), remaining (enabled), health (disabled), count (disabled, desc=true).
  - Comparator order: rares first (if `rareFirst`), then each enabled criterion, then `firstSeen` ascending. The sort is stable.
- **`ns.Macro.build(names, cursorIndex, opts) -> string`**:
  - `opts` fields: `{ stopInCombat=true, fallbacks=2, marker=0 }`.
  - Lines:
    - `/stopmacro [combat,exists,harm,nodead]` if `stopInCombat`
    - `/cleartarget [dead][help]`
    - `/targetexact <names[cursor]>`
    - then, for the following names, wrapping around and up to `fallbacks`: `/targetexact [noexists] <name>`
    - `/tm [exists,harm,nodead] <marker>` if `marker > 0`
  - Lines are joined with `\n`.
  - Byte budget 255: drop fallback lines first, then the marker line. The primary line is always kept.
  - Empty names → `/cleartarget [dead]`.
- **`ns.Macro.Cursor.new() -> c`**:
  - `c:set(names)` resets the index to 1 if `names[1]` changed.
  - `c:current() -> index`.
  - `c:onTargetName(name)` advances the index (with wraparound) when `name == names[index]` and `#names > 1`. It returns true if the index moved.
  - `c:reset()`.

- [ ] **Step 1:** Write the tests:
  - `test_rank_default_order`: levels 7, 5, 5 with remaining 3, 9, 1 → order level 5 (remaining 1), level 5 (remaining 9), level 7.
  - `test_rank_rare_first`: a rare outranks everything, and with `rareFirst=false` it ranks normally.
  - `test_rank_pinned`.
  - `test_rank_criteria_reorder`: remaining before level gives a different order.
  - `test_macro_basic`: exact expected string for `{"A","B","C"}` with cursor 1 and fallbacks 2.
  - `test_macro_cursor_wraps`: cursor 3 → primary C, fallbacks A, B.
  - `test_macro_budget_and_sanitise`: five 60-byte names → length ≤ 255, the primary line is present, and fallbacks are trimmed.
  - `test_macro_empty_list`: → `"/cleartarget [dead]"`.
  - `test_cursor_advances_and_resets`: `onTargetName` matches → index 2. `set` with a new top → index 1. A single name never advances.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement both files and add them to the TOC.
- [ ] **Step 4:** Run the tests and confirm they PASS.
- [ ] **Step 5:** Commit `feat(logic): candidate ranking, targeting macro builder and cursor`.

### Task 5: Alert gate, item relevance, quest index

Branch: `feature/logic` (finish), then `feature/quest-index`

**Files:**
- Create: `Logic/AlertGate.lua`, `Logic/ItemRelevance.lua`, `Data/QuestIndex.lua`
- Test: `tests/lua/test_alertgate.lua`, `tests/lua/test_items.lua`, `tests/lua/test_questindex.lua`. QuestIndex tests stub `C_QuestLog` and `LibQuestieDB`.

**Interfaces:**
- **`ns.AlertGate.new({guidCooldown=60, nameCooldown=10}) -> gate`**:
  - `gate:shouldAlert(guid, name, now) -> bool`. It records a hit when it returns true.
  - `gate:prune(now)`.
- **`ns.ItemRelevance.shouldShow(item, ctx, mode) -> bool`**:
  - `mode` is `"always"` or `"relevant"`.
  - `item` fields: `{ pinned, questID, npcNames={[name]=true}, questZoneMatch }`.
  - `ctx` fields: `{ targetName, inQuestArea }`.
  - In `"relevant"` mode the item shows when it is pinned, or `inQuestArea` is true, or `questZoneMatch` is true, or `targetName` is in `npcNames`.
- **`ns.QuestIndex`**:
  - `:Rebuild()` reads the log via `C_QuestLog.GetNumQuestLogEntries` / `GetInfo` (skipping headers) / `GetQuestObjectives`. Only objectives with `finished == false` and type `"monster"` or `"item"` count.
  - `:ByNpcId(id) -> entry|nil` and `:ByName(name) -> entry|nil`.
  - An entry is `{ name, npcIds = {}, quests = { {questID, title, objIndex, text, have, need} } }`.
  - `:Learn(name, questID)` adds tooltip-learned entries for the session.
  - `:QuestNpcNames(questID) -> set` is used by QuestItems.
  - It fires `ULT_QUEST_INDEX_CHANGED`. Rebuilds are debounced 0.5 s via `C_Timer.After`.
  - DB use: `LibQuestieDB.RequireContract(4)` must be ok, and `QuestDB.Get(id,"name")` must equal the live title, case-insensitive and trimmed. Mapping from objectives:
    - `objectives[1]` creature `{npcId, text, idx}`
    - `[5]` kill credit `{npcIds, creditNpc, text, idx}`, using every id in `npcIds`
    - `[3]` item `{itemId, text, idx}` → `ItemDB.Get(itemId,"npcDrops")`, plus one level of `itemDrops` → npcDrops
  - Objective index matching: a DB tuple's index field, when present, ties to `GetQuestObjectives()[idx]`. Otherwise the DB objective's text is matched against the live objective text by substring, and if that fails it is tied to every unfinished objective of the same type.
  - Names come from `NpcDB.Get(id,"name")` and are used only for `ByName` fallback and display.

- [ ] **Step 1:** Write the tests:
  - `test_alertgate`: same GUID within 60 s → false. A different GUID with the same name within 10 s → false. After 11 s → true.
  - `test_items_modes`: covers all four "relevant" triggers, plus `"always"` → true.
  - `test_index_maps_creature_and_drops`: stub quest 100 "Kobold Camp" with objectives `{monster, unfinished}` and `{item, unfinished}`; DB creature 40 and item 500 dropped by npc 41 → `ByNpcId(40)` and `ByNpcId(41)` exist with the right objective `have`/`need`.
  - `test_index_skips_finished`.
  - `test_index_rejects_name_mismatch`: DB name "Other" → no entries.
  - `test_index_contract_fail`: `RequireContract` returns false → index empty, no error, and `ns.QuestIndex.dbOk == false`.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement the files and add them to the TOC.
- [ ] **Step 4:** Run the tests and confirm they PASS.
- [ ] **Step 5:** Commit `feat(logic): alert gate and item relevance` (on `feature/logic`) and merge it. Then commit `feat(data): quest index from quest log and QuestieDB` on `feature/quest-index` and merge that.

### Task 6: Nameplate scanner service

Branch: `feature/targeting`

**Files:**
- Create: `Services/Nameplates.lua`
- Test: `tests/lua/test_nameplates.lua`. Stubs: `C_NamePlate.GetNamePlates`, `C_NamePlate.GetNamePlateForUnit`, the `Unit*` functions.

**Interfaces:**
- **`ns.Nameplates:Snapshot(unit) -> mob|nil`**:
  - `mob` fields: `{ unit, guid, npcId, name, level, classification, dead, tapped, attackable, isPlayer, healthPct, plate }`.
  - Every field is read through `ns.Safe.read`. It returns nil if guid or name is nil.
  - `healthPct` is nil when unreadable.
  - The unit token comes from `plate.namePlateUnitToken`, `plate.unitToken` or `plate:GetUnit()`, each via pcall.
- **`ns.Nameplates:All() -> mob[]`** (current snapshots).
- **`ns.Nameplates:AddListener(owner, {onAdded=fn(mob), onRemoved=fn(unit, guid), onRefresh=fn(mobs)})`** and `:RemoveListener(owner)`.
- Events: `NAME_PLATE_UNIT_ADDED` / `REMOVED`, plus a ticker at `ns.db.core.scanInterval`, default 0.5 and range 0.2–2. The ticker only runs while at least one listener exists.
- **`ns.Nameplates:EnemyPlatesOn() -> bool`** uses `GetCVarBool("nameplateShowEnemies")`.

- [ ] **Step 1:** Write the tests:
  - `test_snapshot_reads_fields`.
  - `test_snapshot_skips_secret_values`: GUID secret → nil, and level secret → mob with `level = nil`, which Filters must treat as failing the level check. Add that case to `test_filters` too.
  - `test_listeners_added_removed`.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement the scanner. Update `Filters.passes` so that `level == nil` → false, `"level"`, unless the mob is a boss.
- [ ] **Step 4:** Run the tests and confirm they PASS.
- [ ] **Step 5:** Commit `feat(services): nameplate scanner with secret-safe snapshots`.

### Task 7: Targeting service, key button, bar, markers

Branch: `feature/targeting` (continued)

**Files:**
- Create: `Services/Targeting.lua`, `Services/TargetBar.lua`, `Services/Markers.lua`, `Bindings.xml`
- Test: `tests/lua/test_targeting.lua`. It stubs `CreateFrame`, recording `SetAttribute` calls, plus `InCombatLockdown`.

**Interfaces:**
- **`ns.Targeting:RegisterProvider(key, fn)`**: `fn(mobs) -> candidates[]`, where each candidate is the Ranking candidate plus `{ mobs = {mob...}, kind = "quest"|"rare", tooltip = fn(GameTooltip) }`. `:UnregisterProvider(key)`.
- **`ns.Targeting:Refresh()`** collects candidates from every provider and merges them by name (`isRare` is OR'd and `count` is summed). It ranks them with `ns.db.targeting.ranking` opts, sets the cursor, and then calls `ns.Combat:Run("targeting.macro", ...)`, which sets `macrotext` on `UltimateTargetButton`. It fires `ULT_TARGETS_CHANGED(ranked, byName)`.
- **Key button:**
  - Global name `UltimateTargetButton`, `SecureActionButtonTemplate`.
  - Attributes: `type="macro"`, `useOnKeyDown` false. `RegisterForClicks("AnyUp","AnyDown")`.
- **Auto-arm:**
  - When `auto-arm` is true, `Refresh` runs on `ULT_QUEST_INDEX_CHANGED`, on nameplate add, remove or refresh, and on `PLAYER_TARGET_CHANGED`. It is throttled to ≤ 4/s.
  - When false, it runs only from the `ULTIMATE_REFRESH` binding or from `/ult scan`.
- **Cursor advance:** `PLAYER_TARGET_CHANGED` → if `UnitName("target")` is readable and `cursor:onTargetName(name)` moved → rebuild the macro.
- **`ns.Targeting:CreateActionBarMacro()`** works out of combat only. It uses `GetMacroIndexByName("UltTarget")` → `EditMacro` or `CreateMacro("UltTarget", "INV_Misc_QuestionMark" or 134400, "/click UltimateTargetButton", nil)`. It prints the result in chat and returns `ok, message`.
- **Bindings.xml:**
  - Header `ULTIMATE`.
  - `CLICK UltimateTargetButton:LeftButton` (name `BINDING_NAME_CLICK UltimateTargetButton:LeftButton`).
  - `ULTIMATE_REFRESH`.
  - `CLICK UltimateQuestItem1..4:LeftButton`.
  - Binding names are defined in `Locale/enUS.lua`.
- **TargetBar** (`ns.TargetBar`):
  - Up to `ns.db.targeting.bar.max` buttons, default 6. Each is a `SecureActionButtonTemplate, ActionButtonTemplate` button with `type="macro"`, `macrotext="/cleartarget\n/targetexact <name>"`.
  - Icon: `Interface\\TargetingFrame\\UI-TargetingFrame-Skull` for bosses, `UI-RaidTargetingIcon_1` (star) for rares, and the quest bang texture `Interface\\GossipFrame\\AvailableQuestIcon` for others.
  - Label: the name in `GameFontNormalSmall`, plus a level `FontString` colored by `GetCreatureDifficultyColor`. Count text shows when `count > 1`.
  - Tooltip: the candidate's `tooltip` fn.
  - The bar is movable when `bar.locked == false`, via a drag handle with a `GameFontNormalSmall` title "Ultimate". Its position is saved in `ns.db.targeting.bar.point`.
  - Orientation and scale come from settings.
  - All button set, attribute and visibility changes go through `ns.Combat:Run("targetbar.layout", ...)`.
- **Markers** (`ns.Markers`):
  - A pool of non-secure frames parented to `UIParent`, anchored above `mob.plate` (BOTTOM to TOP, y = `offset`).
  - The texture is an atlas that is tried in order: `"QuestNormal"`, `"Crosshair_Quest_64"`, `"UI-QuestPoi-QuestNumber-SuperTracked"`. If none of those works, it falls back to the texture `Interface\\Minimap\\MiniMap-QuestArrow` rotated to point down. The atlas used is recorded via `C_Texture.GetAtlasInfo` at load.
  - The top-ranked name gets `size × 1.4` and full alpha. Others get `size` and 0.8 alpha.
  - Color: difficulty color or `NORMAL_FONT_COLOR`.
  - Animation is an `AnimationGroup`: bob (Translation, y ±6, 0.6 s, bounce), pulse (Scale 1.15), or none.
  - Rares get a silver tint and `size × 1.4`.
  - Tagged mobs get no marker.
  - Settings live at `ns.db.targeting.markers`: `{ enabled=true, size=40, offset=10, colorMode="difficulty", anim="bob", topOnly=false }`.

- [ ] **Step 1:** Write the tests:
  - `test_refresh_merges_providers_and_sets_macro`: two providers both give "A" → merged, and `macrotext` is the expected `Macro.build` output.
  - `test_refresh_in_combat_deferred`: no `SetAttribute` during combat, applied after `PLAYER_REGEN_ENABLED`.
  - `test_cursor_advance_on_target_change`.
  - `test_no_providers_empty_macro`.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement Targeting. Then implement TargetBar and Markers; their visuals are verified in-game, and their secure paths go through Combat.
- [ ] **Step 4:** Run the tests and `check.py`, and confirm they PASS.
- [ ] **Step 5:** Commit `feat(targeting): secure target key, bar and overhead markers`, then merge `feature/targeting`.

### Task 8: Sounds, alerts and the Quest Targeting module

Branch: `feature/quest-targeting`

**Files:**
- Create: `Services/Sounds.lua`, `Services/Alerts.lua`, `Modules/QuestTargeting.lua`
- Test: `tests/lua/test_questtargeting.lua`

**Interfaces:**
- **`ns.Sounds.catalog`** is an ordered list of `{key, label, kit}`:

  | key | label | kit |
  |---|---|---|
  | `none` | None | — |
  | `raidwarning` | Raid Warning | `SOUNDKIT.RAID_WARNING` |
  | `readycheck` | Ready Check | `SOUNDKIT.READY_CHECK` |
  | `mapping` | Map Ping | `SOUNDKIT.MAP_PING` |
  | `questadded` | Quest Added | `SOUNDKIT.UI_QUEST_ADDED` or `IG_QUEST_LIST_OPEN` |
  | `alarm` | Alarm | `SOUNDKIT.ALARM_CLOCK_WARNING_3` |
  | `toast` | Toast | `SOUNDKIT.UI_BNET_TOAST` |
  | `levelup` | Level Up | `SOUNDKIT.LEVEL_UP` / 888 |
  | `pvpqueue` | PvP Queue | `SOUNDKIT.PVP_THROUGH_QUEUE` |
  | `auction` | Auction Open | `SOUNDKIT.AUCTION_WINDOW_OPEN` |
  | `whisper` | Whisper | `SOUNDKIT.TELL_MESSAGE` |

  Entries whose kit resolves to nil are filtered out at load.
- **`ns.Sounds:Play(key, channel)`** calls `PlaySound(kit, channel or "Master")`. **`ns.Sounds:Options()`** returns the dropdown container.
- **`ns.Alerts:Notify({ soundKey, text, color, guid, name })`** passes through the module-owned AlertGate. It plays the sound, and when `showText` is on it calls `RaidNotice_AddMessage(RaidWarningFrame, text, color)`.
- **QuestTargeting module** (key `"questTargeting"`, `defaultEnabled = true`).
  - Defaults:
    - filters as in Task 3
    - `alerts = { enabled=true, showText=true, guidCooldown=60, nameCooldown=10, channel="Master", sounds = { regular="mapping", elite="raidwarning", boss="alarm" }, levelSounds = { enabled=false, easy="questadded", dangerous="alarm" } }`
    - `prompts = { enemyPlates = true }`
    - `tooltipLearning = true`
  - `OnEnable`:
    - Registers the provider `"quest"`, which maps mobs through `QuestIndex:ByNpcId(mob.npcId) or ByName(mob.name)` and the filters, and builds candidates with `remaining = min(need-have)`, `pinned` from `ns.db.questTargeting.pinned[questID]`, and a tooltip listing quest title and `text have/need`.
    - Adds a nameplate listener `onAdded`. That listener alerts when a mob passes the filters, is untagged and is quest-relevant. The sound category is boss if level −1 or worldboss, elite if elite, else regular, or levelSounds when enabled.
    - Tooltip learning: on `onAdded`, if the mob is not indexed, scan `C_TooltipInfo.GetUnit(unit)` lines for `Enum.TooltipDataLineType.QuestObjective` with `completed ~= true`, under a preceding `QuestTitle` line whose text matches an open quest title, then `QuestIndex:Learn(name, questID)`. This is limited to 12 per second.
    - Enemy-plates prompt: if `EnemyPlatesOn()` is false and `prompts.enemyPlates` is true, show `StaticPopup "ULTIMATE_ENEMY_PLATES"` with Enable / Not now / Don't ask again. Enable → `ns.Combat:Run("cvar.plates", function() SetCVar("nameplateShowEnemies","1") end)`.
  - `OnDisable` unregisters the provider and listener.
  - `/ult scan` prints the index entries and the nearby candidates with their filter reasons.

- [ ] **Step 1:** Write the tests:
  - `test_provider_builds_candidates`: an indexed mob plus a passing filter → a candidate with the right `remaining`, and a tapped one is excluded.
  - `test_alert_category_selection`: boss / elite / regular / levelSounds dangerous.
  - `test_alert_suppressed_for_tapped_and_cooldown`.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement the three files and add them to the TOC.
- [ ] **Step 4:** Run the tests and confirm they PASS.
- [ ] **Step 5:** Commit `feat(quest-targeting): quest mob provider, alerts, tooltip learning`, then merge.

### Task 9: Rare Scanner and Quest Items modules

Branch: `feature/rares-items`

**Files:**
- Create: `Modules/RareScanner.lua`, `Modules/QuestItems.lua`
- Test: `tests/lua/test_rares.lua`, `tests/lua/test_questitems.lua`

**Interfaces:**
- **RareScanner** (key `"rareScanner"`, `defaultEnabled = true`).
  - Defaults: `{ sound="raidwarning", showText=true, alertTagged=true, barMode="first", watch={}, cooldown=300 }`, where `barMode` is `"first"|"ranked"|"hidden"`.
  - A rare is `classification ∈ {rare, rareelite, worldboss}` or a name in `watch`.
  - The provider `"rare"` gives candidates with `isRare = true` for untagged, live, attackable rares. With `barMode="hidden"` it gives nothing. With `"ranked"` it sets `isRare=false` for ranking but keeps the rare marker.
  - Alerts: text `RARE: <name> (<level> <Elite/Rare>)`. If tagged and `alertTagged` is on, `" (tagged)"` is appended and no candidate is created.
  - `history`: the last 20 `{name, level, zone=GetZoneText(), time}`, kept for the session only.
- **QuestItems** (key `"questItems"`, `defaultEnabled = true`).
  - Defaults: `{ mode="relevant", max=4, orientation="HORIZONTAL", scale=1, locked=true, point=nil, pinned={}, hideEmptyInCombat=false }`.
  - Item sources:
    1. For each log entry, `GetQuestLogSpecialItemInfo(logIndex)` → link → itemID.
    2. Bags: `C_Container.GetContainerNumSlots` / `GetContainerItemInfo` / `GetContainerItemQuestInfo`, keeping items with `questID` or `isQuestItem` for which `C_Item.GetItemSpell(itemID)` is non-nil (usable).
  - `ctx.inQuestArea`: `C_QuestLog.IsOnMap(questID)` if it exists, else false. `questZoneMatch`: the quest's header zone equals `GetZoneText()`. `npcNames`: `QuestIndex:QuestNpcNames(questID)`.
  - Buttons: `UltimateQuestItem1..max`, `SecureActionButtonTemplate, ActionButtonTemplate`, `type="item"`, `item="item:<id>"`.
    - Icon via `C_Item.GetItemIconByID`. Count via `C_Item.GetItemCount`. Cooldown via `C_Container.GetItemCooldown` → `CooldownFrame_Set`.
    - Tooltip: `GameTooltip:SetItemByID` plus a quest title line.
    - Shift-click toggles pin. This is handled in PreClick only out of combat; it updates `pinned` and re-lays out via Combat.
    - Drag start → `C_Item.PickupItem(itemID)` (out of combat).
  - Re-evaluate on `BAG_UPDATE_DELAYED`, `QUEST_LOG_UPDATE`, `PLAYER_TARGET_CHANGED`, `ZONE_CHANGED*` and `ULT_QUEST_INDEX_CHANGED`. Layout goes through `ns.Combat:Run("questitems.layout", ...)`. Cooldown and count update on `BAG_UPDATE_COOLDOWN` / `SPELL_UPDATE_COOLDOWN` with no combat restriction (not secure).
  - **`ns.QuestItems:Collect() -> items[]`** returns `{ itemID, questID, title, pinned, npcNames, questZoneMatch }`. It is separated from the layout so it can be tested.

- [ ] **Step 1:** Write the tests:
  - `test_rare_detection`: classification and watch list.
  - `test_rare_tagged_alert_no_candidate`.
  - `test_rare_barmode`.
  - `test_collect_special_and_bag_items`: dedupes the same itemID from both sources.
  - `test_layout_deferred_in_combat`.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement both modules and add them to the TOC.
- [ ] **Step 4:** Run the tests and confirm they PASS.
- [ ] **Step 5:** Commit `feat(rares): always-on rare scanner` and `feat(quest-items): relevant quest item bar` as separate commits, then merge.

### Task 10: Settings UI

Branch: `feature/settings`

**Files:**
- Create: `Settings/Builder.lua`, `Settings/Panel.lua`. Modify each module to add `BuildSettings(cat, layout, B)`.
- Test: `tests/lua/test_settings.lua`. Stub `Settings.*` to record created controls.

**Interfaces:**
- **`ns.SettingsBuilder` (`B`)**. Each control uses `Settings.RegisterProxySetting(cat, "ULTIMATE_"..id, Settings.VarType.X, label, default, getter, setter)`, so the values live in our db, and every setter fires `ULT_SETTING_CHANGED(path)`. Functions:
  - `B.Header(layout, text)`
  - `B.Checkbox(cat, path, label, tooltip)`
  - `B.Slider(cat, path, label, min, max, step, fmt, tooltip)`
  - `B.Dropdown(cat, path, label, options{ {value,label} }, tooltip)`
  - `B.Button(layout, label, buttonText, fn, tooltip)` uses `CreateSettingsButtonInitializer`.
  - `B.List(layout, path, label)` is a custom element initializer using `SettingsListElementTemplate` + `InputBoxTemplate` + `UIPanelButtonTemplate` "Add", and rows with "Remove". It edits a name set.
  - `B.Order(layout, path, label)` reorders the ranking criteria with up/down buttons and an enable checkbox per row.
- `path` is a dotted path into `ns.db`, e.g. `"questTargeting.filters.minOffset"`. **`B.get(path)` / `B.set(path, v)`** resolve it.
- **Panel:**
  - Root category "Ultimate":
    - a master checkbox per module (`ns.Modules:SetEnabled`)
    - global options: lock all bars, reset positions button, scan interval slider, debug checkbox, profile scope dropdown (char/account; the change needs `/reload`, and an `ULTIMATE_RELOAD` StaticPopup offers it)
    - the "Create action-bar macro" button
    - the Key Bindings shortcut button
  - Subcategories:
    - "Quest Targeting": filters, ranking order + pinned quests (dropdown of current log quests + list), alerts per category with a sound dropdown and a ▶ preview button, markers, target bar, enemy-plates status line
    - "Rare Scanner"
    - "Quest Items"
  - **`ns.OpenSettings()`** calls `Settings.OpenToCategory(rootCategory:GetID())`.
  - `## AddonCompartmentFunc: Ultimate_OnCompartmentClick` in the TOC; the global function calls `ns.OpenSettings`.
- **Reacting to changes:** `Targeting`, `Markers`, `TargetBar`, `QuestItems` and `Nameplates` listen to `ULT_SETTING_CHANGED` and re-apply settings, through Combat when the change touches anything secure.

- [ ] **Step 1:** Write the tests:
  - `test_path_get_set`.
  - `test_checkbox_writes_db_and_fires_event`.
  - `test_panel_registers_all_categories`: the root plus 3 subcategories, and each module toggle exists.
- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement Builder, Panel and each module's `BuildSettings`, covering every setting listed in spec §4.3–4.8, §5, §7 and §8.
- [ ] **Step 4:** Run the tests and `check.py`, and confirm they PASS.
- [ ] **Step 5:** Commit `feat(settings): native Blizzard settings panel for all modules`, then merge.

### Task 11: Docs, deploy, final verification

Branch: `feature/docs`

**Files:**
- Create: `docs/testing.md`, which is the in-game checklist from spec §10 and covers every item in spec §13. Update `README.md` with install, deploy, test, slash commands and features.

- [ ] **Step 1:** Write the docs.
- [ ] **Step 2:** Run `python tests/run.py` and `python scripts/check.py`. Expected: all pass and `OK`.
- [ ] **Step 3:** Run `powershell -File scripts/deploy.ps1`. Expected: a junction at `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Ultimate` pointing to the repo's `Ultimate/`, and the script prints the target. If that needs admin rights, use a copy instead and say so.
- [ ] **Step 4:** Commit `docs: in-game testing checklist and README`, merge, and run the whole-branch review.
