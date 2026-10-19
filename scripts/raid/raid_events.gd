class_name RaidEvents
extends Node
## Raid events (DESIGN.md §5.2): 1-3 times a raid (PoiConfig.event_count, at random times within
## event_window of the raid) new loot turns up at a point of interest, loudly:
## - an airdrop: a plane passes over, a red flare goes up where the crate will land, and the crate comes
##   down on a parachute (airdrop_fall_seconds), searchable once it's landed;
## - a supply truck: it pulls in with its horn going and leaves its cargo crate behind it;
## - a weapon cache: one of the sealed caches standing at the map's cache spots unlocks with a klaxon
##   and a green flare.
## Each is announced on the HUD with where it is and heard across the map (a sound marker when you can't
## see it), and AI within PoiConfig.event_noise_radius may drop what it's doing and head there
## (Bot.rush_to()). Event crates roll from data/loot_tables/event_*.tres: the best Epic and Legendary
## odds there are. A POI hosts events at its EventSpot markers; the marker's name says which kind
## (EventSpot_airdrop, EventSpot_truck, EventSpot_cache; no suffix: airdrop or truck). A POI with a fresh
## event is hot: it draws Scav waves and roaming AI PMCs (PointOfInterest.heat()). Every RaidLevel has one.

## An event went off: {"kind", "poi", "poi_name", "at", "time", "box" (its crate), "ready" (searchable)}.
signal event_started(event: Dictionary)

const KINDS := ["airdrop", "truck", "cache"]
const TITLES := {"airdrop": "AIRDROP", "truck": "SUPPLY TRUCK", "cache": "WEAPON CACHE"}
const AIRDROP := preload("res://data/loot_tables/containers/airdrop_crate.tres")
const CARGO := preload("res://data/loot_tables/containers/supply_cargo.tres")
const CACHE := preload("res://data/loot_tables/containers/weapon_cache.tres")
const PLANE := preload("res://assets/audio/sfx/plane.wav")
const HORN := preload("res://assets/audio/sfx/truck_horn.wav")
const KLAXON := preload("res://assets/audio/sfx/klaxon.wav")
const FLARE := preload("res://scripts/world/signal_flare.gd")
const TRUCK := preload("res://scenes/props/car.tscn")
const AIRDROP_FLARE := Color(1.0, 0.25, 0.15)
const CACHE_FLARE := Color(0.35, 1.0, 0.4)
## Metres above its spot an airdrop crate starts falling from, and metres a truck drives in.
const DROP_HEIGHT := 30.0
const TRUCK_RUN := 22.0
const ANNOUNCE_COLOR := Color(1.0, 0.75, 0.3)

var config: PoiConfig = preload("res://data/config/poi.tres")
## Raid seconds the remaining events go off at, soonest first.
var schedule: Array[float] = []
## Events so far this raid (see event_started).
var events: Array[Dictionary] = []
## The sealed weapon caches standing at the map's cache spots.
var caches: Array[LootBox] = []
var rng := RandomNumberGenerator.new()

var _raid: RaidController


func _ready() -> void:
	add_to_group("raid_events")
	if GameState.raid.has("seed"):
		rng.seed = int(GameState.raid.seed) + 7919
	else:
		rng.randomize()
	_setup.call_deferred()


func _setup() -> void:
	_raid = get_tree().get_first_node_in_group("raid_controller") as RaidController
	if _raid == null:
		return
	for spot: Dictionary in spots():
		if spot.kind == "cache":
			var cache := _make_box(CACHE, spot.at)
			cache.name = "SealedCache_%s" % spot.poi.poi_id
			caches.append(cache)
	for i in rng.randi_range(config.event_count.x, config.event_count.y):
		schedule.append(_raid.raid_seconds() * rng.randf_range(config.event_window.x, config.event_window.y))
	schedule.sort()


func _physics_process(_delta: float) -> void:
	if _raid == null or _raid.is_over() or schedule.is_empty() or _raid.elapsed < schedule[0]:
		return
	schedule.pop_front()
	var choice := pick()
	if not choice.is_empty():
		start(choice.kind, choice.poi, choice.at)


## Every place an event can happen: [{"poi", "kind" ("" for airdrop or truck), "at"}].
func spots() -> Array:
	var result := []
	for node in get_tree().get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		for child in poi.get_children():
			if child is Marker3D and child.name.begins_with("EventSpot"):
				var kind := str(child.name).trim_prefix("EventSpot").trim_prefix("_")
				result.append({"poi": poi, "kind": kind if kind in KINDS else "", "at": child.global_position})
	return result


## A place and kind for the next event: a random spot that hasn't had one, at a POI you can get into
## now (its requirement met), whose cache (for a cache spot) is still sealed. {} if there's none.
func pick() -> Dictionary:
	var used := events.map(func(event: Dictionary) -> Vector3: return event.at)
	var options := spots().filter(func(spot: Dictionary) -> bool:
		return not spot.at in used and spot.poi.requirement_met())
	if options.is_empty():
		return {}
	var choice: Dictionary = options[rng.randi_range(0, options.size() - 1)]
	var kind: String = choice.kind if choice.kind != "" else ["airdrop", "truck"][rng.randi_range(0, 1)]
	return {"poi": choice.poi, "kind": kind, "at": choice.at}


## Sets off a `kind` event at `poi`, at `at`. Returns the event.
func start(kind: String, poi: PointOfInterest, at: Vector3) -> Dictionary:
	var event := {"kind": kind, "poi": poi, "poi_name": poi.poi_name(), "at": at, "time": _raid.elapsed if _raid else 0.0,
		"box": null, "ready": false}
	events.append(event)
	poi.event_until = event.time + config.event_heat_seconds
	poi.event_name = TITLES.get(kind, kind)
	match kind:
		"airdrop":
			_airdrop(event)
		"truck":
			_truck(event)
		"cache":
			_cache(event)
	_announce(event)
	_call_ai(event)
	event_started.emit(event)
	return event


## The HUD line for `event`: "A plane is dropping supplies over the Main hall".
static func describe(event: Dictionary) -> String:
	match str(event.kind):
		"airdrop":
			return "A plane is dropping supplies over %s" % event.poi_name
		"truck":
			return "A supply truck is pulling in at %s" % event.poi_name
		"cache":
			return "A weapon cache just unlocked in %s" % event.poi_name
	return str(event.poi_name)


func _airdrop(event: Dictionary) -> void:
	_sound(PLANE, event.at)
	_flare(event.at, AIRDROP_FLARE)
	var crate := _make_box(AIRDROP, event.at + Vector3.UP * DROP_HEIGHT)
	crate.name = "AirdropCrate"
	event.box = crate
	var chute := MeshInstance3D.new()
	chute.name = "Parachute"
	var dome := SphereMesh.new()
	dome.radius = 1.8
	dome.height = 1.6
	dome.is_hemisphere = true
	chute.mesh = dome
	chute.position = Vector3(0, 3.2, 0)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.85, 0.85, 0.8)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	chute.material_override = cloth
	crate.add_child(chute)
	var tween := crate.create_tween()
	tween.tween_property(crate, "global_position", event.at, config.airdrop_fall_seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		chute.queue_free()
		crate.unseal()
		event.ready = true
		NoiseSystem.emit_noise(event.at, 30.0, null, &"airdrop"))


func _truck(event: Dictionary) -> void:
	var truck := TRUCK.instantiate() as Node3D
	truck.name = "SupplyTruck"
	_level().add_child(truck)
	truck.global_position = event.at + Vector3(-TRUCK_RUN, 0, 0)
	_set_solid(truck, false)  # Drives through nothing on the way in.
	var horn := AudioStreamPlayer3D.new()
	horn.stream = HORN
	horn.bus = &"Effects"
	horn.max_distance = config.event_noise_radius
	horn.unit_size = 20.0
	truck.add_child(horn)
	horn.play()
	var tween := truck.create_tween()
	tween.tween_property(truck, "global_position", event.at, config.truck_arrive_seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		_set_solid(truck, true)
		var cargo := _make_box(CARGO, event.at + Vector3(-3.0, 0, 0))
		cargo.name = "TruckCargo"
		cargo.unseal()
		event.box = cargo
		event.ready = true)


func _cache(event: Dictionary) -> void:
	var cache: LootBox = null
	for each in caches:
		if is_instance_valid(each) and each.sealed and each.global_position.distance_to(event.at) < 0.5:
			cache = each
	if cache == null:
		cache = _make_box(CACHE, event.at)
		caches.append(cache)
	_sound(KLAXON, event.at, cache)
	_flare(event.at, CACHE_FLARE)
	cache.unseal()
	event.box = cache
	event.ready = true


## Announces it on the HUD and makes it heard: a sound marker for the player, AI within earshot.
func _announce(event: Dictionary) -> void:
	var hud := _level().get_node_or_null("HUD")
	if hud and hud.has_method("announce"):
		hud.announce(TITLES.get(event.kind, "EVENT"), describe(event), ANNOUNCE_COLOR)
	NoiseSystem.emit_noise(event.at, config.event_noise_radius, null, &"event")


## AI within earshot that isn't fighting may head for it (Scavs less keen than PMCs). A boss and its
## guards stay on their haunt.
func _call_ai(event: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group("bots"):
		var bot := node as Bot
		if bot == null or bot.is_dead or not bot.ai_enabled or bot.state == Bot.State.COMBAT or not bot.squad.is_empty():
			continue
		if bot.global_position.distance_to(event.at) > config.event_noise_radius:
			continue
		var chance := config.rush_chance_scav if bot.side == Actor.Side.SCAV else config.rush_chance_pmc
		if rng.randf() < chance:
			bot.rush_to(event.at)


## A sealed event crate of `container` at `at` (rolled when unsealed).
func _make_box(container: LootContainer, at: Vector3) -> LootBox:
	var box := LootBox.new()
	box.container = container
	box.sealed = true
	box.ignore_poi = true
	_level().add_child(box)
	box.global_position = at
	return box


func _flare(at: Vector3, color: Color) -> void:
	var flare: Node3D = FLARE.new()
	flare.color = color
	_level().add_child(flare)
	flare.global_position = at + Vector3.UP * 0.5


func _sound(stream: AudioStream, at: Vector3, parent: Node = null) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = stream
	sound.bus = &"Effects"
	sound.max_distance = config.event_noise_radius * 1.5
	sound.unit_size = 25.0
	(parent if parent else _level()).add_child(sound)
	sound.global_position = at + Vector3.UP * (12.0 if parent == null else 0.5)
	sound.play()
	if parent == null:
		sound.finished.connect(sound.queue_free)


## Turns the collision of a prop's bodies on or off.
static func _set_solid(prop: Node, solid: bool) -> void:
	for node in prop.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if solid:
			body.collision_layer = body.get_meta("events_layer", body.collision_layer)
		else:
			body.set_meta("events_layer", body.collision_layer)
			body.collision_layer = 0


func _level() -> Node:
	return get_parent() if get_parent() else get_tree().current_scene
