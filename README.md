# Ultimate

A personal add-on for **WoW Forever** (client 1.60.1, interface 16001) on the official servers.
It's a container of features that can each be switched on and off. Every option lives in
Blizzard's own Settings panel.

Requires **Questie** (with its **QuestieDB**).

## Development

- Tests run offline under LuaJIT 5.1 via Python [`lupa`](https://pypi.org/project/lupa/):
  `pip install lupa`, then `python tests/run.py`.
- Static checks (syntax, TOC listing, stray globals): `python scripts/check.py`
- Link into the game: `powershell -ExecutionPolicy Bypass -File scripts/deploy.ps1`.
  Pass `-Copy` to copy instead of creating a junction.

Design: `docs/superpowers/specs/2026-11-07-ultimate-addon-design.md`.
Plan: `docs/superpowers/plans/2026-11-07-ultimate-addon.md`.
