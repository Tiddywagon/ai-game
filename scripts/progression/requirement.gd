class_name Requirement
extends RefCounted
## An item that a quest hand-in, hideout upgrade, craft or barter asks for (DESIGN.md §9–11): `count`
## of item `item_id`; with `fir`, only found-in-raid items count. JSON: {"item", "count", "fir"}.
##
## A generic figure requirement asks for any `count` figures passing `figures` instead of one item
## (DESIGN.md §6.6): JSON {"figures": {"rarity", "set"} (either, both or neither: any figure), "count",
## "fir"}, item_id "".
## It counts and takes spare figures only (Figures.spares(): never the one you keep, never the shelf's).

var item_id := ""
var count := 1
var fir := false
## A generic figure requirement's filter ({} with `generic`: any figure).
var figures := {}
var generic := false


static func from_dict(entry: Dictionary) -> Requirement:
	var requirement := Requirement.new()
	requirement.item_id = str(entry.get("item", ""))
	requirement.count = maxi(int(entry.get("count", 1)), 1)
	requirement.fir = bool(entry.get("fir", false))
	if entry.get("figures") is Dictionary:
		requirement.figures = (entry.figures as Dictionary).duplicate()
		requirement.generic = true
	return requirement


static func list(entries: Array) -> Array[Requirement]:
	var result: Array[Requirement] = []
	for entry in entries:
		result.append(from_dict(entry))
	return result


## True for a generic figure requirement ("any 2 Rare figures").
func is_generic() -> bool:
	return generic


## The item asked for (a generic requirement: the cheapest figure that passes, its sample).
func item_data() -> ItemData:
	if is_generic():
		return Figures.cheapest(figures)
	return ItemDB.get_item(item_id)


## What it asks for, as words: the item's name, or "Any Rare figure" (Figures.filter_text()).
func title() -> String:
	if is_generic():
		return Figures.filter_text(figures)
	var data := item_data() if ItemDB.has_item(item_id) else null
	return data.display_name if data else item_id


## An instance to draw in requirement lists: found in raid when that's required, so it carries the
## same checkmark as the items that count.
func sample() -> ItemInstance:
	var data := item_data() if is_generic() else null
	var item := ItemInstance.create(data.id if data else item_id, 1)
	if item:
		item.fir = fir
	return item


## How many you have that count for it (stash and character).
func have() -> int:
	if is_generic():
		return Figures.spare_count(figures, fir)
	return ItemSearch.count(item_id, fir)


## How many the stash holds that count for it in a barter (barters take only from the stash, and only
## whole food, drink and meds: ItemSearch).
func have_in_stash() -> int:
	if is_generic():
		return Figures.spare_count(figures, fir)
	return ItemSearch.count(item_id, fir, true)


func is_met() -> bool:
	return have() >= count
