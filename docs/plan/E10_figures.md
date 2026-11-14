# E10: Collectible figures, the Collectors Shelf, set bonuses and the Collector quest line

Request: "Add collectible figures. Figures are 1x1 items with rarity, a set, a sell value and a small
placeholder 3D model. Add every figure from this table: [paste the table], plus 15 more original figures,
including a figure for each new boss and POI. Add a Collectors Shelf to the hideout with 3 levels (more display
slots per level, built with roubles and found items like the other stations). On the shelf I can place, move and
remove figures from my stash; placed figures show as small 3D models on a lit shelf I can zoom in on, and are
safe forever. Completing a set gives a permanent bonus while every figure in it is displayed: Raiders = +5% loot
search speed, Factions = +5% XP from PMC kills, Traders = 3% better trader prices, Bosses = +10% boss spawn
chance, Wildlife = slower energy and hydration drain, Oddities = +1 free Drip slot spin per day. Add a collection
screen that shows owned and missing figures as silhouettes, with set progress. Duplicate figures can be sold,
bartered, or turned in to a Collector quest line from the Fence that rewards a large secure container at the
end. Put all figure and set bonus data in files."

The table did not come through, so the figures it would have listed are designed here (DESIGN.md must say so).
The "Drip slot" the Oddities bonus refers to doesn't exist in the game yet (Drip is earned from trick shots and
nothing spends it), so a small one is added in this step.

## 1. Figures (data)

- A new item category `figure` (appended to `ItemData.Category`), items in `data/items/figures/*.json`: 1×1,
  rarity, `set`, value (the usual band for the rarity), weight 0.1-0.3 kg, a description, and `model`: the
  recipe of its placeholder 3D model (a base, a body and head from primitive shapes, colours, one prop shape),
  built by a `FigureModel` scene/script; the rarity tints the base. Icons through the existing icon system.
- Sets and their bonuses in `data/config/figures.json` (loader with `problems()`: every figure's set exists,
  every set has at least 3 figures, bonus types known, values in range, shelf slots hold every figure at the top
  level). Sets:
  - **Raiders** (6: the Scav and raider archetypes of the game: e.g. a Scav, a Scav gunner, the Rat, the Looter,
    the Chad, the Quester): +5% loot search speed.
  - **Factions** (6: three BEAR and three USEC operators): +5% XP from PMC kills.
  - **Traders** (7: one per trader): 3% better trader prices.
  - **Bosses** (6: one per map boss, by name): +10 points of boss spawn chance.
  - **Wildlife** (6: animals of the region): 10% slower energy and hydration drain.
  - **Oddities** (6: strange little things): +1 free Drip slot spin per day.
  - **Landmarks** (one per original point of interest: the ones DESIGN §5.2 marks as original / hidden): +10%
    exploration XP. This set and its bonus are an addition (the request asks for a figure per new POI but names
    no set for them).
  Raiders, Factions, Traders, Wildlife and Oddities stand in for the missing table; Bosses and Landmarks are the
  "15 more" (more than 15 in the end, since every boss and every original POI gets one). Original names only.
- Where they come from (all data: loot tables, boss loot, POI spawns, barters): a boss's figure from that boss
  (a fair chance per kill); a Landmark figure at its own POI (a small chance per raid); Raiders on Scav and PMC
  bodies; Factions on AI PMCs of that faction; Wildlife and Oddities in containers, hidden stashes, airdrops and
  the slot machine; each trader's figure from a barter with that trader. Rare on the flea market. Never from
  practice raids.

## 2. Collectors Shelf (hideout station)

- A 14th station `collectors_shelf` in `data/hideout/stations.json` with a room on the plan, 3 levels with
  display slots (12 / 28 / enough for every figure), built like the others (roubles, items, found in raid from
  level 2, build time).
- Shelf screen (from the station panel): a lit 3D shelf in a SubViewport with the placed figures as their models;
  zoom (wheel, pinch, triggers) and pan; pick a slot and a figure from the list of figures in the stash to place
  it, move a placed figure to another slot, remove it back to the stash (needs room). One of each figure at
  most. Mouse, controller and touch.
- Placed figures are kept by the shelf (saved), keep their found-in-raid status, and are safe forever: not lost
  on death, not in the stash for sorting, selling, barters, quests, auto-equip or the flea market.

## 3. Set bonuses

- A set's bonus is on while every figure of the set is on the shelf, off the moment one is removed. One place
  (`Figures.bonus(type)`) answers every caller: loot search time, PMC-kill XP, `Trading.price()` and the sell
  rate (3% better both ways, with the resale floor still holding: the no-resale sweep runs with the bonus on),
  boss spawn chance (capped at 100%), energy and hydration drain, exploration XP, free spins. The shelf screen,
  the collection screen and the affected screens say when a bonus is active.

## 4. Collection screen

- COLLECTION (a tab beside SHELF, and a button on CHARACTER): every figure by set, owned ones in colour with
  how many you have and whether it's displayed, missing ones as dark silhouettes (name hidden until you've owned
  one: a saved "seen" list), set progress ("Raiders 4 / 6 · 3 displayed") and each set's bonus with its state.

## 5. Duplicates: sell, barter, the Collector quest line

- "Spare" figures are copies beyond the one you keep: any figure in the stash whose kind is on the shelf, and
  all but one of a kind that isn't. Quests and generic barters only ever take spares.
- Selling: traders buy figures like valuables (Mole anything; pick who else fits). Barters: a few at Mole and
  Auntie Zoya that ask for "any n figures of a rarity" (a generic requirement type in `BarterTable`, counted and
  taken from spares only, shown with check/cross and FIND like other requirements), within the barter rules.
- The Collector quest line from Mole (5 chained quests: hand in spare figures, growing from any two to one from
  each of several sets and an Epic one), ending with a new large secure container (4×4, bigger than Kappa;
  original name) as the reward.

## 6. Drip Slots (small)

- A slot machine on the shelf screen: a spin costs Drip (config), three reels with weighted symbols, payouts from
  a table in `data/config/drip_slots.json` (three of a kind: an item from a rarity pool that includes figures;
  two of a kind: a little money; else nothing), rewards to the stash (not found in raid). The Oddities bonus
  gives one free spin per real day. Seeded and saved so a reload can't re-roll a spin.

## 7. Save, docs, tests

Save version 18 (shelf contents, seen figures, slot machine state), older saves load with an empty shelf.
DESIGN: a Collectible Figures section (the figure table by set generated from the data and checked by a test, the
missing-table note), §9 (the station), §10/§11 (barters, the quest line), §15, §16, §18; README. Suite
`tests/figures_test.gd`: data and loader problems, every boss and original POI has a figure, sources (seeded
drops), shelf place/move/remove with slots per level and a full stash, safety (death, sort, sell, barter, quest,
flea don't touch displayed figures), each bonus on and off through its real effect, the no-resale sweep with the
Traders bonus on, spares logic, generic barters, the quest line to the secure container, the slot machine (cost,
free spin per day, payouts, no re-roll after reload), the collection screen states, save round trip and an old
save; the shelf screen through its controls, with screenshots looked at.
