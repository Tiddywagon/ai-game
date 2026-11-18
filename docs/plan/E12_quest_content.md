# E12: At least 60 quests as data (after E11)

Request: "Write at least 60 quests as data files across all traders and maps: easy intro chains for each trader,
mid-game chains that send me to every map, faction-specific chains for BEAR and USEC, boss-hunt quests, and
late-game quests that reward Epic and Legendary items. Mix in-raid objectives with out-of-raid ones (hand-ins,
crafting, hideout upgrades). Give each quest original flavor text from the trader."

Built on the E11 quest system (every objective type, rewards and unlocks, chains, `QuestLog.problems()`).

- **Count and files**: at least 60 quests in all (the existing ones count where they fit a chain; rework or
  retire the ones that don't, keeping saved progress valid: a retired quest id that a save has completed still
  counts for prerequisites and task counts). One file per trader in `data/quests/`, plus the faction lines, the
  boss hunts and the Collector line.
- **Intro chains**: 3-4 easy quests per trader (all seven: Bulat, Doc Vera, Auntie Zoya, Stitch, Tinker, Mole,
  The Broker once he's unlocked) that teach that trader's part of the game on the playable maps: a first
  kill or hand-in, a first barter-worthy find, a craft or a station to build, an extract.
- **Mid-game chains**: each trader's chain goes on through every map (Test Yard, Factory, Customs Yard,
  Woodland, Shoreline Resort, Lab Zero), using each map's points of interest, extracts and keys. Maps that have
  no playable scene yet: their quests exist and show "map not open yet"; no quest on a playable map may require
  one of them (the validator checks it), so nothing reachable today is blocked.
- **Faction chains**: BEAR and USEC lines (the five each from E9 grown to 7-8, or a second line each), visible
  only to that faction.
- **Boss hunts**: one per boss (kill the boss on its map; a second step for its guards or with a condition),
  rewarded from the boss-themed gear, plus a final quest for all six.
- **Late game** (level 30+, loyalty 3-4, long chains): rewards of Epic and Legendary items (guns, armor, the
  Legendary rounds, containers), each still inside the economy's rules (no reward worth selling the quest for:
  compare with what the hand-ins cost).
- **Mix**: every chain mixes raid objectives (kills with conditions, place and visit, extract, extract with an
  item) with out-of-raid ones (found-in-raid hand-ins, crafts, station upgrades, levels, loyalty, roubles).
- **Flavor**: every quest has a short briefing and a turn-in line in the trader's own voice (DESIGN §10's
  personalities), original text, no real-world game quotes.
- **Balance and checks**: XP from all quests fits the level curve (DESIGN §2.2 says what quests add in total:
  update it); reputation per trader still reaches loyalty 4 with the money rule; quick-buy task counts and the
  flea level still make sense; `QuestLog.problems()` clean; a DESIGN §11 table of every quest (trader, chain,
  requires, objectives, rewards) generated from the data and checked by a test.
- Suite additions in `tests/quests_test.gd` (or `tests/quest_content_test.gd`): at least 60 quests, every trader
  has an intro chain startable at level 1 (The Broker's at his unlock), every map and every boss appears, both
  factions' lines hidden from the other, every objective type is used, no chain blocked by an unplayable map,
  reward sanity (Epic/Legendary only late), every quest has flavor text, and a played-through chain per trader on
  the playable maps.

## Notes from E11 for quest authors (the system as built)

- **File order matters.** Files in `data/quests/` load in name order, and `requires` must name a quest listed
  earlier (same file or an earlier file). Current files: collector, faction_lines, quests, raid_work,
  trick_shots. Name new files so their prerequisites load first (or put dependent quests later in one file).
- **Quest shape:** `{"id","name","trader","description","success"?,"requires"?:[ids],"level"?,
  "loyalty"?:{trader:LL},"faction"?:"bear"|"usec","gives"?:[{"item","count"}],"objectives":[…],"rewards":{…}}`.
  Unknown keys are errors. `success` is the trader's turn-in line.
- **Objectives** (any may also take `"text"` to override its line; unknown keys are errors):
  - `{"type":"hand_in","item","count","fir"}`, `{"type":"figures","figures":{"rarity"?,"set"?},"count","fir"}`,
    `{"type":"roubles","count"}`
  - `{"type":"kill","count","target"?:"any|scav|pmc|boss|guard","faction"?,"boss"?:"krane|matvei|varga|leshy|reyes|varn","map"?,"weapon"?:gun id,"weapon_class"?,"body_part"?:"head|thorax|stomach|arms|legs|torso|left_arm|…","min_distance"?,"survive"?}`
    (`faction` needs target pmc; `boss` needs target boss or none, and the map must be that boss's map)
  - `{"type":"trick_kill","count","target"?:"scav|pmc","weapon_class"?,"map"?,"survive"?}`
  - `{"type":"visit","map","poi"|"spot","survive"?}` (no count)
  - `{"type":"place","item","count","map","poi"|"spot","seconds"?,"survive"?}`; `{"type":"mark",…}` is place
    with the quest's first `gives` item unless `item` is set
  - `{"type":"extract","count","map"?,"extract"?}` (an extract id needs the map),
    `{"type":"extract_with","item","count","fir"?,"map"?}`, `{"type":"explore","count","map"}` (count ≤ the
    map's points of interest)
  - `{"type":"craft","count", exactly one of "recipe"|"item"|"station"}`
  - `{"type":"upgrade","station","level"}`, `{"type":"level","level"≥2}`, `{"type":"loyalty","trader","level"≥2}`
    (no count on these three)
- **Rewards:** `{"roubles","dollars","xp","reputation" (the giver),"reputation_with":{trader:amount},"drip",
  "items":[{"item","count"}]}` — never found in raid.
- **Unlocks go on the thing unlocked:** barter `"quest"` (data/traders/barters/*.json), buy offer `"quest"`
  (data/traders/offers.json), craft `"quest"` on a recipe (data/hideout/stations.json), extract `"quest"`
  (data/config/extracts.json), quick-buy card `"unlock":{"quests":[…]}`, trader `"unlock":{"quest"}`
  (traders.json). `QuestLog.unlocks(quest)` lists them on the quest.
- **Places:** points of interest in data/config/pois.json; quest spots in data/config/quest_spots.json as
  `{name, position:[x,y,z] in the map scene, radius}`. Only test_yard and factory have scenes.
- **Watch out:** a quest name must not equal a quick-buy card name (the quickbuy suite's DESIGN lookup); quest
  markers are items worth 0 tagged `quest_item`; the hideout and economy suites pin craft and offer counts;
  after any data change paste the regenerated table into DESIGN §11 — the quests suite writes the expected
  table to `<AI_GAME_TESTS>/xdg_<tag>/godot/app_userdata/AI Game/quest_table.md`.
