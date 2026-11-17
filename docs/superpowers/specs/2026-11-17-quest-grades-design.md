# Quest Grades — design

Date: 2026-11-17 · Status: draft for owner review

## Intent

Help the everyday leveler decide, on the spot, whether a quest is worth their time. The owner
doesn't want one fixed definition of "worth it": some sessions they want to level fast, other
sessions they want gear. So Ultimate shows where a quest's time goes and how it pays off, and
the player decides.

## Goals

- Grade every quest the player has or can pick up, on separate axes:
  - **Leveling 1–5**: XP per minute at the player's level.
  - **Gear 1–5 or "–"**: the best reward's upgrade for the player's class and spec. "–" means
    nothing useful.
- Show the raw facts behind the grades: estimated time (travel and objectives), XP, reward
  upgrade, route inclusion, chain unlocks.
- Two display modes, chosen in the options:
  - **Separate grades** (default): Leveling and Gear grades side by side, plus the time
    estimate and warning icons.
  - **Unified grade**: one 1–5 grade from a playing style.
    - Presets: Balanced, Speed leveling, Gear hunter.
    - A Custom style exposes the weight sliders.
- Learn from the player: time each quest from accept to turn-in, show "took you X (est. Y)",
  and use the player's own history to correct later estimates.

## Non-goals

- No scraping of Wowhead or other sites (their terms forbid it, and the data is noisy).
- No sharing of time data between players. History is local to the account.
- No auto-accepting, auto-abandoning or routing. Ultimate informs; the player decides.

## Anti-goals (a failure even if it works)

- Grades that look authoritative but rest on guesses. Every grade has a tooltip that shows its
  inputs, and missing data shows as "?" or "–", never as a made-up number.
- Breaking the native WoW look: use Blizzard fonts, icons and atlas art.
- Slowing the game: grading is lazy and cached, never computed per frame.

## Constraints (standing owner rules)

- Questie and its database (LibQuestieDB, contract 4) are required. Ultimate reads it
  defensively.
- If Blizzard blocks something, don't work around it.
- Every UI control gets the standard right-click menu (lock, hide, settings) via ns.Menu.
- TDD with the lupa harness (`python tests/run.py`). Every Lua file is listed in the TOC
  (`python scripts/check.py`).
- Push main after each finished iteration.

## Data sources (verified on disk)

| Signal | Source |
|---|---|
| Base XP and quest level | QuestieDB `support/Forever/QuestXP/xpDB-classic.lua` (`{level, xp}` per quest ID); quest `questLevel` |
| Objectives | QuestieDB quest `objectives` (creatures, objects, items) |
| Drop rates | QuestieDB `support/Forever/DropTables/classicItemDrops.lua` (item → npc → %) |
| Positions | QuestieDB npc/object `spawns`; quest `startedBy` / `finishedBy` |
| Elite, group, escort, timed | quest `questFlags` / `specialFlags` / `triggerEnd`; npc `rank` |
| Chains | quest `nextQuestInChain`, `childQuests`, `preQuestSingle/Group` |
| Rewards | item `questRewards` (item → quests); the live quest frame/log for the exact reward list when available |
| Gear value | GearQuestForever's scoring (`GQ.Compare:ScoreItemStats`) when that add-on is loaded; otherwise a simple fallback (item level and quality vs. the equipped slot) |
| Route inclusion | Leveling guides the player has loaded (RestedXP, Guidelime, FlowUp), read at runtime. Nothing from them is copied into Ultimate. |
| Reputation | quest `reputationReward` |

## How the numbers are made

- **XP now** = base XP with the classic low-level penalty for the player's level vs. quest level.
- **Time estimate** (minutes) = travel + objectives.
  - Travel: path giver → objective area → turn-in. Straight-line distance at running speed
    plus a per-zone-change constant.
  - Objectives: kills needed (count, or count ÷ drop rate for item drops) × seconds per kill
    (by level gap and elite), plus object interactions.
  - Once the player has history, a personal multiplier corrects the estimate.
- **Leveling grade**: XP now ÷ estimated minutes, ranked against the comparison set (default:
  every quest the player has or can pick up within ±5 levels), then turned into 1–5 by
  percentile.
- **Gear grade**: the best reward's upgrade over the equipped item in that slot, for the
  player's spec, turned into 1–5. "–" when no reward is an upgrade.
- **Unified grade**: a weighted average of 0–1 factor scores (speed, gear, routes, chains,
  travel, difficulty, reputation), ranked against the comparison set and turned into 1–5. Each
  preset is a set of weights; Custom shows the sliders.
- **Warnings** are icons, not grades: elite, group, escort, timed, far travel (another zone).

## Where it shows

1. **Quest log**: grades (or the unified grade) next to each quest title.
2. **Quest dialog** (accept and turn-in frames): grades, plus the tooltip line.
3. **Tooltip** on all of the above: the full breakdown (XP, time split, reward upgrade, routes,
   chain, your past time).
4. **Map and minimap pins** on Questie's quest-giver icons: only if Questie offers a supported
   way to add to them; otherwise skipped.
5. **Over the quest giver's head**: out of scope for v1 (friendly nameplates may be restricted
   on Forever).

## Settings ("Quest grades" module)

- Enable or disable.
- Mode: Separate grades / Unified grade.
- Style (Unified only): Balanced / Speed leveling / Gear hunter / Custom; the sliders appear for
  Custom.
- What to show: time estimate, warning icons, route badge.
- Where to show: quest log, quest dialog.
- Comparison range: ±levels (default 5).
- Learn from my quest times: on/off, and reset history.

## Decided by the owner

- Separate grades per goal, so the player decides in the moment; plus a mode for one unified
  grade from a playing style.
- Weight sliders exist, for the unified grade's Custom style.

## My calls (owner can change)

- Factors, presets and their weights.
- The ±5-level comparison set, and percentile-based grades.
- Route data is read only from guide add-ons the player has loaded, not shipped with Ultimate.
- GearQuestForever is optional, with a simple fallback.
- Over-the-head numbers are out of scope for v1.

## Settled after the builder check (my calls)

- **"Took you X"** = time online and not AFK while the quest was in the log, split evenly
  between the quests that were active at the same moment. Plain clock time would inflate every
  estimate. The personal correction only uses quests with that measure.
- **Gear without GearQuestForever**: show "?" with a tooltip hint, not a guess. The ilvl-only
  fallback can't tell a strength item from a caster item, which breaks the "no made-up numbers"
  anti-goal. With GearQuestForever, "spec" means the spec selected in that add-on.
- **"Can pick up"**: the available quests Questie already computes, read defensively from its
  internals like the party-needs feature does; no rebuilding of prerequisite logic. If the read
  fails, the comparison set falls back to the player's own quest log.
- **Questie map pins**: a defensive hook into Questie's pin tooltips is acceptable. Built last;
  dropped if the hook proves fragile.

## Settled by the owner after the builder check

Both are options, so each player decides:

- **Where grades show**: Blizzard's quest log, Questie's tracker, or both, each with its own
  checkbox.
  - Defaults: Questie's tracker on, quest log on.
  - Either surface is dropped silently if adding to it would need anything Blizzard blocks.
- **Grade scale**: Fixed bands or Relative.
  - **Fixed bands** (default): XP per minute against what's normal at your level, so grades stay
    put.
  - **Relative**: percentile against the comparison set, so grades can shift as the set
    changes.
  - The comparison-range setting only applies to Relative.

## Left to the builder

- Exact constants (running speed, seconds per kill, zone-change cost), tuned with tests.
- Caching and invalidation (quest log changes, level-up, gear change).
- How to read each guide add-on's quest lists. Missing or failed reads mean "no route data".
