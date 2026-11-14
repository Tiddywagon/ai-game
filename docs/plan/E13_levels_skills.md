# E13: Player levels 1-60, skills that grow by use, the character screen

Request: "Add player levels 1-60 from XP (kills, looting, extracting, quests). Add skills that improve by doing
them: Endurance (sprinting), Strength (carrying weight), Vitality, Metabolism, Weapon handling per weapon class,
Search speed, Covert movement, Crafting. Each skill level gives small bonuses. Show a character screen with
level, skills and lifetime stats."

What exists: levels 1-50 from XP (`data/config/progression.json`, DESIGN §2.2; `GameState.add_xp()`), XP from
kills, looting, exploring, extracting and quests; skills in DESIGN §12.3 (Metabolism and Stim resistance built,
weapon class skills present but not levelling, Strength and Endurance trained at the Gym, the rest planned); the
CHARACTER screen with stats and skills.

- **Levels 1-60**: the curve extended to 60 (same shape; the table in DESIGN §2.2 updated), nothing else keyed
  to level breaks (loyalty levels, the flea market, quick-buy and quest level gates stay reachable; say what 60
  takes). Old saves keep their XP and level.
- **Skills** in `data/config/skills.json` (loader with `problems()`): per skill the action that trains it, points
  per action, points per level (growing), max level (50), the bonus per level and its cap, and a per-raid
  fatigue rule (gains slow after a lot in one raid, so idling can't farm a skill). One `Skills` class answers
  `level()`, `bonus()`, `add()` for every caller.
  - Endurance: metres sprinted → more stamina, faster stamina recovery.
  - Strength: carrying weight while moving (more when heavy), melee hits, throws → higher carry limits, a little
    less recoil (as now), farther throws.
  - Vitality: damage taken and survived, bleeds and fractures treated → lower bleed and fracture chance, a little
    more HP regeneration from meds.
  - Metabolism: as built.
  - Weapon handling per weapon class (the seven classes): hits and kills with that class → less recoil, faster
    reloads, faster aim.
  - Search: items found by searching containers and bodies → faster search (stacks with the Raiders figure set).
  - Covert movement: metres moved crouched or walking near enemies who don't notice you → quieter steps (smaller
    noise radius), enemies notice you a little later.
  - Crafting: crafts collected → shorter craft times, a small chance of a bonus output.
  - Stim resistance: as built.
  The Gym keeps giving Strength and Endurance points. Skill levels are saved; old saves keep the levels they
  have.
- **Lifetime stats** (saved): raids by side and outcome, survival rate, kills by target type, headshots,
  longest kill, shots fired and hit, damage dealt and taken, items looted and their value, roubles earned and
  spent, quests completed, distance moved, time in raids, best raid by XP and by loot value, trick shots.
- **CHARACTER screen**: level with the XP bar and what the next level takes, every skill with its level, progress
  bar, current bonus and what trains it, and a STATS tab with the lifetime stats; in a raid a small toast when a
  skill levels up, and the raid summary lists skill points gained.
- Save version bump; DESIGN §2.2, §12.3 (a skill table generated from the data and checked by a test), §16.2,
  §15, §18; README. Suite `tests/skills_test.gd`: the level curve to 60 and old saves, each skill gaining from its
  real action and its bonus changing the real effect, caps and fatigue, the Gym, stats counted from raids and
  menus, the screen, save round trip.
