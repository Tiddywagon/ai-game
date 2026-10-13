class_name Keys
extends RefCounted
## Keys (DESIGN.md §5, §6.1): each opens one locked door (or more) and has a number of uses (its
## "uses" stat), kept on the item as ItemInstance.charges. Unlocking a door uses one; at 0 the key is
## gone.


static func is_key(data: ItemData) -> bool:
	return data != null and data.category == ItemData.Category.KEY


static func max_uses(data: ItemData) -> int:
	return int(data.stats.get("uses", 1))


## Uses one of `key`'s uses; at 0 it's taken out of `inventory`. Returns the uses left.
static func use(key: ItemInstance, inventory: Inventory) -> int:
	key.charges = maxf(key.charges - 1.0, 0.0)
	if key.charges <= 0.0 and inventory:
		inventory.remove_item(key)
	return roundi(key.charges)
