class_name LootSearch
extends RefCounted
## Searching a container or a body (DESIGN.md §7): what's inside starts hidden and is revealed one
## item at a time, in reading order (top row first), while it's open beside your inventory. Each item
## takes RaidConfig.search_base_seconds plus search_seconds_per_cell per cell it covers, so small items
## turn up faster, times the container's search time. Closing pauses the search; what's revealed stays
## revealed. A body's equipment is in plain sight: only what's in its pockets, rig and backpack is
## searched.

## An item was revealed.
signal revealed(item: ItemInstance)

## The grids being searched, in order (a callable, since a body's rig or backpack can be taken).
var _grids: Callable
var _config: RaidConfig
var _time_multiplier := 1.0
## The item being searched now, and how long it's been searched.
var current: ItemInstance
var elapsed := 0.0


## Searches the grids `grids` returns (Array[InventoryGrid]), `time_multiplier` slower or faster.
func _init(grids: Callable, time_multiplier := 1.0, config: RaidConfig = null) -> void:
	_grids = grids
	_time_multiplier = time_multiplier
	_config = config if config else load("res://data/config/raid.tres")


## Hides everything in the grids (and inside containers in them), ready to be searched.
func hide_all() -> void:
	for grid: InventoryGrid in _grids.call():
		for item in grid.all_items():
			item.hidden = true


## Seconds it takes to reveal `item`.
func time_for(item: ItemInstance) -> float:
	var cells := item.data.size.x * item.data.size.y
	return (_config.search_base_seconds + _config.search_seconds_per_cell * cells) * _time_multiplier


## The next hidden item, in grid order and reading order, or null when everything is found.
func next_hidden() -> ItemInstance:
	for grid: InventoryGrid in _grids.call():
		var hidden := grid.items.filter(func(item: ItemInstance) -> bool: return item.hidden)
		if hidden.is_empty():
			continue
		hidden.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool:
			return a.cell.x < b.cell.x if a.cell.y == b.cell.y else a.cell.y < b.cell.y)
		return hidden[0]
	return null


func is_done() -> bool:
	return next_hidden() == null


## How far the current item is (0-1).
func progress() -> float:
	return clampf(elapsed / time_for(current), 0.0, 1.0) if current else 0.0


## How many items are found and how many there are: [found, total].
func counts() -> Array[int]:
	var found := 0
	var total := 0
	for grid: InventoryGrid in _grids.call():
		for item in grid.items:
			total += 1
			found += 0 if item.hidden else 1
	return [found, total]


## Searches for `delta` seconds (while it's open). Returns the items revealed.
func step(delta: float) -> Array[ItemInstance]:
	var found: Array[ItemInstance] = []
	var left := delta
	while left > 0.0:
		var target := next_hidden()
		if target != current:
			current = target
			elapsed = 0.0
		if current == null:
			break
		var needed := time_for(current) - elapsed
		if left < needed:
			elapsed += left
			break
		left -= needed
		_reveal(current)
		found.append(current)
		current = null
		elapsed = 0.0
	return found


func _reveal(item: ItemInstance) -> void:
	for each in item.all_items():
		each.hidden = false
	revealed.emit(item)
