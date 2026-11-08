class_name Bot
extends Actor
## AI Scav or PMC (DESIGN.md §4). Sees (by the same vision rules as the player, DESIGN.md §13.6:
## its own cone, shorter at night, farther through a scope) and hears hostile actors, fights from the same cover points
## the player uses (duck, peek, shoot, move on), and — with an advanced profile — combat-rolls to
## dodge or to reach new cover when under fire.
## A simple state machine: IDLE (stands and looks around) and PATROL (walks to the next point: a random
## one of its zone's, `wander_points`, sometimes a hot point of interest, or the next stop of a fixed
## `patrol_points` route); INVESTIGATE a noise it heard (footsteps by how the actor moves: sprinting is
## loud, crouching quiet, and it walks over carefully; a gunshot or explosion carries far, and it runs
## there and calls the Scavs of its zone nearby to come too) and SEARCH where a target was last seen;
## COMBAT (cover, peek and shoot with its profile's inaccuracy, reload ducked, sometimes flank:
## BotProfile.flank_chance);
## LOOT (out of a fight, walks to loose loot or a ready event crate nearby and takes it); FLEE (low HP:
## runs for cover away from the threat and treats itself with what it carries, then fights on);
## EXTRACT. Pathfinding is the map's NavigationRegion3D (NavigationAgent3D).
## Squads (Squad): a boss and its guards (BossSpawn), or an AI PMC squad of 1-3 of one faction
## (RaidController; DESIGN.md §4.4). Squad mates never fight each other, share targets and what they
## see, and join each other's fights; out of a fight the followers keep to their spots near the leader
## and go where it goes (a noise, an extract), and when the leader falls the next one leads. A boss
## squad pushes as a group in a fight (BotProfile.pushes). What a bot is worth and whether it loots,
## rushes raid events or ever leaves is its `role`'s: a boss and its guards never leave the raid, and
## raid events don't pull them off their haunt, nor a fight they hear farther off
## (BotProfile.haunt_radius). An AI PMC has a faction (Actor.faction: its look, voice and kit); it
## holds back from PMCs of its own faction (DESIGN.md §3: slower to open fire, no fight started far
## off unless they aim at it or shoot) and calls out what happens (Voice).
## Late in the raid it heads for an extract it can use (DESIGN.md §5: the same extracts as the player,
## RaidConfig says when) and leaves the raid after standing in it for the extract time; a fight or a hit
## interrupts it. Up close (its profile's melee_range) a bot carrying a melee weapon swings it instead of
## shooting (Actor.melee_strike(): a parry staggers it).
## An AI PMC squad that RaidController spawned plays a raid plan (RaidPlan, DESIGN.md §4.4) instead of
## patrolling: its leader TRAVELs to the plan's next point of interest along a route that keeps to walls
## and cover (CoverRoute), LOOTs it (its containers and bodies, with the search time, and loose loot:
## the most valuable things that fit), goes on to the next and heads for the plan's extract when its
## leave time comes, the raid clock runs low, its bags are full or its POIs are done. Its personality
## (PmcAi: Rat, Looter, Chad, Quester) decides which noises it goes to look at (hear(): a Chad hunts
## gunfire, a Rat hides: AVOID), which raid events it rushes (rush_chance()), whether it fights or
## avoids Scavs, and how it moves (a Rat crouch-walks near POIs and along cover, a Chad sprints). After a
## fight, once it's quiet, it treats its wounds (HEAL) while its squad mates cover it. In a fight a
## squad spreads out over cover points apart from each other, one of them may flank, and it regroups
## before moving on.

enum State { IDLE, INVESTIGATE, COMBAT, SEARCH, EXTRACT, PATROL, LOOT, FLEE, TRAVEL, HEAL, AVOID }

const ARRIVE_DISTANCE := 0.3
## Distance to a goal above which the bot sprints instead of walking.
const SPRINT_DISTANCE := 3.0
## Seconds spent looking around at a noise or the target's last known position.
const LOOK_AROUND_TIME := 4.0
## Noises that alarm a bot: it runs (sprints) to investigate and alerts its zone (BotProfile.alert_radius).
## Anything else (footsteps, a roll) it walks over to carefully.
const ALARMING_NOISES: Array[StringName] = [&"gunshot", &"explosion"]
## High-contrast outline colours (Settings > Accessibility): hostile to the player, or not.
const HOSTILE_OUTLINE := Color(1.0, 0.3, 0.15)
const NEUTRAL_OUTLINE := Color(0.3, 0.85, 1.0)
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
## In cover, the bot only opens fire once it has nearly stopped moving (share of sprint speed).
const PEEK_SETTLE_SPEED := 0.15
## When no cover is found, wait this long before searching again.
const COVER_RETRY_TIME := 0.5
## With no extract it can use, try again this much later (seconds of raid time).
const EXTRACT_RETRY_TIME := 30.0
## Seconds it stands looking around at each patrol stop, picked at random between x and y.
const PATROL_PAUSE := Vector2(2.0, 5.0)
## Out of a fight it looks for loot this often (seconds); it picks something up from this close, which
## takes LOOT_SECONDS, and gives up on loot it can't reach in LOOT_GIVE_UP seconds.
const LOOT_SCAN_TIME := 1.5
const LOOT_REACH := 1.2
const LOOT_SECONDS := 1.2
const LOOT_GIVE_UP := 15.0
## It takes at most this many items out of an event crate.
const CRATE_TAKES := 2
## After fleeing once it fights on for at least this long (seconds) before fleeing again.
const FLEE_COOLDOWN := 45.0
## It treats itself where it is if it hasn't reached its flee spot in this long, and turns to fight a
## target that gets this close (metres) while it flees.
const FLEE_TIMEOUT := 8.0
const CORNERED_DISTANCE := 6.0
## Treatments in one go at most, and the longest one treatment takes it (seconds).
const MAX_TREATMENTS := 3
const MAX_TREAT_SECONDS := 6.0
## A boss's guards stand this far from it, and walk back once this far from their spot; they sprint
## when farther than BOSS_CATCH_UP behind.
const BOSS_SPACING := 2.0
const ESCORT_DISTANCE := 3.5
const BOSS_CATCH_UP := 9.0
## Squad mates stand this far apart in an extract.
const EXTRACT_SPREAD := 0.8
## Walking somewhere without getting STUCK_PROGRESS metres closer for this long, it gives up on the
## spot (a corner the navmesh cuts too fine, another body in a doorway) as the closest it can get.
const STUCK_SECONDS := 2.0
const STUCK_PROGRESS := 0.5
## Covering a squad mate who treats itself, it stands about this far from it.
const COVER_MATE_DISTANCE := 3.0
## A planned leader heading out follows its cover route until this close to the extract's edge.
const EXTRACT_ROUTE_NEAR := 6.0
## Getting unstuck on a leg (a planned leader's travel to a POI or its way out; DESIGN.md §4.4): the first
## time it's stuck on the way (STUCK_SECONDS) it skips that waypoint; from REROUTE_AFTER times on (a route
## that ends short of the goal counts too) it takes the plain navmesh path from a step UNSTICK_STEP metres
## to the side; at GIVE_UP_AFTER it gives the leg up (skips the POI, or picks another extract). Only times
## stuck on the same spot add up: once it's LEG_PROGRESS metres nearer the goal than when it last got
## stuck, it counts from one again (a new obstacle, not the same one). A follower stuck REROUTE_AFTER
## times on its way out goes the way its leader goes instead.
const REROUTE_AFTER := 2
const GIVE_UP_AFTER := 5
const UNSTICK_STEP := 1.5
const LEG_PROGRESS := 4.0
## With no route to where it's going (the path query came back empty), it walks straight there and asks
## for a route again this often (seconds of its own clock).
const ROUTE_RETRY_TIME := 2.0
## A leader waiting for its squad looks again this often (seconds).
const WORK_PAUSE := 0.3
## How likely a PMC without a plan (or pmc_ai.json) heads for a raid event.
const FALLBACK_RUSH_CHANCE := 0.85
## Bodies the AI walks through (a group, walk_through()): raid event crates and the supply truck, which
## turn up after the navmesh is baked, so paths run through them (a sealed cache leaves a gap too narrow
## for a body). They still block you, sight and bullets.
const WALK_THROUGH := &"ai_walk_through"

@export var profile: BotProfile
## Optional patrol route in world positions, walked in a loop.
@export var patrol_points: PackedVector3Array
## Points it wanders between, in random order (a ScavZone's): used instead of patrol_points if set.
@export var wander_points: PackedVector3Array
## The Scav zone it belongs to: a Scav placed in the scene roams this zone's points (when it has no
## wander_points or patrol_points of its own); ScavZone sets it on the Scavs it spawns. Gunshots alert
## the Scavs of the same zone.
@export var zone: ScavZone
## Untick to freeze the bot in place (it still takes damage).
@export var ai_enabled := true

## What the bot carries (DESIGN.md §4): a random Scav kit (data/bots/scav_kit.tres), its faction's
## AI PMC kit (Factions.ai_kit()) or, set before it enters the tree, a boss's. Its gun is the one in
## hand; its spare rounds are the ones in its rig and pockets, used up as it reloads. Lootable once
## it's dead, with all its gear.
var inventory: Inventory
## Searching the body's pockets, rig and backpack (its equipment is in plain sight).
var search: LootSearch

var state := State.IDLE
## The hostile actor being fought, if any.
var target: Actor
## Seconds into the raid when it heads for an extract (-1: never), and whether it has left the raid.
var extract_at := -1.0
var extracted := false
## The squad it's in (Squad: a boss's, an AI PMC squad), or null on its own.
var squad: Squad
## Who leads its squad when that isn't this bot (null: it leads, or has no squad).
var leader: Bot:
	get:
		return squad.leader if squad and squad.leader != self and is_instance_valid(squad.leader) else null
## What it is, which decides what it's worth and some of what it does: &"boss", &"guard" (BossSpawn), or
## &"" for an ordinary Scav or PMC (a squad member or not).
var role: StringName = &""
## A boss's or guard's haunt (near_haunt()), set by BossSpawn; `title` is a boss's or guard's name (""
## for a plain Scav or PMC).
var boss_spawn: BossSpawn
var title := ""
## What it has picked up (item names), how often it flanked and what it treated itself with.
var looted: Array[String] = []
var flanks := 0
var treated: Array[String] = []
## How often it gave up on getting somewhere it was stuck on the way to, and how many travel routes it
## has worked out (tests: once a leg, not every frame).
var stuck_count := 0
var routes_built := 0
## The Scav wave that brought it (RaidController.spawn_wave(); 0: none). A wave counts as its zone.
var wave := 0
## The gear tier its kit is dressed for (an AI PMC squad's, PmcAi: cheap to well-equipped), set before
## it enters the tree; &"" for the faction kit as it is.
var gear_tier: StringName = &""
## Seconds since it last saw or heard a hostile or was shot at: healing after a fight waits for quiet.
var quiet_time := 0.0
## The route it's walking (TRAVEL; a planned leader heading out): waypoints, from `_route_index` on.
var route := PackedVector3Array()
## Cells its kit took in its pockets, rig and backpack when it joined the raid: what it loots fills the
## rest (loot_fill()).
var kit_cells := 0
## Scav karma (DESIGN.md §2, ScavRuns): whether it attacked the player (shot at or hit them while they
## were its target), whether the player has attacked it, and whether it was friendly when they first did
## (it hadn't attacked them before, and wasn't hostile to them for their karma alone): killing it then is
## killing a friendly Scav.
var attacked_player := false
var player_attacked := false
var friendly_when_attacked := false

## Investigating something alarming (a gunshot): it runs there instead of walking.
var _urgent := false
var _sees_target := false
var _seen_time := 0.0
var _lost_time := 0.0
var _last_known := Vector3.ZERO
var _point_of_interest := Vector3.ZERO
var _perceive_timer := 0.0
var _look_timer := 0.0
var _patrol_index := 0
var _goal_cover: CoverPoint
var _cover_retry := 0.0
var _cover_timer := 0.0
var _wants_peek := false
var _peeks_left := 0
var _burst_clock := 0.0
var _outline: ShaderMaterial
## What the bot sees this perception tick.
var _view: VisionView
## The extract it's heading for, how long it has stood in it, and whether it has got to its spot in it
## (or as close as it gets, inside the extract: _do_extract()).
var _extract_zone: ExtractZone
var _extract_time := 0.0
var _extract_settled := false
## Patrol: the point it's walking to (wandering).
var _patrol_goal := Vector3.ZERO
var _has_patrol_goal := false
## Loot: what it's after (a LootPickup or an event crate), how long it's been at it, the next look
## around for some, and crates it has already looted.
var _loot_target: Node3D
var _loot_timer := 0.0
var _loot_time := 0.0
var _loot_scan := 0.0
var _looted_boxes: Array[Node3D] = []
## Flee: where it runs to (and the cover there), when it can flee again, how long it's been running,
## seconds left on the treatment in hand (-1: still running), the treatment and how many it's had.
var _flee_goal := Vector3.ZERO
var _flee_cover: CoverPoint
var _flee_cooldown := 0.0
var _flee_time := 0.0
var _treat_timer := -1.0
var _treatment := {}
var _treatments := 0
## Getting stuck: where it last made progress, how long since, and whether the last _move_to() gave up.
var _progress_at := Vector3.ZERO
var _stuck_time := 0.0
var _stuck := false
## The route: which waypoints are cover spots, the next one, and where it ends.
var _route_cover := PackedByteArray()
var _route_index := 0
var _route_goal := Vector3.ZERO
## Searching (LOOT): the spot on the navmesh it walks to and how close to the loot counts as there.
var _loot_spot := Vector3.ZERO
var _loot_reach := LOOT_REACH
## Who it's hunting (a Chad going after a noise maker) and for how long; heading for a raid event.
var _hunting: Actor
var _hunt_time := 0.0
var _rushing := false
var _rush_time := 0.0
## Hiding (AVOID): from where, in which cover or at which spot, and how long it's been quiet.
var _avoid_from := Vector3.ZERO
var _avoid_cover: CoverPoint
var _avoid_goal := Vector3.ZERO
var _avoid_quiet := 0.0
## Plan checks, how long it has held for its squad (and why: a RaidPlan.Goal, -1 for not holding), the
## heal cooldown, whether it crouches this tick, when it may next roll for each noise maker, when it may
## try an extract again, and whether it has made its flank this fight.
var _plan_timer := 0.0
var _hold_time := 0.0
var _hold_goal := -1
var _heal_cooldown := 0.0
var _crouch := false
var _noise_rolls := {}
var _extract_retry_at := -1.0
var _flanked := false
var _work_timer := 0.0
## Its own decision rolls (seeded per bot in a seeded raid).
var _rng := RandomNumberGenerator.new()
## Whether _plan_extract() has run.
var _extract_planned := false
## Who hurt it last, and whether a hit or a blow is landing now: a death that isn't a hit's (a bleed) is
## its last attacker's doing (die(): RaidController.bot_died_of_wounds()).
var _last_attacker: Actor = null
var _taking_hit := false
## Seconds it has been thinking (its own clock) and where its slow look around starts (rolled): where a
## bot holding or covering looks doesn't depend on how long the game ran before the raid.
var _clock := 0.0
var _look_phase := 0.0
## The leg it's on (where it ends), how often it got stuck on it (or its route ended short), whether it
## gave it up, and when it may ask for a route again after one came back empty (its own clock).
var _leg_goal := Vector3.ZERO
var _has_leg := false
var _leg_stucks := 0
var _leg_best := INF
var _leg_failed := false
var _route_retry_at := 0.0
## Extracts it gave up getting to this time out (blocked on the way).
var _blocked_extracts: Array[ExtractZone] = []
## Hiding (AVOID): how long it has hidden this time, and until when (its own clock) it doesn't hide again
## after waiting one out (plan avoid_give_up, avoid_calm).
var _avoid_time := 0.0
var _avoid_calm_until := -1.0

@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	if GameState.raid.has("seed"):
		rng.seed = hash([int(GameState.raid.seed), str(get_path())])  # Repeatable kits in a seeded raid.
		_rng.seed = hash([int(GameState.raid.seed), "ai", str(get_path())])
	else:
		rng.randomize()
		_rng.randomize()
	_look_phase = _rng.randf() * TAU
	if profile:
		side = profile.side
	var factions := Factions.ids()
	if side == Side.PMC and not Factions.has(faction) and not factions.is_empty():
		faction = factions[rng.randi_range(0, factions.size() - 1)]  # An AI PMC is always BEAR or USEC.
	if profile:
		ammo_id = profile.ammo_id
		walk_speed = profile.walk_speed
		sprint_speed = profile.sprint_speed
		spread_degrees = profile.spread_degrees
		if not is_equal_approx(profile.health_multiplier, 1.0):
			health_config = _tougher(health_config, profile.health_multiplier)
	super()
	add_to_group("vision_hideable")
	if profile:
		weapon.optic = profile.optic
		weapon.recoil_control = profile.recoil_control
	if inventory == null:
		inventory = Inventory.pmc_bot(rng, faction, PackedFloat32Array(), gear_tier) if side == Side.PMC else Inventory.scav(rng)
		if profile and profile.extra_loot:
			inventory.add_loot(profile.extra_loot, rng)
	kit_cells = inventory.used_cells()
	_equip_kit_gun()
	for door in get_tree().get_nodes_in_group("doors"):
		(door as Door).let_through(self)  # An open door's panel doesn't stop it.
	for body in get_tree().get_nodes_in_group(WALK_THROUGH):
		add_collision_exception_with(body)  # Nor a raid event's crate.
	if zone and wander_points.is_empty() and patrol_points.is_empty():
		wander_points = zone.patrol_points()
	weapon.reload_finished.connect(_on_reload_finished)
	NoiseSystem.noise_emitted.connect(_on_noise)
	Settings.applied.connect(_update_outline)
	_update_outline.call_deferred()  # After the player is in the tree.
	_plan_extract.call_deferred()  # Once the raid has started.


## Makes every body of `prop` (a raid event's crate or truck) one the AI walks through (WALK_THROUGH):
## for the bots in the raid now, and those that join it later (_ready()).
static func walk_through(prop: Node) -> void:
	var bodies: Array[Node] = prop.find_children("*", "PhysicsBody3D", true, false)
	if prop is PhysicsBody3D:
		bodies.append(prop)
	for body in bodies:
		body.add_to_group(WALK_THROUGH)
		for bot in prop.get_tree().get_nodes_in_group("bots"):
			(bot as PhysicsBody3D).add_collision_exception_with(body)


## Without a faction it wears its profile's colour (a Scav's, a boss's).
func _plain_color() -> Variant:
	return profile.body_color if profile else super()


func take_hit(damage: float, from: Actor, hit_position: Vector3, shot: Dictionary = {}) -> Dictionary:
	_attacked_by(from)
	_note_player_attack(from)
	_taking_hit = true
	var outcome := super(damage, from, hit_position, shot)
	_taking_hit = false
	_update_outline()  # A friendly bot shot by the player turns hostile.
	if float(outcome.get("damage", 0.0)) > 0.0:
		_extract_time = 0.0  # A hit starts the extract countdown again.
		if from:
			_last_attacker = from
	if not outcome.is_empty():
		_alert_witnesses(from)
	return outcome


## A melee swing or a grenade: as a hit, for the player's karma and the Scavs that see it.
func take_blow(damage: float, from: Actor, kind: String, weapon_name: String, at: Vector3) -> Dictionary:
	_note_player_attack(from)
	_taking_hit = true
	var outcome := super(damage, from, kind, weapon_name, at)
	_taking_hit = false
	_update_outline()
	if not outcome.is_empty():
		if from:
			_last_attacker = from
		_alert_witnesses(from)
	return outcome


## The first time the player attacks it: was it friendly to them then (it hadn't attacked them first,
## and wasn't hostile to them for their karma alone: one that shoots a low-karma Scav on sight isn't)?
func _note_player_attack(from: Actor) -> void:
	if from is Player and not player_attacked and not is_dead:
		player_attacked = true
		friendly_when_attacked = not attacked_player and not _karma_hostile(from)


## The player Scav attacked this Scav: other Scavs that can see them now turn on them too (RaidController).
func _alert_witnesses(from: Actor) -> void:
	if from is Player and from.side == Side.SCAV and side == Side.SCAV:
		var raid := _raid_controller()
		if raid:
			raid.scav_witnesses(from, self)


## Scav to Scav, it's also hostile to a player Scav whose karma has AI Scavs shoot it on sight
## (Player.scavs_hostile, ScavRuns.hostile()): a boss and its guards too.
func is_hostile(other: Actor) -> bool:
	if _karma_hostile(other):
		return true
	return super(other)


## True if `other` is a player Scav this Scav is hostile to for its karma.
func _karma_hostile(other: Actor) -> bool:
	return side == Side.SCAV and other is Player and other.side == Side.SCAV and other.scavs_hostile and not other.is_dead


## The player Scav's karma no longer has AI Scavs shoot them on sight (RaidController): a Scav fighting
## `player` for that alone (they're not among its enemies: it wasn't attacked by them and didn't see them
## shoot a Scav) drops them as its target and leaves the fight.
func calm_down(player: Actor) -> void:
	if target != player or player == null or player in enemies or is_hostile(player):
		return
	target = null
	_sees_target = false
	fire_input = false
	if state == State.COMBAT:
		_leave_combat(State.IDLE)


## Leaves the raid through an extract: out of the fight, gone from the map with everything it carries.
func leave_raid() -> void:
	extracted = true
	exit_cover()
	CoverSystem.release(self)
	is_dead = true  # Nothing targets it any more.
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_hitbox.collision_layer = 0
	for group in ["actors", "bots", "vision_hideable", "interactables"]:
		remove_from_group(group)
	hide()
	set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)  # After this physics step (it leaves the physics space).
	if squad:
		squad.member_left(self)


## When this bot will head for an extract: a squad with a raid plan at the plan's leave time (or sooner:
## leave_reason()); other AI PMCs some time in RaidConfig.ai_pmc_extract_window of the raid (a squad
## once, for all of it: its leader takes it out), some Scavs (ai_scav_extract_chance) in
## ai_scav_extract_window. A boss and its guards never leave. Seeded in a seeded raid. Once (a raid
## joined mid-way asks early: RaidController's fast-forward).
func _plan_extract() -> void:
	var raid := _raid_controller()
	if raid == null or is_boss() or is_guard() or _extract_planned:
		return  # A boss and its guards hold their ground.
	_extract_planned = true
	var rng := RandomNumberGenerator.new()
	if GameState.raid.has("seed"):
		rng.seed = hash([int(GameState.raid.seed), "extract", str(get_path())])
	else:
		rng.randomize()
	var window := raid.config.ai_pmc_extract_window
	if squad and squad.plan and side == Side.PMC:
		squad.extract_planned = true
		squad.extract_at = squad.plan.leave_at
		extract_at = squad.plan.leave_at
		return
	if squad and side == Side.PMC:
		extract_at = squad.plan_extract(raid, window, rng)
		return
	if side == Side.SCAV:
		if rng.randf() >= raid.config.ai_scav_extract_chance:
			return
		window = raid.config.ai_scav_extract_window
	extract_at = raid.raid_seconds() * rng.randf_range(window.x, window.y)


## Puts the gun in its kit in hand, loaded with the kit's rounds, with the matching rounds it carries as
## spares. Keeps the profile's sight (AI doesn't fiddle with optics).
func _equip_kit_gun() -> void:
	var slot := inventory.weapon_slot()
	var gun: ItemInstance = inventory.equipment[slot] if slot != "" else null
	if gun and gun.data.weapon:
		var ammo := gun.loaded_ammo if gun.loaded_ammo != "" else LootTable.ammo_for(gun.data.weapon.caliber)
		equip_weapon(gun.data.id, ammo, inventory.count_of(ammo), WeaponStats.build(gun))
		if gun.rounds_loaded() > 0:
			weapon.rounds = mini(gun.rounds_loaded(), weapon.data.magazine_size)
		if profile:
			weapon.optic = profile.optic
			weapon.recoil_control = profile.recoil_control
	spare_rounds = inventory.count_of(ammo_id)
	weapon.spare_rounds = spare_rounds


## A copy of `base` with every body part's HP × `multiplier` (the head's × its square root, so a
## headshot still counts).
static func _tougher(base: HealthConfig, multiplier: float) -> HealthConfig:
	var tough := base.duplicate() as HealthConfig
	tough.head_hp = roundf(base.head_hp * sqrt(multiplier))
	tough.thorax_hp = roundf(base.thorax_hp * multiplier)
	tough.stomach_hp = roundf(base.stomach_hp * multiplier)
	tough.arm_hp = roundf(base.arm_hp * multiplier)
	tough.leg_hp = roundf(base.leg_hp * multiplier)
	return tough


func _raid_controller() -> RaidController:
	return get_tree().get_first_node_in_group("raid_controller") as RaidController if is_inside_tree() else null


func worn_gear() -> Inventory:
	return inventory


## Its name in kill lists and death messages: a boss's or guard's title, an AI PMC's faction ("USEC
## operator"), else its profile's ("Scav").
func display_name() -> String:
	if title != "":
		return title
	if faction != &"":
		return Factions.member_name(faction)
	return profile.display_name if profile else super()


## True for a boss, and for one of its guards (role, set by BossSpawn: not for being in a squad).
func is_boss() -> bool:
	return role == &"boss"


func is_guard() -> bool:
	return role == &"guard"


## True if it's in a squad led by another bot that's still alive.
func is_follower() -> bool:
	return leader != null and not leader.is_dead


func is_squad_mate(other: Actor) -> bool:
	return squad != null and other != self and squad.has(other)


## Bots aim only at their target in a fight.
func aims_at(other: Actor) -> bool:
	return state == State.COMBAT and target == other and _sees_target and super(other)


## Whoever attacks one of a squad has the squad to deal with: its squad mates take `by` for an enemy
## too (no more holding back from a PMC of their faction that shot at one of them, DESIGN.md §3).
func provoke(by: Actor) -> void:
	var known := enemies.size()
	if _karma_hostile(by) and not by in enemies and not is_squad_mate(by):
		enemies.append(by)  # Hostile for the player Scav's karma alone so far: now for good, whatever it does next.
	else:
		super(by)
	if enemies.size() > known and squad:
		for mate in squad.mates_of(self):
			mate.provoke(by)


## Dies; of its wounds (a bleed: not a hit or a blow landing now), it's its last attacker's kill
## (RaidController.bot_died_of_wounds(): the player's Scav karma).
func die() -> void:
	var of_wounds := not is_dead and not _taking_hit and is_instance_valid(_last_attacker)
	super()
	if of_wounds:
		var raid := _raid_controller()
		if raid:
			raid.bot_died_of_wounds(self, _last_attacker)
	_loot_target = null  # Whatever it was after is free for others.
	_update_outline()
	# The body can be searched: its gun keeps the rounds left in it.
	var gun: ItemInstance = inventory.equipment[inventory.weapon_slot()] if inventory.weapon_slot() != "" else null
	if gun and gun.data.weapon:
		gun.magazine.clear()
		gun.load_rounds(ItemInstance.full_rounds(ammo_id, weapon.rounds))
	search = LootSearch.new(func() -> Array[InventoryGrid]: return inventory.grids())
	search.hide_all()
	add_to_group("interactables")


## The rounds a reload used come out of the rig and pockets, so the body has what's left.
func _on_reload_finished() -> void:
	var used := inventory.count_of(ammo_id) - weapon.spare_rounds
	if used > 0:
		inventory.take(ammo_id, used)


func interact_text() -> String:
	return ("Search body (%s)" if search == null or not search.is_done() else "Loot body (%s)") % display_name()


func can_interact(_player: Player) -> bool:
	return is_dead


func interact(player: Player) -> void:
	player.open_loot("BODY  ·  %s" % display_name().to_upper(), inventory, self)


## Bright outline for high-contrast mode: hostile bots in red-orange, neutral ones in cyan.
func _update_outline() -> void:
	var capsule := $Body/Capsule as MeshInstance3D
	if is_dead or not Settings.get_value("accessibility", "high_contrast_outlines"):
		capsule.material_overlay = null
		return
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = OUTLINE_SHADER
	var player := get_tree().get_first_node_in_group("player") as Actor
	_outline.set_shader_parameter("outline_color", HOSTILE_OUTLINE if player == null or is_hostile(player) else NEUTRAL_OUTLINE)
	capsule.material_overlay = _outline


func _think(delta: float) -> void:
	move_input = Vector3.ZERO
	sprint_input = false
	fire_input = false
	peek_input = false
	_crouch = false
	if not ai_enabled:
		return
	_clock += delta
	quiet_time += delta
	_heal_cooldown -= delta
	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer = Settings.ai_perceive_interval()  # Longer on the Mobile graphics preset.
		_perceive()
		if _wants_heal():
			_start_heal()
	_flee_cooldown -= delta
	if not is_boss() and not is_guard():
		if is_follower():
			if leader.state == State.EXTRACT and state in [State.IDLE, State.PATROL, State.TRAVEL, State.LOOT]:
				_loot_target = null
				_leg_stucks = 0
				_leg_best = INF
				state = State.EXTRACT  # The leader takes the squad out.
		elif plan() != null:
			_plan_tick(delta)
		elif state in [State.IDLE, State.PATROL, State.LOOT] and extract_at >= 0.0:
			var raid := _raid_controller()
			if raid and not raid.is_over() and raid.elapsed >= extract_at:
				_loot_target = null  # Time to go: whatever it was searching stays.
				state = State.EXTRACT
				_say(&"extract")
	match state:
		State.IDLE:
			_do_idle(delta)
		State.PATROL:
			_do_patrol(delta)
		State.INVESTIGATE, State.SEARCH:
			_do_investigate(delta)
		State.COMBAT:
			_do_combat(delta)
		State.EXTRACT:
			_do_extract(delta)
		State.LOOT:
			_do_loot(delta)
		State.FLEE:
			_do_flee(delta)
		State.TRAVEL:
			_do_travel(delta)
		State.HEAL:
			_do_heal(delta)
		State.AVOID:
			_do_avoid(delta)
	if state != State.COMBAT and _look_timer <= 0.0 and not move_input.is_zero_approx():
		aim_point = global_position + move_input * 5.0
		has_aim = true
	set_crouching(_crouch and not sprint_input and state != State.COMBAT and state != State.FLEE)
	if squad and squad.plan and squad.leader == self:
		squad.plan.goal = goal()


## Bullets flying past put the bot in combat with the shooter and make it duck or dodge.
func on_bullet_near(shooter: Actor) -> void:
	if is_dead or shooter == null or shooter.is_dead:
		return
	if holds_back_from(shooter):
		provoke(shooter)  # Shot at by its own faction: no more holding back.
	_attacked_by(shooter)
	if not ai_enabled or not is_hostile(shooter):
		return
	quiet_time = 0.0
	_say(&"hit")
	if state == State.FLEE:
		_last_known = shooter.global_position
		return  # Keeps running.
	if state != State.COMBAT:
		target = shooter
		_enter_combat()
	if shooter == target and not _sees_target:
		_last_known = shooter.global_position
	if cover and is_peeking:
		_duck()
	elif cover == null and profile.can_roll and randf() < profile.dodge_chance:
		_dodge(shooter.global_position)


## Heads for a raid event at `point` (RaidEvents): it goes there and looks around (waiting up to PmcAi
## plan rush_wait for the crate to land), then loots it. A boss and its guards stay on their haunt; a
## squad follower leaves it to its leader (the squad goes together); a squad with a plan that's
## heading out or treating a wound doesn't go.
func rush_to(point: Vector3) -> void:
	if is_dead or not ai_enabled or state == State.COMBAT or state == State.FLEE or is_boss() or is_guard():
		return
	if is_follower():
		leader.rush_to(point)
		return
	if plan() and (state == State.EXTRACT or state == State.HEAL):
		return
	exit_cover()
	_point_of_interest = point
	_look_timer = 0.0
	_urgent = false
	_hunting = null
	_rushing = true
	_rush_time = 0.0
	state = State.INVESTIGATE


## The chance it heads for a raid event at `point` (RaidEvents; Scavs use PoiConfig.rush_chance_scav):
## its personality's rush (PmcAi), none beyond the personality's rush_within or, for one that needs it
## quiet (a Rat), unless nothing has been seen or heard for plan avoid_quiet seconds. A PMC without a
## plan reacts like the default personality.
func rush_chance(point: Vector3) -> float:
	var knobs := personality() if plan() else PmcAi.personality(PmcAi.default_personality())
	if knobs.is_empty():
		return FALLBACK_RUSH_CHANCE
	var within := float(knobs.get("rush_within", 0.0))
	if within > 0.0 and global_position.distance_to(point) > within:
		return 0.0
	if knobs.get("rush_needs_quiet", false) and quiet_time < float(PmcAi.plan().get("avoid_quiet", 8.0)):
		return 0.0
	return float(knobs.get("rush", 0.0))


## Its squad's raid plan (an AI PMC squad RaidController spawned), or null.
func plan() -> RaidPlan:
	return squad.plan if squad else null


## Its squad's personality's knobs (PmcAi.personality()), {} without a plan.
func personality() -> Dictionary:
	var current := plan()
	return current.knobs() if current else {}


## What it's doing (a RaidPlan.Goal, for the plan and the debug overlay): fighting, investigating,
## hunting, rushing an event, travelling, looting, treating itself, hiding, heading out; a follower
## follows (or covers a squad mate treating itself); a leader waiting for its squad covers or regroups;
## a bot without a plan patrols.
func goal() -> RaidPlan.Goal:
	match state:
		State.COMBAT, State.FLEE:
			return RaidPlan.Goal.COMBAT
		State.INVESTIGATE:
			return RaidPlan.Goal.RUSH if _rushing else RaidPlan.Goal.HUNT if _hunting else RaidPlan.Goal.INVESTIGATE
		State.SEARCH:
			return RaidPlan.Goal.INVESTIGATE
		State.EXTRACT:
			return RaidPlan.Goal.EXTRACT
		State.LOOT:
			return RaidPlan.Goal.LOOT
		State.TRAVEL:
			return RaidPlan.Goal.TRAVEL
		State.HEAL:
			return RaidPlan.Goal.HEAL
		State.AVOID:
			return RaidPlan.Goal.AVOID
	if is_follower():
		return RaidPlan.Goal.COVER if squad.healer() else RaidPlan.Goal.FOLLOW
	if _hold_goal >= 0:
		return _hold_goal as RaidPlan.Goal
	var current := plan()
	if current == null:
		return RaidPlan.Goal.PATROL
	var poi := current.next_poi()
	return RaidPlan.Goal.LOOT if poi and _at_poi(poi) else RaidPlan.Goal.TRAVEL


func goal_name() -> String:
	return RaidPlan.GOAL_NAMES[goal()]


## How full its bags are for leaving (0-1): its squad's on average (Squad.fill()), or its own
## (loot_fill()) on its own.
func bag_fill() -> float:
	return squad.fill() if squad else loot_fill()


## How much of the room its kit left in its pockets, rig and backpack it has filled since it joined the
## raid (0-1): what it looted, not its own spare magazines, meds and food (kit_cells). 0 with no room
## left at all (it can't loot, so its bags never fill).
func loot_fill() -> float:
	if inventory == null:
		return 0.0
	var room := inventory.capacity() - kit_cells
	if room <= 0:
		return 0.0
	return clampf(float(inventory.used_cells() - kit_cells) / room, 0.0, 1.0)


## `by` attacked it: a Scav it was avoiding (a Rat's) is fought from now on.
func _attacked_by(by: Actor) -> void:
	if by and by != self and by.side == Side.SCAV and str(personality().get("scavs", "fight")) == "avoid" and not by in enemies:
		enemies.append(by)


# --- Senses ---------------------------------------------------------------------------------

func _perceive() -> void:
	_view = VisionSystem.view_for(self)
	var seen: Actor = null
	var shunned: Actor = null
	if target and not target.is_dead and _can_see(target):
		seen = target
	else:
		var nearest := INF
		var nearest_shunned := INF
		for node in get_tree().get_nodes_in_group("actors"):
			var other := node as Actor
			if other.is_dead or not is_hostile(other):
				continue
			var distance := global_position.distance_to(other.global_position)
			if not will_engage(other):
				if shuns(other) and distance < nearest_shunned and _can_see(other):
					nearest_shunned = distance
					shunned = other
				continue
			if distance < nearest and _can_see(other):
				nearest = distance
				seen = other
	if seen or shunned:
		quiet_time = 0.0
	if shunned and not seen and not state in [State.COMBAT, State.FLEE, State.EXTRACT, State.HEAL]:
		avoid_threat(shunned.global_position)  # A Rat keeps out of a Scav's way.
	if seen:
		if seen != target or not _sees_target:
			_seen_time = 0.0
		target = seen
		_sees_target = true
		_last_known = seen.global_position
		_lost_time = 0.0
		if squad:
			for mate in squad.mates_of(self):
				if mate.target == seen and not mate._sees_target:
					mate._last_known = _last_known  # The squad shares what it sees.
		if state != State.COMBAT and state != State.FLEE:
			_enter_combat()
			_say(&"contact")
	else:
		_sees_target = false


## Whether it starts a fight with `other` it can see: always, unless it holds back from it (a PMC of its
## own faction, DESIGN.md §3) and `other` is farther than the hold-fire distance without aiming at it,
## or it shuns it (a Rat and a Scav that hasn't attacked it).
func will_engage(other: Actor) -> bool:
	if shuns(other):
		return false
	if not hesitates_at(other):
		return true
	return global_position.distance_to(other.global_position) <= float(Factions.same_faction().get("hold_fire_beyond", 15.0))


## True if it holds back from `other` right now: a PMC of its own faction (holds_back_from()) that isn't
## aiming at it.
func hesitates_at(other: Actor) -> bool:
	return holds_back_from(other) and not other.aims_at(self)


## True if it keeps out of `other`'s way rather than fight it: a squad whose personality avoids Scavs
## (a Rat) and a Scav (a boss or guard too) that hasn't attacked it and isn't aiming at it.
func shuns(other: Actor) -> bool:
	return other.side == Side.SCAV and side == Side.PMC and str(personality().get("scavs", "fight")) == "avoid" \
		and not other in enemies and not other.aims_at(self)


## Seconds between first seeing its target and opening fire: its profile's reaction time, × the
## same-faction reaction_multiplier while it hesitates at the target, and a Scav's × the karma one
## (Player.karma_reaction: slower just under the line, quicker the lower your karma) for a player Scav it
## turned on for their karma alone.
func reaction_time() -> float:
	var seconds := profile.reaction_time if profile else 0.5
	if target and hesitates_at(target):
		seconds *= float(Factions.same_faction().get("reaction_multiplier", 1.0))
	if target is Player and side == Side.SCAV and target.side == Side.SCAV and target.scavs_hostile and not target in enemies:
		seconds *= target.karma_reaction
	return seconds


## Seen by the shared vision rules. In combat the bot keeps turning toward its target, so only the first
## sighting needs the cone; range, light and sight lines always apply.
func _can_see(other: Actor) -> bool:
	return VisionSystem.can_see(_view, other, state == State.COMBAT)


## Its profile's cone (from vision.tres: Scav or PMC), narrowed by pain or a head injury, plus a long
## narrow cone through a magnified optic, which it scans with.
func vision_cones() -> Array[Vector3]:
	var vision := VisionSystem.config
	var scav := side == Side.SCAV
	var half := deg_to_rad(vision.scav_cone_degrees if scav else vision.pmc_cone_degrees) / 2.0
	var reach := vision.scav_range if scav else vision.pmc_range
	var cones: Array[Vector3] = [Vector3(half * status_cone_multiplier(), reach * status_range_multiplier(), 0.0)]
	var optic := vision.optic(weapon.optic)
	if optic and optic.range_multiplier > 1.0:
		cones.append(Vector3(deg_to_rad(optic.cone_degrees) / 2.0, reach * optic.range_multiplier, 0.0))
	return cones


## A noise from a hostile actor within earshot (its radius × the bot's hearing): out of a fight it goes
## to investigate. Footsteps and the like it walks over to carefully; a gunshot or explosion
## (ALARMING_NOISES) it runs to, calling the Scavs of its zone within its alert radius to come too. A
## boss and its guards only go after noises near their haunt (near_haunt()).
func _on_noise(noise_position: Vector3, radius: float, source: Node, kind: StringName) -> void:
	if is_dead or not ai_enabled or source == self:
		return
	var other := source as Actor
	if other == null or not is_hostile(other):
		return
	if global_position.distance_to(noise_position) > radius * profile.hearing * hearing_multiplier():
		return
	quiet_time = 0.0
	if state == State.COMBAT or state == State.FLEE:
		if other == target and not _sees_target:
			_last_known = noise_position
		return
	if not near_haunt(noise_position):
		return  # A fight away from its haunt doesn't draw a boss squad off it.
	if plan():
		(leader if is_follower() else self).hear(noise_position, kind, other)
		return
	var alarming := kind in ALARMING_NOISES
	if state == State.INVESTIGATE and _urgent and not alarming:
		return  # Already running to a gunshot: a footstep doesn't change that.
	if squad:
		squad.investigate(noise_position, alarming)  # The squad goes together.
	else:
		investigate(noise_position, alarming)
	if alarming:
		_alert_zone(noise_position)


## True if `point` is within its profile's haunt_radius of its haunt (boss_spawn): the only noises a
## boss or guard leaves the haunt for (DESIGN.md §4.3). Always true for other bots.
func near_haunt(point: Vector3) -> bool:
	if boss_spawn == null or profile == null or profile.haunt_radius <= 0.0:
		return true
	return point.distance_to(boss_spawn.global_position) <= profile.haunt_radius


## Goes to look at `point` (INVESTIGATE): running if `urgent`, walking otherwise.
func investigate(point: Vector3, urgent := false) -> void:
	exit_cover()
	_point_of_interest = point
	_look_timer = 0.0
	_urgent = urgent
	_rushing = false
	_hunting = null
	state = State.INVESTIGATE


## What a planned squad's leader does about a hostile noise from `source` (DESIGN.md §4.4, by
## personality): a Rat hides from one within its avoid_within (avoid_threat()); the others go to look, the
## squad together, by their investigate chance for its kind (rolled once per noise maker and kind every
## plan noise_memory seconds): a Looter only near the route it's on, a Quester only close by, a Chad
## anything, running to gunfire and hunting whoever it hears (it follows that one's noises without a
## roll). A squad heading out or treating a wound carries on.
func hear(point: Vector3, kind: StringName, source: Actor) -> void:
	if is_dead or state in [State.COMBAT, State.FLEE, State.EXTRACT, State.HEAL]:
		return
	var knobs := personality()
	var category := PmcAi.noise_category(kind)
	var alarming := category == "gunshot"
	if _hunting == source and state == State.INVESTIGATE:
		_point_of_interest = point  # Still after it.
		_look_timer = 0.0
		return
	if knobs.get("avoids_noise", false):
		var reach := float(knobs.get("avoid_within", 0.0))
		if reach <= 0.0 or global_position.distance_to(point) <= reach:
			avoid_threat(point)
		return
	if state == State.INVESTIGATE and _urgent and not alarming:
		return  # Already running to a gunshot: a footstep doesn't change that.
	var within := float(knobs.get("investigate_within", 0.0))
	if within > 0.0 and global_position.distance_to(point) > within:
		return
	var near_route := float(knobs.get("investigate_near_route", 0.0))
	if near_route > 0.0 and distance_to_route(point) > near_route:
		return
	var key := "%d/%s" % [source.get_instance_id(), category]
	var now := float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second
	if now < float(_noise_rolls.get(key, -1.0)):
		return
	_noise_rolls[key] = now + float(PmcAi.plan().get("noise_memory", 10.0))
	if _rng.randf() >= float(knobs.get("investigate", {}).get(category, 0.0)):
		return
	var hunt := bool(knobs.get("hunts", false)) and (alarming or source is Player)
	if squad:
		squad.investigate(point, alarming or hunt)
	else:
		investigate(point, alarming or hunt)
	if hunt:
		_hunting = source
		_hunt_time = 0.0


## Flat metres from `point` to the way it's going: its route from where it is (TRAVEL), else the line
## to its plan's next POI (its own position if it has neither).
func distance_to_route(point: Vector3) -> float:
	var line := PackedVector3Array([global_position])
	if state == State.TRAVEL and route.size() >= 2:
		line.append_array(route.slice(mini(_route_index, route.size() - 1)))
	elif plan() and plan().next_poi():
		line.append(RaidPlan.poi_point(plan().next_poi()))
	var flat := Vector2(point.x, point.z)
	var best := flat.distance_to(Vector2(global_position.x, global_position.z))
	for i in range(1, line.size()):
		var a := Vector2(line[i - 1].x, line[i - 1].z)
		var b := Vector2(line[i].x, line[i].z)
		best = minf(best, flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, a, b)))
	return best


## True if `other` is a Scav of its zone (the same ScavZone, or the same wave).
func same_zone(other: Bot) -> bool:
	if other == self or other.side != side or other.squad != null:
		return false
	return (zone != null and other.zone == zone) or (zone == null and wave > 0 and other.wave == wave)


## A gunshot it heard: the Scavs of its zone within its profile's alert_radius that aren't fighting run
## there too.
func _alert_zone(point: Vector3) -> void:
	if profile == null or profile.alert_radius <= 0.0 or squad != null:
		return
	for node in get_tree().get_nodes_in_group("bots"):
		var mate := node as Bot
		if mate == null or mate.is_dead or not mate.ai_enabled or not same_zone(mate):
			continue
		if mate.state == State.COMBAT or mate.state == State.FLEE or mate.state == State.EXTRACT:
			continue
		if mate.global_position.distance_to(global_position) <= profile.alert_radius:
			mate.investigate(point, true)


# --- States ---------------------------------------------------------------------------------

## Stands looking around (for PATROL_PAUSE at a patrol stop), then patrols on if it has somewhere to
## go, or a squad leader with a raid plan works through it (_work_plan()). A squad follower keeps to its
## spot by the leader instead, covers a squad mate treating itself, and while its leader loots a point of
## interest loots it too. Picks up loot it notices nearby.
func _do_idle(delta: float) -> void:
	if is_follower():
		if _cover_mate():
			return
		var looting := _leader_looting()
		if (looting and _notice_loot(delta)) or _follow_leader() or (not looting and _notice_loot(delta)):
			return
	else:
		if plan() and not _ensure_plan():
			return  # The navmesh isn't ready yet.
		if plan() and _cover_mate():
			_hold_goal = RaidPlan.Goal.COVER  # Before anything else: a squad mate is treating itself.
			return
		if _notice_loot(delta):
			return
	if _look_timer > 0.0:
		_look_around(delta)
		return
	if is_follower():
		return  # Where the leader goes, it goes.
	if plan():
		_work_plan(delta)
		return
	if not wander_points.is_empty() or not patrol_points.is_empty():
		state = State.PATROL


## Walks to its next patrol point, then stands and looks around there (IDLE). A squad leader with
## followers calls the move.
func _do_patrol(delta: float) -> void:
	if is_follower():
		state = State.IDLE
		return
	if _notice_loot(delta):
		return
	if not _has_patrol_goal:
		_patrol_goal = _next_patrol_point()
		_has_patrol_goal = true
		if squad and not squad.followers().is_empty():
			_say(&"move")
	if _move_to(_patrol_goal, false):
		_has_patrol_goal = false
		_look_timer = randf_range(PATROL_PAUSE.x, PATROL_PAUSE.y)
		state = State.IDLE


## The next point to patrol to: sometimes a hot point of interest (BotProfile.hot_poi_chance), else a
## random point of its zone other than the one it's at, else the next stop of its route.
func _next_patrol_point() -> Vector3:
	var raid := _raid_controller()
	if profile and randf() < profile.hot_poi_chance and raid and patrol_points.is_empty():
		var hot: Variant = raid.hot_point(global_position)
		if hot != null:
			return hot
	if not wander_points.is_empty():
		var options := Array(wander_points).filter(func(point: Vector3) -> bool:
			return point.distance_to(global_position) > 2.0)
		if options.is_empty():
			return wander_points[0]
		return options[randi() % options.size()]
	if patrol_points.is_empty():
		return global_position
	var point := patrol_points[_patrol_index]
	_patrol_index = (_patrol_index + 1) % patrol_points.size()
	return point


## A squad follower out of a fight keeps to its spot by the leader (Squad.formation_spot(): a guard
## around its boss, a PMC behind its leader), sprinting when it has fallen far behind. True while it's
## walking there; false once it's close (it then looks around) or if it has no leader left.
func _follow_leader() -> bool:
	if not is_follower():
		return false
	var spot := squad.formation_spot(self)
	if Vector2(spot.x - global_position.x, spot.z - global_position.z).length() <= squad.tolerance:
		return false
	var far := global_position.distance_to(spot) > squad.catch_up
	_crouch = leader.is_crouching and not far  # A Rat squad creeps together.
	_move_to(spot, far or leader.move_state == Move.SPRINT)
	return true


## A squad mate is treating itself (HEAL): it stands by it, looking out the other way, to cover it.
## True while it does.
func _cover_mate() -> bool:
	var healer := squad.healer() if squad else null
	if healer == null or healer == self:
		return false
	var away := global_position - healer.global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	if away.length() > COVER_MATE_DISTANCE + 1.0:
		_move_to(healer.global_position + away.normalized() * COVER_MATE_DISTANCE, false)
		return true
	var sweep := sin(_clock * 0.7 + _look_phase) * 0.8
	aim_point = global_position + away.normalized().rotated(Vector3.UP, sweep) * 5.0
	has_aim = true
	return true


## True while its leader loots (or is about to loot) a point of interest: the squad loots it together.
func _leader_looting() -> bool:
	return is_follower() and leader.plan() != null and (leader.state == State.LOOT or (leader.state == State.IDLE
		and leader.goal() == RaidPlan.Goal.LOOT))


# --- Raid plan --------------------------------------------------------------------------------

## A squad leader with a raid plan picks its POIs and extract as soon as it can (_ensure_plan()), then
## checks every PmcAi plan tick (out of a fight: on its way, looting or hiding) whether to head for its
## extract (leave_reason()); then it does, calling it (_head_out()).
func _plan_tick(delta: float) -> void:
	if not plan().chosen:
		_ensure_plan()  # Fighting from the start or not: it knows where it's going.
		return
	_plan_timer -= delta
	if _plan_timer > 0.0:
		return
	_plan_timer = float(PmcAi.plan().get("tick", 0.5))
	if not plan().chosen or not state in [State.IDLE, State.PATROL, State.TRAVEL, State.LOOT, State.AVOID]:
		return
	var why := leave_reason()
	if why != "":
		_head_out(why)


## Why the squad should head for its extract now ("" if not yet): its leave time ("time"), the raid
## clock too low to walk there and extract with plan extract_margin to spare ("low time"), its bags
## fuller than its personality's bag_full ("bags full"; not a Quester, which visits its quest POIs
## first), or every POI visited ("plan done").
func leave_reason() -> String:
	var raid := _raid_controller()
	var current := plan()
	if raid == null or raid.is_over() or current == null or not current.chosen:
		return ""
	if _extract_retry_at >= 0.0 and raid.elapsed < _extract_retry_at:
		return ""  # Nowhere to go a moment ago.
	if current.leave_at >= 0.0 and raid.elapsed >= current.leave_at:
		return "time"
	if raid.time_left <= seconds_to_extract():
		return "low time"
	if bag_fill() >= float(current.knobs().get("bag_full", 1.0)) and not current.knobs().get("pois", {}).get("quest", false):
		return "bags full"  # (A Quester sees its quest POIs through first.)
	if current.is_done():
		return "plan done"
	return ""


## Roughly how many seconds it needs to get out from here: walking to its planned extract (the straight
## line × plan detour_estimate at walking speed), the extract time and plan extract_margin.
func seconds_to_extract() -> float:
	var raid := _raid_controller()
	var current := plan()
	var zone: ExtractZone = current.extract if current and is_instance_valid(current.extract) else null
	var tuning := PmcAi.plan()
	var walk := 0.0
	if zone:
		walk = global_position.distance_to(zone.global_position) * float(tuning.get("detour_estimate", 1.4)) / maxf(walk_speed, 0.5)
	return walk + (raid.config.extract_seconds if raid else 7.0) + float(tuning.get("extract_margin", 60.0))


## Sets off for the extract (EXTRACT), saying why in the plan and calling it. Not yet while one of the
## squad has a bleed or a fracture it can treat (can_patch_wound(): it treats it first, HEAL, once it's
## quiet), unless the raid clock is running low. True if it set off.
func _head_out(why: String) -> bool:
	if why != "low time" and squad and squad.alive().any(func(mate: Bot) -> bool: return mate.can_patch_wound()):
		return false
	var current := plan()
	if current:
		current.reason = why
	_loot_target = null
	route = PackedVector3Array()
	_extract_zone = null
	_blocked_extracts.clear()
	_hold_goal = -1
	exit_cover()
	CoverSystem.release(self)  # Out of its hiding spot too (AVOID).
	_avoid_cover = null
	state = State.EXTRACT
	_say(&"extract")
	return true


## Works through the raid plan out of a fight: picks its POIs and extract the first time (once the
## navmesh is ready: RaidPlan.choose()), covers a squad mate treating itself, loots the POI it's at
## one container, body or loose item at a time (LOOT) until there's nothing it wants left, waits for the
## squad to regroup (plan regroup_distance, at most regroup_timeout), then travels to the next POI
## (TRAVEL). With every POI done it heads out.
func _work_plan(delta: float) -> void:
	var current := plan()
	if _work_timer > 0.0:
		_work_timer -= delta
		_look_around_slowly()
		return
	_hold_goal = -1
	if not _ensure_plan():
		return
	if _cover_mate():
		_hold_goal = RaidPlan.Goal.COVER
		return
	var poi := current.next_poi()
	if poi == null and current.pois.is_empty():
		if not wander_points.is_empty() or not patrol_points.is_empty():
			state = State.PATROL  # No POI it can reach: it roams until it's time to go.
		return
	if poi == null:
		if not _head_out("plan done"):
			_hold_goal = RaidPlan.Goal.HEAL  # It patches up first.
			_work_timer = WORK_PAUSE
		return
	if _at_poi(poi):
		var target := _poi_loot(poi)
		if target:
			_start_loot(target)
			return
		if _waiting_for_squad(delta, true):
			return
		current.advance()
		return
	if _waiting_for_squad(delta, false):
		return
	_start_travel(RaidPlan.poi_point(poi))


## Picks the plan's POIs and extract if it hasn't yet (RaidPlan.choose(): the squad goes through the
## plan's extract). False while the navmesh isn't ready.
func _ensure_plan() -> bool:
	var current := plan()
	if current.chosen:
		return true
	if not current.choose(self, squad.alive()):
		return false
	squad.extract_zone = current.extract
	return true


## True if it's at (or in) `poi`: inside its box, or within plan poi_reach of its centre.
func _at_poi(poi: PointOfInterest) -> bool:
	return poi.contains(global_position) or _flat_distance(RaidPlan.poi_point(poi)) <= float(PmcAi.plan().get("poi_reach", 3.0))


## Holds (REGROUP) while a follower is still looting (`looting`) or farther than combat regroup_distance
## from its spot by it, for at most regroup_timeout seconds. True while it holds.
func _waiting_for_squad(delta: float, looting: bool) -> bool:
	var tuning := PmcAi.combat()
	var behind := squad.followers().any(func(mate: Bot) -> bool:
		return (looting and mate.state == State.LOOT) or mate.state == State.HEAL \
			or mate.global_position.distance_to(squad.formation_spot(mate)) > float(tuning.get("regroup_distance", 6.0)))
	if not behind or _hold_time >= float(tuning.get("regroup_timeout", 20.0)):
		return false
	_hold_time += delta + WORK_PAUSE
	_work_timer = WORK_PAUSE
	_hold_goal = RaidPlan.Goal.REGROUP
	_look_around_slowly()
	return true


## The nearest thing in `poi` it would loot (_loot_candidates()) that no other bot is fetching; null when
## the POI has nothing more for it.
func _poi_loot(poi: PointOfInterest) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in _loot_candidates():
		if not poi.contains(node.global_position) or _fetched_by_other(node):
			continue
		var distance := global_position.distance_to(node.global_position)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best


## Sets off along a route to `goal` that keeps to walls and cover (CoverRoute; TRAVEL), calling the move
## to its squad.
func _start_travel(goal_point: Vector3) -> void:
	_build_route(goal_point)
	_hold_time = 0.0
	state = State.TRAVEL
	if squad and not squad.followers().is_empty():
		_say(&"move")


## Works out its route to `goal_point` (CoverRoute: along walls and cover), starting a new leg if it's
## going somewhere else; once it has got stuck on this leg REROUTE_AFTER times, the plain way from a step
## to the side instead (_unstick_route()). With no route at all it walks straight there and asks again
## ROUTE_RETRY_TIME later (_follow_route()).
func _build_route(goal_point: Vector3) -> void:
	routes_built += 1
	if not _has_leg or _leg_goal.distance_to(goal_point) > 1.0:
		_has_leg = true
		_leg_goal = goal_point
		_leg_stucks = 0
		_leg_best = _flat_distance(goal_point)
	_leg_failed = false
	var built := _unstick_route(goal_point) if _leg_stucks >= REROUTE_AFTER else \
		CoverRoute.build(get_world_3d().navigation_map, global_position, goal_point, CoverSystem.get_points(), PmcAi.route())
	route = built.points
	_route_cover = built.cover
	_route_index = 0
	_route_goal = goal_point
	if route.size() < 2:
		_route_retry_at = _clock + ROUTE_RETRY_TIME


## A way to `goal_point` that gets it off whatever it's stuck on: a step UNSTICK_STEP metres to the side
## of the way it was going (left and right by turns) and half a metre back, then the plain navmesh path
## from there. In CoverRoute.build()'s form.
func _unstick_route(goal_point: Vector3) -> Dictionary:
	var map := get_world_3d().navigation_map
	var ahead := (route[_route_index] if _route_index < route.size() else goal_point) - global_position
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.1 else -global_basis.z
	var side := ahead.cross(Vector3.UP) * (1.0 if _leg_stucks % 2 == 0 else -1.0)
	var step := global_position + side * UNSTICK_STEP - ahead * 0.5
	var points := PackedVector3Array([global_position])
	if NavigationServer3D.map_get_iteration_id(map) != 0:
		step = NavigationServer3D.map_get_closest_point(map, step)
		points.append(step)
		var path := CoverRoute.plain(map, step, goal_point)
		points.append_array(path.slice(1) if path.size() >= 2 else PackedVector3Array([goal_point]))
	var flags := PackedByteArray()
	flags.resize(points.size())
	return {"points": points, "cover": flags, "plain": CoverRoute.length(points), "length": CoverRoute.length(points)}


## Walks its route to the next POI (a Chad sprinting, a Rat crouching near POIs and along cover), picking
## up loot on the way; there, it's IDLE again and loots the POI. It stops for a squad mate treating
## itself. A route that ends short of the POI counts as getting stuck on the leg (_leg_stuck()); a leg it
## gives up skips the POI (RaidPlan.skip()).
func _do_travel(delta: float) -> void:
	if is_follower() or plan() == null:
		state = State.IDLE
		return
	if squad.healer() != null:
		state = State.IDLE  # Cover it.
		return
	if _notice_loot(delta):
		return
	var poi := plan().next_poi()
	if poi and poi.contains(global_position):
		state = State.IDLE
		return
	_crouch = _wants_crouch()
	var sprint := bool(personality().get("movement", {}).get("sprint", false)) and not _crouch
	if not _follow_route(sprint):
		return
	if not _leg_failed and not _stuck and poi and not _at_poi(poi):
		_leg_stuck()  # The way ran out short of it.
		if not _leg_failed:
			return
	if _leg_failed and poi:
		plan().skip()  # It can't get there: on to the next.
	state = State.IDLE


## Steps along `route` (each waypoint within route waypoint_reach counts as reached; getting stuck on the
## way: _leg_move()). True at its end, or once it gives the leg up (_leg_failed). With no route it walks
## straight to the goal, asking for one again every ROUTE_RETRY_TIME.
func _follow_route(sprint: bool) -> bool:
	if route.size() < 2 and _clock >= _route_retry_at:
		_build_route(_route_goal)
	if route.size() < 2:
		return _leg_move(_route_goal, sprint)
	var reach := float(PmcAi.route().get("waypoint_reach", 1.0))
	while _route_index < route.size() - 1 and _flat_distance(route[_route_index]) < reach:
		_route_index += 1
	if _route_index >= route.size() - 1:
		return _leg_move(route[-1], sprint)
	var at := _route_index
	if _leg_move(route[at], sprint):
		if _leg_failed:
			return true
		_route_index = at + 1  # There, or stuck on the way: on to the next.
	return false


## _move_to() `point` on its leg: true once there, or stuck (counted: _leg_stuck()) on a waypoint it
## then skips, or once it gives the leg up; false while it walks, or after it worked out a new route.
func _leg_move(point: Vector3, sprint: bool) -> bool:
	var there := _move_to(point, sprint)
	if not _stuck:
		return there
	return not _leg_stuck() or _leg_failed


## It got stuck on its leg (or its route ended short of the goal): from REROUTE_AFTER times on it takes a
## way from a step to the side (_build_route()), at GIVE_UP_AFTER it gives the leg up (_leg_failed). True
## if it worked out a new route.
func _leg_stuck() -> bool:
	_count_stuck(_route_goal)
	if _leg_stucks >= GIVE_UP_AFTER:
		_leg_failed = true
		return false
	if _leg_stucks >= REROUTE_AFTER:
		_build_route(_route_goal)
		return true
	return false


## Counts a time stuck on the way to `goal_point` (_leg_stucks), from one again if it has got LEG_PROGRESS
## metres nearer since it last got stuck.
func _count_stuck(goal_point: Vector3) -> void:
	var left := _flat_distance(goal_point)
	if left < _leg_best - LEG_PROGRESS:
		_leg_stucks = 0  # It got on since: a new obstacle, not the same one.
	_leg_best = minf(_leg_best, left)
	_leg_stucks += 1


## Whether it crouch-walks now (its personality's movement): within crouch_near_poi of the POI it's
## going to (or in it), or at a cover spot on its route (crouch_along_cover).
func _wants_crouch() -> bool:
	var movement: Dictionary = personality().get("movement", {})
	var near := float(movement.get("crouch_near_poi", 0.0))
	var poi := plan().next_poi() if plan() else null
	if near > 0.0 and poi and (poi.contains(global_position) or _flat_distance(poi.global_position) <= near):
		return true
	if movement.get("crouch_along_cover", false) and route.size() >= 2:
		for i in [_route_index - 1, _route_index]:
			if i >= 0 and i < _route_cover.size() and _route_cover[i] == 1 and _flat_distance(route[i]) <= 2.5:
				return true
	return false


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


## Turns slowly round, by its own clock (so a seeded raid repeats).
func _look_around_slowly() -> void:
	var angle := _clock * 0.6 + _look_phase
	aim_point = global_position + Vector3(sin(angle), 0.0, cos(angle)) * 5.0
	has_aim = true


# --- After a fight ----------------------------------------------------------------------------

## Whether to treat itself now (HEAL): out of a fight (idle, on its way or searching), quiet for heal
## quiet_seconds, needing it (needs_treatment()) and carrying something for it. Only profiles that heal
## after fights (AI PMCs).
func _wants_heal() -> bool:
	if profile == null or not profile.heals_after_fights or _heal_cooldown > 0.0 or is_dead:
		return false
	if not state in [State.IDLE, State.PATROL, State.TRAVEL, State.SEARCH]:
		return false
	if quiet_time < float(PmcAi.heal().get("quiet_seconds", 6.0)) or not needs_treatment():
		return false
	return not pick_treatment().is_empty()


## True if it has a bleed or a fracture, or its HP is below heal below of its total and it carries
## something that heals HP (lost HP nothing it has can bring back, like a blacked limb's, doesn't count).
func needs_treatment() -> bool:
	if _wounded():
		return true
	if health.total() >= health.max_total() * float(PmcAi.heal().get("below", 0.85)):
		return false
	return _carried_meds().any(func(item: ItemInstance) -> bool: return float(Consumables.plan(item, health).get("heal", 0.0)) > 0.0)


## True if it has a bleed or a fracture it carries something for (its backpack too), and it treats its
## wounds after a fight (an AI PMC): its squad patches it up before heading out (_head_out()).
func can_patch_wound() -> bool:
	if is_dead or profile == null or not profile.heals_after_fights or not _wounded():
		return false
	return _carried_meds().any(func(item: ItemInstance) -> bool:
		return Array(Consumables.plan(item, health).get("fix", [])).any(func(condition: String) -> bool:
			return condition in ["heavy_bleed", "light_bleed", "fracture"]))


func _wounded() -> bool:
	return health.bleeds.has(BodyHealth.Bleed.HEAVY) or health.bleeds.has(BodyHealth.Bleed.LIGHT) or health.fractures.has(true)


## The meds (not stims) in its pockets, rig, backpack and secure container.
func _carried_meds() -> Array[ItemInstance]:
	var meds: Array[ItemInstance] = []
	if inventory == null:
		return meds
	for grid in inventory.grids():
		for item in grid.items:
			if item.data.category == ItemData.Category.MEDS and not Stims.is_stim(item.data):
				meds.append(item)
	return meds


## Stops and treats itself (HEAL), crouched, while its squad mates cover it.
func _start_heal() -> void:
	exit_cover()
	_set_goal_cover(null)
	_loot_target = null
	_treatments = 0
	_treat_timer = -1.0
	_look_timer = 0.0
	state = State.HEAL
	_next_treatment()


## One treatment after another (each its item's use time), up to heal max_treatments, while it still
## needs treating and has something for it; then back to what it was doing.
func _do_heal(delta: float) -> void:
	_crouch = true
	_look_around_slowly()
	_treat_timer -= delta
	if _treat_timer > 0.0:
		return
	_apply_treatment()
	_treatments += 1
	if _treatments < int(PmcAi.heal().get("max_treatments", 4)) and needs_treatment() and not pick_treatment().is_empty():
		_next_treatment()
	else:
		_heal_cooldown = float(PmcAi.heal().get("cooldown", 10.0))
		state = State.IDLE


## Keeps out of the way of something at `threat` (AVOID: a Rat and a Scav it saw or a noise it heard):
## crouched, in the nearest cover that hides it from there, else plan avoid_distance away from it,
## until it has been quiet for plan avoid_quiet seconds. If it still isn't quiet after plan
## avoid_give_up seconds (a Scav standing in its way, a fight that goes on) it stops waiting: a threat
## nearer its next POI than it is makes it skip that POI (a detour: on to the next one, RaidPlan.skip()),
## and it doesn't hide again for plan avoid_calm seconds. The time adds up over the times it hides from
## the same spot (out of sight in cover it gets quiet, walks on and sees the Scav again). Time to leave
## the raid ends it too (_plan_tick()). A follower leaves it to its leader.
func avoid_threat(threat: Vector3) -> void:
	if is_follower():
		leader.avoid_threat(threat)
		return
	if is_dead or state in [State.COMBAT, State.FLEE, State.HEAL, State.EXTRACT] or _clock < _avoid_calm_until:
		return
	_avoid_quiet = 0.0
	if state == State.AVOID and threat.distance_to(_avoid_from) < 5.0:
		return  # Still hiding from it.
	if state != State.AVOID and threat.distance_to(_avoid_from) >= 5.0:
		_avoid_time = 0.0  # Something new (hiding from the same thing again goes on counting).
	_avoid_from = threat
	exit_cover()
	_loot_target = null
	_avoid_cover = CoverSystem.find_cover(self, threat, profile.cover_search_radius) if profile else null
	CoverSystem.claim(self, _avoid_cover)
	if _avoid_cover:
		_avoid_goal = _avoid_cover.position
	else:
		var away := global_position - threat
		away.y = 0.0
		_avoid_goal = global_position + (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) * float(PmcAi.plan().get("avoid_distance", 12.0))
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) != 0:
			_avoid_goal = NavigationServer3D.map_get_closest_point(map, _avoid_goal)
	_look_timer = 0.0
	state = State.AVOID


func _do_avoid(delta: float) -> void:
	_crouch = true
	_avoid_quiet += delta
	_avoid_time += delta
	if cover == null and _move_to(_avoid_goal, false) and _avoid_cover and global_position.distance_to(_avoid_cover.position) < 1.0:
		enter_cover(_avoid_cover)
	if cover or move_input.is_zero_approx():
		aim_point = _avoid_from + Vector3.UP * 1.2
		has_aim = true
	var tuning := PmcAi.plan()
	if _avoid_quiet >= float(tuning.get("avoid_quiet", 8.0)):
		_stop_avoiding()  # Quiet again: on with the plan.
	elif _avoid_time >= float(tuning.get("avoid_give_up", 20.0)):
		var poi := plan().next_poi() if plan() else null
		if poi and _avoid_from.distance_to(RaidPlan.poi_point(poi)) < _flat_distance(RaidPlan.poi_point(poi)):
			plan().skip()  # It's in the way: round it, to the next POI.
		_avoid_calm_until = _clock + float(tuning.get("avoid_calm", 30.0))
		_avoid_time = 0.0
		_stop_avoiding()


func _stop_avoiding() -> void:
	exit_cover()
	CoverSystem.release(self)
	_avoid_cover = null
	state = State.IDLE


# --- Looting --------------------------------------------------------------------------------

## Every LOOT_SCAN_TIME, looks for loot within its profile's loot_radius: loose items on the ground,
## ready raid event crates it hasn't looted (DESIGN.md §5.2) and, if its profile searches (AI PMCs),
## containers and bodies. Goes for the nearest (LOOT). True if it found some. Guards don't wander off to
## loot; a squad follower only takes loot near its leader (farther while the squad loots a POI); nobody
## loots while a squad mate treats itself (they cover it).
func _notice_loot(delta: float) -> bool:
	if profile == null or profile.loot_radius <= 0.0 or is_guard() or _mate_healing():
		return false
	_loot_scan -= delta
	if _loot_scan > 0.0:
		return false
	_loot_scan = LOOT_SCAN_TIME
	var found := find_loot()
	if found == null:
		return false
	_start_loot(found)
	return true


## The nearest loot it would go for now (null: none): one of _loot_candidates() within its loot radius,
## on its floor, in sight and not already being fetched by another bot.
func find_loot() -> Node3D:
	var best: Node3D = null
	var best_distance := profile.loot_radius if profile else 0.0
	var near_leader := 0.0
	if is_follower():
		near_leader = float(PmcAi.loot().get("follower_radius", 12.0)) if _leader_looting() else squad.catch_up
	for node in _loot_candidates():
		var distance := global_position.distance_to(node.global_position)
		if distance >= best_distance or absf(node.global_position.y - global_position.y) > 1.5:
			continue
		if _fetched_by_other(node) or not VisionSystem.line_clear(get_world_3d().direct_space_state, global_position, _sight_point(node), true):
			continue
		if is_follower() and node.global_position.distance_to(leader.global_position) > near_leader:
			continue  # Too far from the leader: the squad stays together.
		best = node
		best_distance = distance
	return best


## Everything it would loot out of a fight: loose items, ready raid event crates it hasn't looted, and if
## its profile searches, containers it can open (searchable_box()) and bodies with something in their
## pockets, rig or backpack (searchable_body()).
func _loot_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	var searches := profile != null and profile.searches
	for node in get_tree().get_nodes_in_group("interactables"):
		if node is LootPickup:
			if node.item != null and not node.has_meta("bots_skip"):
				candidates.append(node)
		elif searches and node is LootBox:
			if searchable_box(node):
				candidates.append(node)
		elif searches and node is Bot:
			if searchable_body(node):
				candidates.append(node)
	var events := get_tree().get_first_node_in_group("raid_events") as RaidEvents
	if events:
		for event: Dictionary in events.events:
			var box: Variant = event.box
			if event.ready and is_instance_valid(box) and not box in _looted_boxes and not box.grid.items.is_empty() and not box.has_meta(Player.LOOTING_META):
				candidates.append(box)
	return candidates


## True if it would search `box`: a container (not a raid event's crate, those are taken as they are)
## with something in it, not sealed, not one it has been through or couldn't reach, not one you have open
## (Player.LOOTING_META), and not hidden unless it's under floorboards in a POI its plan knows (it pries
## them up).
func searchable_box(box: LootBox) -> bool:
	if box.sealed or box.ignore_poi or box in _looted_boxes or box.has_meta("bots_skip") or box.has_meta(Player.LOOTING_META) \
			or box.grid == null or box.grid.items.is_empty():
		return false
	if box.concealed:
		return box.get_parent() is FloorHatch and bool(personality().get("pois", {}).get("knows_hidden", false))
	return true


## True if it would search `body`: someone else's, dead (not one who left the raid), with something in its
## pockets, rig or backpack, not one it has been through or you have open (Player.LOOTING_META).
func searchable_body(body: Bot) -> bool:
	if body == self or not body.is_dead or body.extracted or body.inventory == null or body in _looted_boxes or body.has_meta("bots_skip") \
			or body.has_meta(Player.LOOTING_META):
		return false
	return body.inventory.grids().any(func(grid: InventoryGrid) -> bool: return not grid.items.is_empty())


## Where it checks its line of sight to `node`: a container's side facing it (a tall one hides its own
## middle), else the thing itself.
func _sight_point(node: Node3D) -> Vector3:
	if node is LootBox and (node as LootBox).container:
		var size := (node as LootBox).container.box_size
		var toward := global_position - node.global_position
		toward.y = 0.0
		return node.global_position + toward.normalized() * (maxf(size.x, size.z) / 2.0 + 0.3)
	return node.global_position


## Goes for `target` (LOOT): to the nearest point of the navmesh by it.
func _start_loot(target: Node3D) -> void:
	_loot_target = target
	_loot_timer = 0.0
	_loot_time = 0.0
	_loot_reach = LOOT_REACH
	_loot_spot = target.global_position
	if target is LootBox and (target as LootBox).container:
		var size := (target as LootBox).container.box_size
		_loot_reach = LOOT_REACH + maxf(size.x, size.z) / 2.0
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) != 0:
		_loot_spot = NavigationServer3D.map_get_closest_point(map, target.global_position)
	exit_cover()
	state = State.LOOT


## The search of `node` if it's searched before anything is taken: a container's or a body's (null for
## loose loot and raid event crates).
func _search_of(node: Node3D) -> LootSearch:
	if node is LootBox and not (node as LootBox).ignore_poi:
		return (node as LootBox).search
	if node is Bot:
		return (node as Bot).search
	return null


## True if another bot (alive and in the raid) is already on its way to `node`.
func _fetched_by_other(node: Node3D) -> bool:
	for other in get_tree().get_nodes_in_group("bots"):
		if other != self and not other.is_dead and not other.extracted and other.state == State.LOOT and other._loot_target == node:
			return true
	return false


## Walks to its loot (a Rat crouched), then: loose loot and raid event crates it spends LOOT_SECONDS
## picking up and takes (from a crate its best CRATE_TAKES items); a container or a body it searches
## first, with the same search time as the player (LootSearch; floorboards over a stash it pries up),
## then takes the most valuable things that fit. Then it stands and looks around. Drops it if the loot is
## gone, out of reach or opened by you (Player.LOOTING_META: it may come back for it), after LOOT_GIVE_UP
## seconds getting there or loot give_up seconds at it, (a follower) once its leader moves on, or when a
## squad mate starts treating itself (it covers it, then comes back: a search keeps its progress).
func _do_loot(delta: float) -> void:
	var gone := not is_instance_valid(_loot_target) or (_loot_target is LootPickup and _loot_target.item == null) \
		or (_loot_target is LootBox and (_loot_target as LootBox).sealed) or _loot_target.has_meta(Player.LOOTING_META)
	var left_behind := is_follower() and not _leader_looting() and leader.global_position.distance_to(global_position) > squad.catch_up * 2.0
	if gone or left_behind or _mate_healing():
		_finish_loot()
		return
	if _loot_time > LOOT_GIVE_UP or _loot_timer > float(PmcAi.loot().get("give_up", 45.0)):
		if _search_of(_loot_target):
			_looted_boxes.append(_loot_target)  # Taking too long: it leaves this one be.
		_finish_loot()
		return
	_crouch = float(personality().get("movement", {}).get("crouch_near_poi", 0.0)) > 0.0  # A Rat loots quietly.
	var at := _loot_target.global_position
	var off := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	if off > _loot_reach and _loot_timer <= 0.0:
		_loot_time += delta
		if not _move_to(_loot_spot, false):
			return
		if off > _loot_reach + 1.0:
			_loot_target.set_meta("bots_skip", true)  # Out of reach (as close as it gets is too far).
			_finish_loot()
			return
	aim_point = at
	has_aim = true
	_loot_timer += delta
	var search := _search_of(_loot_target)
	if search:
		if _loot_target is LootBox and (_loot_target as LootBox).concealed and _loot_target.get_parent() is FloorHatch:
			(_loot_target.get_parent() as FloorHatch).open(self)
		if not search.is_done():
			search.step(delta)
			return
		_take_loot(_loot_target)
		_finish_loot()
	elif _loot_timer >= LOOT_SECONDS:
		_take_loot(_loot_target)
		_finish_loot()


## Takes `node`: a loose item into its rig, pockets or pack (if it doesn't fit, other bots leave it
## too), the most valuable items of an event crate that fit, or what's worth taking from a container or
## a body it has searched (_take_best()).
func _take_loot(node: Node3D) -> void:
	if node is Bot:
		_looted_boxes.append(node)
		_take_best((node as Bot).inventory.grids())
		return
	if node is LootBox and not (node as LootBox).ignore_poi:
		_looted_boxes.append(node)
		_take_best([(node as LootBox).grid])
		return
	if node is LootPickup:
		var pickup := node as LootPickup
		pickup.item.hidden = false
		if inventory.add(pickup.item):
			looted.append(pickup.item.data.display_name)
			pickup.item = null
			pickup.queue_free()
		else:
			pickup.set_meta("bots_skip", true)
	elif node is LootBox:
		var box := node as LootBox
		_looted_boxes.append(box)
		var items := box.grid.items.duplicate()
		items.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.value() > b.value())
		var taken := 0
		for item: ItemInstance in items:
			if taken >= CRATE_TAKES:
				break
			box.grid.remove(item)
			item.hidden = false
			if inventory.add(item):
				looted.append(item.data.display_name)
				taken += 1
			else:
				box.grid.add(item)


## Takes the most valuable things it can see in `grids` (revealed by a search), down to loot min_value
## roubles, each that fits in its rig, pockets or backpack (what doesn't is left where it was). Returns
## how many.
func _take_best(grids: Array[InventoryGrid]) -> int:
	var found: Array = []
	for grid in grids:
		for item in grid.items:
			if not item.hidden:
				found.append([item, grid])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0].value() > b[0].value())
	var min_value := float(PmcAi.loot().get("min_value", 0.0))
	var taken := 0
	for pair: Array in found:
		var item: ItemInstance = pair[0]
		var grid: InventoryGrid = pair[1]
		if item.value() < min_value:
			break
		var cell := item.cell
		var turned := item.rotated
		grid.remove(item)
		if inventory.add(item):
			looted.append(item.data.display_name)
			taken += 1
		elif item.count > 0 and not grid.place(item, cell, turned):
			grid.add(item)  # Doesn't fit on it: back where it was.
	return taken


## True if a squad mate (not itself) is treating itself (HEAL): it covers it rather than loot.
func _mate_healing() -> bool:
	var healer := squad.healer() if squad else null
	return healer != null and healer != self


func _finish_loot() -> void:
	_loot_target = null
	_look_timer = 1.0
	state = State.IDLE


## Walks to the nearest extract it can use (a squad's: the one its leader picked, a planned squad's the
## plan's while it's usable, else the nearest one they can use, which becomes the plan's), stands in it
## for the extract time and leaves the raid. A planned leader walks there along a cover route, and if it
## can't get through (it gives the leg up: _leg_stuck()) picks another extract (_give_up_extract()); a
## follower stuck on its own way there goes the way its leader goes. With none it can use, it goes back
## to its patrol or plan and tries again later.
func _do_extract(delta: float) -> void:
	var raid := _raid_controller()
	if raid == null:
		state = State.IDLE
		return
	var picked: ExtractZone = squad.extract_zone if squad and is_follower() and is_instance_valid(squad.extract_zone) else null
	if _extract_zone == null or not _extract_zone.usable_by(self) or (picked and picked != _extract_zone and picked.usable_by(self)):
		_extract_zone = squad.pick_extract() if squad else null  # The leader's pick.
		if _extract_zone == null or not _extract_zone.usable_by(self):
			_extract_zone = _nearest_extract()
		_extract_time = 0.0
		_extract_settled = false
		_leg_stucks = 0
		_leg_best = INF
		route = PackedVector3Array()
		if _extract_zone == null:
			extract_at = raid.elapsed + EXTRACT_RETRY_TIME
			_extract_retry_at = extract_at
			if squad and not is_follower():
				squad.extract_at = extract_at
			state = State.IDLE
			return
		if plan() and not is_follower():
			plan().extract = _extract_zone  # Re-planned if the old one can't be used any more.
	var centre := _extract_zone.global_position
	var off_centre := Vector2(centre.x - global_position.x, centre.z - global_position.z).length()
	if off_centre > _extract_zone.radius:
		_extract_settled = false  # Not in the extract (yet, or any more).
	if plan() and not is_follower() and off_centre > _extract_zone.radius + EXTRACT_ROUTE_NEAR:
		_extract_time = 0.0
		if _route_goal.distance_to(centre) > 0.5:
			_build_route(centre)
		if _follow_route(bool(personality().get("movement", {}).get("sprint", false))) and not _leg_failed and not _stuck:
			_leg_stuck()  # The way ran out short of the extract.
		if _leg_failed:
			_give_up_extract()
		return
	if off_centre > _extract_zone.radius * 0.5 and not _extract_settled:
		_extract_time = 0.0
		if is_follower() and _leg_stucks >= REROUTE_AFTER and off_centre > _extract_zone.radius + EXTRACT_ROUTE_NEAR \
				and leader.state == State.EXTRACT:
			_follow_leader()  # Stuck on its own way out: it goes the way its leader goes.
			return
		# It counts once it's well inside, or at its own spot (or as close to it as it gets) anywhere
		# inside: in a small extract a squad mate's spot can be nearer the edge than the middle.
		var at_spot := _move_to(centre + _extract_offset(), false)
		if _stuck and off_centre > _extract_zone.radius:
			_count_stuck(centre)  # Stuck short of the extract (a follower then follows its leader).
			if plan() and not is_follower() and _leg_stucks >= GIVE_UP_AFTER:
				_give_up_extract()
				return
		_extract_settled = at_spot and off_centre <= _extract_zone.radius
		return
	_extract_time += delta
	var angle := _extract_time * 0.9
	aim_point = global_position + Vector3(sin(angle), 0.0, cos(angle)) * 5.0
	has_aim = true
	if _extract_time >= raid.config.extract_seconds:
		raid.bot_extracted(self, _extract_zone)


## A planned leader can't get through to its extract (it gave the leg up): the nearest other extract the
## squad can use (else the leader alone), not one it has given up on this time, becomes the plan's; with
## none left it tries them all again.
func _give_up_extract() -> void:
	_blocked_extracts.append(_extract_zone)
	var users: Array[Bot] = []
	if squad:
		users = squad.alive()
	var other := _nearest_extract(users, _blocked_extracts)
	if other == null:
		other = _nearest_extract([], _blocked_extracts)
	if other == null:
		_blocked_extracts.clear()
		other = _extract_zone
	_extract_zone = other
	_extract_settled = false
	_has_leg = false
	_leg_failed = false
	_leg_stucks = 0
	_leg_best = INF
	route = PackedVector3Array()
	_route_retry_at = _clock
	if plan():
		plan().extract = other
	if squad:
		squad.extract_zone = other


## 0 to 1 through its extract countdown (0 when not extracting).
func extract_progress() -> float:
	var raid := _raid_controller()
	if state != State.EXTRACT or raid == null or raid.config.extract_seconds <= 0.0:
		return 0.0
	return clampf(_extract_time / raid.config.extract_seconds, 0.0, 1.0)


## The extract it's heading for ("" if none).
func extract_goal() -> String:
	return _extract_zone.extract_name if state == State.EXTRACT and _extract_zone else ""


## Where in the extract it stands: squad mates spread out around the middle (EXTRACT_SPREAD, less in a
## small extract), not on top of each other.
func _extract_offset() -> Vector3:
	if squad == null or squad.size() < 2:
		return Vector3.ZERO
	var angle := TAU * float(squad.members.find(self)) / float(squad.size())
	return Vector3(sin(angle), 0.0, cos(angle)) * minf(EXTRACT_SPREAD, _extract_zone.radius * 0.35)


## The nearest extract it can use, and so can every one of `users` (its squad mates: Squad.pick_extract()),
## other than those in `excluded`. Null if there's none.
func _nearest_extract(users: Array[Bot] = [], excluded: Array[ExtractZone] = []) -> ExtractZone:
	var best: ExtractZone = null
	var best_distance := INF
	for zone: ExtractZone in get_tree().get_nodes_in_group("extract_zones"):
		var distance := zone.global_position.distance_to(global_position)
		if zone in excluded:
			continue
		if distance < best_distance and zone.usable_by(self) and users.all(func(user: Bot) -> bool: return zone.usable_by(user)):
			best = zone
			best_distance = distance
	return best


## True if a raid event near where it's heading has a crate that isn't ready yet (still coming down).
func _event_crate_coming() -> bool:
	var events := get_tree().get_first_node_in_group("raid_events") as RaidEvents
	if events == null:
		return false
	return events.events.any(func(event: Dictionary) -> bool:
		return not event.ready and Vector3(event.at).distance_to(_point_of_interest) < 8.0)


## Walks to the point of interest (a noise, or where the target was last seen) and looks around. It
## runs to something alarming (a gunshot) while it's more than SPRINT_DISTANCE away. A squad follower
## whose leader has stopped looking (and isn't fighting) goes back to its spot by the leader.
func _do_investigate(delta: float) -> void:
	if is_follower() and _look_timer <= 0.0 and not leader.state in [State.INVESTIGATE, State.SEARCH, State.COMBAT]:
		state = State.IDLE  # The leader is done looking: back to its spot.
		return
	if _rushing:
		_rush_time += delta
	if _hunting:
		_hunt_time += delta
		if _hunt_time > float(PmcAi.plan().get("hunt_seconds", 30.0)) or _hunting.is_dead:
			_hunting = null  # Lost it.
	if _look_timer > 0.0:
		_look_around(delta)
		if _look_timer <= 0.0 and _rushing and _rush_time < float(PmcAi.plan().get("rush_wait", 30.0)) and _event_crate_coming():
			_look_timer = 1.0  # The crate isn't down yet: wait for it.
		if _look_timer <= 0.0:
			_urgent = false
			_rushing = false
			_hunting = null
			state = State.IDLE
		return
	var far := global_position.distance_to(_point_of_interest) > SPRINT_DISTANCE
	if _move_to(_point_of_interest, _urgent and far):
		_look_timer = LOOK_AROUND_TIME


func _do_combat(delta: float) -> void:
	if target == null or target.is_dead:
		if target and is_instance_valid(target) and not (target is Bot and (target as Bot).extracted):
			_say(&"enemy_down")
		target = null
		_leave_combat(State.IDLE)
		return
	if _should_flee():
		_start_flee(target.global_position if _sees_target else _last_known)
		return
	if _sees_target and profile.melee_range > 0.0 and melee_weapon() \
			and global_position.distance_to(target.global_position) <= profile.melee_range:
		aim_point = target.chest_point()
		has_aim = true
		melee_strike()  # Up close: the hatchet, not the gun.
		return
	var threat := target.global_position if _sees_target else _last_known
	var seen_point: Variant = visible_point_of(target) if _sees_target else null
	aim_point = seen_point if seen_point != null else _last_known + Vector3.UP * 1.2
	has_aim = true
	if _sees_target:
		_seen_time += delta
	elif cover == null or is_peeking:
		# Time ducked behind cover doesn't count as losing the target.
		_lost_time += delta
		if _lost_time > profile.give_up_time:
			_point_of_interest = _last_known
			_leave_combat(State.SEARCH)
			return
	if not profile.uses_cover:
		_shoot_when_ready(delta)
	elif cover:
		_fight_from_cover(delta, threat)
	else:
		_move_to_cover(delta, threat)


func _move_to_cover(delta: float, threat: Vector3) -> void:
	if _goal_cover and not (CoverSystem.is_available(_goal_cover, self) and CoverSystem.protects(_goal_cover, threat)):
		_set_goal_cover(null)
	_cover_retry -= delta
	if _goal_cover == null and _cover_retry <= 0.0:
		_cover_retry = COVER_RETRY_TIME
		var next: CoverPoint = null
		if squad and squad.flanker == self and not _flanked:
			_flanked = true  # The squad's flanker goes wide first.
			next = _flank_cover(threat, null)
			if next:
				flanks += 1
		if next == null:
			next = _squad_cover(threat, null)
		_set_goal_cover(next)
	if _goal_cover == null:
		_shoot_when_ready(delta)  # Nowhere to hide: stand and fight.
		return
	var far := global_position.distance_to(_goal_cover.position) > SPRINT_DISTANCE
	if _move_to(_goal_cover.position, far):
		if _stuck:
			_set_goal_cover(null)  # Can't get there: find another.
			return
		enter_cover(_goal_cover)
		_goal_cover = null
		_wants_peek = false
		_cover_timer = randf_range(profile.duck_time.x, profile.duck_time.y) * 0.5
		_peeks_left = profile.peeks_before_move
	elif not far:
		_shoot_when_ready(delta)


## Duck, peek and shoot, duck again; move to new cover when flanked or after a few peeks.
## Reloads happen ducked.
func _fight_from_cover(delta: float, threat: Vector3) -> void:
	if not CoverSystem.protects(cover, threat):
		_reposition(threat)  # Flanked: this cover no longer hides us.
		return
	_cover_timer -= delta
	if _cover_timer <= 0.0:
		if _wants_peek:
			_duck()
			_peeks_left -= 1
			if _peeks_left <= 0:
				_reposition(threat)
				return
		elif cover.can_peek:
			_wants_peek = true
			_cover_timer = randf_range(profile.peek_time.x, profile.peek_time.y)
		else:
			_reposition(threat)  # Blind spot: nothing to shoot from here.
			return
	# Reload behind cover, never while exposed; top the magazine up while ducked if it's below half.
	peek_input = _wants_peek and not weapon.is_reloading
	if not peek_input and weapon.has_gun() and weapon.rounds * 2 < weapon.data.magazine_size:
		weapon.reload()
	if is_peeking:
		_shoot_when_ready(delta)


func _shoot_when_ready(delta: float) -> void:
	if not _sees_target or _seen_time < reaction_time():
		_burst_clock = 0.0
		return
	if cover and speed_ratio() > PEEK_SETTLE_SPEED:
		return  # Still stepping out to peek: wait until steady, as moving adds spread.
	_burst_clock += delta
	fire_input = fmod(_burst_clock, profile.burst_time + profile.burst_pause) < profile.burst_time


# --- Fleeing -------------------------------------------------------------------------------

## Low on HP (below its profile's flee_health of the total) and not fled recently.
func _should_flee() -> bool:
	if profile == null or profile.flee_health <= 0.0 or _flee_cooldown > 0.0:
		return false
	return health.total() < health.max_total() * profile.flee_health


## Breaks off the fight: runs (sprinting) for cover farther from `threat`, or straight away from it.
func _start_flee(threat: Vector3) -> void:
	exit_cover()
	_set_goal_cover(null)
	_wants_peek = false
	_flee_cover = _flee_spot(threat)
	CoverSystem.claim(self, _flee_cover)
	if _flee_cover:
		_flee_goal = _flee_cover.position
	else:
		var away := global_position - threat
		away.y = 0.0
		_flee_goal = global_position + (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) * 12.0
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) != 0:
			_flee_goal = NavigationServer3D.map_get_closest_point(map, _flee_goal)
	_flee_time = 0.0
	_treat_timer = -1.0
	_treatments = 0
	_look_timer = 0.0
	_flee_cooldown = FLEE_COOLDOWN
	state = State.FLEE


## Cover within reach (1.5 × its search radius) that hides it from `threat` and is farther from it
## than the bot is now: the nearest such spot it can walk to. Null if there's none.
func _flee_spot(threat: Vector3) -> CoverPoint:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return null
	var reach := (profile.cover_search_radius if profile else 15.0) * 1.5
	var from_threat := global_position.distance_to(threat)
	var best: CoverPoint = null
	var best_distance := INF
	for point in CoverSystem.get_points():
		var distance := point.position.distance_to(global_position)
		if distance > reach or distance >= best_distance or point.position.distance_to(threat) < from_threat + 3.0:
			continue
		if not CoverSystem.is_available(point, self) or not CoverSystem.protects(point, threat):
			continue
		var on_navmesh := NavigationServer3D.map_get_closest_point(map, point.position)
		if Vector2(on_navmesh.x - point.position.x, on_navmesh.z - point.position.z).length() > CoverSystem.NAVMESH_TOLERANCE:
			continue
		best = point
		best_distance = distance
	return best


## Runs for its flee spot; there (or after FLEE_TIMEOUT) it ducks into the cover and treats itself with
## what it carries (Consumables.quick_pick(): bleeds first, then HP), up to MAX_TREATMENTS, each taking
## the item's use time. Then it goes back to the fight (or searches, if it lost its target). A target
## that comes within CORNERED_DISTANCE in sight is fought on the spot.
func _do_flee(delta: float) -> void:
	_flee_time += delta
	if target and not target.is_dead and _sees_target and global_position.distance_to(target.global_position) < CORNERED_DISTANCE:
		_end_flee()  # Cornered: fight.
		return
	if _treat_timer < 0.0:
		if not _move_to(_flee_goal, true) and _flee_time < FLEE_TIMEOUT:
			return
		if _flee_cover and global_position.distance_to(_flee_cover.position) < 1.0:
			enter_cover(_flee_cover)
		_next_treatment()
		return
	aim_point = _last_known + Vector3.UP * 1.2
	has_aim = true
	_treat_timer -= delta
	if _treat_timer > 0.0:
		return
	_apply_treatment()
	_treatments += 1
	if _treatments < MAX_TREATMENTS and health.total() < health.max_total() * 0.9:
		_next_treatment()
	else:
		_end_flee()


## Uses the item of the treatment in hand (if it still has it), on the part it was for.
func _apply_treatment() -> void:
	var item: ItemInstance = _treatment.get("item")
	if item and item in inventory.all_items():
		var result := Consumables.apply(item, health, int(_treatment.get("part", -1)))
		if result.get("ok", false):
			treated.append(item.data.display_name)
			if result.get("used_up", false):
				inventory.remove_item(item)


## Starts its next treatment (or, with nothing to treat or nothing to treat it with, catches its
## breath for a moment).
func _next_treatment() -> void:
	_treatment = pick_treatment()
	var item: ItemInstance = _treatment.get("item")
	_treat_timer = minf(Consumables.use_time(item.data), MAX_TREAT_SECONDS) if item else 1.5
	if item == null:
		_treatments = MAX_TREATMENTS  # Nothing more to do after this.
	else:
		_say(&"heal")


## What it treats itself with now: what quick treatment would use (Consumables.quick_pick()), else
## any med in its kit that fixes or heals something (its backpack too: it has the time), or a painkiller
## while it's in pain. {} if nothing.
func pick_treatment() -> Dictionary:
	var pick := Consumables.quick_pick(inventory, health)
	if pick.has("item"):
		return pick
	for item in _carried_meds():
		var plan := Consumables.plan(item, health)
		if not plan.get("ok", false):
			continue
		var helps := float(plan.get("heal", 0.0)) > 0.0 or not Array(plan.get("fix", [])).is_empty()
		if helps or (str(item.data.stats.get("type", "")) == "painkiller" and health.has_pain()):
			return {"item": item, "part": int(plan.get("part", -1))}
	return {}


func _end_flee() -> void:
	_flee_cover = null
	_treat_timer = -1.0
	if target and not target.is_dead:
		_lost_time = 0.0
		exit_cover()
		_enter_combat(false)
	else:
		_point_of_interest = _last_known
		_leave_combat(State.SEARCH)


# --- Helpers --------------------------------------------------------------------------------

## Starts fighting its target; `alert`: its squad joins in (DESIGN.md §4: squad mates share
## targets).
func _enter_combat(alert := true) -> void:
	state = State.COMBAT
	_look_timer = 0.0
	_cover_retry = 0.0
	_loot_target = null
	_rushing = false
	_hunting = null
	_hold_goal = -1
	quiet_time = 0.0
	if alert and target and squad and _spreads():
		squad.pick_flanker(_rng, float(PmcAi.combat().get("flank_chance", 0.0)))
	if alert and target and squad:
		for mate in squad.mates_of(self):
			if mate.ai_enabled and mate.state != State.COMBAT and mate.state != State.FLEE:
				mate.target = target
				mate._last_known = _last_known if _last_known != Vector3.ZERO else target.global_position
				mate._lost_time = 0.0
				mate._enter_combat(false)


func _leave_combat(next: State) -> void:
	exit_cover()
	_set_goal_cover(null)
	_flanked = false
	_wants_peek = false
	_look_timer = 0.0
	_urgent = false
	state = next


func _duck() -> void:
	_wants_peek = false
	_cover_timer = randf_range(profile.duck_time.x, profile.duck_time.y)


## Leaves the current cover for another one; advanced AI rolls there if it's close enough. Sometimes
## (BotProfile.flank_chance) the new spot is off to the threat's side. A pushing squad (a boss's)
## moves closer to the threat instead, one member at a time: while a squad mate is on the move the
## others stay in their cover (as long as it still hides them) and keep peeking to pin the threat down.
func _reposition(threat: Vector3) -> void:
	var old := cover
	var pushes := profile.pushes and squad != null
	if pushes and old and CoverSystem.protects(old, threat) and _squad_mate_moving():
		_peeks_left = 1
		_duck()
		return
	exit_cover()
	_wants_peek = false
	var next: CoverPoint = null
	if pushes:
		next = _push_cover(threat, old)
	elif randf() < profile.flank_chance:
		next = _flank_cover(threat, old)
		if next:
			flanks += 1
	if next == null:
		next = _squad_cover(threat, old)
	_set_goal_cover(next)
	if next and squad and not squad.mates_of(self).is_empty():
		_say(&"move")  # Moving up.
	_cover_retry = COVER_RETRY_TIME
	if _goal_cover and profile.can_roll and randf() < profile.roll_to_cover_chance:
		_roll_toward_cover()


## Rolls into nearby cover if there is some, otherwise sideways out of the line of fire.
func _dodge(threat: Vector3) -> void:
	if _goal_cover == null:
		_set_goal_cover(CoverSystem.find_cover(self, threat, config.roll_distance + 1.5))
	if _roll_toward_cover():
		return
	var to_threat := threat - global_position
	var sideways := Vector3(to_threat.z, 0.0, -to_threat.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
	if test_move(global_transform, sideways * config.roll_distance):
		sideways = -sideways  # Blocked: roll the other way.
	try_roll(sideways)


## Cover off to the side of `threat`: seen from the threat, 40-110° around from where the bot is now,
## no farther from it than the bot is, protected and reachable. The nearest one, or null.
func _flank_cover(threat: Vector3, avoid: CoverPoint) -> CoverPoint:
	var mine := Vector2(global_position.x - threat.x, global_position.z - threat.z)
	return _best_cover(threat, avoid, func(point: CoverPoint) -> bool:
		var theirs := Vector2(point.position.x - threat.x, point.position.z - threat.z)
		var angle := rad_to_deg(absf(mine.angle_to(theirs)))
		return angle >= 40.0 and angle <= 110.0 and theirs.length() <= mine.length() + 2.0)


## Cover at least 2 m closer to `threat` than the bot is now (a squad's push). The nearest one, or null.
func _push_cover(threat: Vector3, avoid: CoverPoint) -> CoverPoint:
	var from_threat := global_position.distance_to(threat)
	return _best_cover(threat, avoid, func(point: CoverPoint) -> bool:
		return point.position.distance_to(threat) <= from_threat - 2.0)


## Cover against `threat` (CoverSystem.find_cover(), not next to `avoid`) that keeps it apart from its
## squad mates (_spread_ok()); if there's none, any.
func _squad_cover(threat: Vector3, avoid_point: CoverPoint) -> CoverPoint:
	var radius := profile.cover_search_radius
	if _spreads():
		var spread := CoverSystem.find_cover(self, threat, radius, avoid_point, _spread_ok)
		if spread:
			return spread
	return CoverSystem.find_cover(self, threat, radius, avoid_point)


## True for an AI PMC squad (they spread out in a fight; a boss's squad holds together and pushes).
func _spreads() -> bool:
	return squad != null and squad.formation == Squad.Formation.WEDGE and squad.size() > 1


## True if `point` is at least combat spread metres from every squad mate's cover (or the cover it's
## heading for) in this fight.
func _spread_ok(point: CoverPoint) -> bool:
	if not _spreads():
		return true
	var spread := float(PmcAi.combat().get("spread", 4.0))
	for mate in squad.mates_of(self):
		if mate.state != State.COMBAT:
			continue
		for spot: CoverPoint in [mate.cover, mate._goal_cover]:
			if spot and spot.position.distance_to(point.position) < spread:
				return false
	return true


## The nearest cover point within its search radius that hides it from `threat`, is free, reachable,
## not next to `avoid`, passes `accept` and keeps it apart from its squad mates.
func _best_cover(threat: Vector3, avoid: CoverPoint, accept: Callable) -> CoverPoint:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return null
	var best: CoverPoint = null
	var best_distance := profile.cover_search_radius
	for point in CoverSystem.get_points():
		var distance := point.position.distance_to(global_position)
		if distance > best_distance or point.position.distance_to(threat) < CoverSystem.MIN_THREAT_DISTANCE:
			continue
		if avoid and point.position.distance_to(avoid.position) < 2.5:
			continue
		if not accept.call(point) or not _spread_ok(point) or not CoverSystem.is_available(point, self) or not CoverSystem.protects(point, threat):
			continue
		var on_navmesh := NavigationServer3D.map_get_closest_point(map, point.position)
		if Vector2(on_navmesh.x - point.position.x, on_navmesh.z - point.position.z).length() > CoverSystem.NAVMESH_TOLERANCE:
			continue
		best = point
		best_distance = distance
	return best


## True if a living squad mate is moving to new cover in this fight.
func _squad_mate_moving() -> bool:
	if squad == null:
		return false
	for mate in squad.mates_of(self):
		if mate.state == State.COMBAT and mate.cover == null and mate._goal_cover != null:
			return true
	return false


func _roll_toward_cover() -> bool:
	if _goal_cover == null or global_position.distance_to(_goal_cover.position) > config.roll_distance + 1.5:
		return false
	return try_roll(_goal_cover.position - global_position)


func _set_goal_cover(point: CoverPoint) -> void:
	_goal_cover = point
	CoverSystem.claim(self, point)


## Steers along the navigation mesh toward `goal`. Returns true once there, or once it has been stuck
## on the way for STUCK_SECONDS (then `_stuck` is set: as close as it gets).
func _move_to(goal: Vector3, sprint: bool) -> bool:
	_stuck = false
	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if to_goal.length() < ARRIVE_DISTANCE:
		_stuck_time = 0.0
		return true
	if NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) == 0:
		return false  # The navmesh baked at raid start hasn't synced yet: wait a frame.
	if _agent.target_position.distance_to(goal) > 0.05:
		_agent.target_position = goal
		_stuck_time = 0.0
		_progress_at = global_position
	if global_position.distance_to(_progress_at) > STUCK_PROGRESS:
		_progress_at = global_position
		_stuck_time = 0.0
	else:
		_stuck_time += get_physics_process_delta_time()
		if _stuck_time > STUCK_SECONDS:
			_stuck_time = 0.0
			_stuck = true
			stuck_count += 1
			return true
	var next := _agent.get_next_path_position()
	var direction := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	if _agent.is_navigation_finished() or direction.length() < 0.05:
		direction = to_goal  # Last stretch off the navmesh edge, or no path yet.
	move_input = direction.normalized()
	sprint_input = sprint
	return false


## Says a line for `event` if it has a voice (an AI PMC; Voice keeps it from repeating itself) and no
## squad mate has just called the same thing (Squad.claim_call(): no chorus of "Tango down!").
func _say(event: StringName) -> void:
	if voice == null or not voice.can_say(event):
		return
	if squad and not squad.claim_call(event, float(Factions.voice_config().get("speaker_cooldown", 2.5))):
		return
	voice.say(event)


func _look_around(delta: float) -> void:
	_look_timer -= delta
	var angle := _look_timer * 1.6
	aim_point = global_position + Vector3(sin(angle), 0.0, cos(angle)) * 5.0
	has_aim = true
