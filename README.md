# AI Game

Top-down 3D survival extraction looter shooter built in Godot 4 with GDScript. The design lives in [DESIGN.md](DESIGN.md).

## Run it

1. Install **Godot 4.7** (standard version, not .NET) from https://godotengine.org/download. It's a single program file: unzip it and run it, no installer needed.
2. Get this repo: `git clone https://github.com/Tiddywagon/ai-game.git`, or **Code → Download ZIP** on GitHub.
3. In Godot's Project Manager, click **Import**, select this folder's `project.godot`, then **Import & Edit**.
4. Press **F5** (or the ▶ button, top right) to run. The game starts at the main menu.

## Playing

On first launch you pick a faction (BEAR or USEC); that creates your profile. From the main menu:

- **ENTER RAID**: pick a map (only Test Yard is playable so far), play as your PMC or as a Scav, check your loadout, then load in.
- **HIDEOUT**: build and upgrade stations (Generator, Medstation, Workbench, Lavatory) and craft with them.
- **CHARACTER**: your gear, stats, skills and stash. **INVENTORY** (or Tab) opens the grid inventory with the stash beside it, to move gear between them.
- **TRADERS**: loyalty levels and what the next one needs; BUY, BARTER and TASKS (hand-in quests) for each trader.
- **Settings** (gear icon, bottom right): graphics, audio, controls and key bindings, gameplay, interface and accessibility.

## Controls

| Keyboard / mouse | Controller | Action |
|---|---|---|
| W A S D | Left stick | Move (relative to the screen) |
| Mouse | Right stick | Aim (the mouse is captured in a raid and moves the reticle) |
| Left click | RT | Shoot (hold for full-auto) |
| R | X | Reload |
| Right click | LT | Aim (looks through the sight: a scope sees farther and narrower); in cover, peek out |
| Space | A | Combat roll |
| Q | LB | Take / leave cover |
| Shift | L3 | Sprint (uses stamina) |
| C | B | Crouch / stand: slower and quieter |
| Tab | Back | Inventory (open / close; moving items needs the mouse for now) |
| F | Y | Search a container or body, pick up an item |
| L | — | Flashlight |
| B | — | Binoculars (right-click to look through them; can't shoot while holding them) |
| Esc | Start | Pause menu (resume, settings, leave raid, quit) |

**Inventory** (mouse only for now): drag items to move them; the cells underneath turn green where the item fits, amber where it stacks or goes inside a rig or backpack, red where it can't go. **R** while dragging turns it; **Shift**-drag splits a stack in half (the mouse wheel changes how many); **right-click** examines (stats, rarity, value); **double-click** a rig, backpack or case to open it. Drop guns, armor, rigs and so on onto the equipment slots to wear them. Everything you carry has weight: from 25 kg you slow down and sprinting tires you faster; from 40 kg you're overweight and can't sprint or roll (thresholds in `data/config/inventory.tres`).

**Raids and found in raid.** Search containers (crates, toolboxes, jackets, weapon boxes, medical bags, safes, filing cabinets) and bodies with **F**: they open beside your inventory and their contents turn up one item at a time while open (small items faster; closing pauses). Drag what you want across, or drag gear straight off a body's slots, and pick up loose items on the ground. To get out, stand in the green ring in the north-east corner for 7 seconds before the clock (top right) runs out. Anything you looted gets a faded checkmark; if you extract it turns solid: the item is **found in raid** (FIR). Dying, running out of time, LEAVE RAID, or a **Run Through** (extracting within 7 minutes with under 200 raid experience) gives nothing FIR, and as a PMC dying or leaving loses everything except your secure container. Bought, bartered and reward items are never FIR; hideout crafts always are; what you bring in keeps its status. Quests, hideout upgrades and some barters only take FIR items where the requirement shows the checkmark. Hover a checkmark for "Found in raid"; the stash's **FIR only** filter dims the rest; examine a gun to see (or UNLOAD) its rounds by status.

Keyboard and mouse keys can be remapped in Settings > Controls. Menus work with the arrow keys, Enter and Esc, or the D-pad, A and B; Q / E or LB / RB switch settings tabs.

Test Yard debug keys: **F1** left leg fracture, **F2** overweight, **F3** switch ammo (5.45 PS / BS), **F4** AI on/off, **F5** heal everything, **F6** cycle the gun's sight (iron, red dot, holo, 2-4x, 6-8x), **F7** time of day, **F8** weather, **F9** flashbang at the reticle, **F10** fog of war off.

You only see inside a cone pointed at the reticle, plus a small circle around you; enemies outside it aren't drawn, and places you've seen before stay as a dim grey memory. Walls, cars, crates and the hedge block sight; low cover only blocks it while you crouch. Night, dark rooms, fog and rain shorten your sight; the flashlight helps. Sounds you can't see the source of show as arrows at the screen edge.

Health works per body part, as in Tarkov: head or thorax at 0 kills, any other part at 0 is "blacked" and passes further damage on to the rest of the body. Hits can cause bleeds and fractures. The silhouette in the bottom-left corner shows each part's health and effects. There are no meds yet, so bleeds don't stop (F5 heals while testing). When you die, the death screen says what killed you.

The ammo count, spare rounds and reload progress are in the bottom-right corner. With **Auto-reload** on (Settings > Gameplay), pulling the trigger on an empty magazine reloads.

Trader offers live in `data/traders/offers.json`, quests in `data/quests/quests.json`, hideout stations and crafts in `data/hideout/stations.json` (requirements are `{"item", "count", "fir"}`), and extraction, Run Through and raid experience in `data/config/raid.tres`. Roll, cover and bullet numbers live in `data/config/combat.tres`; body-part HP, bleed and fracture chances in `data/config/health.tres`; every vision angle, range and multiplier (cones, light, weather, optics, AI) in `data/config/vision.tres`. Each gun's handling (fire rate, magazine, reload times, spread, recoil) is a `WeaponData` file in `data/weapons/`; add a gun by adding a file there and pointing its item (in `data/items/weapons/`) at it. Your settings are saved in `settings.cfg` and your profile in `savegame.json`, both in Godot's user folder (on Windows: `%APPDATA%\Godot\app_userdata\AI Game\`).

## Adding items

Every item lives in `data/items/` (any subfolder). No code needed: either make an `ItemData` resource in the Inspector and save it as a `.tres`, or add an entry to a `.json` file (one item, or a list):

```json
{
  "id": "gas_analyzer",
  "name": "Gas analyzer",
  "description": "Wanted for the Medstation.",
  "category": "junk",
  "rarity": "uncommon",
  "size": [1, 2],
  "weight": 0.6,
  "value": 25000,
  "max_stack": 1,
  "stats": {},
  "loot_weight": 1.0
}
```

Only `id`, `name`, `category` and `rarity` are required. Categories: weapon, ammo, attachment, armor, rig, backpack, helmet, meds, food, valuable, junk, key, container, melee. Rarities: common, uncommon, rare, ultra_rare (or "Ultra Rare"), epic, legendary. Guns add `"weapon": "res://data/weapons/<gun>.tres"`; `"icon": "res://..."` replaces the placeholder icon; `"loot_weight": 0` keeps an item out of random loot. Rigs, backpacks and cases get their own grid with `"stats": {"grid": [4, 2]}` (add `"secure": true` for a secure container); pistols need `"stats": {"class": "pistol"}` to go in the pistol slot. Mistakes show up in the Output panel with the file name.

## Loot

Every container type has its own loot table in `data/loot_tables/` (`crate.tres`, `medical_bag.tres`, `safe.tres`...; loose loot uses `loose_loot.tres`). A roll picks a rarity (base weights Common 55, Uncommon 25, Rare 12, Ultra Rare 5, Epic 2.5, Legendary 0.5) multiplied by the table's own rarity multipliers (a safe boosts rare drops) and the map's (`loot_multipliers` in `data/maps/*.tres`, e.g. Labs doubles Epic and Legendary), then an item of that rarity from the table's item list or categories. Container types (`data/loot_tables/containers/`) set the table, grid size, search time and look; place one in a map with a `LootBox` node. Search timing is in `data/config/raid.tres`. To check the rates, open `scenes/debug/loot_roll_test.tscn` and press **F6** (Run Current Scene): it rolls 10,000 times for each setup and shows expected vs rolled rates, also printed to the Output panel. From a terminal: `godot --path . res://scenes/debug/loot_roll_test.tscn -- --quit --seed=42`.

## Notes

- Commit the `.uid` files Godot creates next to scripts and scenes; they keep references stable.
- `.godot/` is a local cache and is git-ignored.
- Placeholder music and UI sounds are generated by `tools/make_placeholder_audio.py` (needs Python, numpy and ffmpeg).
- When you set up an export preset, add `*.json` to its "Filters to export non-resource files" so JSON items are included.
