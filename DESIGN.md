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

## 14. Economy

| Item | Value |
|---|---|
| Currencies | Roubles (₽), Dollars ($) |
| Sources | Trader sells, quest rewards, crafting, Bitcoin farm |
| Sinks | Trader buys, insurance, repairs, hideout upgrades, paid extracts |
| FIR | Required for most quest hand-ins and hideout upgrades |

## 15. Technical Notes (Godot 4 / GDScript)

| Area | Approach |
|---|---|
| Item data | `ItemData` custom `Resource` (`.tres`): id, name, size, rarity, weight, value, category, stats |
| Loot tables | `LootTable` Resource with weighted rarity rolls |
| Inventory | `InventoryGrid` (pure data class) + UI `Control` scene; drag & drop |
| Globals (autoloads) | `GameState`, `Stash`, `TraderManager`, `QuestManager`, `HideoutManager`, `SaveSystem` |
| Saves | JSON / `ConfigFile` in `user://` |
| Scenes | `scenes/hideout`, `scenes/maps/*`, `scenes/ui/*`, `scenes/actors/*` |
| Player | `CharacterBody3D`, top-down camera rig, mouse-ray aim |
| AI | `CharacterBody3D` + `NavigationAgent3D` + state machine node |
| Naming | snake_case files, PascalCase classes (`class_name`) |

## 16. Changelog

| Date | Change |
|---|---|
| 2026-10-11 | Initial design document |
