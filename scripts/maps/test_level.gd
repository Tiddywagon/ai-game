extends RaidLevel
## Test level for movement, cover and combat (DESIGN.md §13): the raid map script (RaidLevel) plus
## debug keys. Search the containers and bodies (F), pick up loose loot, and extract (the Test Yard row
## of data/config/extracts.json): the north-east gate is always open; the smuggler's car takes roubles
## and no backpack; the signal point, once Bulat's Flare Path quest is done, needs a signal flare fired
## in it (RaidController, ExtractZone). F12 shows the debug overlay.
## Debug keys: F1 left leg fracture, F2 overweight, F3 next round type for the gun's caliber (adds a stack if you have none), F4 AI on/off, F5 heal (and fill energy and hydration),
## F6 cycle the gun's sight, F7 time of day, F8 weather, F9 flashbang at the reticle, F10 fog of war off.


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			var leg := BodyHealth.Part.LEFT_LEG
			_player.health.set_fracture(leg, not _player.health.fractures[leg])
			_hud.show_message("Left leg fracture: %s" % ("on" if _player.health.fractures[leg] else "off"))
		KEY_F2:
			_player.debug_extra_weight = 0.0 if _player.is_overweight() else _player.inventory_config.overweight_kg + 10.0
			_hud.show_message("Carrying %s%s" % [Settings.format_weight(_player.carried_weight_kg), " (overweight)" if _player.is_overweight() else ""])
		KEY_F3:
			if not _player.weapon.has_gun():
				return
			var types: Array = ItemDB.ammo_of(_player.weapon.data.caliber).map(func(round_type: ItemData) -> String: return round_type.id)
			var ammo: String = types[(types.find(_player.ammo_id) + 1) % types.size()]
			if _player.inventory.count_of(ammo) == 0:
				var spare := ItemInstance.create(ammo, ItemDB.get_item(ammo).max_stack)  # Something to reload with.
				spare.brought_in = true  # A debug gift, not loot.
				_player.inventory.add(spare)
			_player.set_ammo(ammo)
			_player.weapon.spare_rounds = _player.inventory.count_of(ammo)
			_hud.show_message("Ammo: " + _player.ammo_label())
		KEY_F4:
			var bots := get_tree().get_nodes_in_group("bots")
			var enable: bool = bots.size() > 0 and not bots[0].ai_enabled
			for bot: Bot in bots:
				bot.ai_enabled = enable
			_hud.show_message("AI " + ("on" if enable else "off"))
		KEY_F5:
			if not _player.is_dead:
				_player.health.heal_all()
				_player.health.feed(INF, INF)
				_hud.show_message("Healed, fed and watered")
		KEY_F6:
			var sights := VisionConfig.Optic.BINOCULARS  # Every optic before the binoculars fits a gun.
			_player.weapon.optic = (_player.weapon.optic + 1) % sights
			_hud.show_message("Sight: " + VisionSystem.config.optic(_player.weapon.optic).display_name)
		KEY_F7:
			_environment.apply((_environment.time_of_day + 1) % VisionConfig.TimeOfDay.size(), _environment.weather)
			_hud.show_message("Time: " + VisionSystem.time_name(_environment.time_of_day))
		KEY_F8:
			_environment.apply(_environment.time_of_day, (_environment.weather + 1) % VisionConfig.Weather.size())
			_hud.show_message("Weather: " + VisionSystem.weather_name(_environment.weather))
		KEY_F9:
			if _player.has_aim:
				Flashbang.detonate(get_tree(), Vector3(_player.aim_point.x, 0.2, _player.aim_point.z))
		KEY_F10:
			_vision.enabled = not _vision.enabled
			_hud.show_message("Fog of war " + ("on" if _vision.enabled else "off"))
