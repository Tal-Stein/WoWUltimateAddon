# Ultimate

A personal add-on for **WoW Forever** (client 1.60.1, interface 16001) on the official servers.
It's a container of features that can each be switched on and off. Every option lives in
Blizzard's own Settings panel (Options → AddOns → Ultimate).

Requires **Questie**, including its **QuestieDB**.

## Features

| Feature | What it does |
|---|---|
| **Quest Targeting** | Uses Questie's database and your quest log to find nearby mobs you need for quests, including mobs that drop quest items. Plays a sound when one comes into view (separate sounds for regular, elite, boss, or easy vs dangerous mobs). Marks them with a large animated icon. Ranks them by your chosen priorities. |
| **Target key / bar** | Bind "Target next quest mob" (or use the `UltTarget` macro). One press targets the best quest mob; pressing again moves to the next one. A bar shows every quest mob name nearby, colored by difficulty, and you click to target. Mobs tagged by someone else are skipped. |
| **Rare Scanner** | Always-on alert for rare, rare-elite and world-boss mobs, plus your own watch list. Rares go to the front of the target bar. |
| **Quest Items** | Buttons for usable quest items, shown only when relevant (or always). You can bind them to keys, drag them to action bars, and shift-click to pin. |

Blizzard doesn't allow add-ons to target anything without a key press or click, and Ultimate
doesn't try to get around that. The add-on chooses *what* your key targets; you press it.

### Slash commands
- `/ult`: open settings
- `/ult scan`: print the detected quest mobs, nearby candidates (with filter reasons) and rare history
- `/ult reset`: reset bar positions
- `/ult debug`: toggle debug output

## Development

- Tests run offline under LuaJIT 5.1 via Python [`lupa`](https://pypi.org/project/lupa/):
  `pip install lupa`, then `python tests/run.py [filter]`.
- Static checks (syntax, TOC listing, stray globals, XML): `python scripts/check.py`.
- Add files to the TOC with `python scripts/toc.py <after-file|END> <file>...`.
- Link the add-on into the game: `powershell -ExecutionPolicy Bypass -File scripts/deploy.ps1`.
  Pass `-Copy` to copy instead of creating a junction.
- In-game verification checklist: [`docs/testing.md`](docs/testing.md).

Layout: `Ultimate/Logic` is pure, tested Lua. `Core` holds events, the combat queue, saved
variables and the module registry. `Services` holds nameplates, targeting, the bar, markers,
sounds and alerts. `Data` is the quest index. `Modules` holds the features, and `Settings` the
options UI.

Design: `docs/superpowers/specs/2026-11-07-ultimate-addon-design.md`.
Plan: `docs/superpowers/plans/2026-11-07-ultimate-addon.md`.

## Adding a feature
Register a module in `Ultimate/Modules/<Name>.lua`:

```lua
local ADDON, ns = ...
local M = ns.Modules:Register({
  key = "myFeature", name = ns.L.MODULE_MY_FEATURE, description = ns.L.MODULE_MY_FEATURE_DESC,
  defaults = { something = true },
  OnEnable = function() end, OnDisable = function() end,
  BuildSettings = function(ctx) ctx:Checkbox("myFeature.something", "Something") end,
})
```

The module gets an on/off checkbox on the root settings page and its own settings subpage.
Put protected work (secure attributes, secure frame layout) inside `ns.Combat:Run(key, fn)`.
