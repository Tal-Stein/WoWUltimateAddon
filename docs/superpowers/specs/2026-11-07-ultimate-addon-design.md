# Ultimate: WoW Forever add-on design

Date: 2026-11-07
Status: final draft. The owner has not reviewed this document line by line; they asked for autonomous build after the Q&A, so the build proceeds from it.

## 1. Intent

"Ultimate" is a private add-on for the owner (and maybe one friend), played on the **official
WoW Forever servers**. It is a home for a growing set of separate features. Each feature can be
switched on or off, and almost every design choice is a setting you change in-game rather than
something fixed in code.

The first feature is **Quest Targeting**. Questing means hunting for the right mobs. The
add-on should notice when a mob that matters for the owner's quests is nearby, tell them about
it, make it easy to see on screen, and let one key press target it. The second feature,
**Quest Items**, puts quest items that need to be used on clickable buttons so the owner never
has to dig through bags. The owner liked how functional RestedXP's item bar and targeting were,
and that is the bar to meet.

### Non-goals and anti-goals

- **No working around Blizzard restrictions.** This is the owner's explicit rule. If the
  client blocks something (automatic targeting, reading secret values in combat, changing secure
  attributes in combat), the add-on does without it. It does not use hacks, taint tricks or
  timing exploits. *Anti-goal:* anything that could get the account actioned or that the client
  marks "action blocked".
- **No direction arrow toward mobs or quest areas.** Considered and dropped by the owner. The
  on-screen marker above nameplates replaces it.
- **No elaborate tagged-mob handling.** The game already greys out tagged mobs. The add-on
  leaves tagged mobs out of its own marks, alerts and ranking wherever that's easy, and does
  nothing cleverer.
- **No own quest database.** Questie's database is used, and Questie is a required dependency.
- **Not a guide add-on.** No step-by-step routing like RestedXP's guides.
- *Anti-goal:* UI that looks foreign. Everything must feel like part of Blizzard's own UI (§6).

## 2. Platform constraints (researched)

- **Client:** WoW Forever, game version 1.60.1, `## Interface: 16001`. It runs the modern client
  with most of the 12.x (Midnight) API, including Midnight's add-on restrictions. Installed at
  `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`.
- **Secret values:** many unit and quest return values may be "secret" (unreadable) in combat.
  Every read of a unit value is guarded with `issecretvalue` (when that global exists) plus
  `pcall`. When a value is unreadable, the add-on treats that unit as unknown and skips it. It
  does not guess.
- **Targeting:** an add-on can only target from a **hardware event**: a key press or a click on a
  `SecureActionButtonTemplate` button. Prior art (QuestTargets on Forever) found that secure
  `unit=nameplateN` targeting **does not work** on this client, and that `/targetexact <name>`
  macrotext works. So all targeting is **by name**.
- **Combat lockdown:** secure attributes (macrotext, item, shown/hidden state of secure buttons)
  cannot change while `InCombatLockdown()` is true. Changes are queued and applied on
  `PLAYER_REGEN_ENABLED`. While in combat, buttons keep their last state.
- **Quest data:** LibQuestieDB (from the `QuestieDB` add-on, which ships with Questie) is global
  `LibQuestieDB`, contract version 4. Its API:
  - `LibQuestieDB.RequireContract(n)`.
  - `QuestDB.Get(id, "objectives")`: `{ [1]=creature {npcId,text,idx}, [3]=item {itemId,text,idx}, [5]=killCredit {npcIds,creditNpc,text,idx}, ... }`.
  - `ItemDB.Get(id,"npcDrops")`.
  - `NpcDB.Get(id,"name"|"minLevel"|"maxLevel"|"rank")`.
  - Quest IDs may differ on Forever, so a DB quest is used only if its name matches the live
    quest title. This follows the QuestTargets approach.
- **Tooltip reading:** `C_TooltipInfo.GetUnit("nameplateN")` returns lines typed
  `Enum.TooltipDataLineType.QuestObjective` / `QuestTitle`, and it works on Forever. It is the
  fallback and supplementary relevance source.

## 3. Architecture

The add-on is a single folder, `Ultimate/`. The repository root holds `Ultimate/`, `docs/`,
`tests/` and dev scripts.

- **Core**:
  - namespace
  - event bus
  - SavedVariables with per-character profile plus account-wide defaults
  - defaults merge
  - module registry
  - combat-safe queue
  - secret-safe helpers
  - slash command `/ult`
- **Module contract:** each feature registers `{ key, name, description, defaults, OnEnable,
  OnDisable, BuildSettings }`.
  - The core shows a master enable/disable checkbox per module.
  - Disabling a module unregisters its events and hides its frames immediately. If the module
    is a secure frame and the player is in combat, this happens when combat ends.
  - New features slot in as new modules without touching existing ones.
- **Pure logic is separated from WoW glue.** Filtering, ranking, macro building, name
  sanitising, level-color bucketing and alert de-duplication are plain Lua functions with no
  WoW globals, unit-tested outside the game.
- **Modules in v1:**
  1. **QuestTargeting**: the quest-mob index, nameplate scanner, ranking, target key, target
     bar, overhead markers, raid marker, sound alerts.
  2. **RareScanner**: always-on detection of rare, rare-elite and world-boss mobs, quest or not,
     with its own alert and marker. It shares the nameplate scanner service.
  3. **QuestItems**: the quest item bar.
- **Shared services:** NameplateScanner (one pass, many listeners), Sounds (catalog + play),
  Settings UI builder, and **Targeting** (the target key, target bar and overhead markers).
  Targeting is a core service, not part of a module. Modules *feed it candidates*:
  QuestTargeting feeds quest mobs, RareScanner feeds rares. If a module is disabled, its
  candidates disappear. If both are disabled, the bar hides and the key does nothing.
- **Identity is the NPC ID, not the name.** The NPC ID is parsed from `UnitGUID`
  (`Creature-0-...-<npcID>-...`) when readable. Quest relevance is matched on NPC ID from
  QuestieDB, so it doesn't depend on locale. The name used in `/targetexact` is always the
  **live `UnitName` from the nameplate**, so the macro uses the client's own language. Matching
  falls back to the DB name only when the GUID is unreadable.

## 4. Feature: Quest Targeting

### 4.1 Which mobs are relevant (the quest-mob index)

The index is rebuilt on `QUEST_LOG_UPDATE`, `QUEST_ACCEPTED`, `QUEST_REMOVED` and
`UNIT_QUEST_LOG_CHANGED("player")`, debounced to about 0.5 s.

- Read the live quest log (`C_QuestLog.GetNumQuestLogEntries`, `GetInfo`,
  `GetQuestObjectives`). Keep only **unfinished** objectives of type `monster` / `item`
  (`finished == false`). Completed quests and objectives contribute nothing.
- For each such quest, use QuestieDB if the DB quest name matches the live title:
  - creature objectives → NPC IDs
  - kill-credit objectives → NPC IDs
  - item objectives → `npcDrops` NPC IDs, following `itemDrops` one level
- Resolve each NPC ID → name via `NpcDB`, plus DB level and rank for display fallback.
- **Tooltip supplement:** on a nameplate scan, units not in the index whose tooltip has an
  unfinished `QuestObjective` line for an open quest are added as relevant for this session.
  This covers DB gaps.
- Output: `index[name] = { questIDs, objectives = {questID, objIndex, text, have, need}, npcIDs }`.
- An exclusion list (names) and per-quest "ignore" toggles remove entries.

### 4.2 Nearby detection

- The NameplateScanner listens to `NAME_PLATE_UNIT_ADDED/REMOVED`. It also runs a light
  ticker (default 0.5 s, setting 0.2–2 s) to refresh tapped/dead/level state.
- Per plate it reads, with secret guards:
  - `UnitName`
  - `UnitGUID` (dedupe)
  - `UnitLevel`
  - `UnitClassification`
  - `UnitIsDead`
  - `UnitCanAttack("player", u)`
  - `UnitIsTapDenied(u)`
  - `UnitIsPlayer`
- **Requires enemy nameplates.** If they are off, show a one-time, Blizzard-styled prompt
  with a button to turn them on (`SetCVar("nameplateShowEnemies", 1)`, out of combat only).
  Also show a small warning line in the settings panel while they're off.

### 4.3 Filters (all in settings)

| Setting | Default |
|---|---|
| Level window relative to player: min offset / max offset | −10 / +3 |
| Hide grey (no XP) mobs | on |
| Include elites | on |
| Include bosses (worldboss / `??` / level −1) | off |
| Hide tagged mobs (`UnitIsTapDenied`) | on |
| Hide dead | always |
| Exclusion list (names) | empty |

The difficulty color and "grey" use Blizzard's own `GetCreatureDifficultyColor(level)` /
`GetQuestDifficultyColor` and `UnitIsTrivial` where readable.

### 4.4 Ranking (all in settings)

- An ordered list of criteria the owner can reorder. Each criterion can be on or off.
  - **Pinned quests first.** The owner pins quests.
  - **Lowest level first**, with a setting to flip to highest.
  - **Closest to completing**: the objective with the smallest `need − have`.
  - **Most wounded**: health percentage, when readable.
  - **Fewest visible** or **most visible**: off by default.
- Default order: Pinned → Lowest level → Closest to completing.
- Ties break by stable order (first seen).
- The ranking is computed over **untagged, filter-passing, visible** mobs. It produces an
  ordered list of **names** (targeting is by name, §2).

### 4.5 The target key and macro

- A secure button, `UltimateTargetButton`, has
  `type="macro"` and `macrotext="/cleartarget\n/targetexact <Top Name>"`.
- Options:
  - fall back to the 2nd/3rd name if `[noexists]`
  - `/stopmacro [combat,exists,harm,nodead]` so a press in combat doesn't drop your current
    target, on by default
  - append a raid-marker line
- Byte budget: 255.
- Names are sanitised by stripping `[%c%[%];/|]`.
- Bindable through `Bindings.xml` → "Ultimate: Target next quest mob". It shows in Blizzard's
  Key Bindings UI under an "Ultimate" header.
- **Global macro option.** A settings button "Create action-bar macro" creates or updates one
  account macro "UltTarget" whose body is `/click UltimateTargetButton`. The owner drags it to
  a bar. It is created only out of combat and only when the owner clicks the button.
- **Pressing again cycles to the next ranked *name*.** The button keeps a cursor into the
  ranked name list. On `PLAYER_TARGET_CHANGED` (out of combat), if the new target's name equals
  the cursor's name, the cursor advances and the macrotext is rewritten for the *next* name.
  So press 1 targets name A and press 2 targets name B. The cursor resets to the top whenever
  the ranking's top changes or the target is cleared or dead. When only one name is ranked, the
  macro is simply `/targetexact A`. Whether the client itself rotates among same-named mobs on
  repeated `/targetexact` is left to the game (§13). Macro shape:
  `/stopmacro [combat,exists,harm,nodead]` (optional) → `/cleartarget [dead][help]` →
  `/targetexact <cursor name>` → `/targetexact [noexists] <next name>` (fallback, as budget
  allows) → optional `/tm` line.
- **Auto-arm** (on by default): the macrotext refreshes automatically whenever the ranking
  changes out of combat. With auto-arm off, the macro refreshes only when the owner presses a
  separate "refresh" binding or opens the bar.
- In combat the macrotext is frozen. That's fine: you pick your next pull out of combat.

### 4.6 Target bar

- A movable, lockable horizontal or vertical bar. The owner picks the orientation, scale and
  max buttons (default 6). Its position is saved per character. When unlocked, it uses
  Blizzard's edit-mode-style highlight for dragging.
- One secure button per **visible quest mob name**, in rank order. Each button shows:
  - the mob name in `GameFontNormalSmall`
  - the level in the difficulty color, with `??` or a skull icon for bosses
  - an elite or rare dragon border, using Blizzard's elite/rare classification atlases
  - a count badge if several are visible
- Clicking a button targets that name. Hovering shows a `GameTooltip` with the quest title(s)
  and objective progress, for example "Kobold Miner slain: 4/10".
- Tagged-only names (every visible instance tagged) are shown desaturated and not ranked, or
  hidden. Setting, default hidden.
- Button layout changes are queued in combat. Visual-only updates (desaturation, counts on
  non-secure child textures) may update in combat.

### 4.7 On-screen marking (overhead indicator)

- A large, animated, non-secure texture anchored above each relevant **untagged** mob's
  nameplate. The default is Blizzard's quest-objective bang/arrow art: a bobbing down-arrow
  atlas, chosen from in-game atlases at build time and recorded in code.
- The **top-ranked** name gets a larger or brighter variant. Other relevant mobs get a smaller
  variant.
- Settings:
  - on/off
  - size
  - vertical offset
  - color mode (difficulty color / fixed gold)
  - animation (bob / pulse / none)
  - "top-ranked only"
- **Raid marker** option (off by default): put the chosen raid target icon (default skull) on
  the top-ranked mob when targeted with the key.
  - Achieved by appending `/tm [exists,harm,nodead] N` to the macro, using the target-marker
    slash command, which needs a hardware event and gets one.
  - Only when solo, or also in a party (setting).
  - The add-on never marks units outside a hardware event.

### 4.8 Sound and visual alerts ("quest mob in range")

- **Trigger:** a relevant, filter-passing, **untagged** mob's nameplate appears and its GUID
  hasn't alerted in the last N seconds (setting, default 60). There is also a per-name cooldown
  (default 10 s) to avoid packs spamming.
- **Categories**, each with on/off and its own sound picked from a dropdown with a ▶ preview
  button:
  1. Regular quest mob
  2. Elite quest mob
  3. Boss quest mob (worldboss / level −1)
  4. Optional level-based override: "dangerous" (red/orange) vs "easy" (green/yellow). When on,
     it replaces the category-1 sound.
- **Sound catalog:** about 10 built-in game sounds by `SOUNDKIT` (e.g. `RAID_WARNING`,
  `READY_CHECK`, `UI_QUEST_ROLLING_FORWARD_01` / map ping, `ALARM_CLOCK_WARNING_3`,
  `IG_QUEST_LIST_OPEN`, `UI_BNET_TOAST`, `GS_TITLE_OPTION_EXIT`, `PVP_THROUGH_QUEUE`, …), plus
  "None". The exact IDs are verified to exist via `SOUNDKIT[...]` at runtime, and missing ones
  are dropped from the list.
- **Channel:** a setting picks Master / SFX / Dialog, default Master.
- **Visual:** optional text in `RaidWarningFrame` style (`RaidNotice_AddMessage`), with an
  alternative of `UIErrorsFrame`, e.g. "Quest mob: Kobold Miner (7)", colored by difficulty.

## 5. Feature: Rare Scanner (always-on)

- It uses the same NameplateScanner. It fires for classification `rare`, `rareelite` or
  `worldboss`, whether quest-related or not, if the mob is alive and attackable. It optionally
  ignores tagged rares (default: still alert, but say "(tagged)").
- **Own sound** (default `RAID_WARNING`) and own visual line "RARE: Mor'Ladim (35 Elite)".
  It gets a special overhead marker (silver-dragon / star variant) and appears as a highlighted
  button at the **front** of the target bar. A setting chooses: rares first / ranked normally /
  separate.
- **Watch list:** a custom list of NPC names to treat like rares.
- **Tagged rares:** the alert still fires, with "(tagged)" appended and only when the setting
  allows. They get no overhead marker and no bar button, which matches the general tagged rule.
- **Key and bar:** rares are Targeting candidates. With "rares first" (default) an untagged
  rare is ranked ahead of every quest mob, so the key targets it first.
- **History:** remembers the last 20 sightings for the session.
- Its own module toggle, on by default.

## 6. Look and feel: "as built in as possible"

- **Settings:**
  - Use Blizzard's Settings panel (`Settings.RegisterVerticalLayoutCategory` +
    `RegisterAddOnCategory`), with one top category "Ultimate" and one subcategory per module.
  - Controls are native: `Settings.CreateCheckbox`, `Settings.CreateSlider`,
    `Settings.CreateDropdown`, and section headers via
    `CreateSettingsListSectionHeaderInitializer`.
  - Lists (exclusions, watch list, ranking order, pinned quests) need custom rows. Those use
    Blizzard templates (`SettingsListElementTemplate`, `UIPanelButtonTemplate`,
    `InputBoxTemplate`).
  - Prior art notes Forever quirks: keep registration data plain, use `AddModifyPredicate`, and
    use texture paths rather than objects.
- **Fonts:** `GameFontNormal` (gold), `GameFontHighlight` (white), `GameFontNormalSmall`,
  `GameFontDisable`. No custom fonts.
- **Colors:** `NORMAL_FONT_COLOR`, `HIGHLIGHT_FONT_COLOR`, `GetCreatureDifficultyColor`,
  `RAID_CLASS_COLORS` where relevant.
- **Buttons and icons:**
  - `ActionButtonTemplate`-style look: `SecureActionButtonTemplate` + the standard
    icon/border/cooldown/hotkey/count regions (`ActionButtonTemplate` visuals).
  - Masque is not required.
  - Elite and rare art via the Blizzard classification atlases. Raid icons via
    `UI-RaidTargetingIcon_N`.
- **Tooltips:** `GameTooltip` with standard quest-objective formatting.
- **Bindings:** `Bindings.xml` with `BINDING_HEADER_ULTIMATE` and localized names.
- **Alerts:** `RaidNotice_AddMessage(RaidWarningFrame, …)`, popups via `StaticPopupDialogs`.
- **Minimap button:** off by default. Uses LibDBIcon only if the owner wants it later (not in
  v1). Opening is via `/ult`, the AddOn compartment (`## AddonCompartmentFunc`) if Forever
  supports it, and the Settings panel.

## 7. Feature: Quest Items

- **Source of items:**
  1. Quest log special items: `GetQuestLogSpecialItemInfo(logIndex)` /
     `C_QuestLog`-equivalent, the same source Blizzard's own objective tracker uses.
  2. Bag items whose tooltip/`C_Item` data says they start a quest or are usable quest items:
     `C_Container.GetContainerItemQuestInfo` (`isQuestItem`, `questID`, `isActive`) plus
     `C_Item.IsUsableItem` / `GetItemSpell`.
  3. QuestieDB `sourceItemId` / `requiredSourceItems` for active quests, when present in bags.
- **Show mode** (setting):
  - **"Only when relevant"** (default): show the button when any of these hold:
    - the player is in the quest's zone (`zoneOrSort` / `C_QuestLog.IsOnMap` / quest's map ==
      player's map)
    - the current target's name is in the quest's objective NPC set
    - the quest has a special item and its objective area (`C_QuestLog.IsQuestInArea` or the
      equivalent, if available) contains the player
    - **plus** an always-show override per item (shift-click to pin)
  - **"Always while in bags"**.
- **Bar:**
  - A movable, lockable action-style bar of `SecureActionButtonTemplate` buttons with
    `type="item"`, `item="item:ID"`.
  - Each button shows the icon, cooldown spiral (`CooldownFrame_Set`), count, out-of-range
    tint (`C_Item.IsItemInRange` on target where allowed) and a hotkey label.
  - Bindable: "Ultimate: Use quest item 1..4".
  - Buttons are **draggable to action bars** (`C_Item.PickupItem`), like RestedXP.
  - Tooltip: the item tooltip plus the quest title.
- Combat: the button set and positions only change out of combat. While in combat, newly
  relevant items wait. Cooldowns and counts update live.
- Settings: on/off, show mode, max buttons, orientation, scale, lock, hide-in-combat-if-empty,
  "auto-use on target" (**not possible**, needs a hardware event, so not offered).

## 8. Core settings

- Per module: master toggle.
- Global:
  - lock all bars
  - reset positions
  - debug output (off)
  - profile scope: per character (default) / account
- `/ult` opens settings. Subcommands:
  - `/ult debug`
  - `/ult reset`
  - `/ult scan`: prints the current quest-mob index and nearby state, for in-game verification.

## 9. Error handling

- Every event handler runs through a guarded dispatcher (`xpcall` with a stack trace). Errors
  are printed once per unique message in debug mode and otherwise counted silently. One
  failure must not stop other modules.
- The TOC lists `## Dependencies: Questie, QuestieDB` (hard, the owner's choice), so a
  *missing* Questie means the add-on doesn't load. If QuestieDB is present but
  `RequireContract(4)` fails, a one-time popup explains it, and Quest Targeting runs on the
  tooltip supplement (§4.1) alone. That's the same code path, not a separately built mode.
- "Action blocked" must never occur. All secure changes go through the combat queue.

## 10. Testing

- **Offline unit tests:** the pure modules (filters, ranking, macro builder and byte budget,
  sanitiser, alert cooldowns, level buckets, show-mode logic for items) are run with a Lua 5.1
  runtime (LuaJIT through Python `lupa`, or a standalone Lua if installed). There is a tiny
  test runner in `tests/`.
- **Static checks:** `luacheck` if available, else a Lua `loadstring` syntax check of every file
  plus a TOC file-list check.
- **In-game verification checklist** (`docs/testing.md`) for the owner:
  - nameplates prompt
  - `/ult scan` output
  - target key press
  - cycling
  - alert sounds
  - item bar in and out of combat
  - no "action blocked"
- **Dev deploy script:** `scripts/deploy.ps1` copies or junctions `Ultimate/` into the Forever
  AddOns folder.

## 11. Git etiquette

- `main` holds the spec and plan. Feature work happens on `feature/*` branches with small,
  focused commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`). Branches merge back with
  `--no-ff` after tests pass.
- There is no remote. Nothing is pushed unless the owner asks.

## 12. Calls made by the builder (not decided by the owner)

- Default values for every setting in the tables above.
- Name/folder `Ultimate`, slash `/ult` (owner accepted the suggestion).
- Per-character profile by default.
- The specific sound list and overhead art.
- Rare scanner as its own module, on by default. Rares shown at the front of the target bar.
- Raid-marker via `/tm` inside the target macro, off by default.
- "Auto-arm" on by default.
- No minimap button in v1.

## 13. Open for in-game verification (cannot be confirmed offline)

- Whether repeated `/targetexact` cycles among same-named mobs.
- Exact atlas names available on Forever for overhead arrows and elite/rare borders. Fall back
  to texture paths.
- Whether `UnitIsTapDenied` / `UnitClassification` / `UnitLevel` return secret values for
  nameplates out of combat.
- Whether `/tm` and `AddonCompartmentFunc` exist on Forever.
- Which quest-area API (`C_QuestLog.IsOnMap`, `IsQuestInArea`) is available, for the item show
  mode.
