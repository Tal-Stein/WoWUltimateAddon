# Ultimate

A personal add-on for **WoW Forever** (client 1.60.1, interface 16001) on the official servers.
It's a container of features that can each be switched on and off. Every option lives in
Blizzard's own Settings panel (Options → AddOns → Ultimate).

Requires **Questie**, including its **QuestieDB**.

## Features

| Feature | What it does |
|---|---|
| **Quest Targeting** | Uses Questie's database and your quest log to find nearby mobs you need for quests, including mobs that drop quest items. Plays a sound when one comes into view (separate sounds for regular, elite, boss, or easy vs dangerous mobs). Marks them with a large animated icon. Ranks them by your chosen priorities. |
| **Target key / bar** | Bind "Target next quest mob" right in `/ult` → Targeting. One press targets the best quest mob; pressing again moves to the next one. A fixed, movable panel shows every quest mob name nearby, colored by difficulty, growing into rows when there are many. Click one to target it. Mobs tagged by someone else are skipped. |
| **Minimap button** | Click opens settings, drag moves it around the minimap. It can be hidden in settings. |
| **Focused Chat** | Keeps the chats that matter apart from the noise. A **Focused** chat tab collects the chats you pick (whispers, party, raid, guild, ...) and each can get its own tab for catching up. The tabs are additive: General keeps working as usual. Built from Blizzard's own chat tabs; set up with **Apply** (needs a reload). |
| **Rare Scanner** | Always-on alert for rare, rare-elite and world-boss mobs, plus your own watch list. Rares go to the front of the target bar. |
| **Quest Items** | Buttons for usable quest items, shown only when relevant (or always). You can bind them to keys, drag them to action bars, and shift-click to pin. |
| **Flight Times** | Hover a destination on the flight master's map to see how long the flight takes, beside its name. In the air, a bar like the game's breath bar counts down to landing. Your own flights are timed and remembered for all your characters. |
| **Gold Farming** | The world map grades each zone by what your gathering professions earn there at your realm's auction prices, tinting zones in the map's own highlight and listing the best ones for you beside the map. Zone maps pin every herb and ore node you can gather. Your own kills are recorded (coin, loot, skins per mob), so the mobs you farm join the grades with their real gold per kill and per hour at your pace, also shown in their tooltips. Rank zones overall, nearest to you (by travel time at your speed) or for levelling. Toggle it from the world map's filter menu. |

Blizzard doesn't allow add-ons to target anything without a key press or click, and Ultimate
doesn't try to get around that. The add-on chooses *what* your key targets; you press it.

### Slash commands
- `/ult`: open settings
- `/ult scan`: print the detected quest mobs, nearby candidates (with filter reasons) and rare history
- `/ult reset`: reset bar positions
- `/ult debug`: toggle debug output

## Credits

The built-in flight times (`Ultimate/Data/FlightTimes.lua`) come from
[RestedXP Guides](https://www.restedxp.com) and are shared under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/), like the original.
Refresh them with `python scripts/import_flight_times.py --latest`; a weekly GitHub Action does
this and opens a pull request when RestedXP changes them.

Gold Farming copies no third-party data. It reads at runtime from the add-ons that own it, so
updating them updates the map:
- **Node locations:** Questie's Forever database, and GatherMate2's when it's installed.
- **Prices:** Auctionator's scans of your realm, otherwise the vendor price.
- **Node facts:** each node's required skill and item ID live in `Ultimate/Data/GatherNodes.lua`.
- **Gold per kill:** recorded from your own Forever kills, shared by all your characters. Where each mob spawns comes from Questie.

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
