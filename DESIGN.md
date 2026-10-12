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

**Combat behaviour (built for Scavs and AI PMCs).** Scavs are friendly to each other; everyone else is hostile.

| Sense / action | Rule |
|---|---|
| Vision | Cone in front; anyone within 3 m is noticed regardless. Needs a clear line to the target's chest or head (walls and cover block sight) |
| Hearing | Hears any noise whose radius reaches it (footsteps, rolls, shots); walks over to investigate, then looks around |
| Under fire | A bullet passing within 2 m puts the bot in combat with the shooter |
| Cover | Picks a free cover point that hides it from the threat, preferring spots it can shoot from. Ducks, peeks for a burst, ducks again. Moves to new cover when flanked or after a few peeks |
| Search | Loses sight for too long → goes to the last known position and looks around |
| Health | Same body parts, bleeds and fractures as the player (Section 13.5): a leg hit slows a bot, an arm hit makes it sway |
| Shooting | Same guns as the player (Section 13.4): fires in bursts, so recoil builds and settles. Aim error is added on top of the gun's spread. From cover it waits until it has stopped stepping out before firing |
| Reloading | Reloads when the magazine runs dry, and tops up while ducked below half a magazine. Never peeks while reloading. Bots carry 90 spare rounds |

| Profile | Vision | Reaction | Aim error | Hearing | Rolls | Ammo |
|---|---|---|---|---|---|---|
| Scav (basic) | 25 m, 120° | 0.8 s | 2.8° | ×1.0 | Never | 5.45 PS |
| PMC (advanced) | 35 m, 140° | 0.4 s | 0.3° | ×1.3 | 50% chance to roll out of the line of fire when shot at in the open; 70% chance to roll into new cover when it's within reach | 5.45 BS |

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
| Weight | Over-encumbered → slower move, faster stamina drain. Above 40 kg you're **overweight** and can't combat-roll *(tune)* |
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
| Noise | Every shot is a 60 m noise |
| Health | Body parts for everyone, player and AI (Section 13.5). A round damages the part it lands on |
| Guns | Each gun's handling is a `WeaponData` file (Section 15). Damage and penetration always come from the ammo |
| Fire rate | Rounds per minute. Automatic guns fire while the trigger is held; semi-auto guns fire once per click |
| Magazine | Each shot uses a round. Can't fire while reloading |
| Reload (R) | Tactical reload (rounds left) or a slower empty reload (a round has to be chambered). Tops the magazine up from spare rounds of the loaded type. You can move, roll and use cover while reloading |
| Spare ammo | In a raid: the pocket rounds matching the loaded ammo. Rounds used aren't taken out of your profile yet |
| Auto-reload | On by default (Settings > Gameplay): pulling the trigger on an empty magazine reloads. Off: the HUD says "Magazine empty: press R to reload". No spare rounds: "Out of ammo" |
| Spread | Each shot lands at random inside a cone: base spread + movement spread (scaled by speed, full at sprint speed) + recoil + the shooter's aim error (bots only) |
| Recoil | Every shot adds spread up to a cap. It starts wearing off a moment after the last shot, so short bursts and tap fire stay accurate and long sprays don't |
| Feedback | Muzzle flash with a brief light, a small kick of the gun model and camera shake. A burst of particles where a round hits: grey dust (concrete), sparks (metal), splinters (wood), red (a body). The bloom reticle opens to the real spread cone; a ring fills around it while reloading |
| HUD | Bottom right: gun name, rounds in the magazine (amber at a third or less, red when empty), magazine size, spare rounds, loaded ammo and penetration, auto/semi, and a reload bar |

| Ammo | Damage | Penetration | Wood |
|---|---|---|---|
| 5.45x39 PS | 50 | 28 | Stopped |
| 5.45x39 BS | 40 | 45 | Goes through (24 damage after) |

| Gun *(tune)* | Fire rate | Mode | Magazine | Reload / empty | Base spread | Moving (sprint) | Recoil per shot / cap / recovery |
|---|---|---|---|---|---|---|---|
| AK-74N | 650 rpm | Auto | 30 | 2.3 s / 2.9 s | 0.5° | +3.0° | +0.5° / 5° / 10°/s after 0.15 s |

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
| Weapon sway | The aim drifts slowly left and right by up to the total sway, on top of spread. The player sees it as the bloom reticle shifting |
| HUD | Bottom left: body silhouette (seen from behind), each part filled green → amber → red by its HP, black with a red outline when blacked; drops for bleeds (two for heavy), a crack for fractures, a flash on the part that was hit. Next to it, total HP and a list of active effects |
| Death screen | After 1.5 s: **KILLED IN ACTION**, what killed you ("Shot in the head by a Scav", with weapon, ammo, damage and distance; "the damage spread to your thorax" when a blacked limb did it; or "Bled out" with which bleed and who caused it), your body at the moment of death (hover parts for HP), active effects, map, side, time in raid and kills. **BACK TO MENU** |

All of these values live in `data/config/health.tres`.

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
| Item data | `ItemData` custom `Resource` (`scripts/data/item_data.gd`): id, display name, description, category, rarity, size, weight, base value, max stack, stats, and for guns a `weapon` (`WeaponData`). One `.tres` per item in `data/items/<category>/<id>.tres`; enums are saved as numbers, so only append new values |
| Weapons | `WeaponData` `Resource` (`scripts/data/weapon_data.gd`): caliber, fire rate, auto/semi, magazine, reload and empty-reload time, base and movement spread, recoil per shot, recoil cap, recovery rate and delay, camera kick. One `.tres` per gun in `data/weapons/`, referenced by the gun's item. Every gun, player's and AI's, is the same `Weapon` node (`scripts/combat/weapon.gd`, scene `scenes/weapons/weapon.tscn`: placeholder model, muzzle, flash, light), so a new gun is just a new data file. `ImpactEffects` (`scripts/combat/`) spawns the hit bursts |
| Loot tables | `LootTable` Resource with weighted rarity rolls |
| Rolled items | `ItemInstance` (base `ItemData` + rarity + bonuses + gunsmith mod + durability + FIR flag); saved per instance. Bonuses and mods are `AffixData` / `GunsmithModData` Resources |
| Inventory | `InventoryGrid` (pure data class) + UI `Control` scene; drag & drop |
| Globals (autoloads) | Built: `GameState` (profile: faction, level, XP, ₽/$, trader loyalty, equipment, pockets, skills, stash contents; plus the raid being set up), `ItemDB` (loads every `ItemData` under `data/items/`), `SaveManager` (JSON save/load), `NoiseSystem` (sounds AI can hear), `CoverSystem` (cover points), `Settings` (Section 17), `UiSounds` (hover/click sounds for every menu control). Planned: `TraderManager`, `QuestManager`, `HideoutManager` |
| Saves | One JSON file, `user://savegame.json`: `{version, profile, stash}` (version 2 added equipment, pockets and skills; version 1 saves get the starter kit equipped). Written to a temp file first, then swapped in. Bump `SAVE_VERSION` when the format changes |
| Settings | `Settings` autoload: `SCHEMA` lists every option once (tab, default, type, choices); the settings menu is built from it. Saved to `user://settings.cfg` (ConfigFile). Scene settings (shadows, bloom, AO, view distance, DoF) are applied to every light, environment and camera as it enters the tree. Brightness, gamma and colorblind correction are one full-screen shader on top |
| UI | Shared theme `ui/theme/menu_theme.tres` (set as the project theme). Screens opened from a menu extend `MenuScreen` (Esc / B goes back, emits `closed`). Maps are `MapInfo` resources in `data/maps/` |
| Audio | Buses: Master, Music, Effects, Voice, UI, Ambient (`default_bus_layout.tres`). Placeholder music and UI sounds are generated by `tools/make_placeholder_audio.py` |
| Actors | `Actor` (`scripts/actors/actor.gd`) is the shared body: movement, stamina, roll, cover, hitbox, health (a `BodyHealth`), shooting (through its `Weapon`, `$Body/Gun`). `Player` turns input into intents; `Bot` turns AI decisions into the same intents. Each has a separate `Hitbox` (Area3D) that bullets hit and that can shrink independently of the movement collider |
| Player | `scenes/actors/player.tscn`: capsule placeholder; the gun box shows facing. Rules in Section 13 |
| AI | `scenes/actors/bot.tscn` + a `BotProfile` (`data/bots/*.tres`). Behaviour in Section 4 |
| Health | `BodyHealth` (`scripts/actors/body_health.gd`, RefCounted): part HP, blacked-damage spreading, bleeds, fractures, pain, and the death cause. Tuning is a `HealthConfig` resource, `data/config/health.tres`. HUD and death screen draw it with `BodySilhouette` (`scripts/ui/body_silhouette.gd`); the death screen is `ui/death_screen.tscn` |
| Combat tuning | `CombatConfig` resource, `data/config/combat.tres`: roll, cover and bullet values. The numbers are in the file itself, so it can be edited in the Inspector or a text editor |
| Cover | `CoverBox` (`scripts/world/`): @tool box with size + material that builds its own mesh and collision. `CoverSystem` autoload generates `CoverPoint`s every 1.2 m along each side and answers "nearest cover" / "best cover against this threat" |
| Noise | `NoiseSystem` autoload: anything audible calls `emit_noise(position, radius, source)`; bots listen |
| Camera | `TopDownCamera` (`scripts/camera/`): fixed 60° pitch, 18 m back, never turns; follows the player smoothly at any frame rate |
| Physics | Jolt Physics at 60 ticks/s with physics interpolation on: move bodies in `_physics_process`. Anything moved in `_process` (like the camera), or placed once (tracers), turns interpolation off for itself. Layers: 1 world, 2 actors (movement), 3 hitboxes (bullets) |
| Navigation | The level's `NavigationRegion3D` bakes its navmesh from static colliders when the level loads (0.1 m cells, 0.4 m agent radius); bots steer with `NavigationAgent3D` |
| Naming | snake_case files, PascalCase classes (`class_name`) |
| Engine version | Godot 4.7 (current stable 4.7.2), Forward+ renderer, 1920×1080 base resolution. Commit Godot's `.uid` files |

**Folder layout**

| Folder | Contents |
|---|---|
| `scenes/` | Gameplay scenes: `actors/` (player, bots), `weapons/` (the shared gun scene), `props/` (car), `menu/` (main menu background), `hideout/` |
| `maps/` | One scene per raid map (Section 5), plus `test_level.tscn` for movement testing |
| `ui/` | Main menu (entry scene), settings, raid setup, loading, character, traders, pause menu, HUD; `theme/` |
| `scripts/` | All GDScript, mirroring scene folders (`ui/`, `hideout/`, `actors/`, `maps/`, `menu/`), plus `autoload/` (singletons), `data/` (Resource classes), `camera/`, `combat/` (bullets, guns, impact effects) and `world/` (cover) |
| `data/` | `.tres` Resources: `items/` (one subfolder per category), `weapons/` (gun handling), `loot_tables/`, `config/` (tuning), `bots/` (AI profiles), `maps/` (map select info) |
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

WASD is screen-relative: W always moves up the screen. Keyboard and mouse keys can be remapped in Settings; controller bindings are listed in Section 17. Menus also use `ui_tab_previous` / `ui_tab_next` (Q / E, LB / RB).

## 16. Menus & Raid Setup

### 16.1 Main Menu

| Element | Detail |
|---|---|
| Background | Slowly panning dusk shot of an industrial yard: low orange sun, fog (volumetric in Forward+), drifting dust, street lamps, depth of field. Ambient music loop on the Music bus |
| Title | Top left |
| Buttons (left, top to bottom) | **ENTER RAID** (largest, highlighted), CHARACTER, TRADERS, gap, QUIT (asks "Are you sure?") |
| Settings | Gear icon, bottom right |
| Profile | Top right: faction, level, roubles, dollars |
| Feel | Hover/focus slides a button right and makes it glow, with a hover sound; clicks have their own sound. Hovering also takes keyboard focus, so mouse and controller never highlight two buttons |
| Navigation | Full keyboard (arrows, Enter, Esc) and controller (D-pad / left stick, A, B). Esc / B on the main menu asks to quit |

### 16.2 Character & Traders

| Screen | Shows |
|---|---|
| CHARACTER | Gear (all slots from Section 7, loaded ammo, 4 pockets, carried weight), stats (faction, level, XP, health, money), skills (Section 12.3, level and progress) and the stash grid side by side. Stash items show at their grid position with rarity border, rarity letter and stack count; hover for details. Moving items comes with the inventory |
| TRADERS | All traders (Section 10) with loyalty level, reputation, money spent and what the next level needs. Jaeger is locked until his quest. Buying and selling come later |

### 16.3 Enter Raid

| Step | Detail |
|---|---|
| 1. Map | Every map from Section 5 is listed. Maps that aren't built yet show "in development" and can't be picked. Test Yard is playable |
| 2. PMC or Scav | **PMC:** your character and gear; die and lose what you brought. **Scav:** random gear, nothing from your stash at risk; AI Scavs leave you alone unless you shoot them (whoever you shoot turns hostile). AI PMCs are hostile either way |
| 3. Loadout check | Every slot, loaded ammo, pockets and weight, plus warnings: no armor, no helmet, no meds, no backpack, "if you die, everything you bring is lost" |
| 4. Loading | Map name, side, a gameplay tip and a progress bar while the map loads in the background (shown for at least 1.5 s) |

Back (or Esc / B) steps back one step at a time.

### 16.4 New Character

On first launch the player picks **BEAR** or **USEC** (Section 3); that creates and saves the profile. Starter kit *(tune)*:

| Where | Items |
|---|---|
| Equipped | AK-74N loaded with 5.45x39 PS |
| Pockets | 60 × 5.45x39 PS, 1 bandage |
| Stash | AK-74N, 2 × 60 5.45x39 PS, 3 bandages, 2 bolts |

### 16.5 Pause Menu (in raid)

Esc or Start pauses the raid and frees the mouse: **RESUME**, **SETTINGS**, **LEAVE RAID** (asks first), **QUIT GAME** (asks first). Esc / Start / B closes it. It can't be opened once you're dead. Dying shows the death screen (Section 13.5) with **BACK TO MENU**.

## 17. Settings

Settings open from the main menu (gear icon) and the pause menu. Six tabs; edits only take effect on **Apply**, which also saves `user://settings.cfg`. **Reset to Defaults** resets the open tab; **Back** with unapplied edits asks to discard them. Q / E or LB / RB switch tabs.

| Tab | Options (default) |
|---|---|
| Graphics | Display mode (Windowed / Borderless / Fullscreen), resolution (windowed only), monitor, V-Sync (on), FPS limit (30/60/120/144/240/Unlimited), render scale (100%), quality preset (Low/Medium/High/Ultra, High) which sets: shadows, textures, anti-aliasing (Off/FXAA/MSAA/TAA), ambient occlusion, view distance, depth of field quality. Also bloom, motion blur, brightness and gamma |
| Audio | Master (80%), music (50%), effects, voice, interface (70%), ambient volume; output device; mute when the window loses focus (on) |
| Controls | Mouse sensitivity (1.0), aim (optics) sensitivity (0.6), invert mouse; hold or toggle for sprint (hold), crouch (toggle) and aim (hold); key remapping for every action with conflict warnings and per-key reset; controller on/off, sensitivity and stick dead zone (20%) |
| Gameplay | Camera shake (100%), damage numbers (off), hit markers (on), auto-reload (on, Section 13.4), auto-equip on pickup, confirm before selling valuables, language, units (metric / imperial) |
| Interface | HUD scale, HUD opacity, FPS counter, reticle style (dot / cross / circle / bloom) and color, colorblind mode (protanopia / deuteranopia / tritanopia), subtitles and subtitle size |
| Accessibility | Reduce flashing effects (dimmer tracers, smaller muzzle flash without light, steady hit markers), turn off screen shake, high-contrast outlines on enemies (red; neutral bots cyan), press instead of hold (sprint, crouch and aim become toggles) |

| Rule | Detail |
|---|---|
| In-raid aiming | The mouse is captured during a raid and moves an on-screen reticle, so mouse sensitivity, aim sensitivity (while aiming/peeking) and invert apply. A controller's right stick points the reticle out from the player |
| Colorblind modes | A screen-wide correction filter, plus a rarity palette that stays distinct for that type of color blindness (Section 6.2). Rarity letters (C, U, R, UR, E, L) are shown next to colors, so color is never the only cue |
| Controller bindings | Left stick move, right stick aim, RT shoot, LT aim/peek, A roll, B crouch, X reload, Y interact, LB take cover, RB use item, L3 sprint, Back inventory, Start pause, D-pad hotkeys 1–4, R3 hotkey 5. Not remappable yet |
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
