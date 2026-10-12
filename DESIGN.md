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

**Test Yard** (playable): 15-minute raid, one always-open extract (the green ring in the north-east corner), one of each container type (crate, toolbox, jacket, weapon box, medical bag, safe, filing cabinet, duffle bag; rolled from their tables at raid start) and eight loose loot spots. Containers are placeholder shapes in each type's colour.

## 6. Items

### 6.1 Categories

| Category | Examples | Key stats |
|---|---|---|
| Weapons | Pistols, SMGs, shotguns, ARs, DMRs, bolt-actions | Damage, fire rate, recoil, ergonomics, accuracy, caliber |
| Ammo | 9x19, 5.45, 5.56, 7.62, 12ga | Damage, penetration, armor damage |
| Attachments (weapon parts) | Muzzle devices, barrels, handguards, foregrips, stocks, pistol grips, dust covers, sights, lasers, magazines | Vertical and horizontal recoil, recoil recovery, base spread, bloom per shot, max bloom, bloom recovery, hip-fire spread, ergonomics, weight; some also muzzle velocity, aim speed, noise, jam chance, wear, magazine size (Section 12.1) |
| Armor | Vests (class 1–6) | Class, durability, zones, move penalty |
| Rigs | Chest rigs, armored rigs | Grid slots, (armor class if armored) |
| Backpacks | Sling → large raid packs | Grid size, weight |
| Helmets | Bump caps → class 4–5 helmets | Class, durability, ricochet, hearing penalty |
| Meds | Bandage, tourniquet, splint, medkit, surgical kit, painkillers, stims | Heals HP / fixes bleed, fracture; uses |
| Food & Drink | Crackers, canned meat, water, energy drink | Energy, hydration |
| Valuables | Gold chain, Bitcoin, LEDX, GPU, secure flash drive, intelligence folder | High sell value, small size |
| Junk / Barter | Bolts, screws, wires, duct tape, fuel, pliers, screwdriver, nails, hose, medical tools | Used in barters, crafts, hideout upgrades |
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

**How a roll works:** every container type has its **own loot table** (`data/loot_tables/<type>.tres`; loose loot uses `loose_loot.tres`). Weight of each rarity = base weight (55 / 25 / 12 / 5 / 2.5 / 0.5) × the table's rarity multipliers × the map's multiplier. Pick a rarity by weight, then an item of that rarity the table can hold: its item list if it has one (a toolbox holds tools), else its categories (a medical bag holds meds). Each item's `loot_weight` and the table's `item_weights` set how often it comes up among its rarity; `loot_weight` 0 = never from loot (quest items, boss uniques). If a table can't hold any item of some rarity (a medical bag has no Epic meds), that rarity's weight is 0, so the other rarities share its chance. Stackable items (ammo) come as a partial stack (a fifth to a half of a full stack); guns come loaded.

| Container *(tune)* | Holds | Items | Rarity multipliers (C / U / R / UR / E / L) | Grid | Search time | Solid |
|---|---|---|---|---|---|---|
| Loose loot (on the ground) | Anything | 1 (70% of spots) | 1 / 1 / 1 / 1 / 1 / 1 | — | — | — |
| Crate | Ammo, food, junk, melee | 1–4 | 1.1 / 1 / 1 / 0.9 / 0.8 / 0.6 | 5×4 | ×1 | Yes (wood) |
| Toolbox | Bolts, screws, wires, tape, pliers, screwdriver, nails, hose, weapon parts, electric motor | 1–3 | 1 / 1 / 1.1 / 1.2 / 1 / 1 | 4×2 | ×1 | No |
| Jacket | Ammo, meds, food, valuables, junk, keys | 0–2 | 1 / 1 / 1 / 1 / 1 / 1 | 2×2 | ×0.8 | No |
| Weapon box | Weapons, ammo, attachments | 1–2 | 0.8 / 1 / 1.3 / 1.3 / 1.2 / 1 | 6×3 | ×1.1 | Yes (wood) |
| Medical bag | Meds, medical tools | 1–3 | 0.8 / 1.1 / 1.3 / 1.5 / 1 / 1 | 3×3 | ×1 | No |
| Safe | Valuables, keys | 1–2 | 0.3 / 0.8 / 1.5 / 2.5 / 3 / 3 | 3×3 | ×1.4 | Yes (metal) |
| Filing cabinet | Keys, flash drives, intelligence folders (×2 likely), paper, matches, gold chains | 1–3 | 1 / 1 / 1.2 / 1.3 / 1.2 / 1 | 4×4 | ×1.2 | Yes (metal) |
| Duffle bag | Ammo, attachments, meds, food, valuables, junk | 1–3 | 1 / 1 / 1 / 1 / 1 / 1 | 4×3 | ×1 | No |

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
| Slots | Primary weapon, Secondary weapon, Pistol, Melee, Helmet, Body armor, Tactical rig, Backpack, Secure container, plus Pockets (4 × 1×1). Pistols (`"class": "pistol"`) go only in the Pistol slot, other guns in Primary / Secondary. The gun in hand is the primary, else the secondary, else the pistol |
| Rarity | Every item's background and border are its rarity colour, with the rarity letter in the corner so colour is never the only cue (colorblind palette aware) |
| Examine | Right-click: icon, name in its rarity colour, rarity, category, size, weight, value, stack, and what matters for its kind (gun handling with its parts, durability and jam chance, loaded rounds; a weapon part's kind, the guns it fits and what it changes; ammo damage and penetration, armor class and durability, what meds treat, a container's grid and contents, sight, Found in Raid). Out of raid a gun's panel has **MODIFY** (Section 12.1). *Planned:* unknown items must be examined first to reveal their name and value |
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

**Built so far** (`data/hideout/stations.json`, HIDEOUT screen): Generator, Medstation, Workbench and Lavatory. Each starts unbuilt; level 1 costs roubles and ordinary items, level 2+ asks for found-in-raid items (and sometimes another station's level). Levels unlock crafts (inputs → one item, into the stash, **found in raid**). Upgrades and crafts are instant for now; build and craft timers, trader LL requirements and the other stations are planned.

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

**Built so far** (`data/traders/offers.json`, TRADERS screen tabs): **BUY** (roubles or dollars; counts toward money spent for loyalty), **BARTER** (items for an item; some ask for found-in-raid items) and **TASKS** (Section 11). What you get goes to the stash and is never found in raid. Mechanic sells AK and PM parts (compensator, short barrel, rail handguard, grips, stocks, railed dust cover, magazines, laser) and barters the match barrel and the AK suppressor; Skier sells rail parts and the quad rail and barters the PM suppressor. Guns are repaired in the modding screen for roubles (Section 12.1). Selling, trader repair, insurance, LL-gated stock and restocks are planned.

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

**Built so far** (`data/quests/quests.json`, the trader's TASKS tab): hand-in quests. Accept, then HAND OVER per objective (part now, the rest later) from the stash and your character, including inside containers; FIR objectives only take items with the checkmark. TURN IN when everything is handed over: roubles, experience, reputation with the trader, and reward items in the stash (never FIR). Prior-quest prerequisites work. Five quests: Scrap Run (Prapor), Shortage and Sanitary Standards (Therapist), Textile (Ragman), Gunsmith Part 0 (Mechanic).

## 12. Weapon & Gear Upgrades

### 12.1 Weapon Modding

| System | Detail |
|---|---|
| Slot tree | Each gun's `WeaponData` lists its slots. AK-74N: muzzle, barrel, handguard, pistol grip, stock, dust cover (receiver), side mount (sight), magazine. PM: muzzle, grip, magazine. Parts can bring slots of their own: a rail handguard adds a foregrip and a tactical slot (the quad rail a top rail for a sight too), a railed dust cover a top rail. A part taken off keeps whatever is on it. Guns come with their default parts (`default_mods`) |
| Part kinds | Muzzle device, barrel, handguard, foregrip, stock, pistol grip, receiver, sight, tactical device, magazine |
| Compatibility | A slot lists the kinds it takes; a part lists the platforms it fits (`"fits": ["ak"]`). Rail parts (foregrips, tactical devices, sights) leave `fits` out and go in any slot of their kind |
| Handling stats | Every part can change the ten handling stats: **vertical recoil %**, **horizontal recoil %**, **recoil recovery %**, **base spread %**, **bloom per shot %**, **max bloom %**, **bloom recovery %**, **hip-fire spread %**, **ergonomics** (points) and **weight** (% of the part's own weight). What a part does starts from its kind's **profile** (the table below, `data/config/attachment_profiles.json`); a part's own `"handling"` replaces single entries (a skeleton stock trades recoil for ergonomics). The stock parts a gun comes with are "standard": no effects, so a stock gun handles exactly as its `.tres` says |
| Rarity | A positive profile value is a bonus: that many times the part's rarity strength, **Common 4%, Uncommon 8%, Rare 12%, Ultra Rare 16%, Epic 20%, Legendary 23%** (so most Common bonuses land around 3–5% and Legendary ones around 20–25%; ergonomics: 0.25 points per percent). A negative value is a fixed downside that doesn't grow with rarity (a suppressor's −8 ergonomics). Rarer parts are also lighter. *(tune: `handling.tres`)* |
| Other effects | A part's own `"modifiers"`: muzzle velocity, aim speed, noise, jam chance, wear, fixed per part with bonuses × 1 / 1.15 / 1.3 / 1.5 / 1.75 / 2 by rarity (an Epic suppressor's −40% noise is −70%). Magazines set the capacity; sights the optic |
| Ergonomics | 0–100, handling: each point below the gun's default is 1% more spread while moving, sprinting and rolling, 1% more sway and 1% slower to raise a sight (each point above, 1% better) |
| Weight | Every kg the build weighs over the gun with its default parts adds 0.35° of sway and makes bloom recover 15% slower (lighter builds the reverse), so stacking every part isn't always best *(tune)* |
| Skills | The gun's weapon skill (Assault rifles for the AK, Pistols for the PM) takes 0.5% off vertical and horizontal recoil per level, Strength 0.25% per level, up to 15% together (Section 12.3) |
| Wear | Below 70 durability a gun spreads more, up to +1.5° at 0 *(tune)* |
| Empty slots | Some slots change the gun while empty: an AK without a stock climbs 45% more, kicks 30% more sideways, recovers 30% slower and blooms 25% wider (but handles +8 ergonomics); without a pistol grip −15 ergonomics, +10% side kick, +15% hip-fire spread; without a muzzle device +8% climb; without a handguard −10 ergonomics, +10% hip-fire spread. Without a barrel, dust cover or magazine it can't fire (HUD: "NO BARREL") |
| Modding screen | Out of raid, right-click a gun → **MODIFY**. Slot tree on the left (nested slots indented under their part), the gun's stats in the middle, every part you own that fits it on the right (stash, pockets, rig, backpack, inside containers; click a slot to list only its parts). Drag a part onto a slot to fit it (green: fits, red: doesn't); what was in the slot goes to the stash. Drag a part off onto the list, or double-click it, to take it off. Double-click a listed part to fit it to its best slot. Hovering a part, or dragging one over a slot, previews it: the new values with ▲ / ▼ and the change, green if better and red if worse. A smaller magazine sends the rounds that no longer fit to the stash |
| Recoil pattern | Above the stats: where each shot of a full-auto spray (30 rounds, or a magazine) goes relative to the aim, from the same recoil, recovery and (seeded) side kicks the gun uses in a raid. While previewing, the pattern with the change (amber) is drawn over the current one (grey), with before / after numbers for climb, side kick and recovery |
| Spread circles | Beside it: the cone at aimed (base spread + wear), hip-fire and full bloom, drawn like the bloom reticle; while previewing the new circles over the old, with before / after numbers and how long full bloom takes to settle |
| Stats shown | Ergonomics, vertical recoil, horizontal recoil, recoil recovery, base spread, hip-fire spread, bloom per shot, max bloom, bloom recovery, sway, worn spread, muzzle velocity, aim time, how far a shot is heard, magazine, fire rate, weight, durability, jam chance per shot. Skills are included |
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

Parts come from Mechanic and Skier (Section 10), weapon boxes and duffle bags, and the guns you find.

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
| Strength | Carrying weight, melee | Carry more, throw farther; 0.25% less recoil per level |
| Endurance | Sprinting | More stamina |
| Vitality | Taking damage | Lower bleed chance |
| Metabolism | Eating/drinking | Slower energy/hydration drain |
| Search | Searching containers | Faster search, rarer loot (+% capped) |
| Weapon class skills | Using weapon type (built: Assault rifles, Pistols) | 0.5% less recoil per level (up to 15% with Strength); reload speed planned. Levelling isn't built yet |

## 13. Health, Movement & Combat

| System | Detail |
|---|---|
| Body parts | Head, Thorax (death at 0), Stomach, L/R Arm, L/R Leg (Section 13.5) |
| Conditions | Light bleed, heavy bleed, fracture, pain (Section 13.5); dehydration, exhaustion later |
| Energy / Hydration | Drain over time; 0 = HP loss |
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
| Noise | Every shot is a 60 m noise, × the gun's noise from its parts (a suppressed AK: 18 m) |
| Health | Body parts for everyone, player and AI (Section 13.5). A round damages the part it lands on |
| Guns | Each gun's handling is a `WeaponData` file (Section 15), changed by its parts (Section 12.1). Damage and penetration always come from the ammo |
| Durability and jams | Each shot wears the gun; worn guns jam. A jammed gun won't fire or reload until R clears it (1.6 s; the stuck round is lost). A gun missing a barrel, dust cover or magazine can't fire (Section 12.1) |
| Fire rate | Rounds per minute. Automatic guns fire while the trigger is held; semi-auto guns fire once per click |
| Magazine | Each shot uses a round; the magazine fitted sets how many it holds. Can't fire while reloading |
| Reload (R) | Tactical reload (rounds left) or a slower empty reload (a round has to be chambered). Tops the magazine up from spare rounds of the loaded type. You can move, roll and use cover while reloading |
| Spare ammo | In a raid: the pocket rounds matching the loaded ammo. Rounds used aren't taken out of your profile yet |
| Auto-reload | On by default (Settings > Gameplay): pulling the trigger on an empty magazine reloads. Off: the HUD says "Magazine empty: press R to reload". No spare rounds: "Out of ammo" |
| Recoil | Each shot kicks the aim. **Vertical recoil** is muzzle climb: the aim moves out along the aim direction and rounds fly higher, so a long burst at range ends up over the target's head. **Horizontal recoil** kicks left or right at random. **Recoil recovery** pulls the aim back after each shot (it starts a moment after the shot, so full-auto keeps climbing until recovery and kick balance out). You can counter the side kick by moving the mouse; the reticle shows where the next shot goes. AI fight off part of the kick (Scav 30%, PMC 60%) |
| Spread (bloom) | Each shot lands at random inside a cone: **base spread** + wear + **bloom** + the shooter's aim error (AI only). Bloom grows with every shot (**bloom per shot**, up to **max bloom**), while moving (full at sprint speed), sprinting, rolling, and when **hip-firing** (until the sight is up: aim time decides how fast it goes). It shrinks at the gun's **bloom recovery** once you stop shooting (a short pause after the last shot) or stop moving. AI always fire aimed |
| Sway | The aim drifts slowly side to side: the gun's own sway (heavier builds more, less with the sight up) plus injuries (Section 13.5) |
| Feedback | Muzzle flash with a brief light, a small kick of the gun model and camera shake (scaled with vertical recoil). A burst of particles where a round hits: grey dust (concrete), sparks (metal), splinters (wood), red (a body). The **bloom reticle** is a circle the size of the real spread cone at the aim point, growing and shrinking live; it sits where the next shot goes (the cursor moved by recoil and sway), with a faint dot on the cursor itself while they move it. A ring fills around it while reloading or clearing a jam |
| HUD | Bottom right: gun name, rounds in the magazine (amber at a third or less, red when empty), magazine size, spare rounds, loaded ammo and penetration, auto/semi, and a reload bar. In red instead of the ammo line: "JAMMED · R to clear", "CLEARING JAM", or a missing part ("NO MAGAZINE") |

| Ammo | Damage | Penetration | Wood |
|---|---|---|---|
| 5.45x39 PS | 50 | 28 | Stopped |
| 5.45x39 BS | 40 | 45 | Goes through (24 damage after) |

| Gun *(tune, `data/weapons/`)* | Fire rate | Mode | Magazine | Reload / empty | Climb / side kick / recovery | Base spread | Bloom per shot / max / recovery | Hip-fire | Moving / sprint / roll | Sway |
|---|---|---|---|---|---|---|---|---|---|---|
| AK-74N | 650 rpm | Auto | 30 | 2.3 s / 2.9 s | 0.55° / ±0.35° / 7 per s after 0.06 s | 0.5° | +0.35° / +4.5° / 9°/s after 0.2 s | +1.8° | +3.0° / +2.0° / +6.0° | 0.2° |
| PM | 450 rpm | Semi | 8 | 1.8 s / 2.3 s | 1.0° / ±0.55° / 9 per s after 0.05 s | 0.8° | +0.8° / +5.0° / 12°/s after 0.2 s | +1.2° | +3.5° / +2.0° / +6.0° | 0.12° |

### 13.5 Health & Status Effects *(tune)*

Every actor, player and AI, has the same body. There's no armor or meds yet.

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
| Light bleed | 35% chance per hit (at 50 damage; scaled by damage, up to ×1.5). Loses 0.5 HP/s from that part |
| Heavy bleed | 12% chance per hit (same scaling); replaces a light bleed on that part. Loses 1.5 HP/s |
| Bleeding | Doesn't stop on its own. On a blacked part, bleed damage spreads like any other damage. Treatment comes with meds |
| Fracture | 25% chance per hit to an arm or leg (same scaling). Leg (fractured or blacked): 70% speed, no sprinting, no rolling. Arm (fractured or blacked): +2° weapon sway each |
| Pain | While any part is fractured or blacked. +1° weapon sway; for the player, dark red tunnel vision at the screen edges (pulsing; steady with "reduce flashing") |
| Weapon sway | The aim drifts slowly left and right by up to the total sway (injuries plus the gun's own, Section 13.4), on top of spread. The player sees it as the bloom reticle shifting |
| HUD | Bottom left: body silhouette (seen from behind), each part filled green → amber → red by its HP, black with a red outline when blacked; drops for bleeds (two for heavy), a crack for fractures, a flash on the part that was hit. Next to it, total HP and a list of active effects |
| Death screen | After 1.5 s: **KILLED IN ACTION**, what killed you ("Shot in the head by a Scav", with weapon, ammo, damage and distance; "the damage spread to your thorax" when a blacked limb did it; or "Bled out" with which bleed and who caused it), your body at the moment of death (hover parts for HP), active effects, map, side, time in raid and kills. **BACK TO MENU** |

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
| Item data | `ItemData` custom `Resource` (`scripts/data/item_data.gd`): id, display name, description, category (weapon, ammo, attachment, armor, rig, backpack, helmet, meds, food, valuable, junk, key, container, melee), rarity, grid size, weight, base value, max stack, stats, `loot_weight`, an optional `icon`, and for guns a `weapon` (`WeaponData`). Items live in `data/items/<category>/` as either `.tres` files (one item each, made in the Inspector) or `.json` files (one item or a list; keys listed in `ItemData.from_dict()`, see the README). `ItemDB` loads both and reports bad entries with the file name. Enums are saved as numbers in `.tres` files, so only append new values. Exported builds need `*.json` in the export filter |
| Item icons | Until there's art, `ItemData.get_icon()` makes a placeholder (`ItemIcons`, `scripts/ui/`): the grid footprint at 64 px per cell, a dark box tinted and outlined in the rarity colour (colorblind palette aware) with a symbol per category. Setting `icon` replaces it. Inventory grids draw them with `ItemDraw` |
| Weapons | `WeaponData` `Resource` (`scripts/data/weapon_data.gd`): caliber, weapon skill, fire rate, auto/semi, magazine, reload and empty-reload time; recoil (vertical, horizontal, recovery rate and delay, camera kick); spread and bloom (base spread, bloom per shot, max bloom, bloom recovery and delay, hip-fire, moving, sprint and roll spread, sway). Modding fields: platform, ergonomics, muzzle velocity, `slots` and `default_mods`; durability: wear per shot, malfunction threshold, jam chance at 0 durability, time to clear a jam. One `.tres` per gun in `data/weapons/`, referenced by the gun's item. Every gun, player's and AI's, is the same `Weapon` node (`scripts/combat/weapon.gd`, scene `scenes/weapons/weapon.tscn`: placeholder model, muzzle, flash, light), so a new gun is just a new data file. `ImpactEffects` (`scripts/combat/`) spawns the hit bursts |
| Loot tables | `LootTable` Resource, one per container type (`data/loot_tables/*.tres`: base rarity weights, the table's rarity multipliers, categories or an item list, item weights, item count) with `roll_rarity()`, `roll_item()`, `roll()`, `roll_items()` (ready-made, guns loaded) and `chances()`; pass a `RandomNumberGenerator` for repeatable rolls. Container types are `LootContainer` resources (`data/loot_tables/containers/`: their table, grid size, search time, placeholder look, solid or not, bullet material); maps add `MapInfo.loot_multipliers` |
| Item instances | `ItemInstance` (`scripts/inventory/`, RefCounted): the `ItemData`, stack count, grid cell, turned or not, Found-in-Raid (`fir`, plus raid-only `fir_pending` and `brought_in`), its own `InventoryGrid` for rigs / backpacks / containers, for guns the round type and the magazine (ammo instances bottom to top, so each run of rounds keeps its status), `durability` / `max_durability`, and for guns and parts the parts fitted (`mods`, slot id → `ItemInstance`, nested); saved per instance (`to_dict()` / `from_dict()`). *Planned:* rolled bonuses and gunsmith mods (`AffixData` / `GunsmithModData` Resources) |
| Handling tuning | `HandlingConfig` (`data/config/handling.tres`): rarity strength, ergonomics points, the special-modifier rarity factor, ergonomics handling, weight sway and bloom-recovery loss, aimed sway, stance bloom rise, wear spread, recoil jitter, preview shots, skill recoil, stat limits, repair. `data/config/attachment_profiles.json`: each attachment kind's default effects. The `Weapon` node keeps the recoil kick and the bloom (shot and stance) at run time; `Actor.set_stance` each tick feeds it speed, sprint, roll and aim (`aim_blend()`) |
| Weapon modding | `WeaponMods` (`scripts/inventory/`): the slot tree (`walk()`, slot paths like `handguard/foregrip`), what fits where, install / uninstall, default parts, capacity, missing parts. A part is an attachment item with a `"mod"` stat: `{kind, fits, slots, modifiers, capacity}`. `WeaponStats` (`scripts/combat/`): profiles and rarity strength, adding up modifiers (empty slots included), `build(gun, skills)` (the modded `WeaponData` copy the `Weapon` node fires with: weight, ergonomics and skills applied), the recoil kick / recovery / pattern and wear spread shared by the gun and the previews, stat rows for the UI, repair. UI (`scripts/ui/inventory/`): `WeaponModScreen` (opened by `InventoryScreen.open_modding()`), `ModSlotView`, `ModPartRow`, `WeaponStatList`, `RecoilPatternView`, `SpreadCircleView`. `Player` equips the modded copy, sight and durability, and writes the wear back to the item after every shot |
| Found in raid | `FoundInRaid` (`scripts/inventory/`): where items come from (`Source`: trader, flea market, quick-buy, insurance, barter, quest reward, craft, starter) and `make()` with the right status; `mark_brought_in()` at raid start, `claim()` when loot reaches the player's inventory (on `Inventory.changed`), `resolve()` at the end |
| Raid | `RaidController` (`scripts/raid/`, a node in the map): clock, raid experience, extraction (`ExtractZone`, `scripts/world/`), ending. `RaidOutcome` settles it (FIR, keep / lose gear, Scav transfer, XP, save). `RaidConfig` (`data/config/raid.tres`): extract time, Run Through limits, XP, search timing. Interactables are in group `interactables` with `interact_text()`, `can_interact()`, `interact()`: `LootBox` (a container of a `LootContainer` type), `LootPickup` (loose item), dead `Bot`s (their `inventory`). `LootSearch` (`scripts/inventory/`) reveals hidden items one by one; the inventory screen runs it while the loot is open (`ItemInstance.hidden`, raid only). The result screen is `ui/raid_result_screen.tscn` |
| Progression | `scripts/progression/`: `Requirement` (item, count, fir), `ItemSearch` (count / take from the stash and character, FIR-only where required), `Trading` (`data/traders/offers.json`), `QuestLog` (`data/quests/*.json`, progress in `GameState.quests`), `Hideout` (`data/hideout/stations.json`, levels in `GameState.hideout`). Screens: TRADERS tabs, `ui/hideout_screen.tscn`; shared widgets `RequirementRow`, `ItemCell`, `FirMark` |
| Inventory | Data (`scripts/inventory/`, no UI): `InventoryGrid` (placement, rotation, stacking, what may go inside what, weight, save), `Inventory` (equipment slots + pockets: slot rules, weight, ammo count / take, starter and Scav kits), `InventoryConfig` (`data/config/inventory.tres`: stash size, weight thresholds). UI (`scripts/ui/inventory/`): `InventoryScreen` (`ui/inventory_screen.tscn`), `InventoryGridView`, `EquipmentSlotView`, `InventoryDrag` (what a drop would do, and doing it), `InventoryDragPreview`, `ItemDraw`, `ItemExaminePanel`; `InventoryLayer` opens it in a raid. Built on Godot's GUI drag & drop (`_get_drag_data` / `_can_drop_data` / `_drop_data`). The player's weight, gun and spare rounds follow its `Inventory` (`Player.set_inventory()`) |
| Globals (autoloads) | Built: `GameState` (profile: faction, level, XP, ₽/$, trader loyalty, inventory, skills, quests, hideout levels, stash grid; plus the raid being set up), `ItemDB` (loads every `ItemData` under `data/items/`), `SaveManager` (JSON save/load), `NoiseSystem` (sounds AI can hear), `CoverSystem` (cover points), `VisionSystem` (Section 13.6: occluders, light, weather, sight lines, the visibility trace), `Settings` (Section 17), `UiSounds` (hover/click sounds for every menu control). Planned: `TraderManager`, `QuestManager`, `HideoutManager` |
| Saves | One JSON file, `user://savegame.json`: `{version, profile, stash}`. Version 5 saves each gun's parts (nested, each with its FIR status) and durability; older guns load with their default parts at full durability. Version 4 keeps each gun's magazine as runs of rounds with their FIR status, and adds quests and hideout levels (version 3 rounds load as not found in raid). Version 3 saves the inventory and stash as item instances (cell, rotation, contents, loaded rounds, FIR). Version 2 saves (equipment, pockets, skills) are converted: the holster becomes the pistol slot and an Alpha secure container is added; version 1 saves get the starter kit equipped. Written to a temp file first, then swapped in. Bump `SAVE_VERSION` when the format changes |
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
| `assets/` | `models/`, `textures/`, `audio/` (`music/`, `ui/`), `shaders/`, `fonts/` |
| `tools/` | Helper scripts run outside Godot (placeholder audio generator) |

**Input actions** (defined in `project.godot`)

| Action | Default | Action | Default |
|---|---|---|---|
| `move_forward` / `move_back` | W / S | `reload` | R |
| `move_left` / `move_right` | A / D | `toggle_inventory` | Tab |
| `shoot` | Left mouse | `interact` | F |
| `aim` | Right mouse (hold): peek from cover | `use_item` | E |
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
| CHARACTER | Gear (every slot from Section 7 with the loaded ammo or how many items are inside, pockets, carried weight and value), stats (faction, level, XP, health, money), skills (Section 12.3, level and progress) and the stash grid side by side. Stash items show at their grid position in their rarity colours with the rarity letter and stack count; hover for details. **INVENTORY** (or Tab) opens the grid inventory (Section 7) with the stash beside it; closing it saves |
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
| Stash | AK-74N, 2 × 60 5.45x39 PS, 3 bandages, 2 bolts |

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
