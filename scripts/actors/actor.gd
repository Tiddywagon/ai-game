class_name Actor
extends CharacterBody3D
## Shared body of the player and the AI (DESIGN.md §4, §13): movement, stamina, combat roll, cover,
## hitbox, health and shooting. Subclasses decide what to do in _think(); Actor carries it out.
## The gun is a Weapon node ($Body/Gun) whose stats come from the gun item's WeaponData. Health is a
## BodyHealth (seven body parts, bleeds, fractures, pain); bullets hit the part where they land.
## Its timed effects (stims, painkillers, food; DESIGN.md §13.7, §13.8) and hunger and thirst change
## max stamina, stamina recovery, speed, carry weight, sway, recoil, reload speed, noise and vision here.
## Vision (DESIGN.md §13.6): subclasses say which cones they see with (vision_cones()); VisionSystem
## applies light and weather and traces the sight lines.
## Sides and factions (DESIGN.md §3): `side` is PMC or Scav; a PMC also has a `faction` (BEAR or USEC,
## Factions), which gives it that faction's look and voice (set_faction(), Voice). Scavs are friendly
## to Scavs and hostile to PMCs; PMCs are hostile to every PMC outside their squad, but hold back from
## their own faction (holds_back_from()); squad mates never fight (is_squad_mate()).

signal died
## A roll just ended. `direction` is the way it went.
signal roll_finished(direction: Vector3)
## Something the controller asked for can't happen, e.g. "Can't roll: leg fracture".
signal action_blocked(reason: String)
## A hit did damage (bleeding doesn't count): an extract countdown starts again (DESIGN.md §5).
signal hurt(damage: float)
## Melee (DESIGN.md §13.4.2): this actor swung (`target` null for a miss), or parried `attacker`'s swing.
signal melee_swung(target: Actor, parried: bool)
signal parried(attacker: Actor)

enum Side { PMC, SCAV }
enum Move { IDLE, WALK, SPRINT, CROUCH, ROLL, COVER }

## Physics layer bits (named in Project Settings > Layer Names > 3D Physics).
const WORLD_MASK := 1
const ACTOR_MASK := 2
const HITBOX_MASK := 4
const BODY_RADIUS := 0.35
## Gun height as a share of body height (1.3 m when standing).
const GUN_HEIGHT_RATIO := 0.72
## Top speed when stepping into a cover spot or leaning out of it.
const COVER_SNAP_SPEED := 5.0
## Shots only go off when the body faces within this angle of the aim point.
const MAX_AIM_ERROR_DEGREES := 25.0
const FOOTSTEP_INTERVAL := 0.4
## Chest height as a share of hitbox height: the middle of the thorax.
const CHEST_HEIGHT_RATIO := 0.72
## Melee (DESIGN.md §13.4.2) *(tune)*: seconds between swings; fists (no melee weapon) damage and
## reach; how far either side of facing a swing reaches; how far either side of facing a parry
## covers; how long a parried attacker is staggered (can't move, shoot or swing); speed while parrying.
const MELEE_COOLDOWN := 0.75
const FIST_DAMAGE := 12.0
const FIST_REACH := 1.3
const MELEE_REACH := 1.7
const MELEE_ARC_DEGREES := 60.0
const PARRY_ARC_DEGREES := 100.0
const PARRY_STAGGER := 1.2
const PARRY_SPEED := 0.5

@export var side := Side.PMC
## The PMC faction (DESIGN.md §3): &"bear" or &"usec"; &"" for none (a Scav, a boss or guard, the player
## as a Scav). Separate from `side`. set_faction() also changes the look and the voice.
@export var faction: StringName = &""
## Roll, cover and bullet tuning shared by everyone.
@export var config: CombatConfig = preload("res://data/config/combat.tres")
## Body-part HP and status effect tuning.
@export var health_config: HealthConfig = preload("res://data/config/health.tres")
## Weight thresholds: carrying more slows you down (DESIGN.md §7).
@export var inventory_config: InventoryConfig = preload("res://data/config/inventory.tres")
## Gun and ammo item ids from ItemDB. The gun item's WeaponData sets fire rate, magazine, recoil.
@export var weapon_id := "ak_74n"
@export var ammo_id := "ammo_545_ps"
## Spare rounds carried besides the loaded magazine, or -1 for unlimited.
@export var spare_rounds := 90
## The shooter's own aim error in degrees, added to the gun's spread (bots get it from their profile).
@export var spread_degrees := 0.0

@export_group("Speed")
## Metres per second.
@export var walk_speed := 3.5
@export var sprint_speed := 6.0
@export var crouch_speed := 1.6
## How quickly the actor speeds up and slows down (m/s²). Lower feels heavier.
@export var acceleration := 25.0
## How fast the body turns toward the aim point (degrees per second).
@export var turn_speed := 720.0

@export_group("Stamina")
@export var max_stamina := 100.0
## Stamina used per second of sprinting.
@export var sprint_cost := 15.0
## Stamina recovered per second once recovery starts.
@export var regen_rate := 12.0
## Seconds after sprinting or rolling before stamina starts to recover.
@export var regen_delay := 1.0
## After stamina runs out, sprinting and rolling stay locked until stamina is back to this value.
@export var recover_threshold := 25.0

@export_group("Noise")
## How far away footsteps can be heard, in metres (DESIGN.md §4).
@export var walk_noise := 10.0
@export var sprint_noise := 20.0
@export var crouch_noise := 4.0

@export_group("Height")
@export var stand_height := 1.8
@export var crouch_height := 1.1


# What the controller wants this physics tick. Set in _think().
## Flat world direction to move in, length up to 1.
var move_input := Vector3.ZERO
var sprint_input := false
var fire_input := false
## Hold to peek out of cover.
var peek_input := false
## World point to face and shoot at; only used when has_aim is true.
var aim_point := Vector3.ZERO
var has_aim := false

## Body parts, bleeds, fractures and pain (DESIGN.md §13.5).
var health: BodyHealth
var is_dead := false
## Set by the inventory once it exists.
var carried_weight_kg := 0.0
var stamina := 0.0
var is_crouching := false
## True after stamina runs out, until it recovers to recover_threshold.
var is_exhausted := false
var is_rolling := false
var move_state := Move.IDLE
## How far footsteps can be heard right now, in metres.
var noise_radius := 0.0
## The cover spot in use, or null.
var cover: CoverPoint
var is_peeking := false
## Actors that attacked this one: hostile even if they'd normally be friendly (a player Scav who
## shoots an AI Scav).
var enemies: Array[Actor] = []
## Start a reload when the trigger is pulled on an empty magazine.
var auto_reload := true
## Its faction's voice (DESIGN.md §3), or null without a faction.
var voice: Voice

var _roll_direction := Vector3.ZERO
var _roll_time := 0.0
var _roll_cooldown := 0.0
var _regen_cooldown := 0.0
var _footstep_timer := 0.0
var _height := 0.0
var _sway_time := 0.0
## Seconds left blinded (flashbang), and how long the blindness was when it started.
var blind_time := 0.0
## Melee: holding the parry stance (a swing from the front is parried), staggered seconds left (after
## being parried), and the swing cooldown.
var parrying := false
var stagger_time := 0.0
var _melee_cooldown := 0.0
var _blind_length := 0.0

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _hitbox: Area3D = $Hitbox
@onready var _hitbox_shape: CollisionShape3D = $Hitbox/CollisionShape3D
@onready var _body: Node3D = $Body
@onready var weapon: Weapon = $Body/Gun


func _ready() -> void:
	add_to_group("actors")
	health = BodyHealth.new(health_config)
	stamina = max_stamina
	weapon.dry_fired.connect(_on_dry_fire)
	weapon.jammed.connect(_on_jammed)
	equip_weapon(weapon_id, ammo_id, spare_rounds)
	_set_height(stand_height)
	_update_hitbox()
	set_faction(faction)


## Joins faction `id` (&"" for none): its colours on the body and an accent band (Factions.apply_look();
## no faction: the plain look, _plain_color()), and its voice (none without a faction).
func set_faction(id: StringName) -> void:
	faction = id if Factions.has(id) else &""
	Factions.apply_look(_body, faction, _plain_color())
	if faction == &"":
		if voice:
			voice.queue_free()
			voice = null
		return
	if voice == null:
		voice = Voice.new()
		add_child(voice)
	voice.faction = faction


## The body colour without a faction: a Scav's (from data/bots/scav.tres) for the Scav side; null keeps
## the scene's. Bot uses its profile's.
func _plain_color() -> Variant:
	return (load("res://data/bots/scav.tres") as BotProfile).body_color if side == Side.SCAV else null


func _exit_tree() -> void:
	CoverSystem.release(self)


## Override in subclasses: set move_input, sprint_input, fire_input, peek_input and aim_point,
## and call try_roll(), enter_cover() or exit_cover() as needed.
func _think(_delta: float) -> void:
	pass


## Called when a bullet passes within a couple of metres (or hits). Override to react.
func on_bullet_near(_shooter: Actor) -> void:
	pass


## Called when one of this actor's bullets hits someone. Override for hit markers and the like.
func on_hit_landed(_target: Actor, _damage: float, _position: Vector3, _outcome: Dictionary = {}) -> void:
	pass


## Called after each shot this actor fires. Override for recoil, camera shake and the like.
func _on_fired() -> void:
	pass


func _physics_process(delta: float) -> void:
	if is_dead:
		_step_dead(delta)
		return
	health.tick(delta)
	if health.is_dead:
		die()
		return
	_sway_time += delta
	blind_time = maxf(blind_time - delta, 0.0)
	if health.metabolism:
		health.exertion = metabolism_exertion()
	weapon.recoil_multiplier = health.recoil_multiplier()
	weapon.reload_speed = health.reload_multiplier()
	stamina = minf(stamina, stamina_cap())
	_think(delta)
	_melee_cooldown = maxf(_melee_cooldown - delta, 0.0)
	if stagger_time > 0.0:
		stagger_time = maxf(stagger_time - delta, 0.0)
		move_input = Vector3.ZERO
		fire_input = false
		peek_input = false
		sprint_input = false
	if parrying:
		fire_input = false
		sprint_input = false
	_roll_cooldown = maxf(_roll_cooldown - delta, 0.0)
	if is_rolling:
		_step_roll(delta)
	elif cover:
		_step_cover(delta)
	else:
		_step_free(delta)
	_update_hitbox()
	_update_facing(delta)
	weapon.set_stance(speed_ratio(), move_state == Move.SPRINT, is_rolling, aim_blend())
	_update_firing()
	noise_radius *= health.noise_multiplier()
	_update_footsteps(delta)


# --- Actions --------------------------------------------------------------------------------

func set_crouching(value: bool) -> void:
	if cover == null:
		is_crouching = value


## Overweight (DESIGN.md §7): no sprinting or rolling, and slow.
func is_overweight() -> bool:
	return load_weight() >= inventory_config.overweight_kg


## Carrying enough to slow down a little and tire faster.
func is_encumbered() -> bool:
	return load_weight() > inventory_config.encumbered_kg


## The weight that counts against the thresholds: what you carry, less what stims let you carry.
func load_weight() -> float:
	return maxf(carried_weight_kg - health.carry_bonus(), 0.0)


## Why a roll isn't possible right now, or "" if it is.
func roll_block_reason() -> String:
	if is_dead or is_rolling:
		return "busy"
	var legs := health.leg_problem()
	if legs != "":
		return legs
	if is_overweight():
		return "overweight"
	if _roll_cooldown > 0.0:
		return "cooldown"
	if is_exhausted or stamina < config.roll_stamina_cost:
		return "not enough stamina"
	return ""


## Starts a combat roll along `direction` (flattened). Returns false, and emits action_blocked
## with the reason, if a roll isn't allowed.
func try_roll(direction: Vector3) -> bool:
	direction.y = 0.0
	var reason := roll_block_reason()
	if reason == "busy" or direction.is_zero_approx():
		return false
	if reason != "":
		action_blocked.emit("Can't roll: " + reason)
		return false
	exit_cover()
	is_rolling = true
	_roll_direction = direction.normalized()
	_roll_time = 0.0
	stamina -= config.roll_stamina_cost
	_regen_cooldown = regen_delay
	rotation.y = _yaw_toward(_roll_direction)
	NoiseSystem.emit_noise(global_position, config.roll_noise * health.noise_multiplier(), self, &"roll")
	return true


func enter_cover(point: CoverPoint) -> void:
	if point == null or is_dead:
		return
	is_crouching = false
	cover = point
	CoverSystem.claim(self, point)


func exit_cover() -> void:
	if cover == null:
		return
	cover = null
	is_peeking = false
	CoverSystem.release(self)


## Puts the gun `gun_id` in hand ("" for none) with a full magazine of `ammo` and `spare` rounds
## besides (-1 for unlimited). `stats`: its modded stats, if it has mods (WeaponStats.build()).
func equip_weapon(gun_id: String, ammo: String, spare: int, stats: WeaponData = null) -> void:
	weapon_id = gun_id
	ammo_id = ammo
	spare_rounds = spare
	weapon.equip(ItemDB.get_item(gun_id) if gun_id != "" else null, ItemDB.get_item(ammo) if ammo != "" else null, spare, stats)


## Swaps the loaded round type, keeping the round counts (debug key F3 in the test level).
func set_ammo(id: String) -> void:
	ammo_id = id
	weapon.set_ammo(ItemDB.get_item(id))


## Short ammo description for the HUD, e.g. "5.45x39 PS (pen 28)" or "12ga 7mm buckshot (8 pellets, pen 3)".
func ammo_label() -> String:
	if weapon.ammo == null:
		return "no ammo"
	var pellets := Weapon.pellet_count(weapon.ammo)
	var penetration := int(weapon.ammo.stats.get("penetration", 0))
	if pellets > 1:
		return "%s (%d pellets, pen %d)" % [weapon.ammo.display_name, pellets, penetration]
	return "%s (pen %d)" % [weapon.ammo.display_name, penetration]


## Starts a reload (or clears a jam), or emits action_blocked with the reason it can't.
func try_reload() -> bool:
	if is_dead:
		return false
	if weapon.is_jammed:
		return weapon.clear_jam()
	var reason := weapon.reload_block_reason()
	if reason == "already reloading":
		return false
	if reason != "":
		action_blocked.emit("Magazine full" if reason == "magazine full" else "Can't reload: " + reason)
		return false
	return weapon.reload()


## How hard this actor is working, for energy and hydration drain (DESIGN.md §13.7): still or
## crouched is easy, sprinting and rolling hard; carrying too much and being injured make it harder.
func metabolism_exertion() -> float:
	var tuning := health.metabolism
	var multiplier := 1.0
	if is_rolling:
		multiplier = tuning.roll_drain
	elif move_state == Move.SPRINT:
		multiplier = tuning.sprint_drain
	elif speed_ratio() < 0.05:
		multiplier = tuning.still_drain
	elif is_crouching or move_state == Move.CROUCH or move_state == Move.COVER:
		multiplier = tuning.crouch_drain
	if is_overweight():
		multiplier *= tuning.overweight_drain
	elif is_encumbered():
		multiplier *= tuning.encumbered_drain
	if health.is_injured():
		multiplier *= tuning.injured_drain
	return multiplier


## Max stamina right now: more on some stims.
func stamina_cap() -> float:
	return max_stamina + health.stamina_bonus()


## How fast the actor is moving, 1 = sprint speed.
func speed_ratio() -> float:
	return Vector2(velocity.x, velocity.z).length() / sprint_speed


## Spread of the next shot right now, in degrees: the gun's (base spread, bloom, wear) plus aim error.
func current_spread() -> float:
	return weapon.spread() + spread_degrees


## How far the sight is up, 0 (hip-firing) to 1 (aimed): hip-firing adds the gun's hip-fire spread.
## AI always fires aimed; the player raises the sight with the aim button (Player).
func aim_blend() -> float:
	return 1.0


## A bullet from `from` hit this actor at `hit_position`, which decides the body part. `shot`
## (ArmorRules.shot()) is the round: armor worn over that part may stop it, and its stats decide
## fragmentation and bleeds; without it the damage goes straight to the body. Returns what happened
## (ArmorRules.resolve() plus "part"), or {} if the round passed beside the body.
func take_hit(damage: float, from: Actor, hit_position: Vector3, shot: Dictionary = {}) -> Dictionary:
	if is_dead:
		return {}
	provoke(from)  # Whoever shot us is an enemy from now on.
	var part := body_part_at(hit_position, from.global_position if from else hit_position)
	if part < 0:
		return {}
	var frontal := ArmorRules.is_frontal(self, from.global_position if from else hit_position)
	var outcome := ArmorRules.resolve(damage, shot, worn_gear(), part, null, frontal) if not shot.is_empty() \
		else {"damage": damage, "armor": null, "penetrated": true, "ricochet": false, "blunt": false, "fragmented": false}
	outcome.part = part
	var cause := {"kind": "shot", "part": part, "damage": outcome.damage}
	if outcome.has("light_bleed"):
		cause.light_bleed = outcome.light_bleed
		cause.heavy_bleed = outcome.heavy_bleed
	if outcome.armor:
		cause.armor = (outcome.armor as ItemInstance).data.display_name
		cause.penetrated = outcome.penetrated
	if from:
		cause.attacker = from.display_name()
		cause.weapon = from.weapon.display_name()
		cause.ammo = from.weapon.ammo.display_name if from.weapon.ammo else ""
		cause.distance = from.global_position.distance_to(global_position)
	if outcome.damage > 0.0:
		health.hit(part, outcome.damage, cause)
		hurt.emit(outcome.damage)
	if health.is_dead:
		die()
	return outcome


## Damage that isn't a bullet (DESIGN.md §13.4.2): a melee swing or a grenade blast (`kind` "melee" or
## "explosion"), with what did it (`weapon_name`), landing at `at`. No armor stops it. Returns
## {"damage", "part"}.
func take_blow(damage: float, from: Actor, kind: String, weapon_name: String, at: Vector3) -> Dictionary:
	if is_dead or damage <= 0.0:
		return {}
	provoke(from)
	var part := body_part_at(at, from.global_position if from else at)
	if part < 0:
		part = BodyHealth.Part.THORAX
	var cause := {"kind": kind, "part": part, "damage": damage, "weapon": weapon_name}
	if from:
		cause.attacker = from.display_name()
		cause.distance = from.global_position.distance_to(global_position)
	health.hit(part, damage, cause)
	hurt.emit(damage)
	if health.is_dead:
		die()
	return {"damage": damage, "part": part}


## The melee weapon worn (the melee slot), or null for fists.
func melee_weapon() -> ItemInstance:
	var gear := worn_gear()
	return gear.equipment.get("melee") if gear else null


func melee_damage() -> float:
	var item := melee_weapon()
	return float(item.data.stats.get("damage", 30.0)) if item else FIST_DAMAGE


func melee_reach() -> float:
	var item := melee_weapon()
	return float(item.data.stats.get("reach", MELEE_REACH)) if item else FIST_REACH


## Swings the melee weapon (or a fist) at the nearest actor in front within reach. A target holding
## the parry stance and facing the swing parries it and staggers this actor instead. Returns
## {"target" (or null), "parried", "damage"}, or {} if it can't swing now.
func melee_strike() -> Dictionary:
	if is_dead or stagger_time > 0.0 or _melee_cooldown > 0.0 or is_rolling or parrying:
		return {}
	_melee_cooldown = MELEE_COOLDOWN
	NoiseSystem.emit_noise(global_position, 6.0, self, &"melee")
	var target := melee_target()
	if target == null:
		melee_swung.emit(null, false)
		return {"target": null, "parried": false, "damage": 0.0}
	if target.can_parry(self):
		stagger_time = PARRY_STAGGER
		target.parried.emit(self)
		melee_swung.emit(target, true)
		return {"target": target, "parried": true, "damage": 0.0}
	var damage := melee_damage()
	var item := melee_weapon()
	target.take_blow(damage, self, "melee", item.data.display_name if item else "Fists", target.chest_point())
	on_hit_landed(target, damage, target.chest_point())
	melee_swung.emit(target, false)
	return {"target": target, "parried": false, "damage": damage}


## The actor a swing would hit: the nearest living one within reach and within the swing's arc.
func melee_target() -> Actor:
	var facing := vision_facing()
	var reach := melee_reach() + BODY_RADIUS
	var best: Actor = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == self or other.is_dead:
			continue
		var to := Vector2(other.global_position.x - global_position.x, other.global_position.z - global_position.z)
		var distance := to.length()
		if distance > reach or distance >= best_distance or absf(other.global_position.y - global_position.y) > 1.2:
			continue
		if distance > 0.05 and absf(rad_to_deg(facing.angle_to(to))) > MELEE_ARC_DEGREES:
			continue
		best = other
		best_distance = distance
	return best


## True if this actor, holding the parry stance, faces `attacker`'s swing.
func can_parry(attacker: Actor) -> bool:
	if not parrying or is_dead or stagger_time > 0.0:
		return false
	var to := Vector2(attacker.global_position.x - global_position.x, attacker.global_position.z - global_position.z)
	return to.length() < 0.05 or absf(rad_to_deg(vision_facing().angle_to(to))) <= PARRY_ARC_DEGREES


## The kit this actor wears (armor and helmets stop rounds), or null.
func worn_gear() -> Inventory:
	return null


## How far this actor hears, × (DESIGN.md §12.2): a headset on the helmet hears further (better with
## its upgrade level); helmets and face shields muffle. 1 without a helmet.
func hearing_multiplier() -> float:
	var gear := worn_gear()
	var helmet: ItemInstance = gear.equipment.get("helmet") if gear else null
	if helmet == null:
		return 1.0
	var total := 1.0
	for piece: ItemInstance in WeaponMods.installed(helmet) + [helmet]:
		total += GearUpgrades.hearing(piece)
	return clampf(total, 0.5, 2.0)


## Which body part (a BodyHealth.Part) a bullet fired from `shot_from` and landing at `point` hits,
## from its height on the hitbox and how far to the side of the body's centre line it is; -1 if it
## passes beside the head, over a shoulder.
func body_part_at(point: Vector3, shot_from: Vector3) -> int:
	var local := global_transform.affine_inverse() * point
	var height := clampf(local.y / _hitbox_height(), 0.0, 1.0)
	if height >= health_config.head_from:
		# How far the bullet's path passes from the centre line, seen from above (any facing).
		var path := Vector2(point.x - shot_from.x, point.z - shot_from.z).normalized()
		var to_centre := Vector2(global_position.x - point.x, global_position.z - point.z)
		return BodyHealth.Part.HEAD if absf(path.cross(to_centre)) <= health_config.head_half_width else -1
	if height < health_config.stomach_from:
		return BodyHealth.Part.RIGHT_LEG if local.x >= 0.0 else BodyHealth.Part.LEFT_LEG
	if absf(local.x) > health_config.arm_offset:
		return BodyHealth.Part.RIGHT_ARM if local.x > 0.0 else BodyHealth.Part.LEFT_ARM
	return BodyHealth.Part.THORAX if height >= health_config.thorax_from else BodyHealth.Part.STOMACH


## Name used in death messages, e.g. "Scav" or "USEC operator" (a PMC of a faction).
func display_name() -> String:
	if faction != &"":
		return Factions.member_name(faction)
	return "Scav" if side == Side.SCAV else "PMC"


## Current weapon sway in degrees (left/right): from fractured or blacked arms, pain, the gun itself
## (weapon_sway()), and a tremor from stims or thirst (or steadier hands from some stims).
func aim_sway_degrees() -> float:
	var amount := health.injured_arms() * health_config.arm_sway + weapon_sway() + health.extra_sway()
	if health.has_pain():
		amount += health_config.pain_sway
	if amount <= 0.0:
		return 0.0
	return amount * (0.7 * sin(_sway_time * 1.6) + 0.3 * sin(_sway_time * 3.7 + 1.0))


## How far the gun drifts in this actor's hands, in degrees (heavier builds more). None for AI: their
## aim error (BotProfile.spread_degrees) covers it.
func weapon_sway() -> float:
	return 0.0


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_rolling = false
	if not health.is_dead:
		health.is_dead = true  # Killed some other way than by damage.
	weapon.cancel_reload()
	exit_cover()
	CoverSystem.release(self)  # Also frees a spot it was only heading to.
	velocity = Vector3.ZERO
	# Corpses don't block anyone or take hits, but stay on the ground.
	collision_layer = 0
	collision_mask = WORLD_MASK
	_hitbox.collision_layer = 0
	# Lie the placeholder body flat.
	_body.scale = Vector3.ONE
	_body.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_body.position.y = BODY_RADIUS
	_body.reset_physics_interpolation()
	died.emit()


## Whether this actor fights `other` (DESIGN.md §3): never a squad mate; anyone who attacked it; else
## everyone but Scav to Scav (Scavs and PMCs fight, and PMCs fight every other PMC, their own faction
## too: holds_back_from()).
func is_hostile(other: Actor) -> bool:
	if other == null or other == self or is_squad_mate(other) or other.is_squad_mate(self):
		return false
	return other in enemies or not (side == Side.SCAV and other.side == Side.SCAV)


## True if `other` is in this actor's squad (Bot.squad). The player has none.
func is_squad_mate(_other: Actor) -> bool:
	return false


## True if this actor holds back from `other` (DESIGN.md §3, factions.json "same_faction"): both are
## PMCs of the same faction, not squad mates, and `other` hasn't attacked it. Still hostile; AI acts on
## it (Bot): slower to open fire, and no fight started far off unless `other` aims at it.
func holds_back_from(other: Actor) -> bool:
	return other != null and other != self and faction != &"" and other.faction == faction and side == Side.PMC \
		and other.side == Side.PMC and not is_squad_mate(other) and not other in enemies


## True if this actor is aiming at `other`: its aim points within the same-faction rule's
## aimed_at_degrees of it. Bot: only at its target in a fight.
func aims_at(other: Actor) -> bool:
	if not has_aim or other == null or other == self or is_dead:
		return false
	var to_other := Vector2(other.global_position.x - global_position.x, other.global_position.z - global_position.z)
	var to_aim := Vector2(aim_point.x - global_position.x, aim_point.z - global_position.z)
	if to_other.length() < 0.1 or to_aim.length() < 0.1:
		return false
	return absf(rad_to_deg(to_aim.angle_to(to_other))) <= float(Factions.same_faction().get("aimed_at_degrees", 8.0))


## `by` attacked this actor (shot at it, hit it): an enemy from now on, even if it would be friendly (a
## player Scav who shoots an AI Scav) or held back from (a PMC of its own faction). Not a squad mate.
func provoke(by: Actor) -> void:
	if by == null or by == self or by in enemies or is_squad_mate(by):
		return
	if not is_hostile(by) or holds_back_from(by):
		enemies.append(by)


# --- Vision ---------------------------------------------------------------------------------

## The cones this actor sees with, before light and weather: Vector3(half angle in radians, range,
## 1 if the cone brings its own light). Player and Bot override this.
func vision_cones() -> Array[Vector3]:
	return []


## Flat direction the vision cones point in: where the body faces. The player overrides it.
func vision_facing() -> Vector2:
	var forward := -global_basis.z
	return Vector2(forward.x, forward.z).normalized()


## Seen in every direction up to this distance.
func awareness_radius() -> float:
	return VisionSystem.config.ai_awareness_radius


## Crouched, ducked behind low cover, mid-roll or dead: sight lines to or from this actor run below
## low cover.
func is_low_profile() -> bool:
	return is_dead or _height <= config.low_cover_max_height


## True while a flashlight is on, which makes this actor easy to spot in the dark.
func has_light_on() -> bool:
	return false


## Vision range ×: further on some stims (DESIGN.md §13.8).
func status_range_multiplier() -> float:
	return health.vision_range_multiplier()


## Pain and head injuries narrow the vision cone (DESIGN.md §13.6), and so do Exhaustion,
## Dehydration (§13.7) and blurred vision (§13.8).
func status_cone_multiplier() -> float:
	var multiplier := health.vision_multiplier()
	if health.has_pain():
		multiplier *= VisionSystem.config.pain_cone_multiplier
	if health.fraction(BodyHealth.Part.HEAD) < VisionSystem.config.head_injury_threshold:
		multiplier *= VisionSystem.config.head_injury_cone_multiplier
	return multiplier


## Blinds this actor (a flashbang) for `seconds`, or longer if already blinder.
func blind(seconds: float) -> void:
	if seconds > blind_time:
		blind_time = seconds
		_blind_length = seconds


func is_blind() -> bool:
	return blind_time > 0.0


## 1 just after being blinded, falling to 0 as sight returns.
func blind_fraction() -> float:
	return blind_time / _blind_length if _blind_length > 0.0 else 0.0


## Movement speed multiplier, e.g. slower while looking through a scope.
func _move_multiplier() -> float:
	return 1.0


func _can_sprint() -> bool:
	return true


## Called by PlayerVision when the player starts or stops seeing this actor.
func set_seen(seen: bool) -> void:
	_body.visible = seen


## True while the player can see this actor (set_seen()).
func is_seen() -> bool:
	return _body.visible


# --- Body points ----------------------------------------------------------------------------

func gun_height() -> float:
	return _height * GUN_HEIGHT_RATIO


func eye_point() -> Vector3:
	return global_position + Vector3.UP * _height * 0.92


func chest_point() -> Vector3:
	return global_position + Vector3.UP * _hitbox_height() * CHEST_HEIGHT_RATIO


func head_point() -> Vector3:
	return global_position + Vector3.UP * maxf(_hitbox_height() - 0.15, 0.1)


func hitbox_rid() -> RID:
	return _hitbox.get_rid()


## The point of `other` this actor can see (chest first, then head), or null if neither is visible.
func visible_point_of(other: Actor) -> Variant:
	var eye := eye_point()
	for point in [other.chest_point(), other.head_point()]:
		var query := PhysicsRayQueryParameters3D.create(eye, point, WORLD_MASK)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return point
	return null


# --- Per-tick movement ----------------------------------------------------------------------

func _step_free(delta: float) -> void:
	var moving := not move_input.is_zero_approx()
	var injured_legs := health.injured_legs() > 0
	# Shooting stops a sprint, and so does a fractured or blacked leg (unless a painkiller numbs it);
	# sprinting from a crouch stands you up.
	var sprint_held := moving and sprint_input and not fire_input and health.leg_problem() == "" and _can_sprint() and not is_overweight()
	if sprint_held and is_crouching:
		is_crouching = false
	var sprinting := sprint_held and not is_exhausted
	_update_stamina(sprinting, delta)

	var speed := 0.0
	if not moving:
		move_state = Move.IDLE
		noise_radius = 0.0
	elif is_crouching:
		move_state = Move.CROUCH
		speed = crouch_speed
		noise_radius = crouch_noise
	elif sprinting:
		move_state = Move.SPRINT
		speed = sprint_speed
		noise_radius = sprint_noise
	else:
		move_state = Move.WALK
		speed = walk_speed
		noise_radius = walk_noise

	if injured_legs:
		speed *= health_config.injured_leg_speed
	speed *= _move_multiplier() * inventory_config.speed_multiplier(load_weight()) * health.speed_multiplier()
	if parrying:
		speed *= PARRY_SPEED
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(move_input * speed, acceleration * delta)
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	_apply_gravity(delta)
	move_and_slide()
	_set_height(crouch_height if is_crouching else stand_height)


func _step_roll(delta: float) -> void:
	_update_stamina(false, delta)
	var start := _roll_time / config.roll_duration
	_roll_time += delta
	var progress := minf(_roll_time / config.roll_duration, 1.0)
	# Ease-out: fast at the start, slowing to a stop. Covers exactly roll_distance.
	var step := config.roll_distance * (_ease_out(progress) - _ease_out(start))
	var roll_velocity := _roll_direction * step / delta
	velocity = Vector3(roll_velocity.x, velocity.y, roll_velocity.z)
	_apply_gravity(delta)
	move_and_slide()
	move_state = Move.ROLL
	noise_radius = config.roll_noise  # Shown on the HUD; the noise itself is made once, in try_roll().
	_set_height(crouch_height)
	if progress >= 1.0:
		is_rolling = false
		_roll_cooldown = config.roll_cooldown
		velocity = Vector3(0.0, velocity.y, 0.0)
		roll_finished.emit(_roll_direction)


func _step_cover(delta: float) -> void:
	_update_stamina(false, delta)
	# Moving away from the cover leaves it.
	if move_input.dot(cover.normal) > 0.7:
		exit_cover()
		_step_free(delta)
		return
	is_peeking = peek_input and cover.can_peek
	var sliding := false
	if not is_peeking:
		# Slide along the cover with sideways input.
		var along := move_input.dot(cover.tangent)
		if absf(along) > 0.3:
			var next := CoverSystem.point_on_face(cover.box, cover.face, cover.position + cover.tangent * signf(along) * config.cover_move_speed * delta)
			if next and next.position.distance_to(cover.position) > 0.001 and CoverSystem.is_available(next, self):
				enter_cover(next)
				sliding = true
	var goal := cover.position + (cover.peek_offset if is_peeking else Vector3.ZERO)
	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	var cover_velocity := (to_goal / delta).limit_length(COVER_SNAP_SPEED)
	velocity = Vector3(cover_velocity.x, velocity.y, cover_velocity.z)
	_apply_gravity(delta)
	move_and_slide()
	move_state = Move.COVER
	noise_radius = crouch_noise if sliding or to_goal.length() > 0.05 else 0.0
	_set_height(config.duck_height if cover.is_low and not is_peeking else stand_height)


func _step_dead(delta: float) -> void:
	velocity = Vector3(0.0, velocity.y, 0.0)
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta


func _update_stamina(sprinting: bool, delta: float) -> void:
	if sprinting:
		stamina = maxf(stamina - sprint_cost * inventory_config.stamina_multiplier(load_weight()) * health.sprint_cost_multiplier() * delta, 0.0)
		_regen_cooldown = regen_delay
	elif _regen_cooldown > 0.0:
		_regen_cooldown -= delta
	else:
		stamina = minf(stamina + regen_rate * health.stamina_regen_multiplier() * delta, stamina_cap())
		if is_exhausted and stamina >= recover_threshold:
			is_exhausted = false
	if stamina == 0.0:
		is_exhausted = true


func _update_facing(delta: float) -> void:
	if is_rolling or not has_aim:
		return
	var to_aim := aim_point - global_position
	if Vector2(to_aim.x, to_aim.z).length() < 0.2:
		return  # Aim point is on the actor: keep the current facing.
	rotation.y = rotate_toward(rotation.y, _yaw_toward(to_aim), deg_to_rad(turn_speed) * delta)


func _update_firing() -> void:
	if not fire_input:
		weapon.release_trigger()
		return
	if not has_aim or is_rolling or (cover and not is_peeking):
		return  # Can't shoot mid-roll or while hidden behind cover.
	var to_aim := aim_point - global_position
	if absf(angle_difference(rotation.y, _yaw_toward(to_aim))) > deg_to_rad(MAX_AIM_ERROR_DEGREES):
		return  # Still turning toward the target.
	# Bullets start at the body's centre line, so a gun poking into a wall can't shoot through it.
	var origin := global_position + Vector3.UP * gun_height()
	var target := origin + (aim_point - origin).rotated(Vector3.UP, deg_to_rad(aim_sway_degrees()))
	if weapon.pull_trigger(self, origin, target, spread_degrees):
		_on_fired()


## The trigger was pulled and nothing happened: a jam or a missing part says so; an empty magazine
## reloads if allowed, otherwise says why nothing happens.
func _on_dry_fire() -> void:
	if weapon.is_jammed:
		action_blocked.emit("Weapon jammed: press %s to clear it" % Settings.key_label("reload"))
		return
	if weapon.data.missing_part != "":
		action_blocked.emit("Can't fire: no %s" % weapon.data.missing_part.to_lower())
		return
	if auto_reload and weapon.reload():
		return
	var reason := weapon.reload_block_reason()
	if reason == "no spare ammo":
		action_blocked.emit("Out of ammo")
	elif reason == "":
		action_blocked.emit("Magazine empty: press %s to reload" % Settings.key_label("reload"))


func _on_jammed() -> void:
	action_blocked.emit("Jammed! Press %s to clear it" % Settings.key_label("reload"))


func _update_footsteps(delta: float) -> void:
	if noise_radius <= 0.0 or is_rolling:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = FOOTSTEP_INTERVAL
		NoiseSystem.emit_noise(global_position, noise_radius, self, &"footstep")


## Sizes the body collision and squashes the placeholder model to `height`.
func _set_height(height: float) -> void:
	if is_equal_approx(height, _height):
		return
	_height = height
	var capsule := _collision.shape as CapsuleShape3D
	capsule.height = height
	_collision.position.y = height / 2.0
	_body.scale.y = height / stand_height


## The hitbox follows the body, but shrinks for the first moments of a roll (harder to hit).
func _update_hitbox() -> void:
	var height := _height
	var radius := BODY_RADIUS
	if is_rolling and _roll_time <= config.roll_evade_time:
		height = config.roll_evade_height
		radius = config.roll_evade_radius
	var capsule := _hitbox_shape.shape as CapsuleShape3D
	if not is_equal_approx(capsule.height, height) or not is_equal_approx(capsule.radius, radius):
		capsule.radius = radius
		capsule.height = height
		_hitbox_shape.position.y = height / 2.0


func _hitbox_height() -> float:
	return (_hitbox_shape.shape as CapsuleShape3D).height


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


## The yaw that points the model's front (-Z) along `direction`.
static func _yaw_toward(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
