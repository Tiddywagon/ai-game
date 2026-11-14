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
