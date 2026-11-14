# E11: Data-driven quest system (growing the existing one)

Request: "Build a data-driven quest system. Quest objective types: kill X targets (Scavs, PMCs, a faction, a
boss, with optional conditions like map, weapon, or body part), find in raid and hand over items, place a marker
or item at a location, visit/mark a location, survive and extract from a map, extract with a specific item,
craft in the hideout, upgrade a hideout station, reach a level or trader loyalty. Rewards: XP, money, items,
trader reputation, unlocks. Quests are given by traders, have prerequisites forming chains, and show in a quest
log with progress tracking during raids. Mark 'found in raid' status on items so hand-in quests need loot I
found myself."

What exists (keep it working, same saved progress): `QuestLog` (`scripts/progression/quest_log.gd`) reading
`data/quests/*.json` with a `problems()` check; objective types `hand_in` (with `fir`), `roubles`, `trick_kill`,
`kill` (target scav/pmc, faction, map, weapon_class), `extract` (map), `explore`; rewards roubles, dollars, xp,
reputation, items, drip; `requires` chains, `level`, faction-only quests; the TASKS tab on each trader; raid
progress counted when the raid settles (`record_raid`); found-in-raid status on every item (DESIGN §2.1). The
Collector quest line (E10) adds a generic figure hand-in: keep it.

## 1. Objective types (all data)

- `kill`: count; `target` scav / pmc / boss / guard / any; optional `faction`, `boss` (a boss id), `map`,
  `weapon` (an item id), `weapon_class`, `body_part` (head, thorax, …: where the killing hit landed),
  `min_distance`. A kill counts for every active objective it fits.
- `hand_in`: an item (or a generic kind, as the Collector quests use), count, `fir` (found in raid only: bought,
  bartered, crafted-elsewhere or insurance-returned items don't count; the row shows the FIR mark).
- `place`: put an item at a location: stand in the spot and hold the interact key for a few seconds (moving or
  being hit cancels); the item leaves the inventory. `item` is any item, or a quest marker the quest hands out
  on accept (`gives`; a lost marker can be taken again from the trader for free). `mark` is `place` with the
  quest's marker.
- `visit`: reach a location (counts on entry).
- Locations are a map plus a point of interest id (`PoiTable`) or a named quest spot placed in the map scene;
  active ones show on the map item's overlay.
- `extract`: survive and extract from a map (optional extract id; a Run Through doesn't count).
- `extract_with`: extract with an item on you (count, optional `fir`); the item is kept.
- `craft`: collect a craft from the hideout (a craft id, an output item, or any craft at a station), count.
- `upgrade`: a hideout station at a level or higher. `level`: a player level. `loyalty`: a trader at a loyalty
  level. These three are state checks: already true means already done.
- Kept: `roubles`, `trick_kill`, `explore`.
- Optional `"survive": true` on a raid objective: its progress from a raid only counts if you extract.
  Otherwise kills, visits and placements count the moment they happen and stay even if you die. Only PMC raids
  count (not Scav runs, not practice).

## 2. Rewards and unlocks

- xp, roubles, dollars, items, reputation (the giver's, and optionally other traders'), drip, and `unlocks`:
  barters, trader buy offers, hideout crafts, extracts, quick-buy cards, a trader. Existing cross-references
  (a barter's `quest`, quest-unlocked extracts, The Broker) keep working; `QuestLog.unlocks(quest)` gathers
  every kind so the quest's panel lists what it unlocks. Add quest gating to buy offers and crafts where missing.

## 3. Structure

- Given by a trader; prerequisites `requires` (every listed quest completed), `level`, `loyalty`, `faction`.
  States: locked (says what's missing), available, active, ready to turn in, completed. Accept and turn in at
  the trader's TASKS tab and from the quest log when out of raid.
- `QuestLog.problems()` covers every type and field: targets, bosses, maps, locations, items, stations, crafts,
  traders and unlock references exist; chains have no cycles; a prerequisite is visible to the same faction.

## 4. Quest log and tracking in raids

- QUESTS screen (main menu, and from TRADERS): Active / Available / Completed, filter by trader, each quest with
  its objectives and live progress, rewards, unlocks and prerequisites as a chain ("after Old Unit ✓"); TRACK
  toggles (up to 3 tracked).
- In a raid: a small tracker on the HUD with the tracked quests' objectives for this map, updating live; a
  toast when an objective moves or completes ("Scavs killed 3 / 5", "Objective complete: …"); the full log on
  the pause menu and a key; the hold-to-place prompt and progress ring at a location; locations on the map
  overlay. The raid summary lists quest progress made.

## 5. Content

- Every existing quest moved to the new schema with unchanged behaviour and saved progress.
- About 12 new quests across the traders, chained into the existing ones, using every new objective type at
  least once on the playable maps (a boss kill, a headshot quest, a weapon-specific kill, place a marker, place
  an item, visit, extract with an item, craft, station upgrade, level, loyalty), with rewards in line with the
  existing ones and a few unlocks.

## 6. Save, docs, tests

Save version bump (tracked quests, live objective progress, markers handed out), older saves keep their quest
states. DESIGN §11 rewritten (objective table, rewards, states, the log, the tracker, a quest table generated
from the data and checked by a test), §2.1, §15, §16, §18; README. Suite `tests/quests_test.gd`: loader problems
(a broken copy per rule), each objective type through its real trigger (live raids for kill conditions, place,
visit, extract, extract_with; the hideout for craft and upgrade), FIR-only hand-ins, survive-only progress,
death keeps the rest, Scav and practice raids count nothing, chains and states, every reward and unlock kind,
the log and tracker through their controls, old-save migration, save round trip.
