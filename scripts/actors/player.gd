class_name Player
extends Actor
## The player (DESIGN.md §13). Turns input into Actor intents: WASD moves relative to the screen,
## the body faces the in-raid reticle, Shift sprints, C crouches, Space rolls, Q takes or leaves cover,
## right-click peeks out of cover, left-click fires and R reloads.
## In a raid the mouse is captured and moves the reticle (`cursor_position`) at the sensitivity set in
## Settings; a controller's right stick moves it too. Sprint, crouch and aim can hold or toggle.
## Vision (DESIGN.md §13.6): the cone points at the reticle. Aiming (right-click) looks through the
## gun's sight: a scope gives a longer, narrower cone, slows you down and pulls the camera out toward
## the aim point. L toggles the flashlight, B takes out or puts away binoculars (no shooting with them).
## Inventory (DESIGN.md §7): the gun in hand is the first one in the primary, secondary or pistol slot;
## spare rounds come from the pockets, rig and backpack and go into the magazine as they are (keeping
## their Found-in-Raid status); everything carried counts toward the weight that slows you. While an
## inventory screen is open (`ui_open`) you can still walk, but not shoot, aim or move the reticle.
## Looting: F uses the nearest container, body or item on the ground in reach. Anything that reaches
## the inventory and wasn't brought in is claimed as loot: found in raid if you extract (FoundInRaid).
## 360 trick shots (DESIGN.md §13.4): with a bolt-action rifle or DMR in hand, sweeping the reticle a
## full turn around the player in one direction (within the gun's spin time, rolling or not) opens a
## TRICK SHOT READY window; the first shot in it deals bonus damage. No aiming while spinning or while
## the window is open: the shot is fired from the hip, with full hip-fire bloom.
## Meds, stims, food and drink (DESIGN.md §13.7): E (use_item) treats the worst problem with what's in
## the pockets, rig or secure container (Consumables.quick_pick()); the inventory's USE uses any item
## you carry. Each takes its use time, walking slowly (no sprinting, shooting, aiming or reloading).
## Shooting, rolling, sprinting, reloading, aiming, a hit that does damage, losing the item or E again
## interrupts it: nothing happens and nothing is used up. Energy and hydration drain while in a raid.
## Input (DESIGN.md §17.1): every control is an InputMap action, so keyboard and mouse, a controller and
## the touch controls all drive the same code. The right stick (controller or touch) points the reticle
## out from the player (sensitivity per device, invert Y), with aim assist pulling it onto targets near
## it (InputHub.aim_assist_strength()); spinning it a full circle is a 360 trick shot like the mouse.
## Mouse events emulated from touch never move the reticle. Hotkeys 1-5 use the item set for them
## (GameState.hotkeys): meds, stims and food are used, grenades thrown at the reticle (ThrownGrenade),
## a signal flare fired in an extract that needs one. Melee (V / RB / touch): a tap swings the melee
## weapon (or a fist), holding it raises the parry stance (Actor.melee_strike(), can_parry()).
## As a BEAR or USEC PMC it looks and sounds like its faction (Actor.set_faction(), set by RaidLevel)
## and barks too (Voice): reloading, a grenade out, being hit, a kill.

## Emitted when one of the player's bullets hits someone (hit markers, damage numbers).
signal hit_landed(target: Actor, damage: float, position: Vector3)
## Something wants its loot shown beside the inventory: a container's grid or a body's Inventory.
## `source` is the container, body or other node it belongs to (the panel closes if you walk away).
signal loot_requested(title: String, loot: Variant, source: Node3D)
## Loot that just reached the inventory (pending found in raid until you extract).
signal loot_claimed(items: Array[ItemInstance])
## Someone this player shot died (for raid XP).
signal killed(target: Actor)
## A full spin opened a 360 trick shot window (DESIGN.md §13.4).
signal trick_shot_ready
## Started using `item` (a med, stim, food or drink) for `seconds`.
signal item_use_started(item: ItemInstance, seconds: float)
## Using `item` ended: `finished` with what it did in `text`, or interrupted (`text` says why).
signal item_use_ended(item: ItemInstance, finished: bool, text: String)
## A trick shot hit `target` (and killed it, if `killed`).
signal trick_shot_hit(target: Actor, damage: float, position: Vector3, killed: bool)

## Right stick: how far from the player it puts the reticle, and how fast the reticle gets there.
const STICK_AIM_RADIUS := 360.0
const STICK_AIM_SPEED := 2600.0
## Aim assist (sticks only): targets this close (pixels) to where the stick points pull the reticle in;
## the pull eases in and out at this speed (pixels a second).
const AIM_ASSIST_RADIUS := 150.0
const AIM_ASSIST_SPEED := 900.0
## Holding melee this long (seconds) raises the parry stance instead of swinging.
const PARRY_HOLD := 0.25
## Seconds between grenade throws.
const THROW_COOLDOWN := 0.8
## Camera shake strength per hit taken (0-1, scaled by Settings). Each gun sets its own kick per shot.
const HIT_SHAKE := 0.45
const FLASHLIGHT_ENERGY := 8.0
## Through a scope the camera leads toward the aim point, but keeps you within this share of the
## half-screen from its centre.
const MAX_LEAD_SCREEN_SHARE := 0.55
## How close a container, body or item must be to use it with F (metres, flat).
const INTERACT_RANGE := 2.0
## The reticle has to be at least this far from the player (metres, flat) for its direction to count
## toward a spin: right on top of the player, tiny moves would look like huge turns.
const SPIN_MIN_RADIUS := 0.75
## A spin past this share of a full turn (within the spin time) already stops you aiming.
const SPIN_AIM_LOCK := 0.5
## Trick-shot feedback colour (popup, hit marker, banner).
const TRICK_COLOR := Color(1.0, 0.82, 0.25)
## Hit markers and damage numbers for a round that armor stopped (DESIGN.md §6.4).
const ARMOR_HIT_COLOR := Color(0.62, 0.76, 0.95)

## Where the reticle is, in viewport pixels.
var cursor_position := Vector2.ZERO
## Enemies killed this raid.
var kills := 0
var flashlight_on := false
## Binoculars in hand instead of the gun.
var using_binoculars := false
## 0 to 1 while raising a sight to the eye (DESIGN.md §13.6): cone, range, speed and camera blend by it.
var optic_blend := 0.0
## What the player carries. The level sets it from the raid loadout (set_inventory()).
var inventory: Inventory
## Extra weight on top of the inventory (debug key F2).
var debug_extra_weight := 0.0:
	set(value):
		debug_extra_weight = value
		_update_weight()
## True while an inventory screen is open: walking still works; shooting, aiming and the reticle don't.
var ui_open := false
## The nearest thing in reach that F would use (in group "interactables"), or null. The HUD shows it.
var focused_interactable: Node
## Seconds left in the TRICK SHOT READY window (0: closed).
var trick_window_left := 0.0
## Trick shots this raid: hits, and kills.
var trick_hits := 0
var trick_kills := 0

var _roll_requested := false
var _cover_requested := false
## Seconds the melee button has been held (-1: not held), and until the next throw.
var _melee_held := -1.0
var _throw_cooldown := 0.0
## Aim assist's shift of where the stick points (pixels).
var _assist_offset := Vector2.ZERO
var _sprint_toggled := false
var _aim_toggled := false
var _reload_requested := false
var _flashlight: SpotLight3D
## The inventory item of the gun in hand.
var _weapon_item: ItemInstance
## True while a reload moves rounds from the inventory into the magazine.
var _loading_rounds := false
var _spin := SpinTracker.new()
## Where the reticle points on the ground (aim_point snaps to whoever is under it; this doesn't), for
## the spin.
var _cursor_ground := Vector3.ZERO
## What the last round that hit someone did (ArmorRules.resolve()): the HUD's hit marker reads it.
var last_hit: Dictionary = {}
## The last damage number, so the pellets of one shell that hit the same target share it.
var _last_number: Label3D
var _last_number_frame := -1
var _last_number_target: Actor
var _last_number_damage := 0.0
## The item being used (DESIGN.md §13.7), the body part it's meant for (-1: it picks), and the time
## left and in all.
var using_item: ItemInstance
var _use_part := -1
var use_time_left := 0.0
var use_time_total := 0.0


func _ready() -> void:
	super()
	roll_finished.connect(_on_roll_finished)
	cursor_position = get_viewport().get_visible_rect().size * Vector2(0.5, 0.38)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.position = Vector3(0.14, gun_height(), -0.4)
	_flashlight.rotation_degrees.x = -8.0  # Tilted down a little to light the ground.
	_flashlight.spot_range = VisionSystem.config.flashlight_range
	_flashlight.spot_angle = VisionSystem.config.flashlight_cone_degrees / 2.0
	_flashlight.light_energy = FLASHLIGHT_ENERGY
	_flashlight.light_color = Color(1.0, 0.95, 0.85)
	_flashlight.shadow_enabled = true
	_flashlight.visible = false
	add_child(_flashlight)
	weapon.fired.connect(_on_round_fired)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.jam_cleared.connect(_on_jam_cleared)
	hit_landed.connect(func(_target: Actor, _damage: float, _at: Vector3) -> void: InputHub.pulse("hit"))
	hurt.connect(func(_damage: float) -> void: InputHub.pulse("damage"))
	parried.connect(func(attacker: Actor) -> void:
		InputHub.pulse("parry")
		action_blocked.emit("Parried %s" % attacker.display_name()))
	health.start_metabolism(Consumables.CONFIG, GameState.energy, GameState.hydration)
	set_inventory(Inventory.starter())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("melee"):
		_release_melee()
	if ui_open:
		return
	if event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return  # A finger on a touch screen: the touch controls aim.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: Vector2 = event.relative * _sensitivity()
			if Settings.get_value("controls", "invert_mouse"):
				motion.y = -motion.y
			_move_cursor(motion)
		return
	if event.is_action_pressed("crouch") and Settings.is_toggle("crouch_mode"):
		set_crouching(not is_crouching)
	elif event.is_action_pressed("sprint") and Settings.is_toggle("sprint_mode"):
		_sprint_toggled = not _sprint_toggled
	elif event.is_action_pressed("aim") and Settings.is_toggle("aim_mode"):
		_aim_toggled = not _aim_toggled
	elif event.is_action_pressed("roll"):
		_roll_requested = true
	elif event.is_action_pressed("take_cover"):
		_cover_requested = true
	elif event.is_action_pressed("reload"):
		_reload_requested = true
	elif event.is_action_pressed("flashlight"):
		set_flashlight(not flashlight_on)
	elif event.is_action_pressed("binoculars"):
		set_binoculars(not using_binoculars)
	elif event.is_action_pressed("interact") and focused_interactable and not is_dead:
		focused_interactable.interact(self)
	elif event.is_action_pressed("use_item") and not is_dead:
		if using_item:
			cancel_use("Stopped using %s" % using_item.data.display_name)
		else:
			quick_use()
	elif event.is_action_pressed("melee") and not is_dead:
		_melee_held = 0.0
	else:
		for i in GameState.HOTKEY_COUNT:
			if event.is_action_pressed("hotkey_%d" % (i + 1)) and not is_dead:
				use_hotkey(i)
				break


func _process(delta: float) -> void:
	_update_camera_view()
	if not InputHub.sticks_enabled() or ui_open or is_dead:
		return
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if Settings.get_value("controls", "invert_y"):
		stick.y = -stick.y
	var camera := get_viewport().get_camera_3d()
	if stick != Vector2.ZERO and camera:
		# Twin-stick aiming: the stick points the reticle out from the player (plus aim assist's pull).
		var center := camera.unproject_position(global_position + Vector3.UP * gun_height())
		var speed: float = STICK_AIM_SPEED * InputHub.stick_sensitivity()
		var aim_at := center + stick * STICK_AIM_RADIUS
		_assist_offset = _aim_assist(camera, aim_at, delta)
		_move_cursor(cursor_position.move_toward(aim_at + _assist_offset, speed * delta) - cursor_position)
	else:
		_assist_offset = Vector2.ZERO


## Aim assist (controller and touch): how far to shift where the stick points, toward the chest of the
## nearest hostile you can see within AIM_ASSIST_RADIUS of it: more the stronger the setting and the
## closer it is (at full strength and close in, onto it). Eases in and out at AIM_ASSIST_SPEED.
func _aim_assist(camera: Camera3D, aim_at: Vector2, delta: float) -> Vector2:
	var strength := InputHub.aim_assist_strength()
	var wanted := Vector2.ZERO
	if strength > 0.0:
		var best_distance := AIM_ASSIST_RADIUS
		for node in get_tree().get_nodes_in_group("actors"):
			var other := node as Actor
			if other == null or other == self or other.is_dead or not is_hostile(other) or not other.is_seen():
				continue
			var chest := camera.unproject_position(other.chest_point())
			var distance := chest.distance_to(aim_at)
			if distance < best_distance:
				best_distance = distance
				wanted = (chest - aim_at) * minf(1.0, strength * (1.5 - distance / AIM_ASSIST_RADIUS))
	return _assist_offset.move_toward(wanted, AIM_ASSIST_SPEED * delta)


func _think(delta: float) -> void:
	_update_focus()
	_throw_cooldown = maxf(_throw_cooldown - delta, 0.0)
	if _melee_held >= 0.0:
		_melee_held += delta
		parrying = _melee_held >= PARRY_HOLD and not ui_open and stagger_time <= 0.0
	move_input = _input_direction()
	var moving := not move_input.is_zero_approx()
	if Settings.is_toggle("sprint_mode"):
		_sprint_toggled = _sprint_toggled and moving  # Stopping ends a toggled sprint.
		sprint_input = _sprint_toggled
	else:
		sprint_input = Input.is_action_pressed("sprint")
	if not Settings.is_toggle("crouch_mode") and cover == null:
		set_crouching(Input.is_action_pressed("crouch") and not (sprint_input and moving))
	fire_input = Input.is_action_pressed("shoot") and not using_binoculars and not ui_open
	if using_binoculars and Input.is_action_just_pressed("shoot") and not ui_open:
		action_blocked.emit("Put the binoculars away to shoot (%s)" % Settings.key_label("binoculars"))
	auto_reload = Settings.get_value("gameplay", "auto_reload")
	peek_input = (_aim_toggled if Settings.is_toggle("aim_mode") else Input.is_action_pressed("aim")) and not ui_open
	if using_item:
		_update_use(delta, moving)
	if _reload_requested:
		_reload_requested = false
		try_reload()
	_update_aim()
	_update_trick_shot(delta)
	var transition := VisionSystem.config.optic_transition_time
	if weapon.data and not using_binoculars:
		transition *= weapon.data.aim_time_multiplier  # Ergonomics and sights.
	var raise := 1.0 if is_using_optic() else 0.0
	optic_blend = move_toward(optic_blend, raise, delta / transition) if transition > 0.0 else raise
	if is_spinning():
		optic_blend = 0.0  # Spinning: the gun is down at the hip.
	_flashlight.position.y = gun_height()
	if _roll_requested:
		_roll_requested = false
		# Roll the way you're moving, or toward the reticle when standing still.
		try_roll(move_input if moving else aim_point - global_position)
	if _cover_requested:
		_cover_requested = false
		if cover:
			exit_cover()
		else:
			var spot := CoverSystem.find_snap_point(self, config.cover_snap_distance)
			if spot:
				enter_cover(spot)
			else:
				action_blocked.emit("No cover nearby")


func set_flashlight(on: bool) -> void:
	flashlight_on = on
	_flashlight.visible = on


## Carries `new_inventory` into the raid from now on: its weight, its gun, its spare rounds. All of it
## counts as brought in, so none of it turns into found-in-raid loot.
func set_inventory(new_inventory: Inventory) -> void:
	if inventory and inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.disconnect(_on_inventory_changed)
	inventory = new_inventory
	FoundInRaid.mark_brought_in(inventory)
	inventory.changed.connect(_on_inventory_changed)
	_update_weight()
	_sync_weapon(true)


func set_binoculars(on: bool) -> void:
	using_binoculars = on
	weapon.visible = weapon.has_gun() and not on
	if on:
		action_blocked.emit("Binoculars: hold %s to look through them" % Settings.key_label("aim"))


## How far the sight is up (0 hip-firing, 1 aimed): it rises over the gun's aim time while you hold
## the aim button.
func aim_blend() -> float:
	return 0.0 if using_binoculars else optic_blend


## The gun's sway: its build's (DESIGN.md §12.1), less with the sight up.
func weapon_sway() -> float:
	if weapon.data == null:
		return 0.0
	return weapon.data.sway * lerpf(1.0, WeaponStats.CONFIG.aimed_sway_multiplier, aim_blend())


## Where the reticle is drawn: where the next shot goes before spread, i.e. the cursor moved by the
## gun's recoil kick (out along the aim for the climb, sideways for the side kick) and by sway.
func reticle_position() -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not has_aim or weapon.data == null:
		return cursor_position
	var origin := global_position + Vector3.UP * gun_height()
	var to_aim := aim_point - origin
	if Vector2(to_aim.x, to_aim.z).length() < 0.5:
		return cursor_position
	var yaw := -deg_to_rad(weapon.recoil_kick.x - aim_sway_degrees())
	var turned := origin + to_aim.rotated(Vector3.UP, yaw)
	var from_screen := camera.unproject_position(origin)
	var at := camera.unproject_position(turned)
	var along := (at - from_screen).normalized()
	var climb := from_screen.distance_to(at) * tan(deg_to_rad(weapon.recoil_kick.y))
	return cursor_position + (at - camera.unproject_position(aim_point)) + along * climb


## The sight you look through when aiming: binoculars if they're out, else the gun's (VisionConfig.Optic).
func current_optic() -> int:
	return VisionConfig.Optic.BINOCULARS if using_binoculars else weapon.optic


## Aiming down a sight (or the binoculars) right now.
func is_using_optic() -> bool:
	if is_dead or is_rolling or not peek_input:
		return false
	return using_binoculars or (weapon.has_gun() and not weapon.is_reloading and not weapon.is_clearing and not is_spinning())


## True if the gun in hand can make 360 trick shots (a bolt-action rifle or DMR).
func can_trick_shot() -> bool:
	return weapon.has_gun() and weapon.data.allows_trick_shots()


## Spinning for a trick shot (half a turn or more within the spin time) or holding one ready: the gun
## stays at the hip, so no aiming.
func is_spinning() -> bool:
	return can_trick_shot() and (_spin.progress() >= SPIN_AIM_LOCK or trick_window_left > 0.0)


## How far into a spin the aim is, 0-1 of a full turn (the reticle shows it).
func spin_progress() -> float:
	return _spin.progress() if can_trick_shot() else 0.0


## Tracks the reticle turning around the player; a full turn one way opens the trick-shot window.
func _update_trick_shot(delta: float) -> void:
	if trick_window_left > 0.0:
		trick_window_left = maxf(trick_window_left - delta, 0.0)
		if trick_window_left == 0.0:
			weapon.trick_armed = false  # Closed without a shot.
	# The reticle's own direction: sweeping it across someone mustn't jump the spin to their chest.
	var to_aim := _cursor_ground - global_position
	if not has_aim or is_dead or ui_open or Vector2(to_aim.x, to_aim.z).length() < SPIN_MIN_RADIUS:
		return
	_spin.spin_time = weapon.data.trick_spin_time if weapon.data else 1.5
	if _spin.feed(atan2(to_aim.x, to_aim.z), delta) and can_trick_shot():
		trick_window_left = weapon.data.trick_window
		weapon.trick_armed = true
		trick_shot_ready.emit()


# --- Using items (DESIGN.md §13.7) ---------------------------------------------------------------

## The melee button let go: a short press swings, a long one ends the parry stance.
func _release_melee() -> void:
	if _melee_held < 0.0:
		return
	var swing := _melee_held < PARRY_HOLD
	_melee_held = -1.0
	parrying = false
	if swing and not ui_open and not is_dead:
		var result := melee_strike()
		if result.is_empty():
			return
		if result.parried:
			action_blocked.emit("%s parried: you're staggered" % result.target.display_name())
			InputHub.pulse("parry")
		elif result.target:
			InputHub.pulse("melee")


## Uses hotkey `index` (0-4): the first item with its id you carry. Meds, stims and food are used;
## grenades thrown at the reticle; a signal flare fired in an extract that needs one. False (and a
## message) if it can't.
func use_hotkey(index: int) -> bool:
	var id := str(GameState.hotkeys[index]) if index < GameState.hotkeys.size() else ""
	if id == "":
		action_blocked.emit("Hotkey %d is empty: set it when examining an item" % (index + 1))
		return false
	var item: ItemInstance = null
	for carried in inventory.all_items():
		if carried.data.id == id:
			item = carried
			break
	if item == null:
		action_blocked.emit("No %s on you" % (ItemDB.get_item(id).display_name if ItemDB.has_item(id) else id))
		return false
	if item.data.category == ItemData.Category.THROWABLE:
		return throw_item(item)
	if Consumables.is_consumable(item.data):
		return start_use(item)
	if id == ExtractZone.FLARE_ITEM:
		var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
		if raid and raid.extract_zone and raid.extract_zone.needs_flare and not raid.extract_zone.flare_fired:
			return raid.extract_zone.fire_flare(self)
		action_blocked.emit("Fire it inside an extract that needs a flare")
		return false
	action_blocked.emit("Can't use %s from a hotkey" % item.data.display_name)
	return false


## True if items of `data` can go on a hotkey: meds, stims, food and drink, grenades and the signal flare.
static func hotkey_usable(data: ItemData) -> bool:
	return data != null and (data.category == ItemData.Category.THROWABLE or Consumables.is_consumable(data)
		or data.id == ExtractZone.FLARE_ITEM)


## Throws one of `item` (a grenade) at the reticle (ThrownGrenade). False if it can't now.
func throw_item(item: ItemInstance) -> bool:
	if is_dead or is_rolling or _throw_cooldown > 0.0 or stagger_time > 0.0 or ui_open:
		return false
	_throw_cooldown = THROW_COOLDOWN
	var data := item.data
	if item.count > 1:
		item.count -= 1
		var holder := inventory.holder_of(item)
		if holder:
			holder.changed.emit()
	else:
		inventory.remove_item(item)
	ThrownGrenade.throw(self, data, aim_point if has_aim else global_position + Vector3(vision_facing().x, 0.0, vision_facing().y) * 8.0)
	action_blocked.emit("Threw a %s" % data.display_name)
	if voice:
		voice.say(&"grenade")
	return true


## Starts using `item` (on body part `part`, or wherever it's needed): false (with the reason in
## action_blocked) if it can't be used now.
func start_use(item: ItemInstance, part := -1) -> bool:
	var reason := use_block_reason(item)
	if reason != "":
		action_blocked.emit(reason)
		return false
	if using_item:
		cancel_use("")
	using_item = item
	_use_part = part
	use_time_total = Consumables.use_time(item.data)
	use_time_left = use_time_total
	_sprint_toggled = false
	_aim_toggled = false
	weapon.release_trigger()
	item_use_started.emit(item, use_time_total)
	return true


## Why `item` can't be used now, or "".
func use_block_reason(item: ItemInstance) -> String:
	if is_dead:
		return "Dead"
	if item == null or not Consumables.is_consumable(item.data):
		return "Can't be used"
	if inventory.holder_of(item) == null:
		return "Take it first"
	if is_rolling:
		return "Can't use items mid-roll"
	if weapon.is_reloading or weapon.is_clearing:
		return "Can't use items while reloading"
	if not ui_open and (fire_input or peek_input or move_state == Move.SPRINT):
		return "Can't use items while %s" % ("shooting" if fire_input else ("aiming" if peek_input else "sprinting"))
	return Consumables.block_reason(item, health)


## Stops using the item: nothing happens and nothing is used up. `reason` goes to the HUD ("" for none).
func cancel_use(reason: String) -> void:
	if using_item == null:
		return
	var item := using_item
	using_item = null
	use_time_left = 0.0
	item_use_ended.emit(item, false, reason)
	if reason != "":
		action_blocked.emit(reason)


## E: treats the worst problem with what's in reach (Consumables.quick_pick()).
func quick_use() -> bool:
	var pick := Consumables.quick_pick(inventory, health)
	if not pick.has("item"):
		action_blocked.emit(str(pick.reason))
		return false
	return start_use(pick.item, int(pick.part))


## 0 to 1 through the item being used.
func use_progress() -> float:
	return 1.0 - use_time_left / use_time_total if using_item and use_time_total > 0.0 else 0.0


## Shooting, rolling, sprinting, reloading or aiming stops the use (and goes ahead); otherwise the use
## counts down and then takes effect.
func _update_use(delta: float, moving: bool) -> void:
	var interrupt := ""
	if fire_input:
		interrupt = "shooting"
	elif _roll_requested:
		interrupt = "rolling"
	elif sprint_input and moving:
		interrupt = "sprinting"
	elif _reload_requested:
		interrupt = "reloading"
	elif peek_input:
		interrupt = "aiming"
	if interrupt != "":
		cancel_use("%s interrupted: %s" % [using_item.data.display_name, interrupt])
		return
	use_time_left -= delta
	if use_time_left <= 0.0:
		_finish_use()


func _finish_use() -> void:
	var item := using_item
	using_item = null
	use_time_left = 0.0
	var result := Consumables.apply(item, health, _use_part)
	if not result.ok:
		item_use_ended.emit(item, false, str(result.reason))
		action_blocked.emit("%s: %s" % [item.data.display_name, result.reason])
		return
	if result.used_up:
		inventory.remove_item(item)
	else:
		var holder := inventory.holder_of(item)
		if holder:
			holder.changed.emit()  # Redraw the uses left.
	item_use_ended.emit(item, true, str(result.text))
	action_blocked.emit(str(result.text))


## Opens `loot` (a container's InventoryGrid or a body's Inventory) from `source` beside the inventory.
func open_loot(title: String, loot: Variant, source: Node3D = null) -> void:
	loot_requested.emit(title, loot, source)


## Picks `item` up off the ground into the pockets, rig or backpack. False (with a message) if it
## didn't all fit; what fit is taken, the rest stays.
func pick_up(item: ItemInstance) -> bool:
	if inventory.add(item):
		return true
	action_blocked.emit("No room for %s" % item.data.display_name)
	return false


func _update_focus() -> void:
	focused_interactable = null
	if is_dead:
		return
	var best := INF
	for node: Node3D in get_tree().get_nodes_in_group("interactables"):
		var offset := node.global_position - global_position
		var distance := Vector2(offset.x, offset.z).length()
		# Most things are in reach within INTERACT_RANGE; big ones (an extract zone) say how far.
		var reach: float = node.interact_reach() if node.has_method("interact_reach") else INTERACT_RANGE
		if distance <= reach and distance < best and node.can_interact(self):
			best = distance
			focused_interactable = node


func _on_inventory_changed() -> void:
	if using_item and inventory.holder_of(using_item) == null:
		cancel_use("%s interrupted: it's not on you any more" % using_item.data.display_name)
	var claimed := FoundInRaid.claim(inventory)
	if not claimed.is_empty():
		loot_claimed.emit(claimed)
	_update_weight()
	_sync_weapon()


func _update_weight() -> void:
	carried_weight_kg = (inventory.total_weight() if inventory else 0.0) + debug_extra_weight


## Puts the inventory's gun in hand if it changed (or `force`), with its modded stats, sight and
## durability; the rounds come from its magazine and the spare rounds are recounted. The gun reloads
## with its round type (ItemInstance.loaded_ammo, set by dropping rounds on it) and fires whatever is on
## top of its magazine.
func _sync_weapon(force := false) -> void:
	if _loading_rounds:
		return
	var slot := inventory.weapon_slot()
	var item: ItemInstance = inventory.equipment[slot] if slot != "" else null
	# A gun without a round type yet takes the first matching ammo you carry.
	if item and item.data.weapon and item.loaded_ammo == "":
		item.loaded_ammo = _carried_ammo_for(item.data.weapon.caliber)
	if force or item != _weapon_item:
		_weapon_item = item
		if item == null or item.data.weapon == null:
			equip_weapon("", "", 0)
		else:
			trick_window_left = 0.0
			var stats := WeaponStats.build(item, GameState.skills)
			equip_weapon(item.data.id, item.loaded_ammo, inventory.count_of(item.loaded_ammo), stats)
			weapon.optic = stats.optic
			weapon.durability = item.durability
	elif item and item.data.weapon and item.loaded_ammo != ammo_id:
		ammo_id = item.loaded_ammo  # Rounds of another type were loaded into it.
	if _weapon_item and _weapon_item.data.weapon and weapon.data:
		_chamber_top_round()
		weapon.rounds = mini(_weapon_item.rounds_loaded(), weapon.data.magazine_size)
		weapon.spare_rounds = inventory.count_of(ammo_id)
	weapon.visible = weapon.has_gun() and not using_binoculars


## The round the gun fires next: the top of its magazine, else the type it reloads with.
func _chamber_top_round() -> void:
	var top: ItemData = null
	if not _weapon_item.magazine.is_empty():
		top = _weapon_item.magazine.back().data
	elif ammo_id != "":
		top = ItemDB.get_item(ammo_id)
	if top and top != weapon.ammo:
		weapon.set_ammo(top)


## The first rounds of `caliber` you carry (pockets, rig, backpack), or "".
func _carried_ammo_for(caliber: String, except := "") -> String:
	for grid in inventory.ammo_grids():
		for item in grid.items:
			if item.data.category == ItemData.Category.AMMO and item.data.stats.get("caliber", "") == caliber and item.data.id != except:
				return item.data.id
	return ""


## Reloading with none of the gun's round type left switches to another type of the same caliber you
## carry (it goes in on top of what's still in the magazine).
func try_reload() -> bool:
	if _weapon_item and weapon.has_gun() and not weapon.is_jammed and weapon.spare_rounds == 0 \
			and weapon.rounds < weapon.data.magazine_size:
		var other := _carried_ammo_for(weapon.data.caliber, ammo_id)
		if other != "":
			_weapon_item.loaded_ammo = other
			ammo_id = other
			weapon.spare_rounds = inventory.count_of(other)
			action_blocked.emit("Loading %s" % ItemDB.get_item(other).display_name)
	return super()


## Swaps the loaded round type, keeping the counts and their status (debug key F3).
func set_ammo(id: String) -> void:
	super(id)
	if _weapon_item:
		_weapon_item.convert_magazine(id)
	weapon.spare_rounds = inventory.count_of(id)


func _on_round_fired() -> void:
	if weapon.firing_trick_shot:
		trick_window_left = 0.0  # Only the first shot in the window is a trick shot.
	if _weapon_item:
		_weapon_item.fire_round()
		_weapon_item.durability = maxf(weapon.durability, 0.0)
		_chamber_top_round()


## Clearing a jam throws the stuck round out of the gun.
func _on_jam_cleared(ejected: bool) -> void:
	if _weapon_item and ejected:
		_weapon_item.fire_round()


## The rounds a reload put in the magazine come out of the pockets, rig or backpack, and go in as
## they are: found-in-raid rounds stay found in raid.
func _on_reload_finished() -> void:
	if _weapon_item == null:
		return
	var wanted := weapon.rounds - _weapon_item.rounds_loaded()
	if wanted > 0:
		_loading_rounds = true
		for piece in inventory.take_pieces(ammo_id, wanted):
			_weapon_item.load_rounds(piece)
		_loading_rounds = false
	_sync_weapon()


# --- Vision -----------------------------------------------------------------------------------

## The main cone (blended toward the sight's while aiming, narrowed by pain or a head injury), and the
## flashlight beam if it's on.
func vision_cones() -> Array[Vector3]:
	var vision := VisionSystem.config
	var half := deg_to_rad(vision.player_cone_degrees) / 2.0
	var reach := vision.player_range
	var optic := vision.optic(current_optic())
	if optic and optic_blend > 0.0:
		half = lerpf(half, deg_to_rad(optic.cone_degrees) / 2.0, optic_blend)
		reach = lerpf(reach, reach * optic.range_multiplier, optic_blend)
	var cones: Array[Vector3] = [Vector3(half * status_cone_multiplier(), reach * status_range_multiplier(), 0.0)]
	if flashlight_on:
		cones.append(Vector3(deg_to_rad(vision.flashlight_cone_degrees) / 2.0, vision.flashlight_range, 1.0))
	return cones


## Toward the reticle (not the body, which takes a moment to turn).
func vision_facing() -> Vector2:
	if has_aim:
		var to_aim := Vector2(aim_point.x - global_position.x, aim_point.z - global_position.z)
		if to_aim.length() > 0.2:
			return to_aim.normalized()
	return super()


func awareness_radius() -> float:
	return VisionSystem.config.awareness_radius


func has_light_on() -> bool:
	return flashlight_on


func die() -> void:
	optic_blend = 0.0
	cancel_use("")
	super()


func _move_multiplier() -> float:
	var optic := VisionSystem.config.optic(current_optic())
	var multiplier := lerpf(1.0, optic.move_multiplier, optic_blend) if optic else 1.0
	if using_item:
		multiplier *= Consumables.move_multiplier(using_item.data)
	return multiplier


## No sprinting while looking through a sight (iron sights don't count) or using an item.
func _can_sprint() -> bool:
	return using_item == null and (optic_blend <= 0.0 or current_optic() == VisionConfig.Optic.IRON_SIGHTS)


## Through a scope the camera pulls out and leads toward the aim point, so the longer view is on screen.
func _update_camera_view() -> void:
	var camera := get_viewport().get_camera_3d() as TopDownCamera
	if camera == null:
		return
	var optic := VisionSystem.config.optic(current_optic())
	if optic == null or optic_blend <= 0.0:
		camera.focus_offset = Vector3.ZERO
		camera.zoom = 1.0
		return
	var zoom := lerpf(1.0, optic.camera_zoom, optic_blend)
	var to_aim := aim_point - global_position
	var lead := (Vector3(to_aim.x, 0.0, to_aim.z) * optic.camera_lead).limit_length(optic.camera_max_lead)
	var limits := camera.ground_half_extents(zoom) * MAX_LEAD_SCREEN_SHARE
	lead.x = clampf(lead.x, -limits.x, limits.x)
	lead.z = clampf(lead.z, -limits.y, limits.y)
	camera.focus_offset = lead * optic_blend
	camera.zoom = zoom


func on_hit_landed(target: Actor, damage: float, hit_position: Vector3, outcome: Dictionary = {}) -> void:
	last_hit = outcome
	if weapon.firing_trick_shot:
		trick_hits += 1
		if target.is_dead:
			trick_kills += 1
		trick_shot_hit.emit(target, damage, hit_position, target.is_dead)
		_spawn_trick_popup(hit_position)
	if target.is_dead:
		kills += 1  # Corpses can't be hit, so this hit was the kill.
		killed.emit(target)
		if voice:
			voice.say(&"enemy_down")
	hit_landed.emit(target, damage, hit_position)
	if Settings.get_value("gameplay", "damage_numbers"):
		# Pellets from one shell that hit the same target add up into one number.
		var frame := Engine.get_physics_frames()
		if is_instance_valid(_last_number) and _last_number_frame == frame and _last_number_target == target:
			_last_number_damage += damage
			_last_number.text = str(roundi(_last_number_damage))
		else:
			_last_number = _spawn_damage_number(hit_position, damage, outcome)
			_last_number_frame = frame
			_last_number_target = target
			_last_number_damage = damage


func take_hit(damage: float, from: Actor, hit_position: Vector3, shot: Dictionary = {}) -> Dictionary:
	var outcome := super(damage, from, hit_position, shot)
	_shake_camera(HIT_SHAKE)
	if using_item and float(outcome.get("damage", 0.0)) > 0.0 and Consumables.CONFIG.hits_interrupt:
		cancel_use("%s interrupted: hit" % using_item.data.display_name)
	return outcome


func worn_gear() -> Inventory:
	return inventory


func _on_fired() -> void:
	_shake_camera(weapon.data.camera_kick * Weapon.ammo_recoil(weapon.ammo))


## A roll that ends right next to cover, heading into it, snaps into that cover.
func _on_roll_finished(direction: Vector3) -> void:
	enter_cover(CoverSystem.find_snap_point(self, config.roll_snap_distance, direction))


func _sensitivity() -> float:
	return Settings.get_value("controls", "aim_sensitivity" if peek_input else "mouse_sensitivity")


func _move_cursor(motion: Vector2) -> void:
	cursor_position = (cursor_position + motion).clamp(Vector2.ZERO, get_viewport().get_visible_rect().size)


## WASD as a direction on the ground, relative to the screen: W always moves up the screen.
func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0.0, input.y)
	var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var screen_up := Vector3(camera.global_basis.y.x, 0.0, camera.global_basis.y.z).normalized()
	return right * input.x - screen_up * input.y


## Aims at the chest of whoever is under the reticle, or else level with the gun at the ground point
## under it.
func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		has_aim = false
		return
	var from := camera.project_ray_origin(cursor_position)
	var direction := camera.project_ray_normal(cursor_position)
	var on_ground: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(from, direction)
	if on_ground != null:
		_cursor_ground = on_ground
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 200.0, HITBOX_MASK, [hitbox_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target := (hit.collider as Node).get_parent() as Actor if not hit.is_empty() else null
	if target:
		# Centre mass: the reticle picks who, spread and sway decide which body part gets hit.
		aim_point = target.chest_point()
		has_aim = true
		return
	var ground: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(from, direction)
	has_aim = ground != null
	if has_aim:
		aim_point = ground + Vector3.UP * gun_height()


func _shake_camera(amount: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("add_shake"):
		camera.add_shake(amount)


## "360!" over a trick-shot hit: big, gold, rising and fading.
func _spawn_trick_popup(at: Vector3) -> void:
	var label := Label3D.new()
	label.name = "TrickPopup"
	label.text = "360!"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 72
	label.outline_size = 14
	label.modulate = TRICK_COLOR
	label.outline_modulate = Color(0.25, 0.05, 0.2)
	label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().current_scene.add_child(label)
	label.global_position = at + Vector3.UP * 0.6
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position", label.global_position + Vector3.UP * 0.9, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


## A number over a hit: amber, steel blue if armor stopped the round (blunt damage), "RICOCHET" if it
## glanced off, orange-red if it fragmented.
func _spawn_damage_number(at: Vector3, damage: float, outcome: Dictionary = {}) -> Label3D:
	var label := Label3D.new()
	label.text = "RICOCHET" if outcome.get("ricochet", false) else str(roundi(damage))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 42
	label.outline_size = 10
	label.modulate = Color(1.0, 0.85, 0.4)
	if not outcome.get("penetrated", true):
		label.modulate = ARMOR_HIT_COLOR
	elif outcome.get("fragmented", false):
		label.modulate = Color(1.0, 0.5, 0.32)
	label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().current_scene.add_child(label)
	label.global_position = at + Vector3.UP * 0.3
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
	return label
