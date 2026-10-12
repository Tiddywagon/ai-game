class_name Requirement
extends RefCounted
## An item that a quest hand-in, hideout upgrade, craft or barter asks for (DESIGN.md §9–11): `count`
## of item `item_id`; with `fir`, only found-in-raid items count. JSON: {"item", "count", "fir"}.

var item_id := ""
var count := 1
var fir := false


static func from_dict(entry: Dictionary) -> Requirement:
	var requirement := Requirement.new()
	requirement.item_id = str(entry.get("item", ""))
	requirement.count = maxi(int(entry.get("count", 1)), 1)
	requirement.fir = bool(entry.get("fir", false))
	return requirement


static func list(entries: Array) -> Array[Requirement]:
	var result: Array[Requirement] = []
	for entry in entries:
		result.append(from_dict(entry))
	return result


func item_data() -> ItemData:
	return ItemDB.get_item(item_id)


## An instance to draw in requirement lists: found in raid when that's required, so it carries the
## same checkmark as the items that count.
func sample() -> ItemInstance:
	var item := ItemInstance.create(item_id, 1)
	if item:
		item.fir = fir
	return item


## How many you have that count for it (stash and character).
func have() -> int:
	return ItemSearch.count(item_id, fir)


func is_met() -> bool:
	return have() >= count
