class_name Bot
extends Actor
## AI Scav or PMC (DESIGN.md §4). Sees (by the same vision rules as the player, DESIGN.md §13.6:
## its own cone, shorter at night, farther through a scope) and hears hostile actors, fights from the same cover points
## the player uses (duck, peek, shoot, move on), and — with an advanced profile — combat-rolls to
## dodge or to reach new cover when under fire.

enum State { IDLE, INVESTIGATE, COMBAT, SEARCH }

const PERCEIVE_INTERVAL := 0.15
const ARRIVE_DISTANCE := 0.3
## Distance to a goal above which the bot sprints instead of walking.
const SPRINT_DISTANCE := 3.0
## Seconds spent looking around at a noise or the target's last known position.
const LOOK_AROUND_TIME := 4.0
## High-contrast outline colours (Settings > Accessibility): hostile to the player, or not.
const HOSTILE_OUTLINE := Color(1.0, 0.3, 0.15)
const NEUTRAL_OUTLINE := Color(0.3, 0.85, 1.0)
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
## In cover, the bot only opens fire once it has nearly stopped moving (share of sprint speed).
const PEEK_SETTLE_SPEED := 0.15
## When no cover is found, wait this long before searching again.
const COVER_RETRY_TIME := 0.5

@export var profile: BotProfile
## Optional patrol route in world positions, walked in a loop.
@export var patrol_points: PackedVector3Array
## Untick to freeze the bot in place (it still takes damage).
@export var ai_enabled := true

## What the bot carries (DESIGN.md §4): a Scav or PMC kit to match its gun. Its spare rounds are the
## ones in its rig and pockets, used up as it reloads. Lootable once it's dead, with all its gear.
var inventory: Inventory
## Searching the body's pockets, rig and backpack (its equipment is in plain sight).
var search: LootSearch

var state := State.IDLE
## The hostile actor being fought, if any.
var target: Actor

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

@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	if profile:
		side = profile.side
		ammo_id = profile.ammo_id
		walk_speed = profile.walk_speed
		sprint_speed = profile.sprint_speed
		spread_degrees = profile.spread_degrees
	super()
	add_to_group("vision_hideable")
	if profile:
		weapon.optic = profile.optic
		weapon.recoil_control = profile.recoil_control
		var material := StandardMaterial3D.new()
		material.albedo_color = profile.body_color
		($Body/Capsule as MeshInstance3D).material_override = material
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	inventory = Inventory.pmc_bot(rng) if side == Side.PMC else Inventory.scav(rng)
	if profile and profile.extra_loot:
		inventory.add_loot(profile.extra_loot, rng)
	spare_rounds = inventory.count_of(ammo_id)
	weapon.spare_rounds = spare_rounds
	weapon.reload_finished.connect(_on_reload_finished)
	NoiseSystem.noise_emitted.connect(_on_noise)
	Settings.applied.connect(_update_outline)
	_update_outline.call_deferred()  # After the player is in the tree.


func take_hit(damage: float, from: Actor, hit_position: Vector3, shot: Dictionary = {}) -> Dictionary:
	var outcome := super(damage, from, hit_position, shot)
	_update_outline()  # A friendly bot shot by the player turns hostile.
	return outcome


func worn_gear() -> Inventory:
	return inventory


func display_name() -> String:
	return profile.display_name if profile else super()


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
		_perceive_timer = PERCEIVE_INTERVAL
		_perceive()
	match state:
		State.IDLE:
			_do_idle(delta)
		State.INVESTIGATE, State.SEARCH:
			_do_investigate(delta)
		State.COMBAT:
			_do_combat(delta)
	if state != State.COMBAT and _look_timer <= 0.0 and not move_input.is_zero_approx():
		aim_point = global_position + move_input * 5.0
		has_aim = true


## Bullets flying past put the bot in combat with the shooter and make it duck or dodge.
func on_bullet_near(shooter: Actor) -> void:
	if is_dead or not ai_enabled or shooter == null or shooter.is_dead or not is_hostile(shooter):
		return
	if state != State.COMBAT:
		target = shooter
		_enter_combat()
	if shooter == target and not _sees_target:
		_last_known = shooter.global_position
	if cover and is_peeking:
		_duck()
	elif cover == null and profile.can_roll and randf() < profile.dodge_chance:
		_dodge(shooter.global_position)


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
		if state != State.COMBAT:
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


func _on_noise(noise_position: Vector3, radius: float, source: Node, _kind: StringName) -> void:
	if is_dead or not ai_enabled or source == self:
		return
	var other := source as Actor
	if other == null or not is_hostile(other):
		return
	if global_position.distance_to(noise_position) > radius * profile.hearing * hearing_multiplier():
		return
	if state == State.COMBAT:
		if other == target and not _sees_target:
			_last_known = noise_position
	else:
		_point_of_interest = noise_position
		_look_timer = 0.0
		state = State.INVESTIGATE


# --- States ---------------------------------------------------------------------------------

func _do_idle(delta: float) -> void:
	if _look_timer > 0.0:
		_look_around(delta)
		return
	if patrol_points.is_empty():
		return
	if _move_to(patrol_points[_patrol_index], false):
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		_look_timer = 1.5


## Walks to the point of interest (a noise, or where the target was last seen) and looks around.
func _do_investigate(delta: float) -> void:
	if _look_timer > 0.0:
		_look_around(delta)
		if _look_timer <= 0.0:
			state = State.IDLE
		return
	if _move_to(_point_of_interest, false):
		_look_timer = LOOK_AROUND_TIME


func _do_combat(delta: float) -> void:
	if target == null or target.is_dead:
		target = null
		_leave_combat(State.IDLE)
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


# --- Helpers --------------------------------------------------------------------------------

func _enter_combat() -> void:
	state = State.COMBAT
	_look_timer = 0.0
	_cover_retry = 0.0


func _leave_combat(next: State) -> void:
	exit_cover()
	_set_goal_cover(null)
	_wants_peek = false
	_look_timer = 0.0
	state = next


func _duck() -> void:
	_wants_peek = false
	_cover_timer = randf_range(profile.duck_time.x, profile.duck_time.y)


## Leaves the current cover for another one; advanced AI rolls there if it's close enough.
func _reposition(threat: Vector3) -> void:
	var old := cover
	exit_cover()
	_wants_peek = false
	_set_goal_cover(CoverSystem.find_cover(self, threat, profile.cover_search_radius, old))
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


func _roll_toward_cover() -> bool:
	if _goal_cover == null or global_position.distance_to(_goal_cover.position) > config.roll_distance + 1.5:
		return false
	return try_roll(_goal_cover.position - global_position)


func _set_goal_cover(point: CoverPoint) -> void:
	_goal_cover = point
	CoverSystem.claim(self, point)


## Steers along the navigation mesh toward `goal`. Returns true once there.
func _move_to(goal: Vector3, sprint: bool) -> bool:
	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if to_goal.length() < ARRIVE_DISTANCE:
		return true
	if _agent.target_position.distance_to(goal) > 0.05:
		_agent.target_position = goal
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
