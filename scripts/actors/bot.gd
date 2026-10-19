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
## A boss and its guards are a squad (BossSpawn): they share targets, guards stay with the boss, and in
## a fight they push as a group (BotProfile.pushes). They never leave the raid, and raid events don't
## pull them off their haunt, nor a fight they hear farther off (BotProfile.haunt_radius).
## Late in the raid it heads for an extract it can use (DESIGN.md §5: the same extracts as the player,
## RaidConfig says when) and leaves the raid after standing in it for the extract time; a fight or a hit
## interrupts it. Up close (its profile's melee_range) a bot carrying a melee weapon swings it instead of
## shooting (Actor.melee_strike(): a parry staggers it).

enum State { IDLE, INVESTIGATE, COMBAT, SEARCH, EXTRACT, PATROL, LOOT, FLEE }

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
## A guard out of a fight stays this close to its boss.
const ESCORT_DISTANCE := 3.5
## Walking somewhere without getting STUCK_PROGRESS metres closer for this long, it gives up on the
## spot (a corner the navmesh cuts too fine, another body in a doorway) as the closest it can get.
const STUCK_SECONDS := 2.0
const STUCK_PROGRESS := 0.5

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

## What the bot carries (DESIGN.md §4): a random Scav kit (data/bots/scav_kit.tres), a PMC kit or,
## set before it enters the tree, a boss's. Its gun is the one in hand; its spare rounds are the ones in
## its rig and pockets, used up as it reloads. Lootable once it's dead, with all its gear.
var inventory: Inventory
## Searching the body's pockets, rig and backpack (its equipment is in plain sight).
var search: LootSearch

var state := State.IDLE
## The hostile actor being fought, if any.
var target: Actor
## Seconds into the raid when it heads for an extract (-1: never), and whether it has left the raid.
var extract_at := -1.0
var extracted := false
## A boss's squad: the boss and its guards (the same array for all of them; empty for other bots), and
## a guard's boss. Set by BossSpawn; `title` is a boss's or guard's name ("" for a plain Scav or PMC).
## `boss_spawn` is the squad's haunt (near_haunt()).
var squad: Array[Bot] = []
var leader: Bot
var boss_spawn: BossSpawn
var title := ""
## What it has picked up (item names), how often it flanked and what it treated itself with.
var looted: Array[String] = []
var flanks := 0
var treated: Array[String] = []
## How often it gave up on getting somewhere it was stuck on the way to.
var stuck_count := 0
## The Scav wave that brought it (RaidController.spawn_wave(); 0: none). A wave counts as its zone.
var wave := 0

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
## The extract it's heading for, and how long it has stood in it.
var _extract_zone: ExtractZone
var _extract_time := 0.0
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

@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	if profile:
		side = profile.side
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
		var material := StandardMaterial3D.new()
		material.albedo_color = profile.body_color
		($Body/Capsule as MeshInstance3D).material_override = material
	var rng := RandomNumberGenerator.new()
	if GameState.raid.has("seed"):
		rng.seed = hash([int(GameState.raid.seed), str(get_path())])  # Repeatable kits in a seeded raid.
	else:
		rng.randomize()
	if inventory == null:
		inventory = Inventory.pmc_bot(rng) if side == Side.PMC else Inventory.scav(rng)
		if profile and profile.extra_loot:
			inventory.add_loot(profile.extra_loot, rng)
	_equip_kit_gun()
	if zone and wander_points.is_empty() and patrol_points.is_empty():
		wander_points = zone.patrol_points()
	weapon.reload_finished.connect(_on_reload_finished)
	NoiseSystem.noise_emitted.connect(_on_noise)
	Settings.applied.connect(_update_outline)
	_update_outline.call_deferred()  # After the player is in the tree.
	_plan_extract.call_deferred()  # Once the raid has started.


func take_hit(damage: float, from: Actor, hit_position: Vector3, shot: Dictionary = {}) -> Dictionary:
	var outcome := super(damage, from, hit_position, shot)
	_update_outline()  # A friendly bot shot by the player turns hostile.
	if float(outcome.get("damage", 0.0)) > 0.0:
		_extract_time = 0.0  # A hit starts the extract countdown again.
	return outcome


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


## When this bot will head for an extract: AI PMCs some time in RaidConfig.ai_pmc_extract_window of the
## raid, some Scavs (ai_scav_extract_chance) in ai_scav_extract_window.
func _plan_extract() -> void:
	var raid := _raid_controller()
	if raid == null or not squad.is_empty():
		return  # A boss and its guards hold their ground.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var window := raid.config.ai_pmc_extract_window
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


func display_name() -> String:
	if title != "":
		return title
	return profile.display_name if profile else super()


## True for a boss (the leader of its squad), and for one of its guards.
func is_boss() -> bool:
	return not squad.is_empty() and leader == null


func is_guard() -> bool:
	return leader != null


func die() -> void:
	super()
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
	if not ai_enabled:
		return
	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer = Settings.ai_perceive_interval()  # Longer on the Mobile graphics preset.
		_perceive()
	_flee_cooldown -= delta
	if (state == State.IDLE or state == State.PATROL) and extract_at >= 0.0 and not is_guard():
		var raid := _raid_controller()
		if raid and not raid.is_over() and raid.elapsed >= extract_at:
			state = State.EXTRACT
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
	if state != State.COMBAT and _look_timer <= 0.0 and not move_input.is_zero_approx():
		aim_point = global_position + move_input * 5.0
		has_aim = true


## Bullets flying past put the bot in combat with the shooter and make it duck or dodge.
func on_bullet_near(shooter: Actor) -> void:
	if is_dead or not ai_enabled or shooter == null or shooter.is_dead or not is_hostile(shooter):
		return
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


## Heads for a raid event at `point` (RaidEvents): it goes there and looks around. A boss and its
## guards stay on their haunt.
func rush_to(point: Vector3) -> void:
	if is_dead or not ai_enabled or state == State.COMBAT or state == State.FLEE or not squad.is_empty():
		return
	_point_of_interest = point
	_look_timer = 0.0
	_urgent = false
	state = State.INVESTIGATE


# --- Senses ---------------------------------------------------------------------------------

func _perceive() -> void:
	_view = VisionSystem.view_for(self)
	var seen: Actor = null
	if target and not target.is_dead and _can_see(target):
		seen = target
	else:
		var nearest := INF
		for node in get_tree().get_nodes_in_group("actors"):
			var other := node as Actor
			if other.is_dead or not is_hostile(other):
				continue
			var distance := global_position.distance_to(other.global_position)
			if distance < nearest and _can_see(other):
				nearest = distance
				seen = other
	if seen:
		if seen != target or not _sees_target:
			_seen_time = 0.0
		target = seen
		_sees_target = true
		_last_known = seen.global_position
		_lost_time = 0.0
		for mate in squad:
			if mate != self and is_instance_valid(mate) and mate.target == seen and not mate._sees_target:
				mate._last_known = _last_known  # The squad shares what it sees.
		if state != State.COMBAT and state != State.FLEE:
			_enter_combat()
	else:
		_sees_target = false


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
	if state == State.COMBAT or state == State.FLEE:
		if other == target and not _sees_target:
			_last_known = noise_position
		return
	if not near_haunt(noise_position):
		return  # A fight away from its haunt doesn't draw a boss squad off it.
	var alarming := kind in ALARMING_NOISES
	if state == State.INVESTIGATE and _urgent and not alarming:
		return  # Already running to a gunshot: a footstep doesn't change that.
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
	_point_of_interest = point
	_look_timer = 0.0
	_urgent = urgent
	state = State.INVESTIGATE


## True if `other` is a Scav of its zone (the same ScavZone, or the same wave).
func same_zone(other: Bot) -> bool:
	if other == self or other.side != side or not other.squad.is_empty():
		return false
	return (zone != null and other.zone == zone) or (zone == null and wave > 0 and other.wave == wave)


## A gunshot it heard: the Scavs of its zone within its profile's alert_radius that aren't fighting run
## there too.
func _alert_zone(point: Vector3) -> void:
	if profile == null or profile.alert_radius <= 0.0 or not squad.is_empty():
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
## go. A guard stays with its boss instead. Picks up loot it notices nearby.
func _do_idle(delta: float) -> void:
	if _escort() or _notice_loot(delta):
		return
	if _look_timer > 0.0:
		_look_around(delta)
		return
	if not wander_points.is_empty() or not patrol_points.is_empty():
		state = State.PATROL


## Walks to its next patrol point, then stands and looks around there (IDLE).
func _do_patrol(delta: float) -> void:
	if _escort() or _notice_loot(delta):
		return
	if not _has_patrol_goal:
		_patrol_goal = _next_patrol_point()
		_has_patrol_goal = true
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


## A guard out of a fight keeps near its boss (a spot of its own around it). True while it's walking
## there; false once it's close (it then looks around like its boss) or if it has no boss left.
func _escort() -> bool:
	if leader == null or leader.is_dead or not is_instance_valid(leader):
		return false
	var index := maxi(squad.find(self), 1)
	var angle := TAU * float(index) / float(maxi(squad.size(), 2)) + leader.rotation.y
	var spot := leader.global_position + Vector3(sin(angle), 0.0, cos(angle)) * 2.0
	if Vector2(spot.x - global_position.x, spot.z - global_position.z).length() <= ESCORT_DISTANCE:
		return false
	_move_to(spot, global_position.distance_to(spot) > SPRINT_DISTANCE * 3.0)
	return true


# --- Looting --------------------------------------------------------------------------------

## Every LOOT_SCAN_TIME, looks for loot within its profile's loot_radius: loose items on the ground,
## and ready raid event crates it hasn't looted (DESIGN.md §5.2). Goes for the nearest (LOOT). True if
## it found some. Guards don't wander off to loot.
func _notice_loot(delta: float) -> bool:
	if profile == null or profile.loot_radius <= 0.0 or is_guard():
		return false
	_loot_scan -= delta
	if _loot_scan > 0.0:
		return false
	_loot_scan = LOOT_SCAN_TIME
	var found := find_loot()
	if found == null:
		return false
	_loot_target = found
	_loot_timer = 0.0
	_loot_time = 0.0
	state = State.LOOT
	return true


## The nearest loot it would go for now (null: none): a loose item or a ready, unlooted event crate
## within its loot radius, on its floor, in sight and not already being fetched by another bot.
func find_loot() -> Node3D:
	var best: Node3D = null
	var best_distance := profile.loot_radius if profile else 0.0
	var candidates: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("interactables"):
		if node is LootPickup and node.item != null and not node.has_meta("bots_skip"):
			candidates.append(node)
	var events := get_tree().get_first_node_in_group("raid_events") as RaidEvents
	if events:
		for event: Dictionary in events.events:
			var box: Variant = event.box
			if event.ready and is_instance_valid(box) and not box in _looted_boxes and not box.grid.items.is_empty():
				candidates.append(box)
	for node in candidates:
		var distance := global_position.distance_to(node.global_position)
		if distance >= best_distance or absf(node.global_position.y - global_position.y) > 1.5:
			continue
		if _fetched_by_other(node) or not VisionSystem.line_clear(get_world_3d().direct_space_state, global_position, node.global_position, true):
			continue
		best = node
		best_distance = distance
	return best


## True if another bot is already on its way to `node`.
func _fetched_by_other(node: Node3D) -> bool:
	for other in get_tree().get_nodes_in_group("bots"):
		if other != self and other.state == State.LOOT and other._loot_target == node:
			return true
	return false


## Walks to its loot, spends LOOT_SECONDS picking it up and takes it (or, from a crate, its best
## CRATE_TAKES items), then stands and looks around. Drops it if the loot is gone or out of reach.
func _do_loot(delta: float) -> void:
	_loot_time += delta
	var gone := not is_instance_valid(_loot_target) or (_loot_target is LootPickup and _loot_target.item == null)
	if gone or _loot_time > LOOT_GIVE_UP:
		_finish_loot()
		return
	var at := _loot_target.global_position
	if Vector2(at.x - global_position.x, at.z - global_position.z).length() > LOOT_REACH:
		_loot_timer = 0.0
		_move_to(at, false)
		if _stuck:
			_loot_target.set_meta("bots_skip", true)  # Out of reach.
			_finish_loot()
		return
	aim_point = at
	has_aim = true
	_loot_timer += delta
	if _loot_timer >= LOOT_SECONDS:
		_take_loot(_loot_target)
		_finish_loot()


## Takes `node`: a loose item into its rig, pockets or pack (if it doesn't fit, other bots leave it
## too), or the most valuable items of an event crate that fit.
func _take_loot(node: Node3D) -> void:
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


func _finish_loot() -> void:
	_loot_target = null
	_look_timer = 1.0
	state = State.IDLE


## Walks to the nearest extract it can use, stands in it for the extract time and leaves the raid.
## With none it can use, it goes back to its patrol and tries again later.
func _do_extract(delta: float) -> void:
	var raid := _raid_controller()
	if raid == null:
		state = State.IDLE
		return
	if _extract_zone == null or not _extract_zone.usable_by(self):
		_extract_zone = _nearest_extract()
		_extract_time = 0.0
		if _extract_zone == null:
			extract_at = raid.elapsed + EXTRACT_RETRY_TIME
			state = State.IDLE
			return
	var centre := _extract_zone.global_position
	if Vector2(centre.x - global_position.x, centre.z - global_position.z).length() > _extract_zone.radius * 0.5:
		_extract_time = 0.0
		_move_to(centre, false)
		return
	_extract_time += delta
	var angle := _extract_time * 0.9
	aim_point = global_position + Vector3(sin(angle), 0.0, cos(angle)) * 5.0
	has_aim = true
	if _extract_time >= raid.config.extract_seconds:
		raid.bot_extracted(self, _extract_zone)


## 0 to 1 through its extract countdown (0 when not extracting).
func extract_progress() -> float:
	var raid := _raid_controller()
	if state != State.EXTRACT or raid == null or raid.config.extract_seconds <= 0.0:
		return 0.0
	return clampf(_extract_time / raid.config.extract_seconds, 0.0, 1.0)


## The extract it's heading for ("" if none).
func extract_goal() -> String:
	return _extract_zone.extract_name if state == State.EXTRACT and _extract_zone else ""


func _nearest_extract() -> ExtractZone:
	var best: ExtractZone = null
	var best_distance := INF
	for zone: ExtractZone in get_tree().get_nodes_in_group("extract_zones"):
		var distance := zone.global_position.distance_to(global_position)
		if distance < best_distance and zone.usable_by(self):
			best = zone
			best_distance = distance
	return best


## Walks to the point of interest (a noise, or where the target was last seen) and looks around. It
## runs to something alarming (a gunshot) while it's more than SPRINT_DISTANCE away.
func _do_investigate(delta: float) -> void:
	if _look_timer > 0.0:
		_look_around(delta)
		if _look_timer <= 0.0:
			_urgent = false
			state = State.IDLE
		return
	var far := global_position.distance_to(_point_of_interest) > SPRINT_DISTANCE
	if _move_to(_point_of_interest, _urgent and far):
		_look_timer = LOOK_AROUND_TIME


func _do_combat(delta: float) -> void:
	if target == null or target.is_dead:
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
		_set_goal_cover(CoverSystem.find_cover(self, threat, profile.cover_search_radius))
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
	if not _sees_target or _seen_time < profile.reaction_time:
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
	var item: ItemInstance = _treatment.get("item")
	if item and item in inventory.all_items():
		var result := Consumables.apply(item, health, int(_treatment.get("part", -1)))
		if result.get("ok", false):
			treated.append(item.data.display_name)
			if result.get("used_up", false):
				inventory.remove_item(item)
	_treatments += 1
	if _treatments < MAX_TREATMENTS and health.total() < health.max_total() * 0.9:
		_next_treatment()
	else:
		_end_flee()


## Starts its next treatment (or, with nothing to treat or nothing to treat it with, catches its
## breath for a moment).
func _next_treatment() -> void:
	_treatment = pick_treatment()
	var item: ItemInstance = _treatment.get("item")
	_treat_timer = minf(Consumables.use_time(item.data), MAX_TREAT_SECONDS) if item else 1.5
	if item == null:
		_treatments = MAX_TREATMENTS  # Nothing more to do after this.


## What it treats itself with now: what quick treatment would use (Consumables.quick_pick()), else
## any med in its kit that helps (its backpack too: it has the time). {} if nothing.
func pick_treatment() -> Dictionary:
	var pick := Consumables.quick_pick(inventory, health)
	if pick.has("item"):
		return pick
	for grid in inventory.grids():
		for item in grid.items:
			if item.data.category == ItemData.Category.MEDS and not Stims.is_stim(item.data):
				var plan := Consumables.plan(item, health)
				if plan.get("ok", false):
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

## Starts fighting its target; `alert`: its squad joins in (DESIGN.md §4: a boss's guards share
## targets).
func _enter_combat(alert := true) -> void:
	state = State.COMBAT
	_look_timer = 0.0
	_cover_retry = 0.0
	_loot_target = null
	if alert and target:
		for mate in squad:
			if mate != self and is_instance_valid(mate) and not mate.is_dead and mate.ai_enabled and mate.state != State.COMBAT and mate.state != State.FLEE:
				mate.target = target
				mate._last_known = _last_known if _last_known != Vector3.ZERO else target.global_position
				mate._lost_time = 0.0
				mate._enter_combat(false)


func _leave_combat(next: State) -> void:
	exit_cover()
	_set_goal_cover(null)
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
	var pushes := profile.pushes and not squad.is_empty()
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
		next = CoverSystem.find_cover(self, threat, profile.cover_search_radius, old)
	_set_goal_cover(next)
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


## The nearest cover point within its search radius that hides it from `threat`, is free, reachable,
## not next to `avoid` and passes `accept`.
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
		if not accept.call(point) or not CoverSystem.is_available(point, self) or not CoverSystem.protects(point, threat):
			continue
		var on_navmesh := NavigationServer3D.map_get_closest_point(map, point.position)
		if Vector2(on_navmesh.x - point.position.x, on_navmesh.z - point.position.z).length() > CoverSystem.NAVMESH_TOLERANCE:
			continue
		best = point
		best_distance = distance
	return best


## True if a living squad mate is moving to new cover in this fight.
func _squad_mate_moving() -> bool:
	for mate in squad:
		if mate != self and is_instance_valid(mate) and not mate.is_dead and mate.state == State.COMBAT \
				and mate.cover == null and mate._goal_cover != null:
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


func _look_around(delta: float) -> void:
	_look_timer -= delta
	var angle := _look_timer * 1.6
	aim_point = global_position + Vector3(sin(angle), 0.0, cos(angle)) * 5.0
	has_aim = true
