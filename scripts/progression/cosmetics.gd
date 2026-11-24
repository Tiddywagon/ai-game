class_name Cosmetics
extends RefCounted
## What your profile does with Drip and cosmetic skins (DESIGN.md §6.7; the data is SkinTable). Skins
## change how things look and nothing else: no code that works out a number reads them.
##
## GameState.cosmetics: {"seed" (the profile's roll seed), "rolls" (spins rolled so far: the next roll's
## number), "pity" (spins in a row without an Epic or better), "spins" (spins made, free ones too),
## "owned": {skin id: wear} (the collection: skins you own that aren't on an item), "applied": {skin id:
## wear} (skins on one of your items: the item carries {"id", "wear"} in ItemInstance.cosmetics),
## "outfits": {"bear" / "usec": skin id} (the outfit worn as each faction; outfits never leave the
## collection), "last": [the last spin's results, for the machine to show]}. Saved (to_save()).
##
## A spin is paid (Drip, or one of the day's free spins from the Oddities figure set: Figures), rolled
## (roll(): seeded by the profile's seed and the roll's number, so reloading can't roll it again), put in
## the collection and saved before the reels move. A skin you already own (in the collection or on an
## item) pays its rarity's Drip back instead, and if the new wear is better, yours takes it.
##
## A skin goes from the collection onto one item it fits (apply()) and stays on it: in the stash, worn,
## in raids. remove() puts it back. Selling, bartering, handing in, crafting with or listing a skinned
## item puts its skins back first (strip(), from Selling, ItemSearch and FleaMarket). After a PMC raid,
## the skins on items you no longer have are lost, except bound ones (SkinTable.is_bound()), which go
## back to the collection (reconcile(true)); insured items on their way back keep theirs.

## Spins made by one press: one, or ten at the ten-spin price.
const COUNTS := [1, 10]


## A new profile's cosmetics: nothing owned, no spins, a random seed (`seed` when 0 or more).
static func blank(seed := -1) -> Dictionary:
	return {"seed": seed if seed >= 0 else randi(), "rolls": 0, "pity": 0, "spins": 0, "owned": {}, "applied": {}, "outfits": {}, "last": []}


static func state() -> Dictionary:
	return GameState.cosmetics


## The cosmetics as plain data for the save.
static func to_save() -> Dictionary:
	return state().duplicate(true)


## The cosmetics from a save (none before version 22: blank, seeded by `fallback_seed`, so reloading the
## same old save rolls the same). Skins that no longer exist are dropped.
static func from_save(saved: Variant, fallback_seed: int) -> Dictionary:
	if not saved is Dictionary:
		return blank(absi(fallback_seed))
	var result := blank(absi(int(saved.get("seed", fallback_seed))))
	for key in ["rolls", "pity", "spins"]:
		result[key] = maxi(int(saved.get(key, 0)), 0)
	for key in ["owned", "applied"]:
		var table: Variant = saved.get(key, {})
		if table is Dictionary:
			for id: Variant in table:
				if SkinTable.has(str(id)):
					result[key][str(id)] = clampf(float(table[id]), 0.0, 1.0)
	var outfits: Variant = saved.get("outfits", {})
	if outfits is Dictionary:
		for faction: Variant in outfits:
			if str(faction) in SkinTable.FACTIONS and result.owned.has(str(outfits[faction])):
				result.outfits[str(faction)] = str(outfits[faction])
	if saved.get("last") is Array:
		result.last = (saved.last as Array).filter(func(entry: Variant) -> bool: return entry is Dictionary and SkinTable.has(str(entry.get("skin", "")))).duplicate(true)
	return result


# --- Owning -------------------------------------------------------------------------------------

## True when skin `id` is yours: in the collection or on one of your items.
static func owns(id: String) -> bool:
	return state().owned.has(id) or state().applied.has(id)


## True when skin `id` is in the collection (yours and not on an item).
static func in_collection(id: String) -> bool:
	return state().owned.has(id)


## The wear of your skin `id` (-1 if you don't own it).
static func wear_of(id: String) -> float:
	if state().owned.has(id):
		return float(state().owned[id])
	return float(state().applied.get(id, -1.0))


## How many skins of collection `id` you own, of how many.
static func owned_in(id: String) -> Vector2i:
	var skins: Array = SkinTable.collection(id).get("skins", [])
	return Vector2i(skins.filter(func(skin: Dictionary) -> bool: return owns(str(skin.id))).size(), skins.size())


## The skin on `item`'s `slot` ({"id", "wear"}; {} for none).
static func on_item(item: ItemInstance, slot := "skin") -> Dictionary:
	return item.cosmetics.get(slot, {}) if item else {}


## Every item of yours, worn, carried and in the stash (containers too).
static func your_items() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	if GameState.inventory:
		result.append_array(GameState.inventory.all_items())
	if GameState.stash:
		result.append_array(GameState.stash.all_items())
	return result


## The item of yours skin `id` is on (null: none).
static func item_with(id: String) -> ItemInstance:
	for item in your_items():
		for slot: String in item.cosmetics:
			if str(item.cosmetics[slot].get("id", "")) == id:
				return item
	return null


## {skin id: wear} for every skin on your items, worn, in the stash and on insured items on their way back.
static func _on_items() -> Dictionary:
	var found := {}
	for item in your_items():
		for slot: String in item.cosmetics:
			found[str(item.cosmetics[slot].get("id", ""))] = float(item.cosmetics[slot].get("wear", 0.0))
	for entry: Variant in GameState.insurance_pending:
		if entry is Dictionary:
			_scan(entry.get("item") if entry.has("item") else entry, found)
	return found


## Skins in item dictionary `entry` (ItemInstance.to_dict()) and everything inside it, into `found`.
static func _scan(entry: Variant, found: Dictionary) -> void:
	if not entry is Dictionary:
		return
	var saved: Variant = entry.get("cosmetics")
	if saved is Dictionary:
		for slot: Variant in saved:
			if saved[slot] is Dictionary:
				found[str(saved[slot].get("id", ""))] = float(saved[slot].get("wear", 0.0))
	for key in ["contents"]:
		if entry.get(key) is Array:
			for inside: Variant in entry[key]:
				_scan(inside, found)


## Brings the record of skins on items in line with your items: a skin on an item is "applied" (taken out
## of the collection if it was there too). A skin recorded as applied that no item of yours carries is
## lost if `raid_loss` (after a PMC raid) and it isn't bound; otherwise (bound, or outside a raid: never
## lose a skin outside one) it goes back to the collection. Returns {"lost": [ids], "returned": [ids]}.
static func reconcile(raid_loss := false) -> Dictionary:
	var result := {"lost": [], "returned": []}
	var on := _on_items()
	var owned: Dictionary = state().owned
	var applied: Dictionary = state().applied
	for id: String in applied.keys():
		if on.has(id):
			applied[id] = on[id]
		elif raid_loss and not SkinTable.is_bound(SkinTable.find(id)):
			applied.erase(id)
			result.lost.append(id)
		else:
			owned[id] = applied[id]
			applied.erase(id)
			result.returned.append(id)
	for id: String in on:
		if SkinTable.has(id) and not applied.has(id):
			applied[id] = on[id]
			owned.erase(id)
	return result


# --- Spinning -----------------------------------------------------------------------------------

## Why `count` spins (1 or 10; `free`: one of today's free spins) can't be made now ("" if they can).
static func spin_block_reason(count: int, free := false) -> String:
	if not count in COUNTS:
		return "Spin once or ten times"
	if free:
		return "" if count == 1 and Figures.free_spins_left() > 0 else "No free spin left today"
	if GameState.drip < SkinTable.price(count):
		return "Not enough Drip (%s needed)" % UiFormat.thousands(SkinTable.price(count))
	return ""


## Spins `count` times: pays, rolls every result, puts them in the collection (duplicates pay Drip back)
## and saves, all before anything is shown. Returns the results (roll() with "duplicate", "drip" (paid
## back), "better" (a duplicate whose wear was better and replaced yours), "free"); [] if blocked.
static func spin(count: int, free := false) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if spin_block_reason(count, free) != "":
		return results
	if free:
		Figures.use_free_spin()
	else:
		GameState.drip -= SkinTable.price(count)
	for i in count:
		var result := roll(int(state().rolls), int(state().pity), HideoutWork.now())
		state().rolls = int(state().rolls) + 1
		state().spins = int(state().spins) + 1
		state().pity = 0 if int(result.rarity) >= SkinTable.pity_rarity() else int(state().pity) + 1
		result.free = free
		_take(result)
		results.append(result)
	state().last = results.duplicate(true)
	SaveManager.save_game()
	return results


## Roll number `number` with `pity` spins in a row without an Epic or better before it, at `time` (the
## season in the machine): {"skin" (id), "rarity" (index), "wear", "pity" (the pity counter made it at least
## Epic), "near_miss" (the reels tease a higher result: looks only)}. The same number always rolls the same.
static func roll(number: int, pity: int, time: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("skin:%d:%d" % [int(state().get("seed", 0)), number]).hash()
	var forced := pity + 1 >= SkinTable.pity_spins()
	var rarity := _roll_rarity(rng, SkinTable.pity_rarity() if forced else 0)
	var skin := _pick(rng, rarity, SkinTable.season_at(time))
	var wear := _roll_wear(rng)
	var tease := SkinTable.near_miss()
	var near := SkinTable.rarity(skin) < int(tease.below) and rng.randf() < float(tease.chance)
	return {"skin": str(skin.get("id", "")), "rarity": SkinTable.rarity(skin), "wear": wear, "pity": forced, "near_miss": near}


## A rarity index by the odds, `at_least` or better (the pity counter: by the odds of those rarities).
static func _roll_rarity(rng: RandomNumberGenerator, at_least: int) -> int:
	var odds := SkinTable.odds()
	var total := 0.0
	for index in range(at_least, odds.size()):
		total += odds[index]
	var pick := rng.randf() * total
	for index in range(at_least, odds.size()):
		pick -= odds[index]
		if pick < 0.0:
			return index
	return odds.size() - 1


## The skins a spin of `rarity` picks from: the core collections' and season `season`'s, each with its
## weight (a seasonal skin counts SkinTable.season_weight() times). [[skin, weight]].
static func pool(rarity: int, season: String) -> Array:
	var result := []
	for collection in SkinTable.collections():
		if collection.season and collection.id != season:
			continue
		for skin: Dictionary in collection.skins:
			if SkinTable.rarity(skin) == rarity:
				result.append([skin, SkinTable.season_weight() if collection.season else 1.0])
	return result


## A skin of `rarity` (the next rarity down that has any, if none does) from pool(), by weight.
static func _pick(rng: RandomNumberGenerator, rarity: int, season: String) -> Dictionary:
	var entries := []
	var at := rarity
	while entries.is_empty() and at >= 0:
		entries = pool(at, season)
		at -= 1
	var total := 0.0
	for entry: Array in entries:
		total += float(entry[1])
	var pick := rng.randf() * total
	for entry: Array in entries:
		pick -= float(entry[1])
		if pick < 0.0:
			return entry[0]
	return entries[-1][0] if not entries.is_empty() else {}


## A wear value: a band by its chance, then evenly inside it.
static func _roll_wear(rng: RandomNumberGenerator) -> float:
	var bands := SkinTable.wear_bands()
	var pick := rng.randf()
	for band in bands:
		pick -= float(band.chance)
		if pick < 0.0:
			return snappedf(rng.randf_range(float(band.min), float(band.max) - 0.0001), 0.0001)
	return snappedf(rng.randf_range(float(bands[-1].min), float(bands[-1].max)), 0.0001) if not bands.is_empty() else 0.0


## Puts `result` in the collection: new, or a duplicate paying Drip back (and lending its better wear).
static func _take(result: Dictionary) -> void:
	var id := str(result.skin)
	result.duplicate = owns(id)
	result.drip = 0
	result.better = false
	if not result.duplicate:
		state().owned[id] = float(result.wear)
		return
	result.drip = SkinTable.duplicate_drip(int(result.rarity))
	GameState.drip += int(result.drip)
	if float(result.wear) < wear_of(id):
		result.better = true
		set_wear(id, float(result.wear))


## Sets your skin `id`'s wear (in the collection, or on the item that carries it).
static func set_wear(id: String, wear: float) -> void:
	if state().owned.has(id):
		state().owned[id] = wear
		return
	state().applied[id] = wear
	var item := item_with(id)
	if item:
		for slot: String in item.cosmetics:
			if str(item.cosmetics[slot].get("id", "")) == id:
				item.cosmetics[slot].wear = wear


## "Epic or better within 23 spins": the spins left until the pity counter's guarantee.
static func pity_left() -> int:
	return maxi(SkinTable.pity_spins() - int(state().pity), 1)


# --- Applying -----------------------------------------------------------------------------------

## Why skin `id` can't go on `item` now ("" if it can): it isn't in the collection (or is on another
## item), it doesn't fit, or the item isn't yours.
static func apply_block_reason(id: String, item: ItemInstance) -> String:
	var skin := SkinTable.find(id)
	if skin.is_empty():
		return "No such skin"
	if item == null:
		return "Pick an item"
	if state().applied.has(id):
		return "It's on another item: take it off there first"
	if not state().owned.has(id):
		return "Not in your collection"
	if skin.kind == "outfit":
		return "Outfits go on your character"
	if not SkinTable.fits(skin, item.data):
		return "It doesn't fit %s" % item.data.display_name
	if not item in your_items():
		return "Only on your own items"
	return ""


## Puts skin `id` on `item` (on its slot: whatever was there goes back to the collection). "" on success.
static func apply(id: String, item: ItemInstance) -> String:
	var reason := apply_block_reason(id, item)
	if reason != "":
		return reason
	var slot := SkinTable.slot_of(SkinTable.find(id))
	if item.cosmetics.has(slot):
		remove(item, slot)
	var wear := float(state().owned[id])
	item.cosmetics[slot] = {"id": id, "wear": wear}
	state().owned.erase(id)
	state().applied[id] = wear
	return ""


## Takes the skin off `item`'s `slot` back into the collection. "" on success.
static func remove(item: ItemInstance, slot := "skin") -> String:
	if item == null or not item.cosmetics.has(slot):
		return "Nothing on it"
	var entry: Dictionary = item.cosmetics[slot]
	item.cosmetics.erase(slot)
	var id := str(entry.get("id", ""))
	state().applied.erase(id)
	if SkinTable.has(id):
		state().owned[id] = float(entry.get("wear", 0.0))
	return ""


## Every skin on `item` and on everything inside it back to the collection (before it's sold, bartered,
## handed in, used up or listed). Returns how many.
static func strip(item: ItemInstance) -> int:
	var count := 0
	if item == null:
		return 0
	for part in item.all_items():
		for slot: String in part.cosmetics.keys():
			remove(part, slot)
			count += 1
	return count


## The outfit worn as `faction` ("bear" / "usec"; your own when ""), "" for the plain uniform.
static func outfit(faction := "") -> String:
	var side := faction if faction != "" else _faction()
	return str(state().outfits.get(side, ""))


## Why outfit `id` can't be worn now ("" if it can).
static func outfit_block_reason(id: String) -> String:
	var skin := SkinTable.find(id)
	if skin.get("kind") != "outfit":
		return "Not an outfit"
	if not state().owned.has(id):
		return "Not in your collection"
	if str(skin.get("faction", "")) != _faction():
		return "A %s outfit" % str(skin.faction).to_upper()
	return ""


## Wears outfit `id` as your faction ("" for the plain uniform). "" on success.
static func wear_outfit(id: String) -> String:
	if id == "":
		state().outfits.erase(_faction())
		return ""
	var reason := outfit_block_reason(id)
	if reason == "":
		state().outfits[_faction()] = id
	return reason


static func _faction() -> String:
	return "usec" if GameState.faction == GameState.Faction.USEC else "bear"


# --- Drip earned --------------------------------------------------------------------------------

## A raid's Drip: {"extract" (the base, if you got out), "loot" (its bracket), "kills"} from `outcome`
## (a RaidOutcome), not yet paid. Levels are paid as they're gained (GameState.add_xp()).
static func raid_drip(survived: bool, loot_value: int, kill_list: Array) -> Dictionary:
	var parts := {"extract": 0, "loot": 0, "kills": 0}
	if survived:
		var extract := SkinTable.extract_drip(loot_value)
		parts.extract = extract.x
		parts.loot = extract.y
	for kill: Variant in kill_list:
		if kill is Dictionary:
			var role := str(kill.get("role", ""))
			parts.kills += SkinTable.kill_drip(role if role in ["boss", "guard"] else ("pmc" if kill.get("side", "") == "pmc" else "scav"))
	return parts
