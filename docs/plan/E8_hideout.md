# E8: Hideout overhaul

From notes: all 13 stations of DESIGN §9 as data files, real-time builds and crafts that keep running while the
game is closed, generator fuel, a Bitcoin (mining) farm, handing items over toward an upgrade, a hideout map
screen with an upgrade tree, a "needed for the hideout" icon on items, and cosmetics. Two parts.

## Part a: data and logic

- Stations in `data/hideout/` (one file per station or the existing stations.json grown): Generator, Stash,
  Medstation, Nutrition Unit, Rest Space, Workbench, Water Collector, Lavatory, Shooting Range, Gym,
  Intelligence Center, Bitcoin Farm, Security, each with 3 levels (Stash 4): costs (roubles, items, found in raid
  from level 2), other stations' levels, trader loyalty, player level, a build time, and what the level gives.
  Existing saves keep their built levels.
- **Handover**: requirement items can be handed over one kind at a time as the player gets them (kept on the
  station, shown as 3/5); the build can start once everything is in and the money is paid.
- **Real time**: a build takes its duration in real time and finishes while the game is closed (unix times
  saved); crafts are queued per station, take real time, and are collected when done (found in raid as now).
- **Generator and fuel**: fuel cans burn while the generator is on; with no power, stations that need it stop or
  run at a slower rate (crafts ×0.5, the farm stops, no bonus effects). Levels add fuel slots and efficiency.
- **Bitcoin Farm**: graphics cards handed over (more per level), produces bitcoin over time up to a cap, needs
  power, collected by hand.
- **Effects**: Water Collector makes water over time; Rest Space / Nutrition Unit refill energy and hydration
  between raids as now; Gym trains strength or endurance once per period; Intelligence Center shortens the Scav
  cooldown (`Hideout.scav_cooldown_multiplier()` already reads its `scav_cooldown` values), lowers insurance
  prices and return times; Security shows scouting info in the raid setup (whether the map's boss is in);
  Shooting Range opens a practice session on the Test Yard with nothing at stake.
- **Cosmetics**: a few purely visual hideout upgrades (lighting, walls, floor, a poster wall) bought with roubles
  or junk, saved, shown on the map screen.
- Save version bump with migration; DESIGN §9 rewritten with a table of every level's cost, time and effect
  generated from the data and checked by a test.

## Part b: screens

- **Hideout map**: a top-down plan of the hideout with every station as a room or prop showing its state
  (locked, can be built, items missing, building with a countdown, crafting, ready to collect), cosmetics
  applied; mouse, controller and touch.
- **Station panel**: the upgrade tree (each level with its requirements as green checks or red crosses, handover
  buttons, cost, build time, what it gives), the build countdown, the craft list with queue, timers and COLLECT,
  the generator's fuel gauge and switch, the farm's cards and coins.
- **Needed-for icon**: items needed for a hideout level the player hasn't built (or a craft, a quest, a barter:
  `ItemUses`) get a small corner icon in every grid (stash, inventory, loot, traders), with the tooltip saying
  what for and how many more.
- Suite `tests/hideout_test.gd` (every station's data, handover, build and craft timing incl. offline, fuel and
  power, the farm, each effect, migration, the map and panel through their buttons, the icon).
