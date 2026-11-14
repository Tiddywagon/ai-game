# Work plan (feature batch complete)

Working notes for the feature batch, now complete (the status table below). DESIGN.md stays the source of truth for how the game
behaves; these files say what is left to build and how the work is done, so the plan survives a fresh clone.

## Status

| Step | What | State |
|---|---|---|
| A1-A3, S1 | Scav and boss polish, factions and AI PMC squads, PMC roaming, Scav runs and karma | done |
| E1-E5 | Trader roster and levels, selling and restocks, barters, stash, LOADOUT screen and auto-equip | done |
| T0 | Baseline test suites in `tests/`: smoke, economy, gear, menu (the earlier suites lived outside the repo and were lost) | done |
| E6 | Quick Buy tab and loyalty prices: [E6_quick_buy.md](E6_quick_buy.md) (suite `tests/quickbuy_test.gd`) | done |
| E7 | Flea market: [E7_flea_market.md](E7_flea_market.md) (suite `tests/flea_test.gd`) | done |
| E8 | Hideout overhaul: [E8_hideout.md](E8_hideout.md) (suite `tests/hideout_test.gd`) | done |
| E9 | Faction perks: [E9_faction_perks.md](E9_faction_perks.md) (suite `tests/faction_perks_test.gd`) | done |
| E10 | Collectible figures, Collectors Shelf, set bonuses, Collector quests: [E10_figures.md](E10_figures.md) | in progress |
| E11 | Data-driven quest system (more objective types, unlocks, quest log, raid tracker): [E11_quests.md](E11_quests.md) | after E10 |
| E12 | At least 60 quests across traders, maps, factions and bosses: [E12_quest_content.md](E12_quest_content.md) | after E11 |
| E13 | Levels 1-60, skills that grow by use, lifetime stats, character screen: [E13_levels_skills.md](E13_levels_skills.md) | after E12 |
| E14 | Daily and weekly operational tasks: [E14_operations.md](E14_operations.md) | after E13 |
| E15 | Drip economy, cosmetic slot machine, skins, Cosmetics tab: [E15_drip_cosmetics.md](E15_drip_cosmetics.md) | after E14 (two parts) |
| | **The first batch (through E9) is complete**: every step is done and no known bug is open | |

The tables the original requests referred to ("the 6 loadouts from the table", the barter table) never came
through, so their content is designed here; DESIGN.md says so where it matters. The exact wording of the flea
market and hideout requests is no longer available either: E7 and E8 are written from notes.

## Known bugs to fix

None open. (Auto-equip improving on a second run when a stash rig or backpack held rounds or meds was fixed
with E9: `LoadoutPlanner` chooses the rig and backpack again once a run empties one; `tests/gear_test.gd`.)

## Ground rules for every step

- Read the DESIGN.md sections the step touches first (it is large: grep for the section). When behaviour is
  added or changed, update DESIGN.md (the section, the §15 code map, a row at the end of §18 Changelog) and
  README.md where it describes the feature. Plain, concrete writing with the numbers given.
- Match the surrounding code: `##` doc comments, tabs, typed GDScript, static helper classes extending
  RefCounted, data in `data/` (JSON or .tres) read by a loader with a `problems()` check that runs when the items
  load. Tunable numbers go in data/config files, not literals.
- Saves: `scripts/autoload/save_manager.gd` `SAVE_VERSION` (17 now) and its comment block list every version.
  New saved state bumps it once per step, with `GameState.from_dict()` / `SaveManager.upgrade()` loading every
  older save without losing progress.
- Invariants that have bitten before: never lose or create items or rounds; a stack never exceeds its max stack
  (`ItemInstance.split_excess()` / `copy_stack()`); a magazine never holds more than its capacity
  (`trim_magazine()`); the secure container and its contents are never touched by bulk actions; nothing can be
  bought and sold on for a profit; the price shown is the price charged; a dialog over a screen keeps keyboard
  and controller focus inside it.
- Tests live in `tests/` (see tests/README.md). Each step adds a suite covering every clause of its plan file,
  first writing checks that pin down the existing behaviour it is about to change. `tests/run_all.sh` must pass
  in a single run before the step is called done; a failing check that looks unrelated gets its root cause
  found, not a re-run.
- Commit and push to the working branch at every green milestone (the code compiles, the suites that exist
  pass), not only at the end: the cloud machine can be reset at any time and only pushed work survives.
  Never commit temporary `_*.gd` copies in the project root. No pull requests unless asked.
- Screens get a screenshot (xvfb, opengl3) that is looked at before the step is done.
