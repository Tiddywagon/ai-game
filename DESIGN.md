# DESIGN.md — Game Design Document

> **Source of truth.** Read this file before every task. If code and this doc disagree, this doc wins (or update it first). Values marked *(tune)* are starting points for balancing.

## 1. Overview

| Field | Value |
|---|---|
| Working title | *TBD* |
| Genre | Survival extraction looter shooter |
| Camera | Top-down 3D (angled, fixed-rotation; mouse aim) |
| Platform | PC (Windows/Linux), mouse + keyboard |
| Engine / Language | Godot 4.x / GDScript |
| Inspiration | Escape from Tarkov |
| Mode | Single-player PvE first; PvP/co-op later |
| Pillars | Risk vs. reward · Meaningful loot · Gear fear · Long-term progression |

## 2. Core Loop

| Step | Phase | Player actions | Outcome |
|---|---|---|---|
| 1 | **Prepare (Hideout)** | Manage stash, buy/sell/barter, take quests, craft, upgrade stations, build loadout | Ready loadout |
| 2 | **Enter Raid** | Choose faction, map, time of day; deploy at random spawn | Raid timer starts |
| 3 | **Loot** | Fight Scavs/PMCs, search containers & bodies, complete in-raid quest objectives | Backpack fills |
| 4a | **Extract** | Reach an open extract before timer ends | Keep everything carried → stash |
| 4b | **Die / MIA** | Killed or timer expires | Lose all gear except Secure Container + insured items (returned later) |

**Retention rules**

| Item location | Survived | Died |
|---|---|---|
| Equipped / backpack / rig / pockets | Kept | Lost (insured items may return in 1–2 raids) |
| Secure container | Kept | Kept |
| Found-in-Raid (FIR) tag | Applied to looted items on extract | — |

## 3. Factions

Player chooses a PMC faction per character. Both are hostile to Scavs and to the other faction.

| | **BEAR** | **USEC** |
|---|---|---|
| Background | Russian-backed PMC | Western private military contractor |
| Starting gear bias | AK platform, Eastern armor | AR platform, Western armor |
| Starting trader rep bonus | Prapor +0.05 | Peacekeeper +0.05 |
| Exclusive quest line | "Motherland" chain | "Contract" chain |
| Voice / dog tags | Russian | English |

## 4. AI Enemies — Scavs

| Type | Spawn | Behavior | Gear tier | Loot drop |
|---|---|---|---|---|
| Scav | Common, waves | Patrol, loose groups, poor accuracy | Common–Uncommon | Junk, meds, ammo |
| Scav Sniper | Fixed overwatch spots | Static, long range | Uncommon | Rifles, ammo |
| Raider | Specific POIs | Aggressive, flanks, good aim | Rare–Ultra Rare | Armor, attachments |
| Boss | Map-specific, ~30% chance *(tune)* | Unique pattern + guards | Epic–Legendary | Unique loot table |
| AI PMC | Random spawns | Hunt, loot, extract like player | Uncommon–Epic | Full loadout |

AI implementation: state machine (Idle → Patrol → Alert → Combat → Search → Loot), `NavigationAgent3D`, hearing + vision cone, faction relation table.

## 5. Maps

| Map | Size | Players/AI | Raid time | Extracts | Boss | Theme / key loot |
|---|---|---|---|---|---|---|
| Customs Yard | Medium | 6 / 15 | 35 min | 4 (1 paid, 1 conditional) | Reshala | Industrial; starter quests |
| Woodland | Large | 8 / 18 | 45 min | 5 | Shturman | Forest, sawmill; rifles |
| Factory | Small | 4 / 8 | 20 min | 2 (1 key-locked) | Tagilla | Close quarters; fast raids |
| Shoreline Resort | Large | 8 / 20 | 45 min | 5 | Sanitar | Resort; high-value keys & meds |
| Labs | Medium | 6 / 12 Raiders | 35 min | 3 (all conditional) | — | Requires keycard; Epic/Legendary loot |

Extract types: **Always open · Random (chance) · Paid (roubles) · Conditional (no backpack, power on, keycard) · Scav-only**.

## 6. Items

### 6.1 Categories

| Category | Examples | Key stats |
|---|---|---|
| Weapons | Pistols, SMGs, shotguns, ARs, DMRs, bolt-actions | Damage, fire rate, recoil, ergonomics, accuracy, caliber |
| Ammo | 9x19, 5.45, 5.56, 7.62, 12ga | Damage, penetration, armor damage |
| Attachments | Muzzles, sights, stocks, grips, mags, lasers, lights | Recoil %, ergo, accuracy, noise |
| Armor | Vests (class 1–6) | Class, durability, zones, move penalty |
| Rigs | Chest rigs, armored rigs | Grid slots, (armor class if armored) |
| Backpacks | Sling → large raid packs | Grid size, weight |
| Helmets | Bump caps → class 4–5 helmets | Class, durability, ricochet, hearing penalty |
| Meds | Bandage, tourniquet, splint, medkit, surgical kit, painkillers, stims | Heals HP / fixes bleed, fracture; uses |
| Food & Drink | Crackers, canned meat, water, energy drink | Energy, hydration |
| Valuables | Gold chain, Bitcoin, LEDX, GPU | High sell value, small size |
| Junk / Barter | Bolts, screws, wires, duct tape, fuel | Used in barters, crafts, hideout upgrades |
| Keys | Room keys, keycards | Uses, unlocks loot rooms/extracts |
| Containers | Ammo case, item case, Secure container (2x2 → 3x4) | Internal grid |

### 6.2 Rarity Scale

| Rarity | Color | Base drop rate *(tune)* | Typical items |
|---|---|---|---|
| Common | Grey | 55% | Junk, crackers, bandages, 9mm ammo |
| Uncommon | Green | 25% | Basic meds, class 2 armor, pistols |
| Rare | Blue | 12% | ARs, class 3–4 armor, surgical kits |
| Ultra Rare | Purple | 5% | Good scopes, class 5 armor, stims |
| Epic | Orange | 2.5% | Bitcoin, GPU, high-pen ammo, keycards |
| Legendary | Gold | 0.5% | LEDX, class 6 armor, boss uniques |

- Rates are per-roll weights for generic loot spawns; sum = 100%.
- **Modifiers:** container type (safe/jacket/weapon box), map tier (Labs ×2 for Epic+), boss loot tables override, hideout/skill bonuses ≤ +10% relative.

### 6.3 Gear Variance (Rolled Loot)

Borderlands-style variety with Tarkov-style realism. Each dropped **weapon, attachment, armor, helmet, rig, or backpack** is an *instance* of a base item. Depending on rarity, it can roll **craftsmanship bonuses** based on real differences in manufacturing quality, wear, and gunsmith work. Meds, food, ammo, valuables, junk, and keys never roll.

**Realism rules (always apply)**

| Rule | Detail |
|---|---|
| Ballistics decide fights | Ammo sets damage and penetration; armor class sets protection. Rolls never add damage or penetration and never raise armor class |
| Small numbers | Bonuses are a few percent, with hard caps. A Legendary is better, never overpowered |
| Real-world cause | Every bonus has a believable source: match barrel, hand-fitted parts, newer production run, gunsmith work |
| No sci-fi | No elemental damage, lifesteal, stacking buffs, or loot beams |
| Trade-offs | Most gunsmith mods have a downside |
| Condition matters | Below 50% durability, all roll bonuses are halved |

**Rolls by rarity** *(tune)*

| Rarity | Bonuses | Roll quality | Gunsmith mod |
|---|---|---|---|
| Common | 0 | — | — |
| Uncommon | 1 | Low | — |
| Rare | 2 | Low–Mid | — |
| Ultra Rare | 2–3 | Mid | 10% chance |
| Epic | 3 | Mid–High | 35% chance |
| Legendary | 3–4 | High | Always: a named item with a fixed mod |

- **Roll quality** sets where each bonus lands in its range (Low = bottom third, High = top third).
- **Naming:** `[Quality] Base Item`, for example *Match-grade AK-74N* or *Hand-fitted M4A1*. Named Legendaries use their own name.
- **Map bonus:** Labs and boss loot tables roll quality one step higher.

**Weapon bonuses**

| Bonus | Range | Real-world cause | Name |
|---|---|---|---|
| Muzzle velocity | +1–4% (flatter trajectory, slightly more range) | Match barrel | Match-grade |
| Accuracy (MOA) | −5–15% | Free-floated or lapped barrel | Precision |
| Recoil | −2–8% | Tuned gas system | Tuned |
| Ergonomics | +2–6 | Hand-fitted parts | Hand-fitted |
| Malfunction chance | −10–40% | Polished feed ramp | Reliable |
| Durability loss | −10–25% | Chrome-lined barrel | Chrome-lined |
| Weight | −3–10% | Lightened parts | Lightened |

**Gear bonuses**

| Bonus | Range | Real-world cause | Applies to |
|---|---|---|---|
| Max durability | +5–15% | Newer production run | Armor, helmets |
| Blunt damage taken | −3–10% | Better trauma pad | Armor, helmets |
| Movement penalty | −5–20% | Better fit and cut | Armor, helmets |
| Ricochet chance | +3–10% | Better shell geometry | Helmets |
| Weight | −5–15% | Lighter materials | All |
| Stamina drain while loaded | −3–8% | Better harness | Rigs, backpacks |

Attachments roll from the weapon pool at half the range, with at most 2 bonuses.

**Gunsmith mods (Ultra Rare / Epic chance)**

| Mod | Upside | Downside |
|---|---|---|
| Lightened bolt carrier | +8% fire rate | +5% recoil |
| Ported barrel | −8% vertical recoil | +15% noise radius |
| Match trigger | +10% accuracy in semi-auto | — |
| Cerakote finish | −20% durability loss | — |
| Ceramic-composite plates | −20% armor weight | −15% max durability |
| Extra sewn pouch | Rig +1 slot (1×1) | +0.3 kg |

**Named Legendaries** (fixed mod + rolled bonuses)

| Name | Base | Fixed mod | Source |
|---|---|---|---|
| *Reshala's TT* | Gold-plated TT pistol | Hand-fitted: −40% malfunction chance; very high sell value | Reshala |
| *Woodcutter* | SKS | Match barrel, lapped bore: −20% MOA | Shturman |
| *Tagilla's Rig* | Plate carrier | Reinforced: −10% blunt damage, +15% durability | Tagilla |
| *Sanitar's Kit* | Medical rig | Extra sewn pouches: +2 slots (1×1); meds taken from the rig apply 15% faster | Sanitar |
| *Prototype AK-12* | AK-12 | Tuned gas + lightened bolt: −10% recoil, +5% fire rate | Labs |
| *Three-Gun* | M4A1 | Competition build: match trigger + tuned gas | Any Legendary roll |

**Systems interaction**

| System | Rule |
|---|---|
| Examine | An unexamined item hides its rarity, bonuses, and mod |
| UI | Only a subtle rarity-colored cell border; the tooltip lists bonuses and mod. No in-world glow |
| Caps (rolls + mods) | Recoil −15%, ergonomics +10, accuracy −20%, fire rate +10%. These stack with attachment stats |
| Repair | Keeps rolls. A Legendary loses half as much max durability per repair |
| Insurance | Insured items come back with the same rolls |
| Traders | Sell value ×(1 + 0.15 × bonus count); ×2 more for a gunsmith mod. Traders never sell rolled items above Rare |
| Quests | Any rolled variant of the base item counts for a hand-in (FIR still required) |
| Workbench lvl 3 | **Gunsmithing:** add or replace one gunsmith mod using parts and roubles. Can't change Legendaries or reroll bonuses |
| Scavs / AI PMCs | Their gear rolls too, using their gear tier (Section 4) |

## 7. Grid Inventory

| Rule | Detail |
|---|---|
| Grid | Items occupy W×H cells (e.g., bandage 1×1, AR 5×2, backpack folded 5×5) |
| Rotation | `R` rotates 90° while dragging |
| Nesting | Rigs, backpacks, cases have their own grids; can't nest a container in a larger copy of itself |
| Stacking | Ammo, money, some barter items stack (max per type) |
| Slots | Primary, Secondary, Holster, Melee, Helmet, Earpiece, Face, Armor, Rig, Backpack, Pockets (4×1×1), Secure container |
| Weight | Over-encumbered → slower move, faster stamina drain |
| Examine | Unknown items must be examined to reveal name/value |
| Search | Containers/bodies reveal items over time |

## 8. Stash

| Edition / Level | Size (W×H) | Unlock |
|---|---|---|
| Level 1 | 10×30 | Start |
| Level 2 | 10×40 | Hideout: Stash upgrade |
| Level 3 | 10×50 | Hideout: Stash upgrade |
| Level 4 | 10×70 | Hideout: Stash upgrade |

Features: sort, filter by category, search, tagging, quick-sell to traders.

## 9. Hideout

| Station | Max lvl | Function | Example upgrade cost (lvl 2) |
|---|---|---|---|
| Generator | 3 | Powers stations; consumes fuel | 2× Fuel can, 1× Wires |
| Stash | 4 | Increases stash size | 500k ₽, Prapor LL2 |
| Medstation | 3 | Crafts meds | 2× Bandage, 1× Medical tools |
| Nutrition Unit | 3 | Crafts food/drink | 1× Hose, 1× Kettle |
| Workbench | 3 | Crafts ammo/attachments; unlocks repair | 5× Bolts, 3× Screws |
| Water Collector | 3 | Produces water | 3× Hose, 1× Pump |
| Lavatory | 3 | Crafts barter/junk components | 2× Duct tape, 1× Toilet paper |
| Shooting Range | 3 | Test weapons, recoil tuning | 3× Bolts, 1× Weapon parts |
| Gym | 3 | Trains strength/endurance | 2× Dumbbell |
| Intelligence Center | 3 | Faster quests, cheaper insurance | 1× Flash drive, 2× Intel folder |
| Bitcoin Farm | 3 | Passive Bitcoin (needs GPUs) | 1× GPU, Generator lvl 2 |
| Security | 3 | Raid prep buffs (scouting info) | 3× Nails |

Upgrades require items (often FIR), roubles, trader LL, other station levels, and real-time build duration.

## 10. Traders

| Trader | Specialty | Currency | Unique |
|---|---|---|---|
| Prapor | Eastern weapons, ammo | ₽ | Insurance (cheap, slow) |
| Therapist | Meds, food, valuables | ₽ | Buys valuables at best price |
| Skier | Black-market, attachments | ₽ / $ | Cheap barters |
| Peacekeeper | Western weapons | $ | Buys weapons high |
| Mechanic | Attachments, weapon parts | ₽ | Gunsmith quests |
| Ragman | Clothing, rigs, backpacks, armor | ₽ | Cosmetics |
| Jaeger | Survival gear, hunting rifles | ₽ | Unlocked by quest |

**Actions:** Buy · Sell · Barter (items-for-item) · Repair · Insure · Quests.

### Loyalty Levels (LL)

| LL | Player level | Reputation | Spent with trader | Unlocks |
|---|---|---|---|---|
| 1 | 1 | 0.00 | 0 | Basic stock |
| 2 | 15 | 0.20 | 750k ₽ | Mid-tier gear, more barters |
| 3 | 25 | 0.35 | 1.5M ₽ | High-tier gear, better buy prices |
| 4 | 35 | 0.50 | 2.5M ₽ | Top-tier gear, best prices |

Stock restocks every 1 h *(tune)*; some items have per-restock limits.

## 11. Quests

| Type | Where | Example objectives | Rewards |
|---|---|---|---|
| In-raid | During raid | Kill X Scavs on map; mark a location; place item; survive & extract from Y | XP, ₽, rep, items |
| Out-of-raid | Hideout | Hand over FIR items; build station; reach skill level; craft item | XP, ₽, rep, unlocks |
| Faction | Either | BEAR/USEC exclusive chains | Faction gear |
| Daily/Weekly | Either | Rotating random objectives | XP, ₽, rep |

Quest structure: prerequisites (level, LL, prior quest) → objectives (tracked, may require FIR) → turn-in → rewards. Some rewards unlock trader items or barters.

## 12. Weapon & Gear Upgrades

### 12.1 Weapon Modding

| System | Detail |
|---|---|
| Slot tree | Weapon → receiver → handguard → rail slots; attachments can add sub-slots |
| Stat impact | Each part modifies recoil, ergo, accuracy, weight, noise, size |
| Compatibility | Defined per slot via allowed-item lists |
| Presets | Save/load builds; auto-buy missing parts from traders |
| Durability | Lowers with use; low = malfunctions (jams, misfeeds) |
| Repair | Trader/workbench; each repair lowers max durability |
| Weapon mastery | Per-weapon XP → faster reloads, lower recoil (3 tiers) |

### 12.2 Gear Upgrades

| Gear | Upgrade path | Effect |
|---|---|---|
| Armor | Repair kits, plate inserts (class swap) | Restore durability, raise class |
| Helmets | Visors, faceshields, NVG/headset mounts | Face protection, utility |
| Rigs/Backpacks | Tier progression only (no mods) | Bigger grids |
| Secure container | Quest/barter tiers: Alpha 2×2 → Beta 3×2 → Gamma 3×3 → Kappa 3×4 | Safer loot |

### 12.3 Player Skills

| Skill | Leveled by | Benefit |
|---|---|---|
| Strength | Carrying weight, melee | Carry more, throw farther |
| Endurance | Sprinting | More stamina |
| Vitality | Taking damage | Lower bleed chance |
| Metabolism | Eating/drinking | Slower energy/hydration drain |
| Search | Searching containers | Faster search, rarer loot (+% capped) |
| Weapon class skills | Using weapon type | Recoil, reload speed |

## 13. Health & Survival

| System | Detail |
|---|---|
| Body parts | Head, Thorax (death at 0), Stomach, L/R Arm, L/R Leg |
| Conditions | Light bleed, heavy bleed, fracture, pain, dehydration, exhaustion |
| Energy / Hydration | Drain over time; 0 = HP loss |
| Stamina | Sprint, aim stability |

**Movement** *(tune)*

| Move | Speed | Noise radius | Notes |
|---|---|---|---|
| Walk | 3.5 m/s | 10 m | Default |
| Sprint (Shift) | 6.0 m/s | 20 m | Costs 15 stamina/s; standing still with Shift held costs nothing; sprinting while crouched stands you up |
| Crouch (C, toggle) | 1.6 m/s | 4 m | Body 1.1 m tall instead of 1.8 m |
| Standing still | 0 | 0 | — |

- **Stamina:** 100 max. Recovers 12/s, starting 1 s after you stop sprinting. If it hits 0 you're **exhausted**: sprint stays locked until stamina is back to 25.
- **Acceleration:** 25 m/s², so there's a short ramp-up and slow-down.
- **Turning:** the body turns toward the cursor at up to 720°/s.
- **Noise radius:** how far away AI can hear your footsteps (Section 4).

## 14. Economy

| Item | Value |
|---|---|
| Currencies | Roubles (₽), Dollars ($) |
| Sources | Trader sells, quest rewards, crafting, Bitcoin farm |
| Sinks | Trader buys, insurance, repairs, hideout upgrades, paid extracts |
| FIR | Required for most quest hand-ins and hideout upgrades |
| Starting money | 500,000 ₽ and 0 $ for a new character *(tune)* |

## 15. Technical Notes (Godot 4 / GDScript)

| Area | Approach |
|---|---|
| Item data | `ItemData` custom `Resource` (`scripts/data/item_data.gd`): id, display name, description, category, rarity, size, weight, base value, max stack, stats. One `.tres` per item in `data/items/<category>/<id>.tres`; enums are saved as numbers, so only append new values |
| Loot tables | `LootTable` Resource with weighted rarity rolls |
| Rolled items | `ItemInstance` (base `ItemData` + rarity + bonuses + gunsmith mod + durability + FIR flag); saved per instance. Bonuses and mods are `AffixData` / `GunsmithModData` Resources |
| Inventory | `InventoryGrid` (pure data class) + UI `Control` scene; drag & drop |
| Globals (autoloads) | Built: `GameState` (profile: faction, level, XP, ₽/$, trader loyalty; plus stash contents), `ItemDB` (loads every `ItemData` under `data/items/`), `SaveManager` (JSON save/load). Planned: `TraderManager`, `QuestManager`, `HideoutManager` |
| Saves | One JSON file, `user://savegame.json`: `{version, profile, stash}`. Written to a temp file first, then swapped in. Bump `SAVE_VERSION` when the format changes |
| Player | `Player` (`scenes/actors/player.tscn`): `CharacterBody3D` with a capsule placeholder; the gun box shows facing. Movement rules in Section 13 |
| Camera | `TopDownCamera` (`scripts/camera/`): fixed 60° pitch, 18 m back, never turns; follows the player smoothly at any frame rate |
| Physics | Jolt Physics at 60 ticks/s with physics interpolation on: move bodies in `_physics_process`. Anything moved in `_process` (like the camera) turns interpolation off for itself |
| AI | `CharacterBody3D` + `NavigationAgent3D` + state machine node |
| Naming | snake_case files, PascalCase classes (`class_name`) |
| Engine version | Godot 4.7 (current stable 4.7.2), Forward+ renderer, 1920×1080 base resolution. Commit Godot's `.uid` files |

**Folder layout**

| Folder | Contents |
|---|---|
| `scenes/` | Gameplay scenes: `actors/` (player, Scavs), `hideout/` |
| `maps/` | One scene per raid map (Section 5), plus `test_level.tscn` for movement testing |
| `ui/` | Menu, HUD, and inventory scenes (entry scene: `ui/main_menu.tscn`) |
| `scripts/` | All GDScript, mirroring scene folders (`ui/`, `hideout/`, `actors/`, `maps/`), plus `autoload/` (singletons), `data/` (Resource classes) and `camera/` |
| `data/` | `.tres` Resources: `items/` (one subfolder per category), `loot_tables/` |
| `assets/` | `models/`, `textures/`, `audio/`, `fonts/` |

**Input actions** (defined in `project.godot`)

| Action | Default | Action | Default |
|---|---|---|---|
| `move_forward` / `move_back` | W / S | `reload` | R |
| `move_left` / `move_right` | A / D | `toggle_inventory` | Tab |
| `shoot` | Left mouse | `interact` | F |
| `aim` | Right mouse (hold) | `use_item` | E |
| `hotkey_1` … `hotkey_5` | 1–5 | `sprint` | Shift (hold) |
| `crouch` | C (toggle) | Facing | Turns toward where the mouse cursor touches the ground |

WASD is screen-relative: W always moves up the screen.

## 16. Changelog

| Date | Change |
|---|---|
| 2026-10-11 | Initial design document |
| 2026-10-11 | Added rolled loot (6.3): affixes, traits, named Legendaries |
| 2026-10-11 | Reworked 6.3 for realism: grounded craftsmanship bonuses, gunsmith mods with trade-offs, no damage/pen rolls |
| 2026-10-11 | Godot project scaffold: folder layout, input actions, main menu |
| 2026-10-11 | Project targets Godot 4.7 (was 4.3) |
| 2026-10-11 | Autoloads `GameState`, `ItemDB`, `SaveManager` (replace planned `Stash`/`SaveSystem`); `ItemData` resource, 5 example items, starting money |
| 2026-10-11 | Player movement (walk, sprint, crouch, stamina, noise radius), top-down follow camera, stamina HUD, test level; Play opens the test level until the hideout exists |
