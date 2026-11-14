# E14: Daily and weekly operational tasks (after E11-E13)

Request: "Add daily and weekly operational tasks from a random pool, scaled to my level, that reset on a timer
and give money, XP and a chance of a rare item."

- **Pool** in `data/tasks/operations.json` (loader with `problems()`): task templates built from the quest
  objective types (kill Scavs / PMCs / a faction with optional map, weapon class or body part; hand in
  found-in-raid items of a kind; extract from a map; visit or mark a point of interest; craft; sell or spend;
  search containers), each with count ranges and reward weights per level band, the levels it can appear at, and
  whether it is a daily or a weekly. Only playable maps, and only things the profile can do (a craft needs its
  station, a faction task fits your faction).
- **Rolling**: 3 dailies every real day and 3 weeklies every real week (reset hours in the config, UTC), picked by
  a seed from the day or week number and the profile, so reloading never re-rolls and time away just moves on to
  the current set. Counts and rewards scale with the player level at the roll. One re-roll per daily for a fee.
- **Progress** through the same tracking as quests (live in raids, the HUD tracker, toasts); PMC raids only.
  Unfinished tasks are gone at the reset; a finished one is claimed from the board (unclaimed ones are paid out
  at the reset so nothing earned is lost).
- **Rewards**: roubles and XP scaled to level (weeklies about 5× a daily), and a chance of a rare item (dailies
  about 15%, weeklies about 60%: Rare or better from a reward table, not found in raid), all in the config.
  Completing all three dailies gives a small bonus. Later (E15) they also pay Drip.
- **Board**: an OPERATIONS tab in the quest log (and a line on the main menu: "2 / 3 dailies · resets in 5:12"),
  with each task's objective, progress, reward and the time left.
- Save version bump (the day and week rolled, progress, claims, re-rolls), DESIGN §11 (a new Operations
  section), §15, §16, README. Suite `tests/operations_test.gd` with the time override: seeded rolls repeat, reset
  at the day and week boundary incl. while closed, scaling by level, only doable tasks, progress through real
  triggers, claim and auto-claim, the rare-item chance (seeded), re-roll, save round trip, the board.
