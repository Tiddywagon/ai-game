class_name FoundInRaid
extends RefCounted
## Found-in-Raid rules (DESIGN.md §2, §7). An item is found in raid (FIR) when you pick it up, loot it
## from a container or body, or take it off an enemy during a raid, and then survive and extract with
## it. Dying, going missing or a Run Through gives nothing FIR. Items you bring into a raid keep the
## status they had. Bought, flea market, quick-buy, insurance, barter and quest reward items are never
## FIR; hideout crafts are.
##
## In a raid: claim() marks loot the moment it reaches your inventory (`fir_pending`, drawn as a faded
## checkmark); resolve() settles it when the raid ends.

## Where an item came from, outside a raid's loot.
enum Source { TRADER, FLEA_MARKET, QUICK_BUY, INSURANCE, BARTER, QUEST_REWARD, CRAFT, STARTER }

const SOURCE_NAMES := ["Trader", "Flea market", "Quick-buy loadout", "Insurance return", "Barter",
	"Quest reward", "Hideout craft", "Starter kit"]


## True if items from `source` arrive found in raid (only hideout crafts do).
static func gives_fir(source: Source) -> bool:
	return source == Source.CRAFT


## A new item `id` × `amount` from `source`, found in raid or not by the rules above (with whatever is
## inside it). Null if there's no such item.
static func make(id: String, amount: int, source: Source) -> ItemInstance:
	var item := ItemInstance.create(id, amount)
	if item:
		set_found(item, gives_fir(source))
	return item


## Sets the status of `item` and everything in it.
static func set_found(item: ItemInstance, found: bool) -> void:
	for each in item.all_items():
		each.fir = found
		each.fir_pending = false


## At the start of a raid: everything in the loadout is yours, so taking it back from a container or
## the ground keeps its status.
static func mark_brought_in(inventory: Inventory) -> void:
	for item in inventory.all_items():
		item.brought_in = true
		item.fir_pending = false


## In a raid, after the inventory changes: anything in it that wasn't brought in and isn't FIR yet is
## loot, so it becomes pending (found in raid if you extract). Anything you carry is also known, even
## if it came in an unsearched bag. Returns the newly claimed items.
static func claim(inventory: Inventory) -> Array[ItemInstance]:
	var claimed: Array[ItemInstance] = []
	for item in inventory.all_items():
		item.hidden = false
		if not item.brought_in and not item.fir and not item.fir_pending:
			item.fir_pending = true
			claimed.append(item)
	return claimed


## When the raid ends: pending loot becomes found in raid if you `survived` (extracted without a Run
## Through), and simply stops being pending otherwise. The brought-in marks are cleared too. Returns
## the items that became FIR.
static func resolve(items: Array[ItemInstance], survived: bool) -> Array[ItemInstance]:
	var found: Array[ItemInstance] = []
	for item in items:
		if item.fir_pending and survived:
			item.fir = true
			found.append(item)
		item.fir_pending = false
		item.brought_in = false
	return found


## The one-line status for the examine panel and tooltips.
static func status_text(item: ItemInstance) -> String:
	if item.fir:
		return "Found in raid"
	if item.fir_pending:
		return "Found in raid once you extract with it"
	return "Not found in raid"
