class_name SkinsScreen
extends MenuScreen
## The skins collection (DESIGN.md §6.7, §16.6): every skin, collection by collection (the core one,
## then the seasons in rotation order) and kind by kind. A skin you own is drawn in its colours at its
## wear, with the wear named and where it is (in the collection, on which item, or worn as an outfit);
## one you don't is a dark silhouette marked Missing. Every card names the skin and its rarity (in the
## rarity's colour) and says BOUND for bound ones. Each collection's heading has its progress (owned /
## all) and when it's in the machine (always, now with the time left, or the date it comes back). A
## dropdown shows one kind only. Opened from the hideout's Slot Machine (SKINS) and the COSMETICS tab.

const OWNED := Color(0.55, 0.9, 0.55)
const OFF := Color(0.6, 0.6, 0.58)
const CARD := Vector2(164, 0)

## The kind shown ("" for all).
var kind := ""
var _list: VBoxContainer
var _kinds: OptionButton
var _total: Label


static func create() -> SkinsScreen:
	return SkinsScreen.new()


func _ready() -> void:
	name = "SkinsScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.025, 0.03, 0.95)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	InputHub.pad_to_safe_area(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	layout.add_child(header)
	var title := Label.new()
	title.text = "SKINS"
	title.theme_type_variation = &"HeadingLabel"
	header.add_child(title)
	_total = Label.new()
	_total.name = "Total"
	header.add_child(_total)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_kinds = OptionButton.new()
	_kinds.name = "KindFilter"
	_kinds.custom_minimum_size = Vector2(200, 46)
	_kinds.add_item("All kinds")
	for id in SkinTable.KINDS:
		_kinds.add_item(SkinTable.KIND_TITLES[id])
	_kinds.item_selected.connect(func(index: int) -> void: show_kind(SkinTable.KINDS[index - 1] if index > 0 else ""))
	header.add_child(_kinds)
	var drip := Label.new()
	drip.name = "Drip"
	drip.text = UiFormat.drip(GameState.drip)
	drip.add_theme_color_override("font_color", Player.TRICK_COLOR)
	header.add_child(drip)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(150, 46)
	back.pressed.connect(close)
	header.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "Collections"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	refresh()
	back.grab_focus.call_deferred()


## Shows only skins of `which` kind ("" for all).
func show_kind(which: String) -> void:
	kind = which
	_kinds.select(SkinTable.KINDS.find(which) + 1)
	refresh()


## Draws every collection again from the profile.
func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var owned := 0
	for skin in SkinTable.skins():
		if Cosmetics.owns(str(skin.id)):
			owned += 1
	_total.text = "%d / %d owned" % [owned, SkinTable.skins().size()]
	var items := {}
	for item in Cosmetics.your_items():
		for slot: String in item.cosmetics:
			items[str(item.cosmetics[slot].get("id", ""))] = item
	for collection in SkinTable.collections():
		var box := VBoxContainer.new()
		box.name = "Collection_" + str(collection.id)
		_list.add_child(box)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 16)
		box.add_child(head)
		var title := Label.new()
		title.name = "Progress"
		title.text = progress_text(str(collection.id))
		title.theme_type_variation = &"HeadingLabel"
		head.add_child(title)
		var when := Label.new()
		when.name = "Availability"
		when.text = availability_text(str(collection.id))
		when.add_theme_color_override("font_color", OWNED if collection.season and SkinTable.season_at(HideoutWork.now()) == collection.id else OFF)
		head.add_child(when)
		for each_kind in SkinTable.KINDS:
			if kind != "" and each_kind != kind:
				continue
			var skins: Array = collection.skins.filter(func(skin: Dictionary) -> bool: return skin.kind == each_kind)
			if skins.is_empty():
				continue
			var label := Label.new()
			label.text = SkinTable.KIND_TITLES[each_kind]
			label.add_theme_color_override("font_color", OFF)
			box.add_child(label)
			var cards := HFlowContainer.new()
			cards.add_theme_constant_override("h_separation", 10)
			cards.add_theme_constant_override("v_separation", 10)
			box.add_child(cards)
			for skin: Dictionary in skins:
				cards.add_child(_card(skin, items.get(str(skin.id))))
		_list.add_child(HSeparator.new())


## "Core  12 / 91".
static func progress_text(id: String) -> String:
	var count := Cosmetics.owned_in(id)
	return "%s  %d / %d" % [SkinTable.collection(id).get("name", id), count.x, count.y]


## "Always in the machine", "In the machine now · 12 d left", "In the machine from 2026-12-07".
static func availability_text(id: String) -> String:
	var collection := SkinTable.collection(id)
	if not collection.get("season", false):
		return "Always in the machine"
	var now := HideoutWork.now()
	if SkinTable.season_at(now) == id:
		return "In the machine now  ·  %s left" % UiFormat.duration(SkinTable.season_ends(now) - now)
	var next := SkinTable.season_next(id, now)
	return "In the machine from %s" % Time.get_date_string_from_unix_time(int(next)) if next >= 0.0 else "Not in the machine"


## A skin's card: its swatch (a silhouette if you don't own it), name, rarity, BOUND, and its wear and
## where it is, or Missing. `on`: the item of yours carrying it (null: none).
func _card(skin: Dictionary, on: ItemInstance) -> PanelContainer:
	var id := str(skin.id)
	var owns := Cosmetics.owns(id)
	var card := PanelContainer.new()
	card.name = "Card_" + id
	card.custom_minimum_size = CARD
	var rows := VBoxContainer.new()
	card.add_child(rows)
	var swatch := SkinSwatch.create(id, Cosmetics.wear_of(id) if owns else 0.0, not owns, Vector2(156, 96))
	swatch.name = "Swatch" if owns else "Silhouette"
	rows.add_child(swatch)
	var color := Palette.rarity_color(SkinTable.rarity(skin))
	for entry: Array in [["Name", str(skin.name), color if owns else color.darkened(0.35)],
			["Rarity", "%s%s" % [SkinTable.rarity_name(skin), "  ·  BOUND" if SkinTable.is_bound(skin) else ""], color.darkened(0.1)],
			["Fits", SkinTable.fits_text(skin), OFF],
			["State", _state_text(skin, on) if owns else "Missing", OWNED if owns else OFF]]:
		var label := Label.new()
		label.name = entry[0]
		label.text = entry[1]
		label.custom_minimum_size.x = CARD.x - 8
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14 if entry[0] != "Name" else 16)
		label.add_theme_color_override("font_color", entry[2])
		rows.add_child(label)
	return card


## "Field-Tested 0.214 · on AK-74N", "… · worn (BEAR)", "… · in the collection".
static func _state_text(skin: Dictionary, on: ItemInstance) -> String:
	var id := str(skin.id)
	var where := "in the collection"
	if on:
		where = "on " + on.data.display_name
	elif skin.get("kind") == "outfit" and Cosmetics.outfit(str(skin.get("faction", ""))) == id:
		where = "worn (%s)" % str(skin.faction).to_upper()
	elif Cosmetics.state().applied.has(id):
		where = "on an item on its way back"
	return "%s  ·  %s" % [SkinTable.wear_text(Cosmetics.wear_of(id)), where]
