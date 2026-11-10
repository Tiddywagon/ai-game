# Tests

Headless test suites for the game, run with the Godot 4.7 binary. They live in the repository so they
survive a fresh clone; the folder has a `.gdignore`, so Godot doesn't import it and exports leave it out.

```bash
export GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64   # default: `godot` on PATH
$GODOT --headless --editor --quit --path .                # once per fresh clone, and after adding a class_name script
tests/run_all.sh                                          # compile check + every suite; one summary line each
tests/run_one.sh trading                                  # one suite, output printed
```

Logs and the tests' own `user://` data go to `/tmp/ai-game-tests` (`AI_GAME_TESTS` to change it), never to
your real savegame.

## Writing a suite

- `tests/<name>_test.gd`, starting `extends "res://tests/test_base.gd"` and overriding `run()`; add `<name>` to
  `suites.txt` (headless) or `gui_suites.txt` (needs a display: run under xvfb with the opengl3 driver).
- `section("Title")` prints a header; `check(condition, "what should be true")` is one assertion. A check must
  fail when the feature breaks: no `or` escape hatches, no checks that are true by construction.
- Load game scripts with `load("res://scripts/...")`, not by class name. `item(id, amount)` makes an item
  instance, `items([...])` a typed item list, `fresh_profile()` a new profile with no save on disk.
- Seed anything random (`GameState.raid = {"side": "pmc", "map": "test_yard", "loadout": gs.pmc_loadout(),
  "seed": 4, "boss": false, "pmcs": 0}` is the same raid every run; a test that moves `raid.elapsed` sets
  `raid.next_wave = -1.0` first so no Scav wave arrives). A check that depends on a roll is a flaky check.
- Screens: `change_scene_to_file()`, `find_child(name, true, false)`, `button.pressed.emit()`.
- Temporary copies in the project root (`_*.gd`) are never committed.
