class_name Weapon
extends Node3D
## A gun in someone's hands (DESIGN.md §13.4): fire rate, magazine, reload, recoil spread, muzzle flash
## and a small kick of the model. The numbers come from a WeaponData resource, so every gun uses this
## script and scene (scenes/weapons/weapon.tscn). The actor holding it decides when to pull the
## trigger; each shot is a hitscan ray fired through Ballistics.

## A round was fired.
signal fired
## The trigger was pulled on an empty magazine (once per pull).
signal dry_fired
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
## Extra spread from recoil right now, in degrees.
var recoil := 0.0
## The sight mounted on this gun (VisionConfig.Optic). Attachments will set it; for now the loadout
## (player) or BotProfile (AI) does.
var optic := 0

var _cooldown := 0.0
var _since_shot := 0.0
var _reload_left := 0.0
var _reload_duration := 0.0
## False after a shot until the trigger is released (semi-auto guns need a new click).
var _trigger_reset := true
## True once this pull has reported an empty magazine.
var _dry_this_pull := false
var _flash_left := 0.0

@onready var muzzle: Marker3D = $Muzzle
@onready var _model: Node3D = $Model
@onready var _flash: Node3D = $Muzzle/Flash
@onready var _flash_light: OmniLight3D = $Muzzle/FlashLight


func _ready() -> void:
	_flash.visible = false
	_flash_light.visible = false
	visible = data != null


## Puts `gun` (an ItemData with weapon stats, or null for empty hands) in hand with a full magazine of
## `ammo_item`, plus `spare` rounds of it (-1 for unlimited).
func equip(gun: ItemData, ammo_item: ItemData, spare: int) -> void:
	item = gun
	data = gun.weapon if gun else null
	cancel_reload()
	set_ammo(ammo_item)
	rounds = data.magazine_size if data and ammo else 0
	spare_rounds = spare
	recoil = 0.0
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


## Total spread of the next shot in degrees. `speed_ratio` is how fast the shooter moves, 1 = sprinting.
func spread(speed_ratio: float) -> float:
	if data == null:
		return 0.0
	return data.base_spread + data.move_spread * clampf(speed_ratio, 0.0, 1.0) + recoil


## Fires one round at `target` if the gun is ready: not reloading, the fire-rate delay has passed,
## there's a round in the magazine and (for semi-auto) the trigger was released since the last shot.
## `extra_spread` is the shooter's own aim error in degrees. Returns true if a round went off.
func pull_trigger(shooter: Actor, origin: Vector3, target: Vector3, extra_spread: float, speed_ratio: float) -> bool:
	if not has_gun() or is_reloading or _cooldown > 0.0:
		return false
	if not (data.automatic or _trigger_reset):
		return false
	if rounds == 0:
		if not _dry_this_pull:
			_dry_this_pull = true
			dry_fired.emit()
		return false
	# Keep the leftover time when firing continuously, so the fire rate is exact at 60 ticks/s.
	_cooldown = (_cooldown if _cooldown > -get_physics_process_delta_time() else 0.0) + data.shot_interval()
	_trigger_reset = false
	rounds -= 1
	var direction := cone((target - origin).normalized(), spread(speed_ratio) + extra_spread)
	Ballistics.fire(shooter, origin, direction, ammo, muzzle.global_position)
	recoil = minf(recoil + data.recoil_per_shot, data.max_recoil)
	_since_shot = 0.0
	_show_flash()
	_model.position.z = KICK_DISTANCE
	fired.emit()
	return true


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


## 0 to 1 through the current reload; 0 when not reloading.
func reload_progress() -> float:
	if not is_reloading or _reload_duration <= 0.0:
		return 0.0
	return 1.0 - _reload_left / _reload_duration


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, -1.0)
	_since_shot += delta
	if data and _since_shot >= data.recovery_delay:
		recoil = maxf(recoil - data.recoil_recovery * delta, 0.0)
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
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
