class_name Weapon
extends Node3D
## A gun in someone's hands (DESIGN.md §13.4): fire rate, magazine, reload, recoil, bloom, muzzle flash
## and a small kick of the model. The numbers come from a WeaponData resource, so every gun uses this
## script and scene (scenes/weapons/weapon.tscn). The actor holding it decides when to pull the
## trigger; each shot is a hitscan ray fired through Ballistics.
##
## Recoil kicks the aim: each shot climbs (vertical recoil: the aim moves out along the aim direction
## and rounds fly higher) and kicks left or right at random (horizontal recoil); recovery pulls it back.
## Bloom widens the cone shots land in: every shot adds to it (up to max bloom), and so do moving,
## sprinting, rolling and hip-firing (the holder reports these with set_stance()); it shrinks back at
## the gun's bloom recovery. A worn gun adds spread too.
##
## A gun from the inventory fires with its modded stats (WeaponStats.build()) and wears with every
## shot (DESIGN.md §12.1): below its malfunction threshold it can jam, and won't fire again until the
## jam is cleared (clear_jam(), on R), which throws the stuck round out.

## A round was fired.
signal fired
## The trigger was pulled and nothing happened (once per pull): an empty magazine, a jam or a missing
## part.
signal dry_fired
## The gun jammed after a shot.
signal jammed
## A jam was cleared; `ejected` is true if the stuck round was thrown out.
signal jam_cleared(ejected: bool)
signal reload_started(duration: float)
signal reload_finished

## How long the muzzle flash shows, in seconds (3 physics ticks).
const FLASH_TIME := 0.05
## How far the model jumps back per shot, and how fast it returns (metres, metres per second).
const KICK_DISTANCE := 0.07
const KICK_RETURN := 1.2

## The gun's stats. Set by equip(), or directly for a gun that isn't an inventory item.
@export var data: WeaponData
## The gun's inventory item (name, weight, value), if it came from one.
var item: ItemData
## The round type loaded.
var ammo: ItemData
## Rounds in the magazine.
var rounds := 0
## Spare rounds of the loaded type, or -1 for unlimited.
var spare_rounds := 0
var is_reloading := false
## Where recoil has kicked the aim right now, in degrees: x sideways (+ right), y climb (+ up). The next
## shot goes there; it recovers toward zero.
var recoil_kick := Vector2.ZERO
## Bloom right now, in degrees: from shooting, and from moving, sprinting, rolling and hip-firing.
var shot_bloom := 0.0
var stance_bloom := 0.0
## Share of each kick the holder fights off (AI skill; 0 for the player).
var recoil_control := 0.0
## Recoil ×, from the holder's stims (DESIGN.md §13.7). The holder sets it every tick.
var recoil_multiplier := 1.0
## 360 trick shot (DESIGN.md §13.4): the next shot deals the gun's trick-shot bonus damage. Set by the
## holder when a trick window opens; the first shot uses it up.
var trick_armed := false
## True while the shot being fired is a trick shot (hits land during it), so the holder can tell.
var firing_trick_shot := false
## The sight on this gun (VisionConfig.Optic): for the player, the sight fitted to it (WeaponStats);
## for AI, BotProfile.optic.
var optic := 0
## Condition of the gun (0-100), worn by every shot. Below 0 it never wears or jams (AI guns, guns that
## aren't inventory items).
var durability := -1.0
var is_jammed := false
var is_clearing := false

var _cooldown := 0.0
var _since_shot := 0.0
var _reload_left := 0.0
var _reload_duration := 0.0
var _clear_left := 0.0
## False after a shot until the trigger is released (semi-auto guns need a new click).
var _trigger_reset := true
## True once this pull has reported an empty magazine.
var _dry_this_pull := false
var _flash_left := 0.0
## What stance bloom is heading for (set_stance()).
var _stance_target := 0.0
var _rng := RandomNumberGenerator.new()

@onready var muzzle: Marker3D = $Muzzle
@onready var _model: Node3D = $Model
@onready var _flash: Node3D = $Muzzle/Flash
@onready var _flash_light: OmniLight3D = $Muzzle/FlashLight


func _ready() -> void:
	_flash.visible = false
	_flash_light.visible = false
	visible = data != null


## Puts `gun` (an ItemData with weapon stats, or null for empty hands) in hand with a full magazine of
## `ammo_item`, plus `spare` rounds of it (-1 for unlimited). `stats` are its modded stats, if it has
## any (else its .tres). Starts unworn (durability -1): the holder sets `durability` if it wears.
func equip(gun: ItemData, ammo_item: ItemData, spare: int, stats: WeaponData = null) -> void:
	item = gun
	data = stats if stats else (gun.weapon if gun else null)
	cancel_reload()
	trick_armed = false
	is_jammed = false
	is_clearing = false
	durability = -1.0
	set_ammo(ammo_item)
	rounds = data.magazine_size if data and ammo else 0
	spare_rounds = spare
	recoil_kick = Vector2.ZERO
	shot_bloom = 0.0
	stance_bloom = 0.0
	_cooldown = 0.0
	visible = data != null


## Swaps the loaded round type, keeping the counts.
func set_ammo(ammo_item: ItemData) -> void:
	ammo = ammo_item
	if data and ammo and ammo.stats.get("caliber", "") != data.caliber:
		push_warning("Weapon: %s doesn't fit a %s gun" % [ammo.display_name, data.caliber])


func has_gun() -> bool:
	return data != null and ammo != null


func display_name() -> String:
	return item.display_name if item else ""


## The spread cone of the next shot in degrees: base spread, wear, and bloom (shooting, moving,
## hip-firing).
func spread() -> float:
	if data == null:
		return 0.0
	return data.base_spread * ammo_spread(ammo) + WeaponStats.wear_spread(durability) + shot_bloom + stance_bloom


## How the holder is moving and aiming, every tick: `speed_ratio` 1 = sprint speed, `aim_blend` 1 =
## the sight is up (0 = hip-firing). Bloom heads for what these add.
func set_stance(speed_ratio: float, sprinting: bool, rolling: bool, aim_blend: float) -> void:
	if data == null:
		_stance_target = 0.0
		return
	_stance_target = data.move_spread * clampf(speed_ratio, 0.0, 1.0) + data.hip_spread * clampf(1.0 - aim_blend, 0.0, 1.0)
	if sprinting:
		_stance_target += data.sprint_spread
	if rolling:
		_stance_target += data.roll_spread



## Fires one round at `target` if the gun is ready: not reloading, the fire-rate delay has passed,
## there's a round in the magazine and (for semi-auto) the trigger was released since the last shot.
## `extra_spread` is the shooter's own aim error in degrees. Returns true if a round went off.
func pull_trigger(shooter: Actor, origin: Vector3, target: Vector3, extra_spread: float) -> bool:
	if not has_gun() or is_reloading or is_clearing or _cooldown > 0.0:
		return false
	if not (data.automatic or _trigger_reset):
		return false
	if rounds == 0 or is_jammed or data.missing_part != "":
		if not _dry_this_pull:
			_dry_this_pull = true
			dry_fired.emit()
		return false
	# Keep the leftover time when firing continuously, so the fire rate is exact at 60 ticks/s.
	_cooldown = (_cooldown if _cooldown > -get_physics_process_delta_time() else 0.0) + data.shot_interval()
	_trigger_reset = false
	rounds -= 1
	var direction := cone(kicked((target - origin).normalized()), spread() + extra_spread)
	# A trick shot: more damage on the round itself, so armor still applies to it.
	firing_trick_shot = trick_armed
	trick_armed = false
	var damage_multiplier := 1.0 + data.trick_damage_bonus if firing_trick_shot else 1.0
	# Shot shells fire several pellets, each its own round, spread around the aim (chokes tighten it).
	var pellets := pellet_count(ammo)
	var pellet_spread := float(ammo.stats.get("pellet_spread", 0.0)) * data.pellet_spread_multiplier
	for i in pellets:
		var pellet := cone(direction, pellet_spread) if pellets > 1 else direction
		Ballistics.fire(shooter, origin, pellet, ammo, muzzle.global_position, data, damage_multiplier, i == 0)
	recoil_kick += WeaponStats.kick(data, _rng) * ammo_recoil(ammo) * (1.0 - clampf(recoil_control, 0.0, 1.0)) * recoil_multiplier
	shot_bloom = minf(shot_bloom + data.bloom_per_shot, data.max_bloom)
	_since_shot = 0.0
	_show_flash()
	_model.position.z = KICK_DISTANCE
	if durability >= 0.0:
		durability = maxf(durability - data.wear_per_shot(), 0.0)
	fired.emit()
	firing_trick_shot = false
	# The next round fails to feed.
	if rounds > 0 and randf() < data.malfunction_chance(durability):
		is_jammed = true
		jammed.emit()
	return true


## How much `ammo_item` changes the kick of each shot: its "recoil" stat, % more (hot loads) or less
## (subsonic).
static func ammo_recoil(ammo_item: ItemData) -> float:
	return clampf(1.0 + float(ammo_item.stats.get("recoil", 0.0)) / 100.0, 0.5, 2.0) if ammo_item else 1.0


## How much `ammo_item` changes the gun's base spread: its "accuracy" stat, % tighter (match rounds)
## or looser.
static func ammo_spread(ammo_item: ItemData) -> float:
	return clampf(1.0 - float(ammo_item.stats.get("accuracy", 0.0)) / 100.0, 0.5, 2.0) if ammo_item else 1.0


## Rounds each shot of `ammo_item` fires: 1, or a shot shell's pellets.
static func pellet_count(ammo_item: ItemData) -> int:
	return maxi(int(ammo_item.stats.get("pellets", 1)), 1) if ammo_item else 1


## `direction` turned by the recoil kick: sideways, and up by the climb.
func kicked(direction: Vector3) -> Vector3:
	if recoil_kick.is_zero_approx():
		return direction
	var turned := direction.rotated(Vector3.UP, -deg_to_rad(recoil_kick.x))
	var side := turned.cross(Vector3.UP).normalized()
	if side.is_zero_approx():
		return turned
	return turned.rotated(side, deg_to_rad(recoil_kick.y)).normalized()


## Call every tick the trigger isn't held.
func release_trigger() -> void:
	_trigger_reset = true
	_dry_this_pull = false


## Why a reload can't start right now, or "" if it can.
func reload_block_reason() -> String:
	if not has_gun():
		return "no weapon"
	if is_reloading:
		return "already reloading"
	if is_jammed:
		return "jammed"
	if data.magazine_size <= 0:
		return "no magazine"
	if rounds >= data.magazine_size:
		return "magazine full"
	if spare_rounds == 0:
		return "no spare ammo"
	return ""


## Starts a reload. Returns false if one can't start (see reload_block_reason()).
func reload() -> bool:
	if reload_block_reason() != "":
		return false
	is_reloading = true
	_reload_duration = data.empty_reload_time if rounds == 0 else data.reload_time
	_reload_left = _reload_duration
	reload_started.emit(_reload_duration)
	return true


func cancel_reload() -> void:
	is_reloading = false
	_reload_left = 0.0


## Starts clearing a jam (data.clear_time). Returns false if the gun isn't jammed or is already being
## cleared.
func clear_jam() -> bool:
	if not is_jammed or is_clearing:
		return false
	is_clearing = true
	_clear_left = data.clear_time
	return true


## 0 to 1 through the current reload or jam clearing; 0 when doing neither.
func reload_progress() -> float:
	if is_clearing and data.clear_time > 0.0:
		return 1.0 - _clear_left / data.clear_time
	if not is_reloading or _reload_duration <= 0.0:
		return 0.0
	return 1.0 - _reload_left / _reload_duration


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, -1.0)
	_since_shot += delta
	if data:
		if _since_shot >= data.recovery_delay:
			recoil_kick = WeaponStats.recover(recoil_kick, data, delta)
		if _since_shot >= data.bloom_delay:
			shot_bloom = maxf(shot_bloom - data.bloom_recovery * delta, 0.0)
		if stance_bloom < _stance_target:
			stance_bloom = minf(stance_bloom + WeaponStats.CONFIG.stance_bloom_rise * delta, _stance_target)
		else:
			stance_bloom = maxf(stance_bloom - data.bloom_recovery * delta, _stance_target)
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if is_clearing:
		_clear_left -= delta
		if _clear_left <= 0.0:
			_finish_clearing()
	_model.position.z = move_toward(_model.position.z, 0.0, KICK_RETURN * delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
			_flash_light.visible = false


## Tops the magazine up from the spare rounds. (The old magazine isn't kept separately yet.)
func _finish_reload() -> void:
	is_reloading = false
	var needed := data.magazine_size - rounds
	var taken := needed if spare_rounds < 0 else mini(needed, spare_rounds)
	rounds += taken
	if spare_rounds > 0:
		spare_rounds -= taken
	reload_finished.emit()


## The stuck round is thrown out (if there is one) and the gun can fire again.
func _finish_clearing() -> void:
	is_clearing = false
	is_jammed = false
	var ejected := rounds > 0
	if ejected:
		rounds -= 1
	jam_cleared.emit(ejected)


func _show_flash() -> void:
	# "Reduce flashing effects" keeps a small flash and no light.
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	_flash.visible = true
	_flash.scale = Vector3.ONE * (0.55 if reduced else randf_range(0.85, 1.15))
	_flash.rotation.z = randf() * TAU
	_flash.reset_physics_interpolation()
	_flash_light.visible = not reduced
	_flash_left = FLASH_TIME


## `direction` turned by a random angle of up to `degrees`, spread evenly over the cone.
static func cone(direction: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return direction
	var side_axis := direction.cross(Vector3.UP).normalized()
	if side_axis.is_zero_approx():
		side_axis = Vector3.RIGHT
	var up_axis := side_axis.cross(direction).normalized()
	var angle := deg_to_rad(degrees) * sqrt(randf())
	var around := randf() * TAU
	return direction.rotated(side_axis, angle * sin(around)).rotated(up_axis, angle * cos(around)).normalized()
