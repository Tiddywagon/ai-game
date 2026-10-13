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
| 2 | **Enter Raid** | Pick a map, play as your PMC or as a Scav, check the loadout (Section 16.3); deploy at random spawn | Raid timer starts |
| 3 | **Loot** | Fight Scavs/PMCs, search containers & bodies (**F**), pick up loose items, complete in-raid quest objectives | Backpack fills |
| 4a | **Extract** | Stand in an open extract for 7 s *(tune)* before the timer ends | Keep everything carried; loot becomes found in raid |
| 4b | **Die / MIA** | Killed, the raid timer runs out, or LEAVE RAID from the pause menu | Lose all gear except Secure Container + insured items (returned later) |

**Retention rules** (built: `RaidOutcome`)

| Item location | Survived / Run Through | Killed / MIA |
|---|---|---|
| Equipped / backpack / rig / pockets | Kept | Lost (insured items may return in 1–2 raids; insurance isn't built yet) |
| Secure container | Kept | Kept |
| Found-in-Raid (FIR) tag | Applied to loot on a SURVIVED extract (not on a Run Through) | Never |
| Scav run | Everything the Scav carries goes to the stash (what doesn't fit is left behind) | Nothing from the stash was at risk |

**Raid experience** *(tune, `data/config/raid.tres`)*: 100 per Scav kill, 300 per PMC kill, 10 per item looted. Added to the profile however the raid ends.

### 2.1 Found in Raid (FIR)

| Rule | Detail |
|---|---|
| Gains FIR | An item you pick up, loot from a container or body, or take off an enemy during a raid, **and** you survive and extract with it. Until then it's *pending*: a faded checkmark that turns solid on a successful extract |
| Never FIR | Anything bought from traders or the flea market, quick-buy loadouts, insurance returns, barter rewards and quest rewards (the sources the flea market, quick-buy and insurance will use are already defined) |
| Always FIR | Hideout crafts |
| Brought in | Items you bring into a raid keep their status. Putting one in a container or on a body and taking it back doesn't change it |
| No FIR | Killed, MIA (timer or leaving) and Run Through: nothing gains FIR. **Run Through:** extracting within 7 minutes **and** with under 200 raid experience *(tune)* |
| Stacks | Only merge when they share the same status (FIR, looted this raid, brought in). A split keeps the status of its stack |
| Inside things | Containers keep FIR per item inside them (a plain backpack can hold FIR items). A gun's magazine keeps FIR per round: a reload adds the rounds as they are, the last loaded is fired first, and UNLOAD (examine panel) gives them back as stacks by status |
| Display | A small checkmark in the bottom-right corner of the item's cell everywhere items are drawn (stash, inventory, loot panels, trader, quest and hideout screens), with the tooltip "Found in raid". The examine panel shows the status (and how many loaded rounds are FIR) |
| Stash filter | **FIR only** (stash header, inventory and Character screen) dims everything else |
| Requirements | Quest hand-ins, hideout upgrades and certain barters that require FIR only accept items with the checkmark; the requirement shows the same checkmark next to the item name. Requirements without it use non-FIR items first, so FIR items are kept |

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

**Combat behaviour (built for Scavs and AI PMCs).** Scavs are friendly to each other; everyone else is hostile.

| Sense / action | Rule |
|---|---|
| Vision | Same rules as the player (Section 13.6): a cone in front, anyone within 3 m noticed regardless, a clear sight line (walls, cars, crates, hedges block; low cover only if either side is crouched). Shorter at night, in dark rooms, fog and rain; someone with a flashlight on is spotted from 1.5× farther. A magnified scope adds a long narrow cone it scans with. Blinded by flashbangs. Once in combat it tracks its target outside the cone |
| Hearing | Hears any noise whose radius reaches it (footsteps, rolls, shots); walks over to investigate, then looks around |
| Under fire | A bullet passing within 2 m puts the bot in combat with the shooter |
| Cover | Picks a free cover point that hides it from the threat, preferring spots it can shoot from. Ducks, peeks for a burst, ducks again. Moves to new cover when flanked or after a few peeks |
| Search | Loses sight for too long → goes to the last known position and looks around |
| Health | Same body parts, bleeds and fractures as the player (Section 13.5): a leg hit slows a bot, an arm hit makes it sway |
| Shooting | Same guns as the player (Section 13.4): fires in bursts, so recoil and bloom build and settle, and always fires aimed (no hip-fire spread). Fights off part of each recoil kick (Scav 30%, PMC 60%, `BotProfile.recoil_control`). Aim error is added on top of the gun's spread. From cover it waits until it has stopped stepping out before firing |
| Reloading | Reloads when the magazine runs dry, and tops up while ducked below half a magazine. Never peeks while reloading. Bots carry 90 spare rounds in their rig |
| Gear | Each bot carries a full kit, all of it lootable from its body (F): a Scav has an AK-74N with PS, a Scav vest with 90 PS, sometimes a helmet (25%), a hatchet (20%) or a sling bag of junk (40%), and odds and ends in its pockets; an AI PMC has an AK-74N with BS, sometimes a PM pistol (40%), armor, a helmet, a tactical rig with 90 BS and a bandage, a pack with a few finds, and meds in its pockets. Its spare rounds are the ones in its rig: each reload takes them out, and the gun keeps the rounds left in it |

| Profile | Vision (daylight) | Sight | Reaction | Aim error | Hearing | Rolls | Ammo |
|---|---|---|---|---|---|---|---|
| Scav (basic) | 25 m, 120° | Iron sights | 0.8 s | 2.8° | ×1.0 | Never | 5.45 PS |
| PMC (advanced) | 35 m, 140° | 2-4x scope (+70 m, 40° cone) | 0.4 s | 0.3° | ×1.3 | 50% chance to roll out of the line of fire when shot at in the open; 70% chance to roll into new cover when it's within reach | 5.45 BS |

## 5. Maps

| Map | Size | Players/AI | Raid time | Extracts | Boss | Theme / key loot |
|---|---|---|---|---|---|---|
| Customs Yard | Medium | 6 / 15 | 35 min | 4 (1 paid, 1 conditional) | Reshala | Industrial; starter quests |
| Woodland | Large | 8 / 18 | 45 min | 5 | Shturman | Forest, sawmill; rifles |
| Factory | Small | 4 / 8 | 20 min | 2 (1 key-locked) | Tagilla | Close quarters; fast raids |
| Shoreline Resort | Large | 8 / 20 | 45 min | 5 | Sanitar | Resort; high-value keys & meds |
| Labs | Medium | 6 / 12 Raiders | 35 min | 3 (all conditional) | — | Requires keycard; Epic/Legendary loot |

Extract types: **Always open · Random (chance) · Paid (roubles) · Conditional (no backpack, power on, keycard) · Scav-only**.

**Climate** (`climate`, `energy_drain_multiplier`, `hydration_drain_multiplier` in each map's `.tres`; Section 13.7): Shoreline Resort and Factory are **hot** (hydration drains ×1.5 and ×1.35, energy ×1.1), Woodland is **cold** (energy ×1.15, hydration ×0.9), the rest temperate. The HUD shows HOT or COLD next to the weather.

**Test Yard** (playable): 15-minute raid, one always-open extract (the green ring in the north-east corner), one of each container type (crate, toolbox, jacket, weapon box, medical bag, safe, filing cabinet, duffle bag, and the food spots: a fridge and store shelf in the south-east corner, a gas station counter on the east wall, a kitchen cabinet on the west wall; rolled from their tables at raid start) and eight loose loot spots. Containers are placeholder shapes in each type's colour.

## 6. Items

### 6.1 Categories

| Category | Examples | Key stats |
|---|---|---|
| Weapons | Pistols, SMGs, shotguns, ARs, DMRs, bolt-actions, LMGs (22 guns, Section 6.4) | Fire rate, recoil, ergonomics, accuracy, caliber (damage comes from the ammo) |
| Ammo | 9x18, 9x19, .45 ACP, 12ga, 5.45x39, 5.56x45, 7.62x39, 7.62x51, 7.62x54R, .338 Lapua; 4–6 rounds each (Section 6.4) | Damage, penetration, armor damage, fragmentation, velocity, recoil, accuracy, ricochet, light/heavy bleed; pellets, tracer, noise |
| Attachments (weapon parts) | Muzzle devices, barrels, handguards, foregrips, stocks, pistol grips, dust covers, sights, lasers, magazines | Vertical and horizontal recoil, recoil recovery, base spread, bloom per shot, max bloom, bloom recovery, hip-fire spread, ergonomics, weight; some also muzzle velocity, aim speed, noise, jam chance, wear, magazine size (Section 12.1) |
| Armor | Vests and plate carriers (class 1–6; Section 12.2) | Class, durability, zones (thorax, stomach, arms), blunt, ricochet, destructibility, upgrade level; move penalty planned |
| Rigs | Chest rigs, armored rigs (class 1–6) | Grid, (armor stats if armored), upgrade level |
| Backpacks | Daypack → 8×8 raid packs | Grid size, weight, upgrade level |
| Helmets | Bump caps → class 6 helmets, with face shield and headset slots | Class, durability, ricochet, hearing; face shields (face zone), headsets (hearing) |
| Meds | Bandages, tourniquets, a hemostat, splints, painkillers, small and large medkits (HP pools), surgical kits, 9 stimulants (Section 13.7) | Use time; uses or HP pool; treats light/heavy bleed, fracture, blacked parts; timed effects and side effects |
| Food & Drink | Crackers, canned fish, meat and peas, condensed milk, MRE, water, juice, energy drinks, vodka, moonshine (Section 13.7) | Energy, hydration, use time; some have effects |
| Valuables | Gold chain, watches (wrist, pocket, Roler), coins (silver, gold, rare collection), GPU, hard drives (HDD, SSD, military), Bitcoin, cold-wallet crypto drive, LEDX, flash drive, intelligence folder (Section 13.7) | High sell value, small size; wanted in barters and crafts |
| Junk / Barter | Bolts, screws, wires, duct tape, batteries (AA, rechargeable, car), fuel and fuel conditioner, matches, lighter, toothpaste, soap, cigarettes, light bulbs, capacitors, circuit boards, gunpowder, WD-40, military cable, kettle, pliers, screwdriver, nails, hose, medical tools (Section 13.7) | Used in barters, crafts, hideout upgrades |
| Keys | Room keys, keycards | Uses, unlocks loot rooms/extracts |
| Containers | Ammo case, item case, Secure container (2x2 → 3x4) | Internal grid |

### 6.2 Rarity Scale

| Rarity | Color | Base drop rate *(tune)* | Typical items |
|---|---|---|---|
| Common | Grey | 55% | Junk, crackers, bandages, 9mm ammo |
| Uncommon | Green | 25% | Basic meds, class 2 armor, pistols |
| Rare | Blue | 12% | ARs, class 3–4 armor, surgical kits |
| Ultra Rare | Purple | 5% | Good scopes, class 5 armor, stims |
| Epic | Orange | 2.5% | Bitcoin, GPU, Roler, intelligence folder, AFAK, Surv12, combat stims, high-pen ammo, keycards |
| Legendary | Gold | 0.5% | LEDX, crypto drive, Grizzly medkit, eTG-c and Obdolbos stims, class 6 armor, boss uniques |

- Rates are per-roll weights for generic loot spawns; sum = 100%.
- **Modifiers:** container type (safe/jacket/weapon box), map tier (Labs ×2 for Epic+), boss loot tables override, hideout/skill bonuses ≤ +10% relative.

**How a roll works:** every container type has its **own loot table** (`data/loot_tables/<type>.tres`; loose loot uses `loose_loot.tres`). Weight of each rarity = base weight (55 / 25 / 12 / 5 / 2.5 / 0.5) × the table's rarity multipliers × the map's multiplier. Pick a rarity by weight, then an item of that rarity the table can hold: its item list if it has one (a toolbox holds tools), else its categories (a medical bag holds meds). Each item's `loot_weight` and the table's `item_weights` set how often it comes up among its rarity; `loot_weight` 0 = never from loot (quest items, boss uniques). If a table can't hold any item of some rarity (a medical bag has no Epic meds), that rarity's weight is 0, so the other rarities share its chance. Stackable items (ammo) come as a partial stack (a fifth to a half of a full stack); guns come loaded.

| Container *(tune)* | Holds | Items | Rarity multipliers (C / U / R / UR / E / L) | Grid | Search time | Solid |
|---|---|---|---|---|---|---|
| Loose loot (on the ground) | Anything | 1 (70% of spots) | 1 / 1 / 1 / 1 / 1 / 1 | — | — | — |
| Crate | Ammo, junk, melee | 1–4 | 1.1 / 1 / 1 / 0.9 / 0.8 / 0.6 | 5×4 | ×1 | Yes (wood) |
| Toolbox | Bolts, screws, wires, tape, pliers, screwdriver, nails, hose, weapon parts, electric motor, batteries, light bulbs, capacitors, circuit boards, WD-40, gunpowder, military cable, lighters | 1–3 | 1 / 1 / 1.1 / 1.2 / 1 / 1 | 4×2 | ×1 | No |
| Jacket | Ammo, meds, food, valuables, junk, keys | 0–2 | 1 / 1 / 1 / 1 / 1 / 1 | 2×2 | ×0.8 | No |
| Weapon box | Weapons, ammo, attachments | 1–2 | 0.8 / 1 / 1.3 / 1.3 / 1.2 / 1 | 6×3 | ×1.1 | Yes (wood) |
| Medical bag | Meds and stims (all 26), medical tools | 1–3 | 0.8 / 1.1 / 1.3 / 1.5 / 1 / 1 | 3×3 | ×1 | No |
| Safe | Valuables, keys | 1–2 | 0.3 / 0.8 / 1.5 / 2.5 / 3 / 3 | 3×3 | ×1.4 | Yes (metal) |
| Filing cabinet | Keys, flash drives, intelligence folders (×2 likely), paper, matches, gold chains, hard drives, crypto drives, cigarettes, lighters | 1–3 | 1 / 1 / 1.2 / 1.3 / 1.2 / 1 | 4×4 | ×1.2 | Yes (metal) |
| Duffle bag | Ammo, attachments, meds, valuables, junk | 1–3 | 1 / 1 / 1 / 1 / 1 / 1 | 4×3 | ×1 | No |
| Fridge | Drinks, canned food, alcohol, field rations | 1–4 | 1 / 1.1 / 1 / 0.9 / 1 / 1 | 3×4 | ×0.8 | Yes (metal) |
| Kitchen cabinet | Dry and canned food, combo rations, matches, lighters, soap, kettles | 1–4 | 1 / 1.1 / 1 / 0.9 / 1 / 1 | 4×3 | ×1 | Yes (wood) |
| Store shelf | Snacks, food, drinks, combo rations, cigarettes, hygiene, batteries, bulbs | 2–5 | 1 / 1.1 / 1 / 0.9 / 1 / 1 | 5×3 | ×1.1 | Yes (metal) |
| Gas station counter | Energy and sports drinks, water, coffee, snacks, combo rations, cigarettes, lighters, batteries, WD-40, fuel conditioner | 1–4 | 1 / 1.1 / 1 / 0.9 / 1 / 1 | 4×3 | ×1 | Yes (metal) |

Solid containers block movement and bullets (wood ones can be shot through) and the AI paths around them.

| Map | Rarity multipliers |
|---|---|
| Labs | Epic and Legendary ×2 |
| Every other map | ×1 |

So a safe on Labs drops Epic about 22% and Legendary about 4.4% of the time, against 2.5% and 0.5% for loose loot elsewhere. `scenes/debug/loot_roll_test.tscn` rolls 10,000 times for the base table, every container type's table, loose loot on Labs and a safe on Labs, and prints expected vs rolled rates.

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

### 6.4 Weapons & Ammo

The starter arsenal: **22 guns** in seven classes, **10 calibers with 4–6 rounds each (50 rounds)** and **183 weapon parts**, all in data files (made-up names, each inspired by a real type of gun). The round decides damage, penetration and armor damage; the gun decides how it handles (Section 12.1) and its parts what that becomes. Bolt-action rifles and DMRs make 360 trick shots (Section 13.4.1).

**Guns** *(tune: `data/weapons/<gun>.tres`; items in `data/items/weapons/`)*. Every gun trains its class's skill: Pistols, SMGs, Shotguns, Assault rifles, Marksman rifles, Bolt-action rifles or Machine guns (Section 12.3). Pistols go in the Pistol slot. Climb / side is the recoil per shot with the parts each gun comes with. Every gun can also turn up as loot (weapon boxes, loose loot), loaded with its caliber's everyday round.

| Gun | Class | Inspired by | Caliber | Fire | Magazine | Ergonomics | Climb / side | Rarity | Where |
|---|---|---|---|---|---|---|---|---|---|
| PM pistol | Pistol | Soviet service pistol | 9x18 | 450 rpm semi | 8 | 70 | 1.0° / 0.55° | Uncommon | Prapor |
| Vektor P9 | Pistol | Polymer-frame striker pistol | 9x19 | 450 rpm semi | 17 | 76 | 0.85° / 0.45° | Uncommon | Peacekeeper |
| Bastion 45 | Pistol | All-steel .45 single-action | .45 ACP | 400 rpm semi | 8 | 68 | 1.25° / 0.55° | Rare | Peacekeeper |
| Strelka MP | Pistol | Select-fire machine pistol with a holster stock | 9x18 | 750 rpm auto | 20 | 62 | 0.6° / 0.5° | Rare | Prapor |
| Hornet SMG | SMG | Roller-delayed SMG | 9x19 | 800 rpm auto | 30 | 66 | 0.32° / 0.26° | Rare | Peacekeeper |
| Brigand 45 | SMG | Polymer .45 SMG | .45 ACP | 600 rpm auto | 25 | 63 | 0.45° / 0.3° | Rare | Skier |
| Wasp PDW | SMG | Short-stroke piston PDW | 9x19 | 850 rpm auto | 30 | 70 | 0.3° / 0.27° | Ultra Rare | Peacekeeper |
| Warden 870 | Shotgun | Pump-action tube shotgun | 12ga | 70 rpm pump | 6 (tube) | 50 | 1.9° / 0.6° | Uncommon | Skier, Jaeger |
| Tempest S12 | Shotgun | Semi-auto box-fed shotgun on an AK receiver | 12ga | 300 rpm semi | 5 | 46 | 1.6° / 0.55° | Rare | Skier |
| AK-74N | Assault rifle | 5.45 Kalashnikov | 5.45x39 | 650 rpm auto | 30 | 50 | 0.55° / 0.35° | Rare | Prapor |
| Tundra 47 | Assault rifle | 7.62x39 stamped Kalashnikov | 7.62x39 | 600 rpm auto | 30 | 46 | 0.72° / 0.42° | Rare | Prapor |
| Sentinel AR | Assault rifle | Direct-impingement carbine | 5.56x45 | 800 rpm auto | 30 | 56 | 0.45° / 0.28° | Ultra Rare | Peacekeeper |
| Halcyon B5 | Assault rifle | Bullpup rifle | 5.56x45 | 700 rpm auto | 30 | 58 | 0.4° / 0.3° | Epic | Loot |
| Partisan | DMR | Semi-auto carbine with a fixed 10-round magazine | 7.62x39 | 350 rpm semi | 10 (fixed) | 45 | 1.0° / 0.35° | Uncommon | Prapor |
| SVD marksman rifle | DMR | Soviet marksman rifle | 7.62x54R | 300 rpm semi | 10 | 40 | 1.4° / 0.4° | Rare | Prapor |
| Longbow DMR | DMR | Big-frame AR marksman rifle | 7.62x51 | 400 rpm semi | 20 | 42 | 1.15° / 0.38° | Epic | Loot |
| Mosin rifle | Bolt-action | Soviet infantry rifle | 7.62x54R | 50 rpm bolt | 5 | 35 | 2.4° / 0.5° | Uncommon | Prapor |
| Huntsman 700 | Bolt-action | Hunting / police sniper rifle | 7.62x51 | 45 rpm bolt | 5 | 38 | 2.2° / 0.45° | Ultra Rare | Peacekeeper, Jaeger |
| Leviathan .338 | Bolt-action | Magnum chassis sniper rifle | .338 Lapua | 40 rpm bolt | 5 | 30 | 3.0° / 0.6° | Legendary | Loot (Jaeger barter once he unlocks) |
| Grizzly 74 | LMG | Kalashnikov squad automatic | 5.45x39 | 600 rpm auto | 45 | 36 | 0.46° / 0.32° | Rare | Prapor |
| Bulwark 249 | LMG | Belt-fed squad automatic | 5.56x45 | 750 rpm auto | 100 (box) | 28 | 0.42° / 0.34° | Epic | Loot |
| Anvil PK | LMG | General-purpose machine gun | 7.62x54R | 650 rpm auto | 100 (box) | 22 | 0.7° / 0.45° | Epic | Loot |

**Ammo** *(tune: every round in `data/items/ammo/<caliber>.json`; the rules in `data/config/combat.tres`, "Rounds and armor")*. Every gun takes every round of its caliber, and every caliber has at least 4 (50 rounds; 6 tracers). In each caliber the cheapest round is Common and the best armor-piercing one Epic or Legendary. **Soft rounds** (hollow and soft points) hit the unarmored hardest, fragment and bleed; **AP rounds** get through armor but do less flesh damage and rarely fragment; ball rounds sit between. So the round you load is a choice about who you expect to fight.

| Caliber | Round | Rarity | Damage | Pen | Armor dmg | Frag | Velocity | Recoil | Accuracy | Ricochet | Bleed L / H | Where (trader LL, Workbench level) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 9x18 | PM P | C | 46 | 5 | 20% | 25% | 300 m/s | — | −5% | 15% | 35% / 12% | Prapor 1 |
| 9x18 | PM PSt | C | 50 | 12 | 28% | 15% | 302 m/s | — | — | 25% | 30% / 10% | Prapor 1, Skier 1 |
| 9x18 | PM HP | U | 66 | 3 | 15% | 55% | 310 m/s | — | −5% | 5% | 55% / 30% | Prapor 2 |
| 9x18 | PM PBM | E | 40 | 28 | 55% | 5% | 519 m/s | +10% | +5% | 40% | 20% / 5% | Prapor 4 |
| 9x19 | FMJ | C | 54 | 18 | 30% | 20% | 380 m/s | — | — | 25% | 35% / 12% | Peacekeeper 1 |
| 9x19 | HP | U | 70 | 6 | 15% | 55% | 370 m/s | — | −5% | 5% | 55% / 30% | Skier 1 |
| 9x19 | Green Tracer | U | 58 | 14 | 33% | 15% | 365 m/s | — | −5% | 25% | 35% / 12% | Peacekeeper 2 |
| 9x19 | AP | R | 49 | 30 | 55% | 5% | 392 m/s | +5% | — | 40% | 20% / 6% | Peacekeeper 3 |
| 9x19 | PBP | E | 52 | 39 | 65% | 3% | 560 m/s | +15% | +5% | 45% | 20% / 5% | Skier 4, Workbench 2 |
| .45 ACP | FMJ | C | 66 | 19 | 35% | 15% | 260 m/s | — | — | 20% | 40% / 15% | Peacekeeper 1 |
| .45 ACP | HP | U | 82 | 8 | 20% | 50% | 300 m/s | +5% | −5% | 5% | 60% / 35% | Skier 1 |
| .45 ACP | Match | R | 70 | 25 | 40% | 10% | 255 m/s | — | +20% | 25% | 40% / 15% | Peacekeeper 3 |
| .45 ACP | AP | E | 64 | 38 | 60% | 3% | 300 m/s | +10% | — | 45% | 25% / 8% | Peacekeeper 4 |
| 12ga | 7mm buckshot | C | 37 × 8 | 3 | 20% | 0% | 415 m/s | — | — | 30% | 15% / 4% | Skier 1, Jaeger 1 |
| 12ga | magnum buckshot | U | 50 × 8 | 2 | 22% | 0% | 400 m/s | +15% | −5% | 30% | 20% / 6% | Skier 2, Jaeger 1 |
| 12ga | slug | U | 167 | 15 | 45% | 15% | 410 m/s | +10% | +15% | 10% | 55% / 35% | Skier 2, Jaeger 1 |
| 12ga | flechette | R | 25 × 8 | 31 | 33% | 0% | 450 m/s | −5% | +10% | 35% | 30% / 10% | Skier 3 |
| 12ga | AP-20 slug | E | 164 | 37 | 65% | 5% | 510 m/s | +15% | +10% | 35% | 45% / 25% | Skier 4, Workbench 2 |
| 5.45x39 | PS | C | 50 | 28 | 40% | 20% | 890 m/s | — | — | 25% | 35% / 12% | Prapor 1 |
| 5.45x39 | HP | U | 62 | 9 | 15% | 55% | 884 m/s | — | −5% | 5% | 55% / 30% | Prapor 2 |
| 5.45x39 | BT (red tracer) | R | 48 | 37 | 50% | 12% | 880 m/s | — | — | 35% | 30% / 10% | Prapor 3 |
| 5.45x39 | BS | E | 40 | 45 | 80% | 3% | 830 m/s | +5% | — | 45% | 20% / 6% | Prapor 3, Workbench 1 |
| 5.45x39 | PPBS "Needle" | L | 37 | 62 | 90% | 2% | 905 m/s | +5% | +5% | 50% | 15% / 5% | Workbench 3 |
| 5.56x45 | FMJ | C | 54 | 23 | 33% | 35% | 957 m/s | — | — | 25% | 40% / 15% | Peacekeeper 1 |
| 5.56x45 | HP | U | 68 | 9 | 16% | 60% | 936 m/s | — | −5% | 5% | 60% / 30% | Peacekeeper 2 |
| 5.56x45 | M856 tracer | U | 54 | 20 | 35% | 30% | 874 m/s | — | −5% | 25% | 35% / 12% | Peacekeeper 2 |
| 5.56x45 | EPR | R | 49 | 44 | 52% | 15% | 945 m/s | +5% | +5% | 35% | 30% / 10% | Peacekeeper 3 |
| 5.56x45 | AP | E | 42 | 53 | 58% | 4% | 1013 m/s | +10% | — | 45% | 20% / 6% | Peacekeeper 4 |
| 5.56x45 | SSA AP | L | 38 | 57 | 60% | 2% | 990 m/s | +5% | +10% | 50% | 15% / 5% | Workbench 3 |
| 7.62x39 | PS | C | 57 | 35 | 52% | 15% | 718 m/s | — | — | 30% | 35% / 15% | Prapor 1 |
| 7.62x39 | HP | U | 80 | 15 | 20% | 50% | 754 m/s | — | −5% | 5% | 60% / 35% | Prapor 2 |
| 7.62x39 | US (subsonic) | U | 56 | 29 | 35% | 12% | 301 m/s | −15% | −10% | 25% | 30% / 10% | Prapor 2 |
| 7.62x39 | T-45M tracer | U | 64 | 30 | 49% | 15% | 720 m/s | — | −5% | 30% | 35% / 15% | Prapor 2 |
| 7.62x39 | BP | E | 58 | 47 | 63% | 4% | 730 m/s | +5% | — | 45% | 25% / 8% | Prapor 3, Workbench 2 |
| 7.62x39 | MAI AP | L | 53 | 58 | 70% | 3% | 730 m/s | +5% | +5% | 50% | 20% / 6% | Workbench 3 |
| 7.62x51 | FMJ | C | 80 | 29 | 45% | 20% | 833 m/s | — | — | 30% | 40% / 18% | Peacekeeper 1 |
| 7.62x51 | SP | U | 102 | 18 | 30% | 45% | 822 m/s | — | — | 5% | 60% / 40% | Peacekeeper 2, Jaeger 1 |
| 7.62x51 | M80 | R | 80 | 41 | 66% | 15% | 833 m/s | — | +5% | 35% | 35% / 15% | Peacekeeper 3 |
| 7.62x51 | M62 tracer | R | 79 | 44 | 75% | 12% | 838 m/s | — | −5% | 35% | 35% / 15% | Peacekeeper 3 |
| 7.62x51 | M61 | E | 70 | 64 | 83% | 4% | 849 m/s | +5% | — | 45% | 25% / 10% | Peacekeeper 4 |
| 7.62x51 | M993 | L | 67 | 70 | 85% | 3% | 910 m/s | +5% | +10% | 50% | 20% / 8% | Workbench 3 |
| 7.62x54R | LPS | C | 81 | 41 | 66% | 15% | 865 m/s | — | — | 35% | 35% / 15% | Prapor 1 |
| 7.62x54R | SP | U | 92 | 27 | 32% | 45% | 830 m/s | — | — | 5% | 60% / 40% | Prapor 2, Jaeger 1 |
| 7.62x54R | T-46M tracer | U | 82 | 39 | 83% | 15% | 800 m/s | — | −5% | 35% | 35% / 15% | Prapor 2 |
| 7.62x54R | SNB | E | 75 | 62 | 88% | 4% | 875 m/s | +5% | +10% | 45% | 25% / 10% | Prapor 4 |
| 7.62x54R | BS | L | 72 | 70 | 88% | 3% | 785 m/s | +10% | +5% | 50% | 20% / 8% | Workbench 3 |
| .338 Lapua | FMJ | C | 122 | 47 | 83% | 15% | 890 m/s | — | — | 35% | 50% / 30% | Jaeger 1 |
| .338 Lapua | UCW | U | 142 | 32 | 70% | 30% | 849 m/s | — | — | 15% | 60% / 40% | Jaeger 2 |
| .338 Lapua | TAC-X | R | 196 | 18 | 55% | 50% | 880 m/s | — | +5% | 5% | 70% / 50% | Jaeger 3 |
| .338 Lapua | AP | L | 115 | 79 | 89% | 3% | 849 m/s | +10% | +5% | 50% | 35% / 15% | Workbench 3 |

Where: the trader and the loyalty level you need with them (Section 10), and the Workbench level that crafts it (Section 9). Legendary rounds aren't sold: they're found in raid or made at the Workbench.

| Round stat | What it does |
|---|---|
| Damage | Taken off the body part hit (Section 13.5) by a round that reaches flesh; per pellet for shot shells. Rounds keep full damage to 40% of their range, then lose it in a straight line to 75% at the end of it |
| Penetration | Against armor: a piece of armor of class N resists penetration 10 × N when new, down to half that as it wears (nothing at 0 durability). The chance to get through is 50% when penetration equals the resistance, +5% per point above and −5% per point below (always at +10, never at −10). Also decides wood: 30+ goes through (Section 13.4) |
| Armor damage | How hard the round wears armor: each hit takes penetration × armor damage % × the armor's destructibility off its durability (half that for a ricochet) |
| Fragmentation | Chance that a round that reaches flesh fragments: +40% damage, a sure light bleed and double its heavy-bleed chance. High on soft rounds, low on AP |
| Velocity | m/s out of a standard barrel; each gun's barrel scales it (the gun's muzzle velocity over its caliber's everyday round's) and parts change it. Range is 150 m at 800 m/s and faster, less for slower rounds (at least 35%: pistols reach about 55–70 m, subsonic 7.62x39 about 55 m), and slower rounds keep less energy through wood |
| Recoil | % more (or less) kick per shot and camera shake: hot loads +5–15%, subsonic −15% |
| Accuracy | % tighter (or looser) base spread: match rounds +20%, subsonic −10%, tracers −5% |
| Ricochet | Chance, × the armor's own ricochet factor (helmets 0.4–0.6, plates 0–0.1), that a round armor stops glances off for no damage instead of pushing blunt damage through |
| Bleed L / H | Chance per hit that reaches flesh of a light / heavy bleed (heavy first, replacing a light one). Stopped rounds don't bleed |
| Pellets, pellet spread | Shot shells: 8 pellets, each its own round, spread around the aim (chokes tighten it) |
| Noise | Subsonic rounds are heard 60% as far |
| Tracer | Red or green: a thick, bright streak that lasts 0.25 s, and anyone the round passes within 6 m of (instead of 2 m) learns where you are |

| Armor rule | Detail |
|---|---|
| Armor | Helmets, face shields, body armor and armored rigs (an armor `class`, 1–6) stop rounds on the body parts they cover (`zones`): helmets the head, face shields the face, most vests the thorax and stomach, plate carriers only the thorax, the heaviest suits the arms too. Legs are never covered. All the gear is listed in Section 12.2 |
| Face | A head hit from within 60° of where the target faces is a face hit: only a face shield covers it (helmets don't). From the side or behind, the helmet takes it. A face shield is checked before its helmet |
| Armored rigs | An armored rig is armor and pouches in one: it can't be worn with body armor (neither goes on over the other) |
| Stopped | A round that doesn't get through either glances off (ricochet) or pushes blunt damage through: damage × the armor's blunt share × penetration / resistance (at least 30% of that), so a pistol round on a rifle plate barely hurts. No bleed, no fragmentation |
| Through | A round that gets through keeps 85% of its damage, then may fragment and bleed as above |
| Wear | Armor keeps its durability per item, saved with your gear and on bodies: looted armor can be half shot through. Upgrades raise its max durability and lower its blunt share (Section 12.2) |
| Feedback | A round armor stops gets a smaller steel-blue hit marker with a square and a steel-blue damage number ("RICOCHET" if it glanced off); fragmenting hits an orange-red number; sparks instead of blood on the armor |

Every piece of armor, with its class, zones, durability and blunt share, is in Section 12.2.

| Rule | Detail |
|---|---|
| Ammo charts | Examining a gun or a round shows every round of its caliber side by side: damage, penetration, armor damage and six squares for armor classes 1–6, each filled to the round's chance to get through new armor of that class and coloured by it (green → red; a colorblind-safe scale in the colorblind modes); hover for the numbers. The round loaded (or examined) is marked ▶; tracers have a coloured dot. The trader screen's **AMMO** tab shows the same for the gun in hand (or any caliber you pick), with velocity out of that gun, fragmentation, bleeds, recoil, accuracy and where to get each round |
| Loading | Drag rounds onto a gun (in a grid or an equipment slot, in raid or out) to load them. Rounds of another type come out first, into the grid the new ones came from (else your pockets, rig or backpack; any with nowhere to go stay in, under the new ones), then the new ones fill the magazine. The gun reloads with that type from then on, and fires whatever is on top of its magazine |
| Running out | Reloading with none of the gun's round type left switches to another round of the same caliber you carry ("Loading 12ga slug") |
| Everyday round | Found guns come loaded with their caliber's everyday round (the commonest, then least penetrating: `ItemDB.ammo_of()`). Debug F3 in the test level cycles the gun's caliber |
| Traders | Ammo offers need a loyalty level with the trader (`"ll"` in `offers.json`): everyday rounds at LL1, soft rounds, tracers and subsonic at LL2, armor-piercing rounds at LL3–4. Legendary AP rounds aren't sold |
| Workbench | Level 1 crafts 5.45 BS, level 2 9x19 PBP, 12ga AP-20 and 7.62x39 BP, level 3 the six Legendary AP rounds (PPBS, SSA AP, MAI AP, M993, 7.62x54R BS, .338 AP) from found-in-raid parts and valuables (Section 9) |

**Weapon parts** *(tune: `data/items/attachments/*.json`)*: what each kind does and how rarity scales it is in Section 12.1. Every gun comes with **standard** parts (Common, no effects), and each platform has upgrades from Common to Legendary. Parts shared between guns: AK-74 grips, handguards and dust covers also fit the Tundra 47, Grizzly 74 and Tempest S12 (stocks the Tundra and Grizzly, 5.45 muzzle devices and magazines the Grizzly); AR grips and stocks fit the Sentinel and the Longbow (grips the Wasp too); STANAG magazines and 5.56 muzzle devices fit the Sentinel, Halcyon and Bulwark; 7.62x54R muzzle devices the Mosin, SVD and Anvil; the 9x18 suppressor the PM and Strelka. Foregrips, tactical devices and sights go in any slot of their kind.

| Fits | Parts (rarity; * = standard, what the gun comes with) |
|---|---|
| Vektor P9 | P9 17-round magazine (C*); P9 33-round stick magazine (U); P9 50-round drum (R) |
| Bastion 45 | Bastion wooden grip panels (C*); Bastion rubber grip (U); Bastion custom grip (E); Bastion 8-round magazine (C*); Bastion 10-round magazine (U) |
| Strelka MP | Strelka 20-round magazine (C*); Strelka holster stock (U); Strelka wire stock (R) |
| Vektor P9, Hornet SMG, Wasp PDW | 9mm compensator (U); 9mm suppressor (R) |
| Bastion 45, Brigand 45 | .45 compensator (R); .45 suppressor (E) |
| Hornet SMG | Hornet polymer handguard (C*); Hornet tri-rail handguard (R); Hornet fixed stock (C*); Hornet collapsible stock (U); Hornet 30-round magazine (C*); Hornet 50-round drum (E) |
| Wasp PDW | Wasp 4.5in M-LOK handguard (C*); Wasp 8in M-LOK handguard (U); Wasp folding stock (C*); Wasp telescoping stock (R); Wasp 30-round magazine (C*); Wasp 20-round magazine (U); Wasp 41-round magazine (R) |
| Brigand 45 | Brigand folding stock (C*); Brigand fixed stock (U); Brigand 25-round magazine (C*); Brigand 35-round magazine (R) |
| Warden 870, Tempest S12 | 12ga modified choke (C); 12ga full choke (U); 12ga muzzle brake (R); 12ga suppressor (E) |
| Warden 870 | Warden 20in barrel (C*); Warden 14in breacher barrel (U); Warden 26in vent-rib barrel (R); Warden wooden forend (C*); Warden rail forend (U); Warden wooden stock (C*); Warden pistol-grip stock (U); Warden tactical stock (R) |
| Tempest S12 | Tempest polymer handguard (C*); Tempest folding stock (C*); Tempest adjustable stock (R); Tempest 5-round magazine (C*); Tempest 12-round magazine (U); Tempest 20-round drum (E) |
| Sentinel AR, Halcyon B5, Bulwark 249 | 5.56 A2 flash hider (C*); 5.56 compensator (U); 5.56 muzzle brake (R); 5.56 suppressor (E); 5.56 rapid-detach suppressor (L); 5.56 STANAG 30-round magazine (C*); 5.56 STANAG 20-round magazine (U); 5.56 STANAG 40-round magazine (R); 5.56 60-round quad-stack magazine (UR) |
| Sentinel AR | AR 14.5in barrel (C*); AR 10.5in barrel (U); AR 18in match barrel (UR); AR polymer handguard (C*); AR 9in M-LOK handguard (U); AR 13in free-float handguard (R); AR flat-top upper receiver (C*); AR billet upper receiver (E) |
| Sentinel AR, Longbow DMR, Wasp PDW | AR A2 pistol grip (C*); AR ergonomic grip (U); AR competition grip (UR) |
| Sentinel AR, Longbow DMR | AR buffer-tube stock (C*); AR lightweight stock (R); AR precision stock (UR); AR competition stock (L) |
| Halcyon B5 | B5 20in barrel (C*); B5 16in barrel (U) |
| Bulwark 249 | Bulwark 465mm barrel (C*); Bulwark para barrel (U); Bulwark polymer handguard (C*); Bulwark rail handguard (R); Bulwark fixed stock (C*); Bulwark collapsible stock (U); Bulwark 100-round box (C*); Bulwark 200-round box (E) |
| Tundra 47 | AKM slant brake (C*); AKM 415mm barrel (C*); AKM short barrel (U); AKM wooden stock (C*); AKM 30-round magazine (C*); AKM 40-round magazine (U); AKM 75-round drum (UR) |
| Tundra 47, Partisan | 7.62x39 compensator (U); 7.62x39 muzzle brake (R); 7.62x39 suppressor (E); 7.62x39 competition brake (L) |
| AK-74N, Tundra 47, Grizzly 74 | AK modern stock (R) |
| Partisan | Partisan wooden stock (C*); Partisan tactical stock (R) |
| Longbow DMR | AR-10 flash hider (C*); AR-10 16in barrel (C*); AR-10 20in match barrel (E); Longbow 15in rail handguard (C*); AR-10 20-round magazine (C*); AR-10 10-round magazine (U) |
| Longbow DMR, Huntsman 700 | 7.62 NATO muzzle brake (R); 7.62 NATO suppressor (E) |
| Huntsman 700 | Huntsman 24in barrel (C*); Huntsman 26in heavy barrel (UR); Huntsman hunting stock (C*); Huntsman aluminium chassis (E); Huntsman 5-round magazine (C*); Huntsman 10-round magazine (R) |
| Leviathan .338 | Leviathan muzzle brake (C*); Leviathan 27in barrel (C*); Leviathan 27in match barrel (L); Leviathan folding chassis (C*); Leviathan 5-round magazine (C*); Leviathan 10-round magazine (UR) |
| Mosin, SVD, Anvil PK | 7.62x54R muzzle brake (U); 7.62x54R suppressor (E) |
| SVD | SVD 20-round magazine (R) |
| Anvil PK | Anvil flash hider (C*); Anvil 658mm barrel (C*); Anvil 550mm barrel (U); Anvil skeleton stock (C*); Anvil 100-round box (C*); Anvil 200-round box (E) |
| Grizzly 74 | Grizzly 590mm barrel (C*); Grizzly wooden handguard (C*); Grizzly club-foot stock (C*); Grizzly 45-round magazine (C*); Grizzly 95-round drum (UR) |
| Any slot of its kind (rails, sight mounts) | Stubby foregrip (C); Handstop (U); Bipod grip (R); Carbon fibre foregrip (E); Pistol light (C); Infrared laser (R); Mini reflex sight (U); Prism sight (R); 3x combat scope (UR); 1-6x LPVO (L); 5-25x precision scope (L) |

The 40 parts from before (AK-74N, PM, SVD and the rail parts) are listed in Section 12.1.

## 7. Grid Inventory

| Rule | Detail |
|---|---|
| Opening | **Tab** in a raid; the game keeps running (you can walk, but not shoot or aim). Out of raid: CHARACTER → INVENTORY (or Tab), with the stash beside you. Tab or Esc closes it (Esc closes the examine panel and open windows first) |
| Layout | Equipment slots on the left; pockets and the grids of the equipped rig, backpack and secure container in the middle; the stash on the right (out of raid only). Header: carried weight, what it does to you, carried value |
| Grid | Items take W×H cells (bandage 1×1, AK 5×2, armor 3×3) and can't overlap |
| Moving | Drag and drop with the mouse. While dragging, the cells under the item light **green** (fits), **amber** (stacks onto / goes inside the item underneath) or **red** (doesn't fit). Nothing moves until you drop somewhere valid; dropping anywhere else cancels |
| Rotation | `R` while dragging turns the item 90° |
| Stacking | Drop a stack on the same item to merge, up to its max stack (only stacks with the same found-in-raid status merge, Section 2.1); the rest stays where it was. **Shift-drag** splits off half; the mouse wheel changes how many while dragging |
| Containers | Rigs, backpacks and cases have their own grid (`"grid": [w, h]` stat). Drop an item on one to put it inside; double-click one to open it in its own window (e.g. a backpack in the stash). A container only goes inside another when empty, and never inside itself. The secure container takes no rigs, backpacks or containers |
| Slots | Primary weapon, Secondary weapon, Pistol, Melee, Helmet, Body armor, Tactical rig, Backpack, Secure container, plus Pockets (4 × 1×1). Pistols (`"class": "pistol"`) go only in the Pistol slot, other guns in Primary / Secondary. The gun in hand is the primary, else the secondary, else the pistol. An armored rig and body armor don't go together. Face shields and headsets go on the helmet (Section 12.2) |
| Rarity | Every item's background and border are its rarity colour, with the rarity letter in the corner so colour is never the only cue (colorblind palette aware) |
| Examine | Right-click: icon, name in its rarity colour, rarity, category, size, weight, value, stack, and what matters for its kind (a gun's type, caliber and how many round types it takes, handling with its parts, durability and jam chance, loaded rounds; a weapon part's kind, the guns it fits and what it changes; ammo damage (per pellet), penetration, armor damage, velocity, fragmentation, bleeds, recoil, accuracy, ricochet, tracer and the guns it fits, with an ammo chart of its caliber beside the stats (a gun shows its caliber's too, Section 6.4); armor class, what it covers and its durability and durability, what meds treat, a container's grid and contents, sight, Found in Raid). Out of raid a gun's panel has **MODIFY** (Section 12.1). *Planned:* unknown items must be examined first to reveal their name and value |
| Weapon parts | Out of raid, dropping a part on a gun (in a grid or an equipment slot) fits it to a free slot it fits (the gun lights amber). A gun's weight and value include its parts. Hover a gun for its durability, a part for what it does |
| Weight | Everything you carry counts, containers with their contents. Up to **25 kg** no effect. 25–40 kg **heavy**: speed falls to 80% and sprinting costs up to 1.5× stamina. **40 kg+ overweight**: no sprinting or combat roll, speed falls to 55% at 65 kg. Shown in the inventory header and the HUD. Values in `data/config/inventory.tres` *(tune)* |
| Ammo | Spare rounds are counted from the pockets, rig and backpack (not the secure container); a reload takes the rounds it used out of them. Guns remember the rounds loaded |
| Search | In a raid, **F** near a container or body opens it beside your inventory and searches it: everything inside starts hidden (a dark cell with "?") and turns up **one item at a time**, top row first, while it's open. Each item takes 0.35 s + 0.25 s per cell it covers *(tune, `raid.tres`)*, × the container's search time, so small items turn up faster. The item being searched shows a filling ring; the title counts ("SEARCHING 2 / 5", then "SEARCHED"). Hidden items can't be moved, examined or stacked onto. Closing (or walking away) pauses; what's found stays found. A body's equipment is in plain sight (take its gun, armor, rig straight off its slots); its pockets, rig and backpack are searched. Anything you carry is known, even an unsearched bag you took. F on a loose item picks it up |

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
| Nutrition Unit | 3 | Crafts food/drink; faster energy/hydration refill | 1× Hose, 1× Kettle |
| Rest Space | 3 | Faster energy/hydration refill between raids | 2× Light bulb, 1× Rechargeable battery |
| Workbench | 3 | Crafts ammo/attachments; unlocks repair | 5× Bolts, 3× Screws |
| Water Collector | 3 | Produces water | 3× Hose, 1× Pump |
| Lavatory | 3 | Crafts barter/junk components | 2× Duct tape, 1× Toilet paper |
| Shooting Range | 3 | Test weapons, recoil tuning | 3× Bolts, 1× Weapon parts |
| Gym | 3 | Trains strength/endurance | 2× Dumbbell |
| Intelligence Center | 3 | Faster quests, cheaper insurance | 1× Flash drive, 2× Intel folder |
| Bitcoin Farm | 3 | Passive Bitcoin (needs GPUs) | 1× GPU, Generator lvl 2 |
| Security | 3 | Raid prep buffs (scouting info) | 3× Nails |

Upgrades require items (often FIR), roubles, trader LL, other station levels, and real-time build duration.

**Built so far** (`data/hideout/stations.json`, HIDEOUT screen): Generator, Medstation, Workbench, Lavatory, Nutrition Unit and Rest Space. Each starts unbuilt; level 1 costs roubles and ordinary items, level 2+ asks for found-in-raid items (and sometimes another station's level). Levels unlock crafts (inputs → one item, into the stash, **found in raid**). The Workbench also upgrades gear (GEAR UPGRADES: up to +2 at level 1, +4 at level 2, +5 at level 3, for less money than Ragman; Section 12.2). It hand-loads ammo: 5.45 BS at level 1, 9x19 PBP, 12ga AP-20 and 7.62x39 BP at level 2, and at level 3 (generator level 2, found-in-raid weapon parts, an electric motor and wires) the six Legendary AP rounds traders never sell (Section 6.4). The Medstation makes meds from supplies: an AI-2 and army bandages at level 1; the CALOK-B, a Salewa and morphine at level 2; and at level 3 (generator level 2, found-in-raid medical tools, toothpaste, soap and light bulbs) the AFAK, propital, the Surv12 and the Legendary Grizzly, eTG-c and Obdolbos, which traders never sell. The Workbench also makes circuit boards, rechargeable batteries, 5.45 BT rounds (gunpowder) and military cable; the Lavatory soap, hoses and cigarettes; the **Nutrition Unit** (level 1: hose, kettle, lighter) makes food and drink from junk (water + sugar + coffee = two energy drinks; field rations, tea, water rations, Aquamari, MREs), at level 2 kvass, buckwheat, Hot Rod, vodka and moonshine, and at level 3 Survivor's emergency kits, isotonic drinks and chocolate (Section 13.7). The Nutrition Unit (+50% a level) and the **Rest Space** (three levels of bunks, heater and TV; +75% a level) make energy and hydration refill faster between raids. A craft that makes several items that don't stack gives that many items. Generator level 3 now also wants a car battery and fuel conditioner. Upgrades and crafts are instant for now; build and craft timers, trader LL requirements and the other stations are planned.

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

**Built so far** (`data/traders/offers.json`, TRADERS screen tabs): **BUY** (roubles or dollars; counts toward money spent for loyalty), **BARTER** (items for an item; some ask for found-in-raid items) and **TASKS** (Section 11). What you get goes to the stash and is never found in raid. Prapor also sells the Mosin, the SVD, the Tundra 47, Partisan, Strelka MP and Grizzly 74 and Eastern rounds; Peacekeeper sells Western guns (Vektor P9, Bastion 45, Hornet SMG, Wasp PDW, Sentinel AR, Huntsman 700), rounds and AR parts for dollars and barters the Sentinel and Hornet; Skier sells the Brigand 45, Tempest S12 and Warden 870, 9x19 and .45 hollow points, buckshot, slugs and small parts and barters the 9mm suppressor; Therapist sells meds and food by loyalty level (bandages, the AI-2, car medkit and basic food at LL1; the CAT, ibuprofen, Salewa, morphine and adrenaline at LL2; the CALOK-B, aluminium splint, IFAK, CMS, Aquamari and MREs at LL3) and barters medkits and stims for barter goods and valuables (toothpaste and soap for a car medkit, a Roler for an AFAK, up to a rare coin collection for the Grizzly at LL4; Section 13.7); Prapor, Skier, Mechanic, Jaeger, Ragman and Peacekeeper barter for cigarettes, gunpowder, drives, watches, coins and the rest; Ragman sells the gear in Section 12.2 by loyalty level (LL1 Common/Uncommon … LL4 Epic) and the cloth upgrade materials, and upgrades gear in his **UPGRADES** tab (up to +2 at LL1 … +5 at LL4); Jaeger's stock is ready for when he unlocks (Warden 870, Huntsman 700, shells, chokes, hunting rounds, the Leviathan .338 for a LEDX); Mechanic also sells magazines, a choke and parts for the new guns and barters the free-float AR handguard and the bipod grip (Section 6.4). Mechanic sells AK and PM parts (and the SVD magazine) (compensator, short barrel, rail handguard, grips, stocks, railed dust cover, magazines, laser) and barters the match barrel and the AK suppressor; Skier sells rail parts and the quad rail and barters the PM suppressor. Guns are repaired in the modding screen for roubles (Section 12.1). **Loyalty levels** go up on their own as soon as you meet the next level's player level, reputation (from quests) and roubles spent with that trader (table below). Offers can need a loyalty level (`"ll"` in `offers.json`; BUY shows "LL3" and the button says "Needs loyalty level 3"): ammo is gated so cheap rounds are LL1 and AP rounds LL3–4 (Section 6.4). The **AMMO** tab compares every round of the gun in hand (or any caliber). Selling, trader repair, insurance and restocks are planned.

### Loyalty Levels (LL)

| LL | Player level | Reputation | Spent with trader | Unlocks |
|---|---|---|---|---|
| 1 | 1 | 0.00 | 0 | Basic stock |
| 2 | 15 | 0.20 | 750k ₽ | Mid-tier gear, more barters; soft rounds, tracers, subsonic |
| 3 | 25 | 0.35 | 1.5M ₽ | High-tier gear, better buy prices; armor-piercing rounds |
| 4 | 35 | 0.50 | 2.5M ₽ | Top-tier gear, best prices; the best AP rounds traders sell |

Stock restocks every 1 h *(tune)*; some items have per-restock limits.

## 11. Quests

| Type | Where | Example objectives | Rewards |
|---|---|---|---|
| In-raid | During raid | Kill X Scavs on map; mark a location; place item; survive & extract from Y | XP, ₽, rep, items |
| Out-of-raid | Hideout | Hand over FIR items; build station; reach skill level; craft item | XP, ₽, rep, unlocks |
| Faction | Either | BEAR/USEC exclusive chains | Faction gear |
| Daily/Weekly | Either | Rotating random objectives | XP, ₽, rep |

Quest structure: prerequisites (level, LL, prior quest) → objectives (tracked, may require FIR) → turn-in → rewards. Some rewards unlock trader items or barters.

**Built so far** (`data/quests/quests.json`, the trader's TASKS tab): hand-in quests. Accept, then HAND OVER per objective (part now, the rest later) from the stash and your character, including inside containers; FIR objectives only take items with the checkmark. TURN IN when everything is handed over: roubles, experience, reputation with the trader, and reward items in the stash (never FIR). Prior-quest prerequisites work. Five quests: Scrap Run (Prapor), Shortage and Sanitary Standards (Therapist), Textile (Ragman), Gunsmith Part 0 (Mechanic).

**Kill objectives** (`data/quests/trick_shots.json`): `{"type": "trick_kill", "count", "target": "pmc" / "scav", "weapon_class": "bolt_action" / "dmr"}` counts 360 trick-shot kills (Section 13.4) matching the filters, added up at the end of each raid while the quest is active, whether you survive or not; the TASKS tab shows them with a gold "360" and the count so far. Rewards can include Drip.

| Quest | Trader | Needs | Objective | Rewards |
|---|---|---|---|---|
| Showboat | Prapor | — | 1 trick-shot kill | 40,000 ₽, 3,000 XP, 25 Drip, 40× 7.62x54R LPS |
| Around the World | Mechanic | Showboat | 3 trick-shot kills with a bolt-action rifle | 90,000 ₽, 6,000 XP, 50 Drip, 2-4x scope |
| Spin Doctor | Skier | Showboat | 2 trick-shot kills on PMCs | 120,000 ₽, 8,000 XP, 100 Drip, 6-8x scope |

## 12. Weapon & Gear Upgrades

### 12.1 Weapon Modding

| System | Detail |
|---|---|
| Slot tree | Each gun's `WeaponData` lists its slots. AK-74N: muzzle, barrel, handguard, pistol grip, stock, dust cover (receiver), side mount (sight), magazine. PM: muzzle, grip, magazine. Mosin: muzzle, scope mount. SVD: muzzle, side mount, magazine. The other guns (Section 6.4) have their own: the Sentinel AR's sight goes on its upper receiver's top rail, the Warden 870 has a fixed six-shell tube (no magazine slot) and can't fire without its forend, belt-fed machine guns take ammo boxes in their feed slot. Parts can bring slots of their own: a rail handguard adds a foregrip and a tactical slot (the quad rail a top rail for a sight too), a railed dust cover a top rail. A part taken off keeps whatever is on it. Guns come with their default parts (`default_mods`) |
| Part kinds | Muzzle device, barrel, handguard, foregrip, stock, pistol grip, receiver, sight, tactical device, magazine |
| Compatibility | A slot lists the kinds it takes; a part lists the platforms it fits (`"fits": ["ak"]`). Rail parts (foregrips, tactical devices, sights) leave `fits` out and go in any slot of their kind |
| Handling stats | Every part can change the ten handling stats: **vertical recoil %**, **horizontal recoil %**, **recoil recovery %**, **base spread %**, **bloom per shot %**, **max bloom %**, **bloom recovery %**, **hip-fire spread %**, **ergonomics** (points) and **weight** (% of the part's own weight). What a part does starts from its kind's **profile** (the table below, `data/config/attachment_profiles.json`); a part's own `"handling"` replaces single entries (a skeleton stock trades recoil for ergonomics). The stock parts a gun comes with are "standard": no effects, so a stock gun handles exactly as its `.tres` says |
| Rarity | A positive profile value is a bonus: that many times the part's rarity strength, **Common 4%, Uncommon 8%, Rare 12%, Ultra Rare 16%, Epic 20%, Legendary 23%** (so most Common bonuses land around 3–5% and Legendary ones around 20–25%; ergonomics: 0.25 points per percent). A negative value is a fixed downside that doesn't grow with rarity (a suppressor's −8 ergonomics). Rarer parts are also lighter. *(tune: `handling.tres`)* |
| Other effects | A part's own `"modifiers"`: muzzle velocity, aim speed, noise, jam chance, wear, pellet spread (chokes and shotgun barrels), fixed per part with bonuses × 1 / 1.15 / 1.3 / 1.5 / 1.75 / 2 by rarity (an Epic suppressor's −40% noise is −70%). Magazines set the capacity; sights the optic |
| Ergonomics | 0–100, handling: each point below the gun's default is 1% more spread while moving, sprinting and rolling, 1% more sway and 1% slower to raise a sight (each point above, 1% better) |
| Weight | Every kg the build weighs over the gun with its default parts adds 0.35° of sway and makes bloom recover 15% slower (lighter builds the reverse), so stacking every part isn't always best *(tune)* |
| Skills | The gun's weapon skill (its class's: Assault rifles for the AK, Pistols for the PM, Section 6.4) takes 0.5% off vertical and horizontal recoil per level, Strength 0.25% per level, up to 15% together (Section 12.3) |
| Wear | Below 70 durability a gun spreads more, up to +1.5° at 0 *(tune)* |
| Empty slots | Some slots change the gun while empty: an AK without a stock climbs 45% more, kicks 30% more sideways, recovers 30% slower and blooms 25% wider (but handles +8 ergonomics); without a pistol grip −15 ergonomics, +10% side kick, +15% hip-fire spread; without a muzzle device +8% climb; without a handguard −10 ergonomics, +10% hip-fire spread. Without a barrel, dust cover or magazine it can't fire (HUD: "NO BARREL") |
| Modding screen | Out of raid, right-click a gun → **MODIFY**. Slot tree on the left (nested slots indented under their part), the gun's stats in the middle, every part you own that fits it on the right (stash, pockets, rig, backpack, inside containers; click a slot to list only its parts). Drag a part onto a slot to fit it (green: fits, red: doesn't); what was in the slot goes to the stash. Drag a part off onto the list, or double-click it, to take it off. Double-click a listed part to fit it to its best slot. Hovering a part, or dragging one over a slot, previews it: the new values with ▲ / ▼ and the change, green if better and red if worse. A smaller magazine sends the rounds that no longer fit to the stash |
| Recoil pattern | Above the stats: where each shot of a full-auto spray (30 rounds, or a magazine) goes relative to the aim, from the same recoil, recovery and (seeded) side kicks the gun uses in a raid. While previewing, the pattern with the change (amber) is drawn over the current one (grey), with before / after numbers for climb, side kick and recovery |
| Spread circles | Beside it: the cone at aimed (base spread + wear), hip-fire and full bloom, drawn like the bloom reticle; while previewing the new circles over the old, with before / after numbers and how long full bloom takes to settle |
| Stats shown | Ergonomics, vertical recoil, horizontal recoil, recoil recovery, base spread, hip-fire spread, bloom per shot, max bloom, bloom recovery, sway, worn spread, muzzle velocity, aim time, how far a shot is heard, magazine, fire rate, (shotguns: pellet spread,) weight, durability, jam chance per shot. Skills are included |
| Quick fit | Out of raid, dropping a part on a gun in the inventory fits it to a free slot it fits. There's no modding in a raid |
| Durability | Guns have durability out of 100 (and a max). Each shot wears it (AK 0.03, PM 0.04, × the parts' wear). Below **85** a gun can jam: chance per shot = 6% × ((85 − durability) / 85)² × the parts' jam modifier, about 1% at 50 and 4.7% at 10 *(tune, per gun in its `.tres`)*. Found guns come worn: loot 60–95, Scav kits 50–85, AI PMC kits 75–95 |
| Jams | After a shot the next round can fail to feed: the gun won't fire or reload ("JAMMED · R to clear" on the HUD) until **R** clears it, which takes 1.6 s (the reload ring fills) and throws the stuck round out. AI guns in hand don't wear or jam |
| Repair | In the modding screen, **REPAIR** brings it back to its max durability for roubles (0.4% of the gun's base value per point); each repair lowers the max by 15% of the points restored. Trader and workbench repair kits are planned |
| Presets | *Planned:* save/load builds; auto-buy missing parts from traders |
| Weapon mastery | *Planned:* per-weapon XP → faster reloads, lower recoil (3 tiers) |

**Attachment profiles** *(tune: `data/config/attachment_profiles.json`)*: the default direction of each kind. + is a bonus in rarity-strength units (better: less recoil, spread and bloom, faster recovery, more ergonomics, a lighter part), − a fixed downside in % (ergonomics: points), – none.

| Kind | Vertical recoil | Horizontal recoil | Recovery | Base spread | Bloom / shot | Max bloom | Bloom recovery | Hip-fire | Ergonomics | Weight |
|---|---|---|---|---|---|---|---|---|---|---|
| Muzzle device | +1.0 | +0.6 | +0.3 | – | +0.4 | – | – | – | −1 | +0.4 |
| Barrel | – | – | – | +1.0 | +0.3 | +0.3 | – | – | −1 | +0.4 |
| Handguard | – | +0.4 | – | – | – | – | +0.6 | +0.4 | +0.8 | +0.5 |
| Foregrip | +0.5 | +1.0 | +0.4 | – | – | +0.4 | – | +0.4 | +0.4 | +0.5 |
| Stock | +1.0 | +0.7 | +1.0 | – | +0.6 | +0.6 | +0.4 | – | −1 | +0.4 |
| Pistol grip | – | +0.3 | +0.3 | – | – | – | +0.5 | +0.3 | +1.0 | +0.5 |
| Receiver (dust cover) | – | – | – | +0.4 | – | +0.3 | – | – | – | +0.5 |
| Sight | – | – | – | +0.4 | – | – | – | – | −1 | +0.5 |
| Tactical device | – | – | – | – | – | – | +0.3 | +1.2 | −1 | +0.5 |
| Magazine | – | – | – | – | – | – | – | – | – | +0.5 |

**Parts** *(tune; the entries that differ from their kind's profile, AK unless noted)*

| Slot | Parts |
|---|---|
| Muzzle | Muzzle brake (C, standard); compensator (U: climb +1.3, side +0.8; noise +10%); flash hider (U: climb −3%, side +0.3, ergonomics +0.5; noise −10%); suppressor (E, 2×1: climb and side +0.6, bloom +0.3, ergonomics −8; noise −40%, velocity −2%); competition brake (L: climb and side +1.0, recovery +0.6, bloom +0.6; noise +15%) |
| Barrel | 415 mm (C, standard); short (U: base spread −10%, bloom per shot −5%, hip-fire +1.0, ergonomics +1.5; velocity −8%, noise +10%); match (R: base spread +1.3, bloom +0.5, max bloom +0.5; velocity +2%, wear −10%) |
| Handguard | Wooden (C, standard); rail (U: profile; foregrip and tactical slots); quad rail (R: side +0.6, profile otherwise; plus a top rail) |
| Pistol grip | Standard (C, standard); rubberized (C: profile); ergonomic (U: ergonomics +1.3); tactical (R: side +0.6, recovery +0.6, ergonomics +1.0) |
| Stock | Polymer (C, standard); skeleton (U: climb −6%, side −4%, recovery −10%, bloom recovery +1.0, ergonomics +2.0, weight +1.0); adjustable (R: profile, ergonomics +0.4); precision (UR: climb +1.3, side +1.0, recovery +1.2, base spread +0.4, max bloom +0.8, ergonomics −2) |
| Dust cover | Standard (C, standard); railed (U: ergonomics −1; a top rail) |
| Magazine | 30-round (C, standard); 20-round (U: ergonomics +1.0; jams −15%); RPK 45-round (R: ergonomics −4; jams +15%); 60-round quad-stack (UR, 1×3: ergonomics −8; jams +30%) |
| Foregrip (any rail) | Polymer (C: profile); vertical (U: profile); angled (R: climb +0.3, side +0.8, recovery +0.6, hip-fire +0.5, ergonomics +1.0; aim speed +4%) |
| Tactical (any rail) | Laser (U: profile; aim speed +3%); laser-light combo (E: hip-fire +1.4, bloom recovery +0.4; aim speed +4%) |
| Sight (any sight slot) | Red dot (R: base spread +0.3; aim speed +2%); holographic (R: ergonomics −2; aim speed +2%); 2-4x (UR: base spread +0.8, ergonomics −3; aim speed −8%); 6-8x (E: base spread +1.2, ergonomics −5; aim speed −15%). You aim through the strongest sight fitted (Section 13.6) |
| PM | Grip (C, standard) or rubber grip (U: climb and side +0.5, recovery +0.5, ergonomics +1.2); 8-round (C, standard) or 12-round magazine (U: ergonomics −2; jams +10%); suppressor (R: climb +0.6, side +0.5, ergonomics −4; noise −40%, velocity −4%) |

These are the first 40 parts; the other 143 (every new gun's standard parts and upgrades, shared muzzle devices and magazines, more rail parts and sights) are listed in Section 6.4. Parts come from Mechanic, Skier, Peacekeeper and Jaeger (Section 10), weapon boxes and duffle bags, and the guns you find.

### 12.2 Gear & Gear Upgrades

**Gear** *(tune: `data/items/armor/`, `helmets/`, `rigs/`, `backpacks/` and `attachments/helmet_mods.json`)*: 13 vests and 7 armored rigs in classes 1–6, 10 helmets in classes 1–6 with 7 face shields and 6 headsets, and 9 rigs and 9 backpacks from 3×1 to 8×8 (47 new pieces, every rarity). How armor stops rounds (penetration against class, durability loss) is in Section 6.4. Ragman sells gear by loyalty level (Common and Uncommon at LL1, Rare LL2, Ultra Rare LL3, Epic LL4; Legendary gear is only found in raid); all of it can turn up as loose loot or on bodies.

**Body armor**

| Armor | Class | Covers | Durability | Material | Blunt | Weight | Rarity (max upgrade) | Where |
|---|---|---|---|---|---|---|---|---|
| Trooper soft vest | 1 | Thorax, Stomach | 35 | Aramid | 40% | 2.2 kg | C (+1) | Ragman LL1 |
| Module-3M body armor | 2 | Thorax, Stomach | 40 | Aramid | 38% | 2.8 kg | C (+1) | Ragman LL1 |
| PACA soft armor | 2 | Thorax, Stomach | 50 | Aramid | 35% | 3.5 kg | U (+2) | Ragman LL1 |
| Zhuk-3 press vest | 3 | Thorax, Stomach | 52 | Titanium | 30% | 5.2 kg | U (+2) | Ragman LL1 |
| MMAC plate carrier | 3 | Thorax | 46 | Polyethylene | 28% | 3.6 kg | R (+3) | Ragman LL2 |
| 6B23-1 body armor | 4 | Thorax, Stomach | 49 | Steel | 25% | 8.6 kg | R (+3) | Ragman LL2 |
| Gzhel-K body armor | 5 | Thorax, Stomach | 65 | Ceramic | 20% | 9.0 kg | UR (+4) | Ragman LL3 |
| Korund-VM body armor | 5 | Thorax, Stomach | 60 | Ceramic | 20% | 10.2 kg | UR (+4) | Ragman LL3 |
| Redut-T5 body armor | 5 | Thorax, Stomach, arms | 75 | Steel | 22% | 13.4 kg | UR (+4) | Ragman LL3 |
| Hexgrid plate carrier | 5 | Thorax | 55 | Ceramic | 18% | 6.4 kg | E (+5) | Ragman LL4 |
| Zabralo-Sh body armor | 6 | Thorax, Stomach, arms | 85 | Steel | 18% | 18.0 kg | E (+5) | Ragman LL4 |
| Slick plate carrier | 6 | Thorax | 80 | Ceramic | 15% | 9.5 kg | L (+5) | Loot |
| Atlas heavy assault armor | 6 | Thorax, Stomach, arms | 110 | Ceramic | 12% | 20.0 kg | L (+5) | Loot |

**Armored rigs** (armor and pouches in one; not worn with body armor)

| Rig | Class | Covers | Durability | Grid | Weight | Rarity (max upgrade) | Where |
|---|---|---|---|---|---|---|---|
| Improvised plate rig | 1 | Thorax | 25 | 3×1 | 3.0 kg | C (+1) | Ragman LL1 |
| Patrol armored vest | 2 | Thorax, Stomach | 38 | 4×1 | 2.6 kg | U (+2) | Ragman LL1 |
| 6B5 armored rig | 3 | Thorax, Stomach | 45 | 4×2 | 7.5 kg | U (+2) | Ragman LL1 |
| Thor plate rig | 4 | Thorax | 50 | 4×3 | 6.2 kg | R (+3) | Ragman LL2 |
| Bagariy armored rig | 5 | Thorax, Stomach | 60 | 5×2 | 9.5 kg | UR (+4) | Ragman LL3 |
| AVS assault rig | 5 | Thorax, Stomach | 70 | 6×2 | 8.0 kg | E (+5) | Ragman LL4 |
| TSR combat rig | 6 | Thorax | 80 | 6×3 | 9.0 kg | L (+5) | Loot |

**Helmets** (cover the head except the face; face shield and headset slots)

| Helmet | Class | Durability | Ricochet | Hearing | Slots | Comes with | Rarity (max upgrade) | Where |
|---|---|---|---|---|---|---|---|---|
| Bump cap | 1 | 20 | ×0.2 | — | headset | — | C (+1) | Ragman LL1 |
| Kolpak riot helmet | 1 | 26 | ×0.3 | −5% | face shield, headset | — | C (+1) | Ragman LL1 |
| SSh-68 steel helmet | 2 | 30 | ×0.5 | −10% | headset | — | U (+2) | Ragman LL1 |
| Kiver-M helmet | 3 | 34 | ×0.3 | −15% | face shield, headset | — | U (+2) | Ragman LL1 |
| ZSh-1-2M helmet | 4 | 36 | ×0.4 | −15% | face shield, headset | — | R (+3) | Ragman LL2 |
| FAST high-cut helmet | 4 | 30 | ×0.35 | −5% | face shield, headset | — | R (+3) | Ragman LL2 |
| Sentry ballistic helmet | 5 | 38 | ×0.4 | −5% | face shield, headset | — | UR (+4) | Ragman LL3 |
| Altyn assault helmet | 5 | 50 | ×0.6 | −25% | face shield, headset | Altyn face shield | E (+5) | Ragman LL4 |
| Lynx-T helmet | 5 | 44 | ×0.5 | −20% | face shield, headset | Lynx-T face shield | E (+5) | Ragman LL4 |
| Vulkan-6 heavy helmet | 6 | 60 | ×0.6 | −30% | face shield, headset | Vulkan-6 face shield | L (+5) | Loot |

**Face shields** (cover the face: head hits from the front)

| Face shield | Class | Durability | Ricochet | Hearing | Fits | Rarity (max upgrade) | Where |
|---|---|---|---|---|---|---|---|
| Kolpak riot visor | 1 | 20 | ×0.3 | −5% | Kolpak riot helmet | C (+1) | Ragman LL1 |
| Kiver face shield | 2 | 28 | ×0.4 | −10% | Kiver-M helmet | U (+2) | Ragman LL1 |
| Ballistic rail visor | 3 | 30 | ×0.45 | −5% | FAST high-cut helmet, Sentry ballistic helmet | R (+3) | Ragman LL2 |
| ZSh armored visor | 4 | 36 | ×0.5 | −10% | ZSh-1-2M helmet | UR (+4) | Ragman LL3 |
| Altyn face shield | 5 | 50 | ×0.6 | −10% | Altyn assault helmet | E (+5) | Loot |
| Lynx-T face shield | 5 | 46 | ×0.55 | −10% | Lynx-T helmet | E (+5) | Loot |
| Vulkan-6 face shield | 6 | 60 | ×0.6 | −15% | Vulkan-6 heavy helmet | L (+5) | Loot |

**Headsets** (any helmet's headset slot)

| Headset | Hearing | Weight | Rarity (max upgrade) | Where |
|---|---|---|---|---|
| GSSh-01 headset | +15% | 0.15 kg | C (+1) | Ragman LL1 |
| Sordin headset | +25% | 0.30 kg | U (+2) | Ragman LL1 |
| ComTac headset | +35% | 0.35 kg | R (+3) | Ragman LL2 |
| Tactical Sport headset | +40% | 0.25 kg | UR (+4) | Ragman LL3 |
| Razor headset | +45% | 0.30 kg | E (+5) | Ragman LL4 |
| Ghost headset | +55% | 0.25 kg | L (+5) | Loot |

**Rigs and backpacks** (plain)

| Item | Kind | Grid | Item size | Weight | Rarity (max upgrade) | Where |
|---|---|---|---|---|---|---|
| Sling bag | Backpack | 3×3 | 2×3 | 0.3 kg | C (+1) | Ragman LL1 |
| Daypack | Backpack | 4×4 | 3×4 | 0.6 kg | C (+1) | Ragman LL1 |
| MBSS backpack | Backpack | 4×5 | 3×4 | 0.9 kg | U (+2) | Ragman LL1 |
| Tourist backpack | Backpack | 5×6 | 4×5 | 1.4 kg | U (+2) | Ragman LL1 |
| Trizip backpack | Backpack | 6×6 | 4×5 | 1.8 kg | R (+3) | Ragman LL2 |
| Large raid pack | Backpack | 6×8 | 5×6 | 3.6 kg | R (+3) | Ragman LL2 |
| Pilgrim tourist backpack | Backpack | 7×7 | 5×6 | 3.2 kg | UR (+4) | Ragman LL3 |
| Attack 2 raid backpack | Backpack | 6×8 | 5×6 | 2.4 kg | E (+5) | Ragman LL4 |
| Blackjack 50 backpack | Backpack | 8×8 | 5×6 | 2.0 kg | L (+5) | Loot |
| Battle belt | Rig | 3×1 | 2×1 | 0.4 kg | C (+1) | Ragman LL1 |
| Scav vest | Rig | 4×1 | 2×2 | 0.3 kg | C (+1) | Ragman LL1 |
| Tactical chest rig | Rig | 4×2 | 3×3 | 1.0 kg | U (+2) | Ragman LL1 |
| Triton chest rig | Rig | 6×2 | 3×3 | 1.2 kg | R (+3) | Ragman LL2 |
| Bear assault rig | Rig | 6×3 | 3×3 | 1.6 kg | UR (+4) | Ragman LL3 |
| Blackrock chest rig | Rig | 7×3 | 3×3 | 1.3 kg | E (+5) | Ragman LL4 |
| Operator chest rig | Rig | 8×3 | 3×3 | 1.1 kg | L (+5) | Loot |

| Helmet rule | Detail |
|---|---|
| Slots | Helmets list their slots (`"slots"`): a face shield (fits by mount, `"platform"`: the rail visor goes on any railed helmet) and a headset (any headset). Some come with their face shield (`"default_mods"`: Altyn, Lynx-T, Vulkan-6). Out of raid, drop a face shield or headset on a helmet to fit it; examining the helmet lists them with TAKE OFF (to the stash) |
| Hearing | Helmets and face shields muffle (−5% to −30% hearing), a headset amplifies (+15% to +55%, more when upgraded). The total (×0.5 to ×2) sets how far you hear: the sound markers of things you can't see (Section 13.6), and for AI how far they hear you |

**Upgrades** *(tune: `data/config/gear_upgrades.json`)*: raise a piece of gear's level, **+1 to +5**, one level at a time, for roubles and barter items.

| Rule | Detail |
|---|---|
| What | Armor (vests, armored rigs, helmets, face shields), plain rigs and backpacks, and headsets. Guns are modded, not upgraded (Section 12.1); secure containers, meds and the rest don't upgrade |
| Max level | By rarity: Common +1, Uncommon +2, Rare +3, Ultra Rare +4, Epic and Legendary +5 |
| Effects per level | Armor: **+10% max durability** (the current durability goes up as much), **−4% blunt damage**; helmets and face shields **+6% ricochet**. Rigs and backpacks: **5% lighter**, **+1 row of room at +2, +2 rows at +4, +1 column and +2 rows at +5** (armored rigs get both). Headsets: **+5% hearing** |
| Where | **Ragman** (UPGRADES tab): up to +2 at LL1, +3 at LL2, +4 at LL3, +5 at LL4; full price, counted as money spent with him. **Workbench** (hideout, GEAR UPGRADES): up to +2 at level 1, +4 at level 2, +5 at level 3; 40% of the money but an extra roll of duct tape. Out of raid, **UPGRADE** in the examine panel opens a dialog with both |
| Cost | Roubles: 15 / 25 / 40 / 60 / 85% of the item's value for +1 … +5 (at least 3,000). Barter items: armor needs aramid fabric (then bolts, epoxy resin, ceramic plate shards); rigs and backpacks paracord and ripstop fabric (then duct tape, epoxy resin); headsets wires (then screws, a screwdriver, a flash drive, a GPU). Ragman sells ripstop fabric and paracord (LL1) and aramid fabric (LL2); the rest is loot |
| Showing it | The item's name gets "+N" (examine, tooltips, lists) and a gold "+N" in its grid cell; examine shows "Upgrade: +1 of +3 (Rare)" and the durability, blunt share, ricochet, room and hearing at its level. Each row in the upgrade lists shows what the next level changes, the price (red if you can't afford it), the items (with how many you have) and UPGRADE, disabled with the reason ("Needs a higher loyalty level with Ragman", "Upgrade the Workbench for +3", "Missing items") |
| Saving | The level is saved with the item (`"upgrade"`); its max durability and grid are rebuilt from it on load |

| Planned gear upgrades | Upgrade path | Effect |
|---|---|---|
| Armor | Repair kits, plate inserts (class swap) | Restore durability, raise class |
| Helmets | NVG mounts | Night vision |
| Secure container | Quest/barter tiers: Alpha 2×2 → Beta 3×2 → Gamma 3×3 → Kappa 3×4 | Safer loot |

### 12.3 Player Skills

| Skill | Leveled by | Benefit |
|---|---|---|
| Strength | Carrying weight, melee | Carry more, throw farther; 0.25% less recoil per level |
| Endurance | Sprinting | More stamina |
| Vitality | Taking damage | Lower bleed chance |
| Metabolism | Eating/drinking (built: 0.5 points per point of energy or hydration; a level takes 100 points, +10% each) | 1% slower energy/hydration drain per level, up to 50% at level 50 (built, Section 13.7) |
| Search | Searching containers | Faster search, rarer loot (+% capped) |
| Weapon class skills | Using weapon type (built: Pistols, SMGs, Shotguns, Assault rifles, Marksman rifles, Bolt-action rifles, Machine guns) | 0.5% less recoil per level (up to 15% with Strength); reload speed planned. Levelling isn't built yet |

## 13. Health, Movement & Combat

| System | Detail |
|---|---|
| Body parts | Head, Thorax (death at 0), Stomach, L/R Arm, L/R Leg (Section 13.5) |
| Conditions | Light bleed, heavy bleed, fracture, pain (Section 13.5); hungry and thirsty (below 30), Exhaustion and Dehydration (at 0); timed effects from meds, stims and food (Section 13.7) |
| Energy / Hydration | 0–100 each; drain in a raid (hydration twice as fast; more sprinting, rolling, overweight, injured or on hot maps, less crouched or still), carried between raids, refilled in the hideout; below 30 slows stamina recovery, 0 drains HP from every part, shakes the aim and blurs vision (Section 13.7) |
| Stamina | Sprint, aim stability |

### 13.1 Movement *(tune)*

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

### 13.2 Combat Roll (Space) *(tune)*

| Rule | Value |
|---|---|
| Direction | The way you're moving; toward the cursor if standing still |
| Distance / time | 3 m in 0.5 s, fast at the start and slowing to a stop. Walls stop it |
| Stamina | Costs 20; can't roll with less, or while exhausted |
| Cooldown | 1 s after a roll ends |
| Blocked by | Overweight (>40 kg), a fractured or blacked leg. The HUD says why |
| Harder to hit | For the first 0.3 s the hitbox shrinks to 0.8 m tall, 0.25 m radius (standing: 1.8 m, 0.35 m). Not invincible: low shots still hit |
| Noise | 25 m, louder than sprinting, so nearby AI hears it |
| Into cover | A roll toward cover that ends within 1 m of it snaps into that cover |

All of these values live in `data/config/combat.tres`.

### 13.3 Cover

| Rule | Detail |
|---|---|
| What counts | Walls, crates, cars and low barriers built from `CoverBox` (concrete, wood or metal) |
| Take cover | Q within 1.5 m of cover (Q again to leave), or roll into it |
| Low cover (≤1.3 m) | Duck behind it (body 0.9 m). Hold right-click to stand up and aim over it; release to duck |
| Tall cover | Lean against it, standing. Hold right-click to step out past its end and aim; release to step back. Only possible within 1.2 m of an end |
| Moving | A/D (sideways along the cover) slides along it at 1.6 m/s; moving away from it leaves cover |
| No shooting | While ducked or leaning (not peeking) |
| HUD | Shield icon with cover type and material; turns amber while peeking |
| Shared | Player and AI use the same cover points; a spot someone holds (or is heading to) is taken |

### 13.4 Shooting & Bullets

| Rule | Detail |
|---|---|
| Model | Hitscan rays from the body's centre line at gun height (1.3 m standing); a short tracer shows each shot |
| Aim | At whoever is under the cursor, otherwise level with the gun toward the cursor |
| Wood | Stops rounds with penetration below 30. Rounds with 30+ go through, keeping 60% damage and losing 15 penetration |
| Concrete, metal | Stop every round |
| Noise | Every shot is a 60 m noise, × the gun's noise from its parts (a suppressed AK: 18 m) × the round's (subsonic 7.62x39 US: 60%) |
| Range | 150 m for rounds at 800 m/s or faster, less for slower ones (pistols about 55–70 m); damage falls off over the last 60% of the range to 75% (Section 6.4) |
| Armor | Helmets and body armor may stop a round on the parts they cover, by its penetration against their class (Section 6.4) |
| Health | Body parts for everyone, player and AI (Section 13.5). A round damages the part it lands on |
| Guns | 22 guns in seven classes (Section 6.4). Each gun's handling is a `WeaponData` file (Section 15), changed by its parts (Section 12.1). Damage and penetration always come from the ammo |
| Shot shells | Buckshot and flechettes fire 8 pellets per shot, each a round of its own, spread around the aim by the shell's pellet spread × the gun's (chokes); slugs fire one (Section 6.4) |
| Durability and jams | Each shot wears the gun; worn guns jam. A jammed gun won't fire or reload until R clears it (1.6 s; the stuck round is lost). A gun missing a barrel, dust cover or magazine can't fire (Section 12.1) |
| Fire rate | Rounds per minute. Automatic guns fire while the trigger is held; semi-auto guns fire once per click |
| Magazine | Each shot uses a round; the magazine fitted sets how many it holds. Can't fire while reloading |
| Reload (R) | Tactical reload (rounds left) or a slower empty reload (a round has to be chambered). Tops the magazine up from spare rounds of the gun's round type; with none left it switches to another round of the same caliber you carry. Drag rounds onto a gun to load a different type (Section 6.4). You can move, roll and use cover while reloading |
| Spare ammo | In a raid: the pocket rounds matching the loaded ammo. Rounds used aren't taken out of your profile yet |
| Auto-reload | On by default (Settings > Gameplay): pulling the trigger on an empty magazine reloads. Off: the HUD says "Magazine empty: press R to reload". No spare rounds: "Out of ammo" |
| Recoil | Each shot kicks the aim. **Vertical recoil** is muzzle climb: the aim moves out along the aim direction and rounds fly higher, so a long burst at range ends up over the target's head. **Horizontal recoil** kicks left or right at random. **Recoil recovery** pulls the aim back after each shot (it starts a moment after the shot, so full-auto keeps climbing until recovery and kick balance out). You can counter the side kick by moving the mouse; the reticle shows where the next shot goes. AI fight off part of the kick (Scav 30%, PMC 60%) |
| Spread (bloom) | Each shot lands at random inside a cone: **base spread** + wear + **bloom** + the shooter's aim error (AI only). Bloom grows with every shot (**bloom per shot**, up to **max bloom**), while moving (full at sprint speed), sprinting, rolling, and when **hip-firing** (until the sight is up: aim time decides how fast it goes). It shrinks at the gun's **bloom recovery** once you stop shooting (a short pause after the last shot) or stop moving. AI always fire aimed |
| Sway | The aim drifts slowly side to side: the gun's own sway (heavier builds more, less with the sight up) plus injuries (Section 13.5) |
| Feedback | Muzzle flash with a brief light, a small kick of the gun model and camera shake (scaled with vertical recoil). A burst of particles where a round hits: grey dust (concrete), sparks (metal), splinters (wood), red (a body). The **bloom reticle** is a circle the size of the real spread cone at the aim point, growing and shrinking live; it sits where the next shot goes (the cursor moved by recoil and sway), with a faint dot on the cursor itself while they move it. A ring fills around it while reloading or clearing a jam |
| HUD | Bottom right: gun name, rounds in the magazine (amber at a third or less, red when empty), magazine size, spare rounds, the round in the chamber and its penetration (and pellets), auto/semi, and a reload bar. In red instead of the ammo line: "JAMMED · R to clear", "CLEARING JAM", or a missing part ("NO MAGAZINE") |

| Ammo (examples; every round is in Section 6.4) | Damage | Penetration | Wood |
|---|---|---|---|
| 5.45x39 PS | 50 | 28 | Stopped |
| 5.45x39 BS | 40 | 45 | Goes through (24 damage after) |
| 7.62x54R LPS | 81 | 41 | Goes through (49 damage after) |
| 12ga 7mm buckshot | 37 × 8 pellets | 3 | Stopped |

| Gun *(tune, `data/weapons/`)* | Fire rate | Mode | Magazine | Reload / empty | Climb / side kick / recovery | Base spread | Bloom per shot / max / recovery | Hip-fire | Moving / sprint / roll | Sway |
|---|---|---|---|---|---|---|---|---|---|---|
| AK-74N | 650 rpm | Auto | 30 | 2.3 s / 2.9 s | 0.55° / ±0.35° / 7 per s after 0.06 s | 0.5° | +0.35° / +4.5° / 9°/s after 0.2 s | +1.8° | +3.0° / +2.0° / +6.0° | 0.2° |
| PM | 450 rpm | Semi | 8 | 1.8 s / 2.3 s | 1.0° / ±0.55° / 9 per s after 0.05 s | 0.8° | +0.8° / +5.0° / 12°/s after 0.2 s | +1.2° | +3.5° / +2.0° / +6.0° | 0.12° |
| Mosin (bolt-action) | 50 rpm (bolt cycle 1.2 s) | Semi | 5 | 3.2 s / 3.8 s | 2.4° / ±0.5° / 6 per s after 0.1 s | 0.12° | +1.0° / +3.0° / 5°/s after 0.3 s | +3.5° | +4.0° / +2.5° / +7.0° | 0.35° |
| SVD (DMR) | 300 rpm | Semi | 10 | 2.7 s / 3.3 s | 1.4° / ±0.4° / 7 per s after 0.08 s | 0.2° | +0.7° / +3.5° / 6°/s after 0.25 s | +3.0° | +3.8° / +2.2° / +6.5° | 0.3° |

The other 18 guns follow class templates (pistol, SMG, shotgun, assault rifle, DMR, bolt-action, LMG) with their own fire rate, magazine, recoil, spread and ergonomics (Section 6.4 lists them; every value is in the gun's `.tres`).

### 13.4.1 360 Trick Shots

A risk / reward move for bolt-action rifles and DMRs (`WeaponData.weapon_class` "bolt_action" or "dmr"); assault rifles and pistols can't.

| Rule | Detail *(tune per gun in its `data/weapons/*.tres`, "Trick shot")* |
|---|---|
| The spin | Sweep the reticle a full 360° around your character in one direction within **1.5 s** (`trick_spin_time`), rolling or not. What counts is the direction from you to the reticle, so the combat roll doesn't stop it. Turning back more than 20° starts the count over; the reticle has to be at least 0.75 m from you |
| Ready window | A full spin opens **TRICK SHOT READY** for **1 s** (`trick_window`): a gold label over the HUD with the time left, a low sting, and a full gold ring around the reticle. While spinning, a gold arc around the reticle shows how far round you are |
| The bonus | The **first shot** in the window deals **+50% damage** (`trick_damage_bonus`). It's put on the round as it leaves the muzzle, before wood, cover or armor reduce it, so armor still matters (Section 6.4). The window closes with that shot; the next one is normal |
| The risk | No aiming while spinning (from half a turn) or while the window is open: the sight drops and the shot is fired from the hip with full hip-fire bloom (+3.5° on the Mosin), plus any movement or roll bloom. Miss and the bolt has to cycle |
| Hit | A gold hit marker with a diamond (held twice as long), "360!" popping up over the hit, and a sound sting |
| Kill | A kill banner across the screen ("★ 360 TRICK SHOT ★", who went down, the bonus), +250 raid experience on top of the kill's and +25 **Drip** *(tune: `raid.tres`)* |
| Stats | The character screen counts trick-shot kills and hits ("Trick Shots") and your Drip; the raid result lists the raid's trick shots. Kills count toward trick-shot quests (Section 11) |

### 13.5 Health & Status Effects *(tune)*

Every actor, player and AI, has the same body. Armor stops rounds before they reach it (Section 6.4); meds, stims and food treat and change it (Section 13.7).

| Part | HP | At 0 HP | Damage spread when blacked |
|---|---|---|---|
| Head | 35 | Death | — |
| Thorax | 85 | Death | — |
| Stomach | 70 | Blacked | ×1.5 |
| Left / right arm | 60 each | Blacked | ×0.7 |
| Left / right leg | 65 each | Blacked | ×1.0 |
| **Total** | **440** | | |

| Rule | Detail |
|---|---|
| Hit zones | Where a round lands on the hitbox decides the part, by height (head from 86%, thorax from 60%, stomach from 47%, legs below) and by side (in the torso band, more than 0.22 m off the centre line is an arm; legs split left/right). The head is narrower than the hitbox: a round passing more than 0.13 m beside the centre line at head height misses, over the shoulder. Shots from the side tend to hit an arm first |
| Aiming | With the reticle over someone, the player aims at their chest (the middle of the thorax), as bots do. Spread, sway and their movement decide where rounds land |
| Blacked parts | A part at 0 is blacked. Damage it takes from then on, and any damage beyond a part's remaining HP, is multiplied (table) and shared evenly by every part that still has HP, head and thorax included. So limb hits can still kill |
| Light bleed | Each round has its own chance per hit that reaches flesh (Section 6.4: soft rounds high, AP low; a fragmenting round always). Anything else: 35% at 50 damage, scaled by damage up to ×1.5. Loses 0.5 HP/s from that part |
| Heavy bleed | The round's own chance (else 12%, same scaling); replaces a light bleed on that part. Loses 1.5 HP/s |
| Bleeding | Doesn't stop on its own. On a blacked part, bleed damage spreads like any other damage. Bandages stop light bleeds, tourniquets heavy ones, the hemostat and most medkits both; Zagustin pauses the damage (Section 13.7) |
| Fracture | 25% chance per hit to an arm or leg (same scaling). Leg (fractured or blacked): 70% speed, no sprinting, no rolling (a painkiller allows both). Arm (fractured or blacked): +2° weapon sway each. Splints (and the Grizzly) set it |
| Pain | While any part is fractured or blacked, unless a painkiller is working ("Pain (numbed)"). +1° weapon sway; for the player, dark red tunnel vision at the screen edges (pulsing; steady with "reduce flashing") |
| Weapon sway | The aim drifts slowly left and right by up to the total sway (injuries plus the gun's own, Section 13.4), on top of spread. The player sees it as the bloom reticle shifting |
| HUD | Bottom left: body silhouette (seen from behind), each part filled green → amber → red by its HP, black with a red outline when blacked; drops for bleeds (two for heavy), a crack for fractures, a flash on the part that was hit. Next to it, total HP, a list of conditions, the running effects (benefits green, drawbacks red, with time left) and what E would treat; energy and water bars under stamina; a USING bar above the player (Section 13.7) |
| Death screen | After 1.5 s: **KILLED IN ACTION**, what killed you ("Shot in the head by a Scav", with weapon, ammo, damage and distance; "the damage spread to your thorax" when a blacked limb did it; or "Bled out" with which bleed and who caused it; "Died of exhaustion", "Died of thirst" or "Poisoned" by a stim), your body at the moment of death (hover parts for HP), active effects, map, side, time in raid and kills. **BACK TO MENU** |

All of these values live in `data/config/health.tres`.

### 13.6 Vision *(tune)*

Project Zomboid-style: you only see what your character can see.

| Rule | Detail |
|---|---|
| Vision cone | 110°, pointed at the reticle (not the body), 30 m in daylight |
| Awareness circle | 2 m all around, so you sense things right behind you. Walls still block it |
| What's hidden | Outside the cone and circle, or behind an occluder: enemies (and later loot and bodies' contents) aren't drawn; the area is darkened and desaturated. Places you've seen this raid stay as a dim grey "memory" of the layout; places never seen are near black |
| Occluders | Walls, cars, crates and other cover (`CoverBox`), plus sight-only `VisionOccluder`s such as the hedge in the test yard (blocks sight, not bullets or movement) and, later, doors |
| Low cover | Blocks your view only when you're crouched (or ducked). An enemy crouched behind low cover is hidden too |
| Shadows | 2D shadow casting from your position 30 times a second: rays along the cone's edge, around the awareness circle and either side of every occluder corner in reach. Wall tops you're looking at are lit |
| Light | Range × (0.25 + 0.75 × light). Light: day 1.0, dusk 0.6, night 0.15; dark rooms (`DarkZone`) 0.1, and they look darker. Day: 30 m; night: 10.9 m; dark room: 9.75 m |
| Flashlight (L) | A 30°, 22 m cone that brings its own light (not shortened by darkness); lights dark rooms. AI spots you from 1.5× farther while it's on |
| Weather | Fog ×0.5, rain ×0.75 (cones only, not the awareness circle) |
| Status effects | Pain: cone ×0.8. Head below 70% HP: cone ×0.7. Flashbang: blinded for up to 4 s (within 15 m with a clear line; less with distance, ×0.35 facing away): only the awareness circle, and a white-out on screen (a dark fade with "reduce flashing effects") |
| Sounds | Gunshots, footsteps, rolls and flashbangs you can hear but whose source you can't see show as a marker at the screen edge pointing toward them, fading after 1.5 s (gunshots and flashbangs 2.25 s). One marker per source. Shape and colour show the kind: double red chevron = gunshot, white ring = flashbang, amber chevron = roll, small pale chevron = footsteps |

**Optics** (while aiming, right-click). Raising or lowering a sight takes 0.3 s; the cone, range, speed and camera blend over it. No sprinting through any optic.

| Sight | Range | Cone | Move speed | Camera |
|---|---|---|---|---|
| Iron sights | ×1 | 110° | 100% | — |
| Red dot / holographic | ×1 | 120° | 85% | — |
| 2-4x scope | ×2 (60 m) | 40° | 60% | Pulls out ×1.25, leads up to 20 m toward the aim |
| 6-8x scope | ×3 (90 m) | 25° | 50% | ×1.5, up to 35 m |
| Binoculars (B) | ×4 (120 m) | 15° | 50% | ×1.7, up to 50 m. Can't shoot while holding them |

The camera lead always keeps you within the middle 55% of the screen. The gun's sight is the strongest sight fitted to it (the side mount or a top rail, Section 12.1), iron sights without one; F6 cycles it in the test yard. AI use `BotProfile.optic`.

**Raid conditions:** each raid has a time of day (day, dusk, night) and weather (clear, fog, rain), set on the map's `RaidEnvironment` (sun, ambient light, fog, rain). The HUD shows both next to the map name. In the test yard F7 and F8 cycle them.

All of these values live in `data/config/vision.tres`.

### 13.7 Meds, Stims, Food & Metabolism *(tune)*

Meds treat the body of Section 13.5, stims trade a few minutes of buffs for side effects, and food and drink keep energy and hydration up. Every one of them takes time to use, and that time can be interrupted.

**Using items**

| Rule | Detail |
|---|---|
| Use time | Every med, stim, food and drink has one (2 s for an injector, 3 s for a bandage, 14 s for CMS surgery). While using, you walk at 65% speed (surgery 30–40%) and can't sprint, shoot, aim or reload. The HUD shows **USING …** with a bar above the player; the inventory header shows it too |
| Interrupted | Shooting, rolling, sprinting, reloading or aiming (they go ahead), a hit that does damage, the item leaving your inventory, or the use key again. Nothing happens and nothing is used up |
| Quick treatment (E, `use_item`) | Treats the worst problem with what's **in your pockets, rig or secure container** (not the backpack): heavy bleed, light bleed, fracture, pain, lost HP, blacked part, then thirst and hunger (at 60% or less). Dedicated items before medkits, cheaper first, part-used first; stims and anything with a side effect are never picked for you. The HUD shows what E would do ("E  Bandage: light bleed (left arm)") or that you have nothing for it |
| From the inventory | Examine (right-click) → **USE**: any med, stim, food or drink you carry, backpack included (not straight out of a container or body: take it first). Disabled with the reason as its tooltip ("No light bleed to treat") |
| Where it goes | A med picks the body part that needs it most: heavy bleeds first, then light bleeds, fractures and blacked parts (legs before the stomach and arms), then missing HP. Checked again when the use finishes |
| Uses and HP pools | Multi-use items count down their uses ("2/3" on the item); medkits spend their HP pool (HP left on the item, amber once opened). A part-used item is worth its share of uses left. Saved per item |
| Bleeds | Bandages stop one light bleed, tourniquets one heavy bleed (anywhere), the CALOK-B hemostat either |
| Fractures | Splints set one fracture |
| Painkillers | For their duration: no pain (no sway or tunnel vision from it) and a fractured or blacked leg can sprint and roll again (still at 70% speed). The fracture is still there: "Pain (numbed)" |
| Medkits | One body part a use: stop its bleeds the kit can treat (paying the listed HP from the pool), set its fracture (Grizzly), then heal its missing HP from what's left. Can't heal a blacked part |
| Surgery | On a blacked stomach, arm or leg: it comes back at a share of its max HP, but its max HP drops for the rest of the raid (repeat surgery lowers it further). Bleeds and fractures there still need treating |
| Effects | Stims, painkillers and some food and drink start timed effects: listed beside the body on the HUD (benefits green, drawbacks red, with time left) and on the death screen. Taking the same item again refreshes its effects instead of stacking them; different items stack. Side effects often start when the buffs end |
| Out of raid | Only food and drink can be used (on the profile's energy and hydration, instantly); meds and stims say "Only in a raid" |
| AI | Bots don't use items yet; they carry them as loot |

| Med | Rarity | Size | Treats (one body part a use) | Uses / HP | Use time | Notes |
|---|---|---|---|---|---|---|
| Bandage | Common | 1×1 | light bleed | 1 | 3.0 s | — |
| Army bandage | Uncommon | 1×1 | light bleed | 2 | 2.5 s | — |
| Esmarch tourniquet | Common | 1×1 | heavy bleed | 1 | 4.0 s | — |
| CAT tourniquet | Uncommon | 1×1 | heavy bleed | 2 | 3.0 s | — |
| CALOK-B hemostatic applicator | Rare | 1×1 | light bleed, heavy bleed | 3 | 2.0 s | — |
| Immobilizing splint | Common | 1×1 | fracture | 1 | 5.0 s | — |
| Aluminium splint | Rare | 1×1 | fracture | 3 | 3.0 s | — |
| Analgin painkillers | Uncommon | 1×1 | pain | 4 | 3.0 s | painkiller 1:35 |
| Ibuprofen tablets | Rare | 1×1 | pain | 6 | 3.0 s | painkiller 4:00; side effect: hydration -2/min 4:00 |
| AI-2 medkit | Common | 1×1 | heals missing HP | 100 HP | 2.0 s | — |
| Car first aid kit | Uncommon | 2×1 | light bleed (50 HP), heals missing HP | 220 HP | 3.0 s | — |
| Salewa first aid kit | Rare | 1×2 | light bleed (45 HP), heavy bleed (175 HP), heals missing HP | 400 HP | 3.0 s | — |
| IFAK individual first aid kit | Ultra Rare | 1×1 | light bleed (30 HP), heavy bleed (210 HP), heals missing HP | 300 HP | 2.5 s | — |
| AFAK tactical first aid kit | Epic | 1×1 | light bleed (30 HP), heavy bleed (170 HP), heals missing HP | 400 HP | 2.0 s | — |
| Grizzly medical kit | Legendary | 2×2 | light bleed (40 HP), heavy bleed (130 HP), fracture (50 HP), heals missing HP | 1800 HP | 5.0 s | — |
| CMS surgical kit | Rare | 2×1 | blacked part | 3 | 14.0 s | back at 35% HP, −35% max HP for the raid; walk at 30% |
| Surv12 field surgical kit | Epic | 3×1 | blacked part | 8 | 10.0 s | back at 50% HP, −20% max HP for the raid; walk at 40% |

| Stim (injector, 1×1, 2 s) | Rarity | Effects | Side effects |
|---|---|---|---|
| Adrenaline injector | Rare | stamina recovery +50% 1:00, painkiller 1:00 | sway +1.5° 0:30 after 1:00, hydration -10 |
| Morphine injector | Rare | painkiller 5:00 | hydration -15 |
| Propital regenerative stimulant | Ultra Rare | regeneration 1 HP/s 4:00, painkiller 4:00 | sway +1.5° 0:30 after 4:00 |
| L1 norepinephrine injector | Ultra Rare | max stamina +30 2:00, speed +6% 2:00, painkiller 2:00 | energy -10, hydration -20 |
| 3-(b-TG) stimulant | Ultra Rare | recoil -15% 4:00, sway -0.5° 4:00 | sway +1.5° 0:40 after 4:00, hydration -10 |
| Zagustin hemostatic drug | Epic | hemostatic 3:00 | sway +1.0° 0:40 after 3:00, hydration -15 |
| SJ6 TGLabs combat stimulant | Epic | max stamina +40 4:00, stamina recovery +50% 4:00, speed +8% 4:00 | sway +2.0° 1:00 after 4:00, energy -20/min 1:00 after 4:00, hydration -20/min 1:00 after 4:00 |
| Obdolbos 2 cocktail injector | Legendary | max stamina +50 5:00, stamina recovery +100% 5:00, speed +12% 5:00, recoil -20% 5:00, painkiller 5:00 | hydration -6/min 5:00, toxin 0.4 HP/s 1:00 after 5:00, sway +2.5° 1:00 after 5:00 |
| eTG-change regenerative stimulant | Legendary | regeneration 6 HP/s 1:00 | energy -40/min 1:00, hydration -25/min 1:00 |

| Effect | What it does |
|---|---|
| Painkiller | No pain; broken legs can sprint and roll |
| Regeneration | Heals X HP/s spread over the damaged parts (not blacked ones) |
| Hemostatic | Bleeds do no damage (they don't stop) |
| Max stamina / stamina recovery | + stamina points / + recovery speed |
| Speed | Move speed |
| Recoil | Recoil of every shot (−15% = 15% less) |
| Sway | Weapon sway in degrees: a tremor (+) or steadier hands (−) |
| Energy / hydration | Extra drain (or gain) per minute |
| Toxin | HP/s lost from the stomach (spreads once it's blacked) |

**Energy and hydration**

| Rule | Detail |
|---|---|
| Range | 0 to 100 each. A new character starts full |
| Drain | In a raid, walking: −1 energy and −2 hydration a minute (hydration twice as fast) |
| Faster / slower | × activity: standing or crouching still 0.5, moving crouched 0.75, walking 1, sprinting 2, rolling 3. × 1.2 heavy (from 25 kg), × 1.5 overweight. × 1.25 injured (bleeding, a fracture or a blacked part). × the map's climate: Shoreline Resort (hot) hydration ×1.5, energy ×1.1; Factory (hot) ×1.35 / ×1.1; Woodland (cold) hydration ×0.9, energy ×1.15. Stims and food add their own rates (above) |
| Metabolism skill | Eating and drinking train it: 0.5 skill points per point of energy or hydration an item gives or takes; a level takes 100 points, +10% per level, up to 50. Each level drains 1% slower, up to 50% at level 50. Shown on the character screen |
| Below 30 | Hungry (energy) or thirsty (hydration): stamina recovers at 70% speed for each, and the HUD warns (amber bar, a pulsing HUNGRY / THIRSTY line under the bars, the status list) |
| At 0 | **Exhaustion** (energy) or **Dehydration** (hydration): every body part with HP loses 0.03 HP/s (Exhaustion) or 0.05 HP/s (Dehydration), so the head or thorax eventually gives out ("Died of exhaustion", "Died of thirst"); +1° (Exhaustion) and +1.5° (Dehydration) weapon sway; the view blurs (more at the edges, swimming in and out; steady with "reduce flashing") and the vision cone narrows ×0.85 each. Red EXHAUSTION / DEHYDRATION warning |
| Between raids | A PMC's energy and hydration carry over from raid to raid (at least 30 each after dying). In the hideout they refill by 0.5 a real minute, × (1 + 0.5 per Nutrition Unit level + 0.75 per Rest Space level): ×4.75 with both at level 3, about 2.4 a minute. Eat and drink from the stash. A Scav starts full and doesn't touch the PMC's |
| Eating and drinking | Takes the item's use time (2–6 s), can be cancelled (E again, or shooting, rolling, sprinting, reloading, aiming, a hit) and then nothing is eaten. Multi-use items take one use at a time and keep the rest (uses left on the item, saved) |
| Previews | Hovering a food or drink in the inventory shows what one use would do: "Energy 62 → 77 (+15)  ·  Hydration 40 → 35 (−5)" in its tooltip and in the inventory header (against the player in a raid, the profile out of raid) |
| HUD | Energy and water bars under stamina (amber below 30, red at 0) and the warning line; the inventory header and character screen show both |

Values below are per use; negative values drain that stat. Combo rations (Field ration pack, Survivor's emergency kit) restore both, are Common / Uncommon and drop 3× / 2.5× as often as other items of their rarity, so they're a regular find wherever food spawns.

| Food / drink | Rarity | Size | Energy | Hydration | Uses | Use time | Effects (side effects marked) |
|---|---|---|---|---|---|---|---|
| Sunflower seeds | Common | 1×1 | +6 | -4 | 5 | 2.0 s | — |
| Crackers | Common | 1×1 | +15 | -5 | 1 | 3.0 s | — |
| Oat bar | Common | 1×1 | +12 | -3 | 1 | 2.0 s | — |
| Sugar | Common | 1×1 | +20 | -8 | 2 | 2.0 s | — |
| Dried fish | Common | 1×1 | +18 | -12 | 2 | 3.0 s | — |
| Rye bread | Common | 1×2 | +15 | -4 | 3 | 3.0 s | — |
| Green peas | Common | 1×1 | +25 | +10 | 1 | 4.0 s | — |
| Chocolate bar | Common | 1×1 | +20 | -6 | 1 | 2.0 s | — |
| Pickles | Common | 1×1 | +10 | +12 | 2 | 3.0 s | — |
| Sprats | Common | 1×1 | +30 | -10 | 1 | 4.0 s | — |
| Canned soup | Common | 1×1 | +18 | +18 | 1 | 4.0 s | — |
| Kvass | Common | 1×2 | +12 | +20 | 2 | 3.0 s | — |
| Beef jerky | Common | 1×1 | +12 | -6 | 3 | 2.0 s | — |
| Apple juice | Common | 1×2 | +10 | +25 | 2 | 3.0 s | — |
| Water bottle | Common | 1×2 | — | +30 | 2 | 3.0 s | — |
| Field ration pack | Common | 1×2 | +20 | +15 | 3 | 4.0 s | — |
| Coffee | Uncommon | 1×1 | +8 | -4 | 4 | 2.0 s | stamina recovery +10% 3:00 |
| Birch sap | Uncommon | 1×2 | +8 | +28 | 2 | 3.0 s | — |
| Black tea | Uncommon | 1×2 | +5 | +20 | 3 | 4.0 s | sway -0.3° 2:00 |
| Energy drink | Uncommon | 1×1 | +10 | +35 | 1 | 3.0 s | stamina recovery +20% 2:00 |
| Mineral water | Uncommon | 1×2 | — | +45 | 1 | 3.0 s | stamina recovery +10% 2:00 |
| Buckwheat | Uncommon | 1×1 | +40 | +5 | 1 | 6.0 s | — |
| Honey | Uncommon | 1×1 | +15 | -3 | 3 | 3.0 s | stamina recovery +10% 1:00 |
| Water ration | Uncommon | 1×1 | — | +35 | 1 | 3.0 s | — |
| Tushonka | Uncommon | 1×1 | +45 | -12 | 1 | 4.0 s | — |
| Condensed milk | Uncommon | 1×1 | +25 | -5 | 2 | 3.0 s | — |
| Beef stew | Uncommon | 1×1 | +60 | -10 | 1 | 5.0 s | — |
| Vodka | Uncommon | 1×2 | — | -8 | 3 | 3.0 s | painkiller 1:30; side effect: sway +1.0° 1:30 |
| Survivor's emergency kit | Uncommon | 1×2 | +25 | +25 | 2 | 5.0 s | — |
| Isotonic drink | Rare | 1×2 | +10 | +40 | 1 | 3.0 s | max stamina +10 3:00; stamina recovery +30% 3:00 |
| Hot Rod energy drink | Rare | 1×1 | +20 | +30 | 1 | 3.0 s | max stamina +20 5:00; stamina recovery +30% 5:00; side effect: sway +0.5° 5:00 |
| Aquamari bottle with filter | Rare | 1×2 | — | +50 | 2 | 4.0 s | — |
| MRE ration pack | Rare | 1×2 | +75 | +15 | 1 | 6.0 s | — |
| Moonshine | Ultra Rare | 1×2 | — | -15 | 2 | 4.0 s | painkiller 5:00; side effect: sway +2.0° 5:00; side effect: speed -5% 5:00 |

**Where food spawns**

| Spot | What it holds |
|---|---|
| Fridge | Drinks (water ×2.5 as likely, energy drinks), canned food, vodka and moonshine, field rations |
| Kitchen cabinet | Dry and canned food (sugar and coffee more likely), combo rations, matches, lighters, soap, kettles |
| Store shelf | Snacks, canned food, drinks, combo rations, cigarettes, toothpaste, soap, batteries, light bulbs |
| Gas station counter | Energy and sports drinks, water, coffee, snacks, combo rations, cigarettes, lighters, batteries, WD-40, fuel conditioner |
| Scav bodies | A snack in the pockets (always), often a drink or ration in the vest, food in the sling bag |
| Elsewhere | Jackets and loose loot can hold food; crates and duffle bags no longer do |

**Nutrition Unit crafts** (found in raid): level 1: energy drink ×2 (water + sugar + coffee), black tea (water + sugar + lighter), field ration ×2 (crackers ×2, jerky, water, tape), water ration ×2, Aquamari (water ×2 + hose), MRE; level 2 (generator 1): kvass ×2 (rye bread + sugar + water), buckwheat ×2 (sugar + water + matches ×2), Hot Rod, vodka, moonshine; level 3 (generator 2; found-in-raid hoses, kettle, capacitors, toothpaste): Survivor's emergency kit ×2, isotonic drink ×2, chocolate ×3.

**Valuables** sell high and are wanted in barters and crafts; the best are Epic and Legendary.

| Valuable | Rarity | Size | Value (₽) | Wanted for |
|---|---|---|---|---|
| Old silver coin | Uncommon | 1×1 | 12,000 | barters (Skier) |
| Old wrist watch | Uncommon | 1×1 | 15,000 | barters (Skier, Therapist) |
| Hard drive | Uncommon | 1×1 | 18,000 | barters (Skier); upgrades (Rest Space 3) |
| Gold chain | Rare | 1×1 | 30,000 | barters (Peacekeeper, Prapor, Skier, Therapist); crafts (Workbench) |
| Antique pocket watch | Rare | 1×1 | 38,000 | barters (Therapist) |
| SSD drive | Rare | 1×1 | 46,000 | barters (Peacekeeper, Skier, Therapist) |
| Secure flash drive | Rare | 1×1 | 85,000 | sells |
| Antique gold coin | Ultra Rare | 1×1 | 88,000 | barters (Therapist); crafts (Medstation) |
| Bronze lion | Ultra Rare | 2×2 | 95,000 | barters (Ragman) |
| Encrypted military hard drive | Ultra Rare | 1×1 | 120,000 | barters (Peacekeeper, Therapist) |
| Roler Submariner gold wrist watch | Epic | 1×1 | 210,000 | barters (Peacekeeper, Therapist) |
| Intelligence folder | Epic | 2×1 | 240,000 | barters (Therapist) |
| Rare coin collection | Epic | 2×1 | 260,000 | barters (Therapist) |
| Physical bitcoin | Epic | 1×1 | 300,000 | sells |
| Graphics card | Epic | 2×1 | 420,000 | barters (Peacekeeper, Skier); crafts (Workbench) |
| LEDX Skin Transilluminator | Legendary | 1×1 | 900,000 | barters (Jaeger) |
| Cold-wallet crypto drive | Legendary | 1×1 | 1,100,000 | sells |

**Barter goods** (junk) are for barters, crafts and hideout upgrades.

| Barter good | Rarity | Size | Value (₽) | Used in |
|---|---|---|---|---|
| Matches | Common | 1×1 | 2,000 | barters (Jaeger, Skier); crafts (Lavatory, Nutrition Unit) |
| Lighter | Common | 1×1 | 2,500 | barters (Jaeger, Prapor, Ragman); crafts (Nutrition Unit); upgrades (Nutrition Unit 1) |
| Soap | Common | 1×1 | 2,800 | barters (Ragman, Therapist); crafts (Medstation); upgrades (Lavatory 2, Medstation 2, Medstation 3, Rest Space 2) |
| Toothpaste | Common | 1×1 | 3,000 | barters (Ragman, Therapist); crafts (Lavatory); upgrades (Lavatory 2, Medstation 2, Medstation 3, Nutrition Unit 3) |
| Cigarettes | Common | 1×1 | 3,000 | barters (Prapor, Ragman, Skier, Therapist) |
| Light bulb | Common | 1×1 | 3,200 | upgrades (Medstation 3, Nutrition Unit 2, Rest Space 1, Rest Space 2) |
| AA battery | Common | 1×1 | 3,500 | crafts (Workbench) |
| Toilet paper | Common | 1×1 | 3,500 | barters (Therapist); crafts (Lavatory); upgrades (Lavatory 1, Lavatory 2) |
| Screwdriver | Common | 1×1 | 3,500 | barters (Mechanic) |
| Pack of nails | Common | 1×1 | 4,000 | barters (Jaeger); upgrades (Rest Space 1) |
| Pliers | Common | 1×1 | 5,000 | barters (Mechanic) |
| Screw nuts | Common | 1×1 | 6,000 | barters (Mechanic, Prapor); crafts (Workbench); upgrades (Workbench 1, Workbench 2) |
| Wires | Common | 1×1 | 7,000 | barters (Mechanic, Ragman); crafts (Lavatory, Workbench); upgrades (Generator 2, Generator 3, Workbench 3) |
| Bolts | Common | 1×1 | 8,000 | barters (Mechanic, Prapor); crafts (Workbench); upgrades (Workbench 1, Workbench 2) |
| Duct tape | Common | 1×1 | 9,000 | barters (Prapor, Ragman, Skier); crafts (Lavatory, Medstation, Nutrition Unit, Workbench); upgrades (Lavatory 1, Lavatory 2, Rest Space 1) |
| Kettle | Uncommon | 1×2 | 9,000 | upgrades (Nutrition Unit 1, Nutrition Unit 2, Nutrition Unit 3) |
| WD-40 can | Uncommon | 1×1 | 11,000 | barters (Mechanic); crafts (Lavatory) |
| Capacitors | Uncommon | 1×1 | 12,000 | barters (Mechanic); crafts (Workbench); upgrades (Nutrition Unit 3) |
| Rechargeable battery | Uncommon | 1×1 | 14,000 | barters (Mechanic); crafts (Workbench); upgrades (Nutrition Unit 2, Rest Space 2) |
| Corrugated hose | Uncommon | 2×1 | 14,000 | barters (Jaeger); crafts (Nutrition Unit); upgrades (Nutrition Unit 1, Nutrition Unit 3) |
| Printed circuit board | Uncommon | 1×1 | 15,000 | barters (Mechanic); upgrades (Rest Space 3) |
| Weapon parts | Uncommon | 2×1 | 15,000 | barters (Mechanic, Prapor); crafts (Workbench); upgrades (Workbench 3) |
| Gunpowder "Kite" | Uncommon | 1×1 | 18,000 | barters (Prapor); crafts (Workbench) |
| Medical tools | Uncommon | 1×1 | 19,000 | barters (Therapist); crafts (Medstation); upgrades (Medstation 3) |
| Fuel can | Uncommon | 2×2 | 30,000 | upgrades (Generator 1, Generator 2) |
| Military power cable | Rare | 1×1 | 36,000 | barters (Mechanic, Prapor); upgrades (Rest Space 3, Workbench 3) |
| Fuel conditioner | Rare | 1×2 | 48,000 | barters (Jaeger); upgrades (Generator 3) |
| Car battery | Rare | 2×2 | 52,000 | upgrades (Generator 3) |
| Electric motor | Rare | 2×2 | 55,000 | barters (Mechanic); crafts (Workbench); upgrades (Generator 3, Workbench 3) |

All of this is data: meds and stims in `data/items/meds/`, food and drink in `data/items/food/`, valuables in `data/items/valuables/`, barter goods in `data/items/junk/`; use, energy and hydration tuning in `data/config/consumables.tres`.

## 14. Economy

| Item | Value |
|---|---|
| Currencies | Roubles (₽), Dollars ($); **Drip** (style points from 360 trick-shot kills and trick-shot quests; nothing spends it yet) |
| Sources | Trader sells, quest rewards, crafting, Bitcoin farm |
| Sinks | Trader buys, insurance, repairs, hideout upgrades, paid extracts |
| FIR | Required for most quest hand-ins and hideout upgrades |
| Starting money | 500,000 ₽ and 0 $ for a new character *(tune)* |

## 15. Technical Notes (Godot 4 / GDScript)

| Area | Approach |
|---|---|
| Item data | `ItemData` custom `Resource` (`scripts/data/item_data.gd`): id, display name, description, category (weapon, ammo, attachment, armor, rig, backpack, helmet, meds, food, valuable, junk, key, container, melee), rarity, grid size, weight, base value, max stack, stats, `loot_weight`, an optional `icon`, and for guns a `weapon` (`WeaponData`). Items live in `data/items/<category>/` as either `.tres` files (one item each, made in the Inspector) or `.json` files (one item or a list; keys listed in `ItemData.from_dict()`, see the README). `ItemDB` loads both and reports bad entries with the file name. Enums are saved as numbers in `.tres` files, so only append new values. Exported builds need `*.json` in the export filter |
| Item icons | Until there's art, `ItemData.get_icon()` makes a placeholder (`ItemIcons`, `scripts/ui/`): the grid footprint at 64 px per cell, a dark box tinted and outlined in the rarity colour (colorblind palette aware) with a symbol per category. Setting `icon` replaces it. Inventory grids draw them with `ItemDraw` |
| Weapons | `WeaponData` `Resource` (`scripts/data/weapon_data.gd`): caliber, weapon skill, class (`weapon_class`: pistol, smg, shotgun, assault_rifle, dmr, bolt_action, lmg), fire rate, auto/semi, magazine, reload and empty-reload time; recoil (vertical, horizontal, recovery rate and delay, camera kick); spread and bloom (base spread, bloom per shot, max bloom, bloom recovery and delay, hip-fire, moving, sprint and roll spread, sway). Modding fields: platform, ergonomics, muzzle velocity, `slots` and `default_mods`; durability: wear per shot, malfunction threshold, jam chance at 0 durability, time to clear a jam. One `.tres` per gun in `data/weapons/`, referenced by the gun's item. Every gun, player's and AI's, is the same `Weapon` node (`scripts/combat/weapon.gd`, scene `scenes/weapons/weapon.tscn`: placeholder model, muzzle, flash, light), so a new gun is just a new data file. `ImpactEffects` (`scripts/combat/`) spawns the hit bursts |
| Content files | Guns: `data/weapons/<gun>.tres` plus their items in `data/items/weapons/<class>.json`; ammo: `data/items/ammo/<caliber>.json` (stats `caliber`, `damage`, `penetration`, `armor_damage`, `fragmentation`, `velocity`, `recoil`, `accuracy`, `ricochet`, `light_bleed`, `heavy_bleed`, optional `pellets`, `pellet_spread`, `noise`, `tracer`); armor: `class`, `durability`, `zones`, `material`, `blunt`, `ricochet`, `destructibility`; parts: `data/items/attachments/<family>_mods.json`. `ItemDB.ammo_of(caliber)` lists a caliber's rounds (commonest first); `LootTable.ammo_for()` picks the everyday one. `Weapon.pull_trigger` fires one `Ballistics.fire` per pellet (`sound` only on the first); `InventoryDrag.can_load()` / `load_into()` load rounds dropped on a gun; `Player` chambers the top round of the magazine and switches round type on reload |
| Gear and upgrades | Helmets use the mod slot tree (`WeaponMods`: `slots_of()` reads a helmet's `"slots"`, `platform_of()` its `"platform"`, `install_defaults()` its `"default_mods"`; `has_slots()`, `is_gear_mod()`); face shields and headsets are attachment items with a `"mod"` stat of kind `face_shield` / `headset`. `ArmorRules.armor_for(gear, part, frontal)` checks face shields before helmets (`is_frontal()`), `Actor.hearing_multiplier()` adds up helmet hearing. `Inventory.accepts()` keeps body armor and armored rigs apart. `GearUpgrades` (`scripts/progression/`, data in `data/config/gear_upgrades.json`): groups, max level, effects (`blunt()`, `ricochet()`, `hearing()`, `weight_multiplier()`, `grid_size()`, `apply()`), sources and limits, `cost()`, `block_reason()`, `upgrade()`, `owned()`. `ItemInstance.upgrade_level` (saved as `"upgrade"`) and `title()`. UI: `GearUpgradeRow` (`scripts/ui/`), `GearUpgradePanel` (`scripts/ui/inventory/`, from the examine panel's UPGRADE), Ragman's UPGRADES tab, the Workbench's GEAR UPGRADES |
| Armor and rounds | `ArmorRules` (`scripts/combat/`): resistance, penetration chance, `resolve()` (penetration, ricochet, blunt, wear, fragmentation, bleed chances) and `effectiveness()` for the charts. `Actor.take_hit(damage, from, position, shot)` resolves a round (`ArmorRules.shot()`) against `worn_gear()` and returns the outcome, which `Ballistics` passes to `on_hit_landed()` (`Player.last_hit` drives the armor hit marker). `BodyHealth.hit` takes the round's bleed chances from the cause. `WeaponStats.shot_speed()` gives a round's speed out of a gun; `Weapon.ammo_recoil()` / `ammo_spread()` apply the round's recoil and accuracy. Armor `ItemInstance`s keep their durability (`is_armor()`, `has_durability()`). `AmmoChart` (`scripts/ui/`) draws the charts; `Trading.offer_level()`, `loyalty_block_reason()` and `update_loyalty()` gate offers by loyalty level |
| Loot tables | `LootTable` Resource, one per container type (`data/loot_tables/*.tres`: base rarity weights, the table's rarity multipliers, categories or an item list, item weights, item count) with `roll_rarity()`, `roll_item()`, `roll()`, `roll_items()` (ready-made, guns loaded) and `chances()`; pass a `RandomNumberGenerator` for repeatable rolls. Container types are `LootContainer` resources (`data/loot_tables/containers/`: their table, grid size, search time, placeholder look, solid or not, bullet material); maps add `MapInfo.loot_multipliers` |
| Item instances | `ItemInstance` (`scripts/inventory/`, RefCounted): the `ItemData`, stack count, grid cell, turned or not, Found-in-Raid (`fir`, plus raid-only `fir_pending` and `brought_in`), its own `InventoryGrid` for rigs / backpacks / containers, for guns the round type and the magazine (ammo instances bottom to top, so each run of rounds keeps its status), `durability` / `max_durability`, and for guns and parts the parts fitted (`mods`, slot id → `ItemInstance`, nested); saved per instance (`to_dict()` / `from_dict()`). *Planned:* rolled bonuses and gunsmith mods (`AffixData` / `GunsmithModData` Resources) |
| Handling tuning | `HandlingConfig` (`data/config/handling.tres`): rarity strength, ergonomics points, the special-modifier rarity factor, ergonomics handling, weight sway and bloom-recovery loss, aimed sway, stance bloom rise, wear spread, recoil jitter, preview shots, skill recoil, stat limits, repair. `data/config/attachment_profiles.json`: each attachment kind's default effects. The `Weapon` node keeps the recoil kick and the bloom (shot and stance) at run time; `Actor.set_stance` each tick feeds it speed, sprint, roll and aim (`aim_blend()`) |
| Trick shots | `SpinTracker` (`scripts/combat/`): feeds on the aim direction each tick and reports a full one-way turn within the spin time. `Player` runs it (`spin_progress()`, `is_spinning()`, `trick_window_left`, signals `trick_shot_ready` and `trick_shot_hit`) and arms the `Weapon` (`trick_armed`; `firing_trick_shot` is true while that shot's hits land); `Ballistics.fire(..., damage_multiplier)` scales the round. `RaidController` adds the bonus XP and Drip and lists the kills for quests (`QuestLog.record_trick_kills()` at settle); `GameState.drip` and `GameState.trick_shots` keep them. HUD: TRICK SHOT READY, banner, sting (`assets/audio/sfx/trick_sting.wav`, from `tools/make_placeholder_audio.py`); reticle: spin ring, gold marker |
| Weapon modding | `WeaponMods` (`scripts/inventory/`): the slot tree (`walk()`, slot paths like `handguard/foregrip`), what fits where, install / uninstall, default parts, capacity, missing parts. A part is an attachment item with a `"mod"` stat: `{kind, fits, slots, modifiers, capacity}`. `WeaponStats` (`scripts/combat/`): profiles and rarity strength, adding up modifiers (empty slots included), `build(gun, skills)` (the modded `WeaponData` copy the `Weapon` node fires with: weight, ergonomics and skills applied), the recoil kick / recovery / pattern and wear spread shared by the gun and the previews, stat rows for the UI, repair. UI (`scripts/ui/inventory/`): `WeaponModScreen` (opened by `InventoryScreen.open_modding()`), `ModSlotView`, `ModPartRow`, `WeaponStatList`, `RecoilPatternView`, `SpreadCircleView`. `Player` equips the modded copy, sight and durability, and writes the wear back to the item after every shot |
| Found in raid | `FoundInRaid` (`scripts/inventory/`): where items come from (`Source`: trader, flea market, quick-buy, insurance, barter, quest reward, craft, starter) and `make()` with the right status; `mark_brought_in()` at raid start, `claim()` when loot reaches the player's inventory (on `Inventory.changed`), `resolve()` at the end |
| Raid | `RaidController` (`scripts/raid/`, a node in the map): clock, raid experience, extraction (`ExtractZone`, `scripts/world/`), ending. `RaidOutcome` settles it (FIR, keep / lose gear, Scav transfer, XP, save). `RaidConfig` (`data/config/raid.tres`): extract time, Run Through limits, XP, search timing. Interactables are in group `interactables` with `interact_text()`, `can_interact()`, `interact()`: `LootBox` (a container of a `LootContainer` type), `LootPickup` (loose item), dead `Bot`s (their `inventory`). `LootSearch` (`scripts/inventory/`) reveals hidden items one by one; the inventory screen runs it while the loot is open (`ItemInstance.hidden`, raid only). The result screen is `ui/raid_result_screen.tscn` |
| Progression | `scripts/progression/`: `Requirement` (item, count, fir), `ItemSearch` (count / take from the stash and character, FIR-only where required), `Trading` (`data/traders/offers.json`), `QuestLog` (`data/quests/*.json`, progress in `GameState.quests`), `Hideout` (`data/hideout/stations.json`, levels in `GameState.hideout`). Screens: TRADERS tabs, `ui/hideout_screen.tscn`; shared widgets `RequirementRow`, `ItemCell`, `FirMark` |
| Inventory | Data (`scripts/inventory/`, no UI): `InventoryGrid` (placement, rotation, stacking, what may go inside what, weight, save), `Inventory` (equipment slots + pockets: slot rules, weight, ammo count / take, starter and Scav kits), `InventoryConfig` (`data/config/inventory.tres`: stash size, weight thresholds). UI (`scripts/ui/inventory/`): `InventoryScreen` (`ui/inventory_screen.tscn`), `InventoryGridView`, `EquipmentSlotView`, `InventoryDrag` (what a drop would do, and doing it), `InventoryDragPreview`, `ItemDraw`, `ItemExaminePanel`; `InventoryLayer` opens it in a raid. Built on Godot's GUI drag & drop (`_get_drag_data` / `_can_drop_data` / `_drop_data`). The player's weight, gun and spare rounds follow its `Inventory` (`Player.set_inventory()`) |
| Globals (autoloads) | Built: `GameState` (profile: faction, level, XP, ₽/$, trader loyalty, inventory, skills, quests, hideout levels, stash grid; plus the raid being set up), `ItemDB` (loads every `ItemData` under `data/items/`), `SaveManager` (JSON save/load), `NoiseSystem` (sounds AI can hear), `CoverSystem` (cover points), `VisionSystem` (Section 13.6: occluders, light, weather, sight lines, the visibility trace), `Settings` (Section 17), `UiSounds` (hover/click sounds for every menu control). Planned: `TraderManager`, `QuestManager`, `HideoutManager` |
| Saves | One JSON file, `user://savegame.json`: `{version, profile, stash}`. Version 6 adds Drip and trick-shot stats (older profiles start at 0). Version 5 saves each gun's parts (nested, each with its FIR status) and durability; older guns load with their default parts at full durability. Version 4 keeps each gun's magazine as runs of rounds with their FIR status, and adds quests and hideout levels (version 3 rounds load as not found in raid). Version 3 saves the inventory and stash as item instances (cell, rotation, contents, loaded rounds, FIR). Version 2 saves (equipment, pockets, skills) are converted: the holster becomes the pistol slot and an Alpha secure container is added; version 1 saves get the starter kit equipped. Written to a temp file first, then swapped in. Bump `SAVE_VERSION` when the format changes |
| Settings | `Settings` autoload: `SCHEMA` lists every option once (tab, default, type, choices); the settings menu is built from it. Saved to `user://settings.cfg` (ConfigFile). Scene settings (shadows, bloom, AO, view distance, DoF) are applied to every light, environment and camera as it enters the tree. Brightness, gamma and colorblind correction are one full-screen shader on top |
| UI | Shared theme `ui/theme/menu_theme.tres` (set as the project theme). Screens opened from a menu extend `MenuScreen` (Esc / B goes back, emits `closed`). Maps are `MapInfo` resources in `data/maps/` |
| Audio | Buses: Master, Music, Effects, Voice, UI, Ambient (`default_bus_layout.tres`). Placeholder music and UI sounds are generated by `tools/make_placeholder_audio.py` |
| Actors | `Actor` (`scripts/actors/actor.gd`) is the shared body: movement, stamina, roll, cover, hitbox, health (a `BodyHealth`), shooting (through its `Weapon`, `$Body/Gun`). `Player` turns input into intents; `Bot` turns AI decisions into the same intents. Each has a separate `Hitbox` (Area3D) that bullets hit and that can shrink independently of the movement collider |
| Player | `scenes/actors/player.tscn`: capsule placeholder; the gun box shows facing. Rules in Section 13 |
| AI | `scenes/actors/bot.tscn` + a `BotProfile` (`data/bots/*.tres`). Behaviour in Section 4 |
| Health | `BodyHealth` (`scripts/actors/body_health.gd`, RefCounted): part HP, blacked-damage spreading, bleeds, fractures, pain, and the death cause. Tuning is a `HealthConfig` resource, `data/config/health.tres`. HUD and death screen draw it with `BodySilhouette` (`scripts/ui/body_silhouette.gd`); the death screen is `ui/death_screen.tscn` |
| Combat tuning | `CombatConfig` resource, `data/config/combat.tres`: roll, cover and bullet values. The numbers are in the file itself, so it can be edited in the Inspector or a text editor |
| Cover | `CoverBox` (`scripts/world/`): @tool box with size + material that builds its own mesh and collision. `CoverSystem` autoload generates `CoverPoint`s every 1.2 m along each side and answers "nearest cover" / "best cover against this threat" |
| Noise | `NoiseSystem` autoload: anything audible calls `emit_noise(position, radius, source, kind)`; bots listen, and the player's vision turns unseen ones into edge markers |
| Vision | `VisionConfig` resource, `data/config/vision.tres` (with an `OpticProfile` per sight). `VisionSystem.view_for(actor)` gives a `VisionView` (cones, awareness, posture); `can_see()` tests a target; `visibility_polygon()` traces the visible area. Occluders (`CoverBox`, `VisionOccluder`) are also on physics layer 4 "vision": sight lines are rays against it at eye height (1.45 m standing, 0.5 m crouched). `PlayerVision` (in the map) draws the area into two SubViewport masks (visible now / seen before, one never cleared) that `assets/shaders/vision.gdshader` reads on a full-screen quad: it rebuilds each pixel's world position from depth and darkens what isn't visible. Actors in group `vision_hideable` get `set_seen()`. `RaidEnvironment` and `DarkZone` are in `scripts/world/` |
| Camera | `TopDownCamera` (`scripts/camera/`): fixed 60° pitch, 18 m back, never turns; follows the player smoothly at any frame rate. `focus_offset` and `zoom` pull it out toward the aim point through a scope |
| Physics | Jolt Physics at 60 ticks/s with physics interpolation on: move bodies in `_physics_process`. Anything moved in `_process` (like the camera), or placed once (tracers), turns interpolation off for itself. Layers: 1 world, 2 actors (movement), 3 hitboxes (bullets), 4 vision (sight blockers) |
| Navigation | The level's `NavigationRegion3D` bakes its navmesh from static colliders when the level loads (0.1 m cells, 0.4 m agent radius); bots steer with `NavigationAgent3D` |
| Naming | snake_case files, PascalCase classes (`class_name`) |
| Engine version | Godot 4.7 (current stable 4.7.2), Forward+ renderer, 1920×1080 base resolution. Commit Godot's `.uid` files |

**Folder layout**

| Folder | Contents |
|---|---|
| `scenes/` | Gameplay scenes: `actors/` (player, bots), `weapons/` (the shared gun scene), `props/` (car), `menu/` (main menu background), `hideout/`, `debug/` (test scenes such as the loot roll check) |
| `maps/` | One scene per raid map (Section 5), plus `test_level.tscn` for movement testing |
| `ui/` | Main menu (entry scene), settings, raid setup, loading, hideout, character, inventory, traders, pause menu, HUD, raid result; `theme/` |
| `scripts/` | All GDScript, mirroring scene folders (`ui/` with `ui/inventory/`, `hideout/`, `actors/`, `maps/`, `menu/`), plus `autoload/` (singletons), `data/` (Resource classes), `inventory/` (item instances, grids, the inventory, found-in-raid rules), `raid/` (raid controller and outcome), `progression/` (trading, quests, hideout), `camera/`, `combat/` (bullets, guns, impact effects, flashbang), `world/` (cover, vision, raid environment) and `debug/` |
| `data/` | `.tres` Resources (and `.json` data): `items/` (one subfolder per category), `traders/` (offers), `quests/`, `hideout/` (stations), `weapons/` (gun handling), `loot_tables/` (`default.tres`, `containers/`), `config/` (tuning), `bots/` (AI profiles), `maps/` (map select info, loot multipliers) |
| `assets/` | `models/`, `textures/`, `audio/` (`music/`, `ui/`, `sfx/`), `shaders/`, `fonts/` |
| `tools/` | Helper scripts run outside Godot (placeholder audio generator) |

**Input actions** (defined in `project.godot`)

| Action | Default | Action | Default |
|---|---|---|---|
| `move_forward` / `move_back` | W / S | `reload` | R |
| `move_left` / `move_right` | A / D | `toggle_inventory` | Tab |
| `shoot` | Left mouse | `interact` | F |
| `aim` | Right mouse (hold): peek from cover | `use_item` | E: quick treatment (Section 13.7) |
| `roll` | Space | `take_cover` | Q |
| `pause` | Esc | `aim_left/right/up/down` | Right stick (controller only) |
| `hotkey_1` … `hotkey_5` | 1–5 | `sprint` | Shift (hold) |
| `crouch` | C (toggle) | Facing | Turns toward where the mouse cursor touches the ground |
| `flashlight` | L | `binoculars` | B |

WASD is screen-relative: W always moves up the screen. Keyboard and mouse keys can be remapped in Settings; controller bindings are listed in Section 17. Menus also use `ui_tab_previous` / `ui_tab_next` (Q / E, LB / RB).

## 16. Menus & Raid Setup

### 16.1 Main Menu

| Element | Detail |
|---|---|
| Background | Slowly panning dusk shot of an industrial yard: low orange sun, fog (volumetric in Forward+), drifting dust, street lamps, depth of field. Ambient music loop on the Music bus |
| Title | Top left |
| Buttons (left, top to bottom) | **ENTER RAID** (largest, highlighted), HIDEOUT, CHARACTER, TRADERS, gap, QUIT (asks "Are you sure?") |
| Settings | Gear icon, bottom right |
| Profile | Top right: faction, level, roubles, dollars |
| Feel | Hover/focus slides a button right and makes it glow, with a hover sound; clicks have their own sound. Hovering also takes keyboard focus, so mouse and controller never highlight two buttons |
| Navigation | Full keyboard (arrows, Enter, Esc) and controller (D-pad / left stick, A, B). Esc / B on the main menu asks to quit |

### 16.2 Character & Traders

| Screen | Shows |
|---|---|
| CHARACTER | Gear (every slot from Section 7 with the loaded ammo or how many items are inside, pockets, carried weight and value), stats (faction, level, XP, health, money, Drip, Trick Shots: 360 kills and hits), skills (Section 12.3, level and progress) and the stash grid side by side. Stash items show at their grid position in their rarity colours with the rarity letter and stack count; hover for details. **INVENTORY** (or Tab) opens the grid inventory (Section 7) with the stash beside it; closing it saves |
| TRADERS | All traders (Section 10) with loyalty level, reputation, money spent and what the next level needs, and tabs: **BUY**, **BARTER** and **TASKS** (Section 11). Requirements show the found-in-raid checkmark when only FIR items count, and how many you have. Jaeger is locked until his quest. Selling comes later |
| HIDEOUT | Every station (Section 9) with its level, the next level's requirements and UPGRADE, and its crafts (inputs → output, the output drawn with its checkmark) with CRAFT |

### 16.3 Enter Raid

| Step | Detail |
|---|---|
| 1. Map | Every map from Section 5 is listed. Maps that aren't built yet show "in development" and can't be picked. Test Yard is playable |
| 2. PMC or Scav | **PMC:** your character and gear; die and lose what you brought. **Scav:** random gear, nothing from your stash at risk; AI Scavs leave you alone unless you shoot them (whoever you shoot turns hostile). AI PMCs are hostile either way |
| 3. Loadout check | Every slot with its loaded ammo and what's inside rigs, backpacks and the secure container, pockets and weight, plus warnings (heavy / overweight too): no armor, no helmet, no meds, no backpack, a gun that can't fire (a missing part) or is worn enough to jam, "if you die, everything you bring is lost" |
| 4. Loading | Map name, side, a gameplay tip and a progress bar while the map loads in the background (shown for at least 1.5 s) |

Back (or Esc / B) steps back one step at a time.

### 16.4 New Character

On first launch the player picks **BEAR** or **USEC** (Section 3); that creates and saves the profile. Starter kit *(tune)*:

| Where | Items |
|---|---|
| Equipped | AK-74N loaded with 5.45x39 PS, Secure container Alpha (2×2) |
| Pockets | 60 × 5.45x39 PS, 1 bandage |
| Stash | AK-74N, 2 × 60 5.45x39 PS, 3 bandages, a tourniquet, a splint, an AI-2 medkit, a bottle of water, 2 packs of crackers, 2 bolts |

### 16.5 Pause Menu (in raid)

Esc or Start pauses the raid and frees the mouse: **RESUME**, **SETTINGS**, **LEAVE RAID** (asks first; counts as missing in action: a PMC loses everything but the secure container, and nothing becomes found in raid), **QUIT GAME** (asks first). Esc / Start / B closes it. It can't be opened once you're dead. Dying shows the death screen (Section 13.5) with **BACK TO MENU**.

## 17. Settings

Settings open from the main menu (gear icon) and the pause menu. Six tabs; edits only take effect on **Apply**, which also saves `user://settings.cfg`. **Reset to Defaults** resets the open tab; **Back** with unapplied edits asks to discard them. Q / E or LB / RB switch tabs.

| Tab | Options (default) |
|---|---|
| Graphics | Display mode (Windowed / Borderless / Fullscreen), resolution (windowed only), monitor, V-Sync (on), FPS limit (30/60/120/144/240/Unlimited), render scale (100%), quality preset (Low/Medium/High/Ultra, High) which sets: shadows, textures, anti-aliasing (Off/FXAA/MSAA/TAA), ambient occlusion, view distance, depth of field quality. Also bloom, motion blur, brightness and gamma |
| Audio | Master (80%), music (50%), effects, voice, interface (70%), ambient volume; output device; mute when the window loses focus (on) |
| Controls | Mouse sensitivity (1.0), aim (optics) sensitivity (0.6), invert mouse; hold or toggle for sprint (hold), crouch (toggle) and aim (hold); key remapping for every action with conflict warnings and per-key reset; controller on/off, sensitivity and stick dead zone (20%) |
| Gameplay | Camera shake (100%), damage numbers (off), hit markers (on), auto-reload (on, Section 13.4), auto-equip on pickup, confirm before selling valuables, language, units (metric / imperial) |
| Interface | HUD scale, HUD opacity, FPS counter, reticle style (dot / cross / circle / bloom: a circle that shows your spread, the default) and color, colorblind mode (protanopia / deuteranopia / tritanopia), subtitles and subtitle size |
| Accessibility | Reduce flashing effects (dimmer tracers, smaller muzzle flash without light, steady hit markers), turn off screen shake, high-contrast outlines on enemies (red; neutral bots cyan), press instead of hold (sprint, crouch and aim become toggles) |

| Rule | Detail |
|---|---|
| In-raid aiming | The mouse is captured during a raid and moves an on-screen reticle, so mouse sensitivity, aim sensitivity (while aiming/peeking) and invert apply. A controller's right stick points the reticle out from the player |
| Colorblind modes | A screen-wide correction filter, plus a rarity palette that stays distinct for that type of color blindness (Section 6.2). Rarity letters (C, U, R, UR, E, L) are shown next to colors, so color is never the only cue |
| Controller bindings | Left stick move, right stick aim, RT shoot, LT aim/peek, A roll, B crouch, X reload, Y interact, LB take cover, RB use item, L3 sprint, Back inventory, Start pause, D-pad hotkeys 1–4, R3 hotkey 5. Flashlight and binoculars have no controller button yet (every button is taken). Not remappable yet |
| Not active yet | Motion blur (Godot has no built-in motion blur), auto-equip, confirm selling, extra languages and subtitles: stored, and shown as "takes effect once..." in the menu |

## 18. Changelog

| Date | Change |
|---|---|
| 2026-10-11 | Initial design document |
| 2026-10-11 | Added rolled loot (6.3): affixes, traits, named Legendaries |
| 2026-10-11 | Reworked 6.3 for realism: grounded craftsmanship bonuses, gunsmith mods with trade-offs, no damage/pen rolls |
| 2026-10-11 | Godot project scaffold: folder layout, input actions, main menu |
| 2026-10-11 | Project targets Godot 4.7 (was 4.3) |
| 2026-10-11 | Autoloads `GameState`, `ItemDB`, `SaveManager` (replace planned `Stash`/`SaveSystem`); `ItemData` resource, 5 example items, starting money |
| 2026-10-11 | Player movement (walk, sprint, crouch, stamina, noise radius), top-down follow camera, stamina HUD, test level; Play opens the test level until the hideout exists |
| 2026-10-11 | Combat roll, cover system (low/tall, peek, slide, shared cover points), hitscan bullets with wood/concrete/metal penetration, Scav and PMC AI (vision, hearing, cover, peeking, PMC dodge rolls), `combat.tres` tuning file, 5.45 BS ammo |
| 2026-10-11 | New main menu (dusk backdrop, music, profile, quit confirm, faction pick), Enter Raid flow (map, PMC/Scav, loadout check, loading), Character and Traders screens, Settings (six tabs, `user://settings.cfg`), in-raid pause menu and reticle, controller support, starter kit, save version 2 |
| 2026-10-11 | Guns: `WeaponData` resource + shared `Weapon` node (fire rate, auto/semi, magazine, R reload with tactical/empty times, spread from movement and recoil), muzzle flash, hit sparks, HUD ammo panel, reload ring, auto-reload setting active. Bots use the same guns and reload behind cover; their spread is now aim error on top of the gun (Scav 2.8°, PMC 0.3°) |
| 2026-10-12 | Body-part health (head, thorax, stomach, arms, legs; blacked parts spread damage), light/heavy bleeds, fractures, pain, weapon sway, HUD silhouette and pain vignette, death screen with cause of death, `health.tres`. Replaces single health pools; player aims at the chest of whoever is under the reticle |
| 2026-10-12 | Vision (13.6): Project Zomboid-style cone + awareness circle, 2D shadow casting, fog-of-war shader with remembered layout, enemies hidden outside view, low cover blocks only crouched, time of day / dark rooms / flashlight, fog and rain, pain / head injury / flashbang, sound markers, optics and binoculars with camera pull-out, AI on the same rules (scoped PMCs), `vision.tres`; AI vision values moved there from bot profiles |
| 2026-10-12 | Item system: categories renamed food and junk (same numbers), items in `.tres` or JSON, `loot_weight`, rarity-coloured placeholder icons, 46 new items (52 in all) across every category and rarity, PM pistol. Loot tables: base weights 55 / 25 / 12 / 5 / 2.5 / 0.5, container types and map multipliers (Labs Epic+ ×2), debug roll scene |
| 2026-10-12 | Grid inventory (Section 7): Tab in raid, CHARACTER → INVENTORY out of raid with the stash; drag and drop, R to turn, stacking, Shift-drag splits, right-click examine, rigs / backpacks / containers with their own grids, rarity-coloured items. Slots are now Primary, Secondary, Pistol (was Holster), Melee, Helmet, Body armor, Rig, Backpack, Secure container (Earpiece and Face cover dropped). Weight slows you from 25 kg and makes you overweight at 40 kg (`inventory.tres`); reloads use rounds you carry. New items: hatchet (melee category), Secure containers Alpha and Beta (55 items). Starter kit adds the Alpha container. Save version 3 (item instances), version 2 saves converted |
| 2026-10-12 | Found in Raid (Section 2.1): loot picked up, looted from containers and bodies or taken off enemies becomes FIR when you extract (faded checkmark until then); dying, MIA and Run Through give nothing; bought, bartered, quick-buy, insurance and reward items never FIR; crafts always FIR; brought-in items keep their status. Stacks merge only with the same status; containers and magazines keep it per item / per round (UNLOAD). Checkmark with "Found in raid" tooltip, examine status, FIR-only stash filter. Raids now end for real: extract zone (7 s), raid clock, Run Through, raid results written back (PMC death loses all but the secure container; Scav extract moves loot to the stash), LEAVE RAID is MIA, raid result screen, raid XP. In-raid looting: F searches containers and bodies (bots carry lootable kits) and picks up loose items. Traders BUY / BARTER / TASKS, 5 hand-in quests, HIDEOUT with 4 stations and crafts. Save version 4 |
| 2026-10-12 | Containers: crate, toolbox, jacket, weapon box, medical bag (was medical case), safe, filing cabinet (and duffle bag), each with its own loot table, grid, search time and look; big ones are solid (block movement and bullets, baked into the AI navmesh). Searching: F reveals items one by one, faster for small ones, while the container or body is open; hidden items can't be moved. Loose loot rolls from its own table with a 70% spawn chance. Bodies carry full kits (Scav helmet / hatchet / bag, PMC pistol and meds) whose spare rounds come out of their rig as they reload. New items: pliers, screwdriver, nails, hose, medical tools, secure flash drive, intelligence folder (62 in all) |
| 2026-10-12 | Weapon modding (Section 12.1): slot trees with nested slots (rail handguards and dust covers add foregrip, tactical and top-rail slots), 31 new weapon parts (36 with the sights and foregrip) across muzzle, barrel, handguard, foregrip, stock, pistol grip, receiver, sight, tactical and magazine slots, for the AK-74N and PM. Parts change recoil, ergonomics, spread, muzzle velocity, aim speed, noise, jam chance, wear, weight and magazine size; bonuses grow with rarity (×1 to ×2); empty slots matter (no stock, no barrel). Modding screen out of raid (MODIFY): drag parts onto slots, live stat preview with deltas, REPAIR. Durability: every shot wears the gun, worn guns jam (R clears), found and AI kit guns come worn. Suppressors shorten how far shots are heard; the sight fitted is the one you aim through. Mechanic and Skier sell parts. Gun items now weigh and cost their bare receiver plus their parts (an AK is still 3.2 kg, 30,000). Save version 5 (93 items) |
| 2026-10-12 | Weapon handling rework (Sections 12.1, 13.4): recoil split into vertical (muzzle climb: the aim moves out along the aim direction and rounds fly higher) and horizontal (random side kick), with recoil recovery pulling the aim back after each shot; bloom replaces recoil spread (grows per shot up to max bloom, while moving, sprinting, rolling and hip-firing; shrinks at bloom recovery); the bloom reticle is now a circle at the kicked aim point. Attachments change ten handling stats from a per-kind profile table (`attachment_profiles.json`) with rarity strength Common 4% to Legendary 23% and fixed downsides; heavier builds sway more and recover bloom slower; low durability adds spread; weapon skills (new: Pistols) and Strength reduce recoil. Modding screen: recoil pattern preview and spread circles with before / after numbers. Tuning in `handling.tres` and the gun `.tres` files. New parts: polymer foregrip and rubberized AK grip (Common), AK competition brake (Legendary) (96 items) |
| 2026-10-12 | 360 trick shots (Section 13.4.1): sweep the reticle a full turn one way within 1.5 s (rolling or not) with a bolt-action rifle or DMR and a TRICK SHOT READY window opens for 1 s; its first shot deals +50% damage on the round (before armor), fired from the hip with full bloom (no aiming while spinning). Gold hit marker, "360!" popup, sound sting, kill banner, +250 XP and +25 Drip per kill. Drip (new), Trick Shots on the character screen, three trick-shot quests (Showboat, Around the World, Spin Doctor; new quest objective type `trick_kill`). New guns: Mosin (bolt-action) and SVD (DMR) with 7.62x54R LPS and an SVD magazine (100 items); new skills Bolt-action rifles and Marksman rifles. Tuning per gun (`trick_spin_time`, `trick_window`, `trick_damage_bonus`) and in `raid.tres`. Save version 6 |
| 2026-10-12 | Starter arsenal (Section 6.4; the ammo table referred to as "3.2a" didn't exist in this document, so it was written there): 18 new guns, 22 in all across pistols, SMGs, shotguns, assault rifles, DMRs, bolt-action rifles and LMGs (Vektor P9, Bastion 45, Strelka MP, Hornet SMG, Wasp PDW, Brigand 45, Warden 870, Tempest S12, Sentinel AR, Tundra 47, Halcyon B5, Partisan, Longbow DMR, Huntsman 700, Leviathan .338, Grizzly 74, Bulwark 249, Anvil PK); 10 calibers with 3–5 rounds each (45 rounds; new `armor_damage` stat on every round, Common everyday rounds, Epic/Legendary best AP); 143 new weapon parts (183 in all) with standard parts for every gun and upgrades from Common to Legendary, plus AK, AR, STANAG and caliber parts shared across guns. Shot shells fire 8 pellets (chokes tighten them: new `pellet_spread` part modifier, shown for shotguns), subsonic rounds are quieter (`noise` ammo stat), rounds dragged onto a gun load it, reloading with none of the gun's round type left switches to another of its caliber, found guns come loaded with their caliber's everyday round. Mosin and SVD get a muzzle slot. New weapon classes `smg`, `shotgun`, `lmg` and skills SMGs, Shotguns, Machine guns. Traders sell most of it (Jaeger has hunting stock ready for when he unlocks). 302 items |
| 2026-10-12 | Ammo rework (Section 6.4; the request's ammo table didn't come through, a "[paste the table]" placeholder, so the rounds in Section 6.4 were kept and extended): every round now has fragmentation, velocity, recoil, accuracy, ricochet and light/heavy bleed chances on top of damage, penetration and armor damage (50 rounds, 4–6 per caliber; 5.45 PS and BS moved into `545.json`); 5 new tracer rounds (9x19, 5.56, 7.62x39, 7.62x51, 7.62x54R; 5.45 BT is one too). Armor works: helmets and vests stop rounds on the parts they cover by penetration against class and wear, push blunt damage through or let them ricochet, and wear down (durability saved per item). Soft rounds fragment and bleed, AP rounds get through armor for less flesh damage. Velocity sets range, damage falloff and energy through wood; rounds change recoil and spread. Ammo charts (examine panel for guns and rounds; new AMMO tab on the trader screen) compare every round of a caliber with armor class 1–6 squares. Ammo offers need trader loyalty (LL1 cheap, LL3–4 AP; Legendary rounds aren't sold); loyalty levels now rise when you meet their requirements. Workbench level 3 crafts the Legendary AP rounds. Armor hit marker and damage numbers. 307 items |
| 2026-10-12 | Gear and gear upgrades (Section 12.2): armor classes 1–6 across 13 vests, 7 armored rigs and 10 helmets (penetration and durability as in Section 6.4), new zones (face for frontal head hits, arms for the heaviest suits), helmet face shield and headset slots (7 face shields, 6 headsets; helmets muffle hearing, headsets amplify it for the player's sound markers and AI hearing), armored rigs that can't be worn with body armor, plain rigs and backpacks from 3×1 to 8×8: 47 new gear items across every rarity, plus 5 upgrade materials. Upgrades +1…+5 (max by rarity: Common +1 … Epic/Legendary +5) at Ragman (by loyalty level) or the Workbench (by its level, cheaper): +10% durability and −4% blunt per level for armor, +6% ricochet for helmets and face shields, lighter and roomier rigs and backpacks, +5% hearing for headsets; roubles plus barter items per level (`data/config/gear_upgrades.json`). UPGRADE in the examine panel, Ragman's UPGRADES tab, the Workbench's GEAR UPGRADES; "+N" on upgraded items. 359 items |
| 2026-10-13 | Consumables (Section 13.7): meds that work (bandages and army bandages stop light bleeds, Esmarch and CAT tourniquets heavy ones, the CALOK-B hemostat either; splints set fractures; painkillers numb pain and let broken legs sprint; AI-2 and car (small) and Salewa, IFAK, AFAK and Grizzly (large) medkits with HP pools that pay for bleeds and heal one part a use; CMS and Surv12 surgery restores blacked parts at a max HP cost), 9 stimulants with timed effects (regeneration, painkiller, hemostatic, stamina, speed, recoil, sway) and side effects (tremor, thirst, hunger, toxin). Every item has a use time and can be interrupted (shooting, rolling, sprinting, reloading, aiming, a hit, E); E quick-treats with what's in your pockets, rig and secure container; USE in the examine panel. Energy and hydration drain in raids (faster sprinting), make you hungry or thirsty when low and hurt at 0, carry over between raids and recover out of raid; 14 foods and drinks. New valuables (watches, coins, hard drives, crypto drive) and barter goods (batteries, fuel conditioner, toothpaste, soap, cigarettes, lighter and more) in barters, crafts and hideout upgrades; Medstation level 3, Nutrition Unit; best meds and valuables Epic or Legendary. HUD energy and water bars, effects, E hint, use bar; uses left on items; `consumables.tres`. 412 items. Save adds energy and hydration |
| 2026-10-13 | Energy and hydration system (Section 13.7). The request's food table came through as a "[paste the table]" placeholder, so the table was built from the items it named (crackers, sugar, jerky, vodka, moonshine, water, coffee, energy drink, Field ration pack, Survivor's emergency kit) and the existing food, plus 15 originals: 34 foods and drinks with per-use energy and hydration, uses, use time, rarity, size and side effects. Drain: −1 energy / −2 hydration a minute walking, × activity (still 0.5, crouched 0.75, sprint 2, roll 3), load, injuries and the map's climate (hot Shoreline Resort and Factory, cold Woodland); below 30 slower stamina recovery and a HUD warning (was 25, with sway); at 0 Exhaustion / Dehydration drain HP from every body part (was the stomach), add sway and blur and narrow vision. Hideout refill 0.5 a minute, faster with the Nutrition Unit (now 3 levels, 14 crafts from junk) and the new Rest Space. Metabolism skill levels from eating and drinking (new `Skills`). Food containers: fridge, kitchen cabinet, store shelf, gas station counter (placed in the Test Yard); crates and duffle bags no longer hold food; Scavs always carry a snack. Hover preview of energy and hydration on food. Crafts that make several non-stacking items give them all. 432 items |
