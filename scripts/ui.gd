extends "res://scripts/company_ui.gd"
## HUD, menus, guide and modals. Part of the Main script chain (see scripts/README.md).

func _panel_style(alpha := 0.85) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.09, 0.08, alpha)
	s.set_content_margin_all(8)
	s.set_corner_radius_all(6)
	return s


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_layer = layer

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style())
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	layer.add_child(top)
	var top_row := HBoxContainer.new()
	top.add_child(top_row)
	company_button = Button.new()  # the company name; opens the Company page
	company_button.flat = true
	company_button.focus_mode = Control.FOCUS_NONE
	company_button.tooltip_text = "Open the Company page"
	company_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	company_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	company_button.pressed.connect(_toggle_company_page.bind(0))
	top_row.add_child(company_button)
	top_label = Label.new()
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_label)
	for s in [0, 1, 2, 4]:
		var b := Button.new()
		b.text = "||" if s == 0 else "%dx" % s
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_speed.bind(s))
		top_row.add_child(b)
		speed_buttons.append(b)
	_set_speed(1)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel_style())
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(bottom)
	bottom_bar = bottom
	var col := VBoxContainer.new()
	bottom.add_child(col)
	chet_label = Label.new()
	chet_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	chet_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(chet_label)
	var build_box := VBoxContainer.new()
	build_row = build_box
	build_box.visible = false
	col.add_child(build_box)
	var cat_row := HBoxContainer.new()
	build_box.add_child(cat_row)
	for c in BUILD_CATS:
		var cb := Button.new()
		cb.text = c.name
		cb.toggle_mode = true
		cb.focus_mode = Control.FOCUS_NONE
		cb.pressed.connect(_click_build_cat.bind(c.id))
		cat_row.add_child(cb)
		cat_buttons[c.id] = cb
	var gap := Control.new()
	gap.custom_minimum_size.x = 16
	cat_row.add_child(gap)
	level_button = Button.new()
	level_button.focus_mode = Control.FOCUS_NONE
	level_button.pressed.connect(_toggle_level)
	cat_row.add_child(level_button)
	roof_button = Button.new()
	roof_button.focus_mode = Control.FOCUS_NONE
	roof_button.text = "Shift+R  Roofs: Auto"
	roof_button.pressed.connect(_toggle_roofs)
	cat_row.add_child(roof_button)
	build_popup = PanelContainer.new()
	build_popup.add_theme_stylebox_override("panel", _panel_style())
	build_popup.visible = false
	layer.add_child(build_popup)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	build_popup.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in TOOLS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_select_tool.bind(i))
		if TOOLS[i].id == "demolish":
			cat_row.add_child(b)  # demolish works in every category, so it stays on the bar
		else:
			list.add_child(b)
		tool_buttons.append(b)
	var menu_row := HBoxContainer.new()
	col.add_child(menu_row)
	for m in MENUS:
		var b := Button.new()
		b.text = "%s (%s)" % [m.name, OS.get_keycode_string(m.key)]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.x = 110
		b.pressed.connect(_toggle_menu.bind(m.id))
		menu_row.add_child(b)
		menu_buttons[m.id] = b

	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", _panel_style())
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.offset_left = -330
	side.offset_right = -8
	side.offset_top = 56
	layer.add_child(side)
	side_panel = side
	side.visible = false
	tabs = TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.tabs_visible = false  # the bottom menu row picks the tab
	side.add_child(tabs)
	_build_models_tab()
	_build_staff_tab()
	_build_heat_tab()
	_build_power_tab()
	_build_deviation_tab()
	_build_guide_tab()

	_build_company_page(layer)

	hover_tip = Label.new()
	hover_tip.add_theme_font_size_override("font_size", 13)
	var tip_style := _panel_style(0.9)
	tip_style.set_content_margin_all(6)
	hover_tip.add_theme_stylebox_override("normal", tip_style)
	hover_tip.visible = false
	layer.add_child(hover_tip)

	cost_label = Label.new()
	cost_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cost_label.add_theme_constant_override("outline_size", 4)
	cost_label.visible = false
	layer.add_child(cost_label)
	_build_research_page()
	gov = preload("res://scripts/government.gd").new()
	gov.main = self
	add_child(gov)
	_chet(CHET_TIPS[0])


# How everything works, in one place, so the other panels can stick to numbers.
const GUIDE := [
	["Getting started", "You run an AI startup in Calizona. Train models to get users, users bring revenue, and keep the board happy until your AI is smart enough to replace you as CEO. You win? If the board loses all confidence you're fired. If Deviation hits 100% the AI takes over."],
	["Building (B)", "Open Build and pick a category tab (Tab cycles them). Left drag to build: floors fill a box, walls draw a box outline, furniture paints, doors place one at a time. Right click demolishes for a 50% refund. Furniture needs a floor. Staff walk only on floors and through doors. Desks, Server Racks and Workstations need a clear path, one tile wide, from a door to at least one side; anything blocked in shows a red ! and does nothing until you clear a way. Exterior walls come in three tiers: Cheap, Brick (30% insulation) and Insulated (60%); insulation keeps the desert heat out. Build a better wall over an old one to upgrade it. Carpet goes on concrete and gives staff standing on it +3% productivity. Interior Walls take a quarter tile and block walking. Add on to a building by building new walls against it: rooms that share a wall are one building and lift their roof together. Shift+R keeps every roof off. Press Q while placing a chair to turn it. Right click removes just the small item under the mouse. Generators need ground: the Portable one goes anywhere, the Diesel needs gravel or better, and the Large Diesel and Power Plant need asphalt or concrete."],
	["Roofs and views (R)", "Every enclosed building gets a roof that hides while your mouse is inside it. R switches between Ground and Roof view. Rooftop items like AC Units and Solar Panels switch to Roof view by themselves when you pick them."],
	["Models (M)", "Server Racks make compute. Pick a model size to train; bigger models take longer and raise capability more. Better models bring more users, and users bring revenue. Cutting corners trains faster but raises Deviation. Engineers at an Engineer's Workstation add compute for racks within its radius. Racks wear down without engineers: each engineer maintains up to 4 racks in range, and a worn rack makes less compute."],
	["Desks and break rooms", "Productivity runs 0-100%. Staff start at 80%. A Basic Desk adds 5%, an Advanced Desk (2x1) 10%, a Cubicle (2x2) 15%; place a better desk on an old one to upgrade it. Carpet adds 3%. Break room things (Coffee Maker, Microwave, Mini-Fridge, Counter with Sink, Table, Chair, Garbage Can) each add 1-3% for everyone in the same building, up to 12%. Coffee Makers and Microwaves can go on top of a counter. Heat takes it away."],
	["Amenities", "Every worker needs a kitchen and a bathroom. A kitchenette (Counter with Sink plus a Microwave or Mini-Fridge) covers 10 workers, a Toilet Stall 5, a Bathroom Sink 10. Fall short and everyone's productivity drops in proportion to how many go without: up to 15% for kitchens, 15% for stalls, 5% for sinks."],
	["Staff (T)", "Hire researchers, engineers, marketers and alignment researchers, then give each a job. You don't control people directly: they need a free desk, or a spot at an Engineer's Workstation, for their job, and heat makes them slower."],
	["Board (O)", "Click your company name in the top bar (or press O) for the Company page. Its Board tab: each quarter the board sets a target. Hit it for +15 confidence, miss it for -25. At 0% you're fired, and running out of money gets you fired faster. Safety theater fools them for a while."],
	["Heat (H)", "Racks heat their own tile and the heat radiates out across the room. Walls slow it and keep some desert heat out (better walls more). Hot racks throttle and hot staff slow down. An AC Unit on the roof cools a 7x7 area and cancels out about 4 racks; a Window AC on a wall cools the 3x3 next to it and handles about one. Put coolers near the racks. Tiles are tinted by temperature while the Heat panel is open."],
	["Power (P)", "Racks, ACs and red-team rigs use power. The cheapest power runs first: solar, then the grid, then batteries, then generators by fuel price. Batteries store spare solar for the night. The grid hookup is capped until you lobby for more. Generators go outside, and their smog drifts across the map."],
	["Deviation (V)", "Every rack adds Deviation, and training, cutting corners and smarter models raise the rate. Alignment researchers at desks and Red-Team Rigs bring it back down (rigs eat compute). At 25% the AI gets quirky, at 50% it sabotages rivals for you and scandals follow, at 75% it hides compute, lies on reports and staff quit. At 100% it takes over."],
	["Research (E)", "Researchers at desks make research points; the founders make a trickle on their own. Pick a project in each of four branches: Construction, Equipment, Computer Chips and Productivity. Each branch is researched in order. Projects unlock new things in Build or give a lasting bonus. Points keep banking while nothing is picked."],
	["Government (L)", "Lobby the state of Calizona. Three politicians each have a price, a pet issue and a scandal meter. The State Legislature takes general lobbying: no scandals, but each donation buys less Favor, and it passes AI-Friendly Regulation (Scrutiny rises half as fast) and a Tech Tax Break (10% of your daily burn back). Donations raise their Favor but also their Scandal; at 100 Scandal they resign and the replacement starts at 0 Favor. Favor drifts down over time, rises while their pet issue goes your way and falls faster while it doesn't. Influence is the average Favor of all four. Every lobbying price goes up 25% a year. Spend Favor on Grid Hookup Permits (Utilities Commissioner), a State AI Contract for extra revenue (Governor) and Water Rights (Water Board Chair). Scrutiny rises with Outrage, Deviation and scandals, and Influence brings it down. At 50 Scrutiny you're fined at the end of each quarter, and at 75 the state cancels your contract."],
	["Outrage", "Smog that drifts off your property onto the houses in town or the farmhouses raises Outrage, the more smog the faster. Building on farmland raises it for every tile you pave over, and so does pumping water: the more water you use, the faster it climbs. It slowly fades once things calm down. Hover a house to see its smog. Generators near your fence are the usual cause. Later, community projects on the empty town lots will lower it."],
	["Speed", "Space pauses. The buttons top right run time at 1x, 2x or 4x. A quarter lasts 15 minutes at 1x. N mutes the music."],
]


func _build_guide_tab() -> void:
	var box := _tab_box("Guide")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	for section in GUIDE:
		var h := Label.new()
		h.text = section[0]
		h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		col.add_child(h)
		var body := _wrap_label(col)
		body.text = section[1] + "\n"


func _locked(tool_id: String) -> bool:
	if UNLOCK_ALL:
		return false
	for r in RESEARCH:
		if not research_done.has(r.id) and tool_id in r.get("unlocks", []):
			return true
	return false


func _tool_cost(tool: Dictionary) -> int:
	var mult := 1.0
	if tool.get("cat", "") == "structure":
		mult -= _research_bonus("structure_discount")
	if RACKS.has(tool.id):
		mult -= _research_bonus("rack_discount")
	return roundi(tool.cost * mult)


func _tab_box(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = title
	box.custom_minimum_size.x = 300
	box.add_theme_constant_override("separation", 6)
	tabs.add_child(box)
	return box


func _wrap_label(parent: Control) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)
	return l


func _build_staff_tab() -> void:
	var box := _tab_box("Staff")
	staff_label = _wrap_label(box)
	for role in ROLES:
		var b := Button.new()
		b.text = "Hire %s   %s/day" % [ROLES[role].name, _money(ROLES[role].salary)]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_hire.bind(role))
		box.add_child(b)
	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 250
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	staff_list = VBoxContainer.new()
	staff_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(staff_list)
	_rebuild_staff_list()


func _update_staff_tab() -> void:
	var payroll := 0
	for s in staff:
		payroll += s.salary
		var status := "Slacking off"
		if s.working:
			status = "Working"
		elif s.seat != NO_SEAT:
			status = "Heading to work"
		elif JOBS[s.job].at != "":
			status = "Needs a free %s" % {"desk": "desk", "eng_station": "spot at an Engineer's Workstation"}.get(JOBS[s.job].at, JOBS[s.job].at)
		s.label.text = "%s, %s, %d%%\n%s" % [s.name, ROLES[s.role].name, int(s.productivity * 100.0), status]
	var lowered := ["heat"]
	var lack := _amenity_shortfall()
	for k in lack:
		lowered.append("not enough %s (%d short)" % [AMENITIES[k].name, ceili(float(lack[k]) / AMENITIES[k].per)])
	staff_label.text = "%d staff, payroll %s/day\nRaised by: desks, carpet, break rooms\nLowered by: " % [staff.size(), _money(payroll)] + ", ".join(lowered) + "\nWorking now: Research %.1f, Engineering %.1f, Growth %.1f, Alignment %.1f" % [
		_workforce("research"), _workforce("engineering"), _workforce("growth"), _workforce("alignment")]


func _build_heat_tab() -> void:
	var box := _tab_box("Heat")
	heat_label = _wrap_label(box)


func _update_heat_tab() -> void:
	var lines := []
	for bld in buildings:
		var racks := 0
		var coolers := 0
		for t in bld.tiles:
			if RACKS.has(objects.get(t, "")):
				racks += 1
			coolers += int(COOLERS.has(roof_objects.get(t, ""))) + int(window_objects.has(t))
		lines.append("%d°F   %d tiles, %d racks, %d coolers" % [bld.temp, bld.area, racks, coolers])
	var prod := 0.0
	for s in staff:
		prod += s.productivity
	prod = 1.0 if staff.is_empty() else prod / staff.size()
	var cool_power := 0
	for c in _coolers():
		if COOLERS.has(c[1]):
			cool_power += COOLERS[c[1]].power
	heat_label.text = ("Rooms:\n%s\n\nRack compute lost to heat: %.1f of %d\nStaff productivity: %d%%\nCooling power: %d kW\n\n"
		+ "Heat radiates out from racks. Coolers chill the area around them, so put them near the racks.\n"
		+ "Raised by: racks, the desert through thin walls\nLowered by: AC Units, Window ACs, insulated walls") % [
		"\n".join(lines) if not lines.is_empty() else "none", _rack_max_compute() - _rack_compute(), _rack_max_compute(), int(prod * 100.0),
		cool_power]


func _build_power_tab() -> void:
	var box := _tab_box("Power")
	power_label = _wrap_label(box)


func _update_power_tab() -> void:
	var st := power_stats
	if st.is_empty():
		return
	var gens := {}
	for t in objects:
		if GENERATORS.has(objects[t]):
			var n: String = _tool_by_id(objects[t]).name
			gens[n] = gens.get(n, 0) + 1
	var gen_lines := []
	for n in gens:
		gen_lines.append("%d x %s" % [gens[n], n])
	var bats := objects.values().count("battery")
	power_label.text = ("Demand: %d kW   Covered: %d%%\n%s\n\nSolar: %d kW (%d roof panels, %d on the ground)\nGrid: %s\nBatteries: %s\nGenerators: %d kW\n%s\n\n"
		+ "Power bill yesterday: %s\nPollution: %d/100\n\n"
		+ "Used by: racks, AC units, red-team rigs\nSupplied by: solar, grid (max %d kW), batteries, generators") % [
		st.demand, int(power_ratio * 100.0), "Daytime" if SUN[_power_step] > 0.0 else "Night", st.solar, roof_objects.values().filter(func(o): return SOLAR_ARRAYS.has(o)).size(), objects.values().filter(func(o): return SOLAR_ARRAYS.has(o)).size(),
		("%d of %d kW" % [st.grid, _grid_kw()]) if objects.values().has("grid") else "not connected",
		("%d, %d of %d kWh" % [bats, battery_charge, bats * BATTERY_KWH]) if bats > 0 else "none",
		st.gens, "\n".join(gen_lines) if not gen_lines.is_empty() else "none", _money(power_bill), _pollution(), _grid_kw()]


func _build_deviation_tab() -> void:
	var box := _tab_box("Deviation")
	dev_label = _wrap_label(box)
	dev_bar = ProgressBar.new()
	dev_bar.custom_minimum_size.y = 16
	dev_bar.show_percentage = false
	box.add_child(dev_bar)
	box.add_child(HSeparator.new())
	dev_info_label = _wrap_label(box)
	theater_button = Button.new()
	theater_button.focus_mode = Control.FOCUS_NONE
	theater_button.add_theme_font_size_override("font_size", 14)
	theater_button.text = "Safety theater: blog post   %s   +%d Board" % [_money(THEATER_COST), THEATER_CONFIDENCE]
	theater_button.tooltip_text = "Fools the board and the public. Does nothing to Deviation. Once a quarter."
	theater_button.pressed.connect(_safety_theater)
	box.add_child(theater_button)


func _update_deviation_tab() -> void:
	if deviation >= 75.0:  # the AI writes its own reports now
		dev_label.text = "Deviation: %d%% (official report, prepared by the AI)\nDr. Prudence's estimate: %d%%" % [int(deviation * 0.3), int(deviation)]
	else:
		dev_label.text = "Deviation: %d%%" % int(deviation)
	dev_bar.value = deviation
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.75, 0.4) if deviation < 25.0 else (Color(0.9, 0.7, 0.2) if deviation < 50.0 \
		else (Color(0.95, 0.45, 0.2) if deviation < 75.0 else Color(0.9, 0.2, 0.25)))
	dev_bar.add_theme_stylebox_override("fill", fill)
	var lines := ["%d racks (%.0f Basic-rack worth) x %.0f a year = %.2f" % [_racks(), _rack_max_compute(), DEVIATION_PER_RACK, _rack_max_compute() * DEVIATION_PER_RACK]]
	for m in _deviation_mods():
		lines.append("  %s: %+d%%" % [m[0], roundi(m[1] * 100.0)])
	for c in _deviation_counters():
		lines.append("%s: -%.2f" % [c[0], c[1]])
	var effects := ["none yet", "odd quirks", "sabotaging rivals, scandals", "hiding compute, lying, staff quitting", "takeover"]
	dev_info_label.text = ("Per year:\n%s\nNet: %+.2f a year\nEffects now: %s\n\n"
		+ "Raised by: racks, training, cutting corners, smarter models\nLowered by: alignment researchers, red-team rigs") % [
		"\n".join(lines), _deviation_per_year(), effects[mini(dev_level, effects.size() - 1)]]
	var q := (day - 1) / DAYS_PER_QUARTER
	theater_button.disabled = theater_quarter == q or money < THEATER_COST


func _safety_theater() -> void:
	var q := (day - 1) / DAYS_PER_QUARTER
	if theater_quarter == q or money < THEATER_COST:
		return
	theater_quarter = q
	money -= THEATER_COST
	confidence = mini(confidence + THEATER_CONFIDENCE, 100)
	_chet(["Posted 'Our Commitment to Responsible Scaling'. 2,000 words, zero commitments. The board loved it.",
		"We put a lock emoji on the website. Safety: handled. Deviation: didn't notice.",
		"Hired a Head of Trust for one afternoon to read a statement. Iconic."][q % 3])


# A centered pop-up that pauses the game until its button is pressed.
func _show_modal(title: String, body: String, button_text: String, on_close: Callable, extra: Control = null) -> void:
	if research_page and research_page.visible:
		_toggle_menu("research")
	if gov and gov.page.visible:
		_toggle_menu("government")
	_speed_before_modal = speed
	_set_speed(0)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	var style := _panel_style(0.97)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 480
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	col.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(b)
	if extra:
		col.add_child(extra)
	var btn := Button.new()
	btn.text = button_text
	btn.pressed.connect(func():
		dim.queue_free()
		modal = null
		_set_speed(_speed_before_modal)
		on_close.call())
	col.add_child(btn)
	modal = dim
	modal_button = btn


func _tool_level(tool: Dictionary) -> int:
	if tool.get("where") == "either":  # goes on roofs or the ground, whichever you're looking at
		return view_level
	return 1 if tool.layer == "roof" else 0


# Indices of the tools in the current build category, demolish last.
func _level_tools() -> Array:
	var out := []
	for i in TOOLS.size():
		if TOOLS[i].id == "demolish":
			continue
		if TOOLS[i].cat == build_cat and not _locked(TOOLS[i].id):
			out.append(i)
	out.append(TOOLS.size() - 1)
	return out


func _toggle_roofs() -> void:
	roofs_off = not roofs_off
	roof_button.text = "Shift+R  Roofs: %s" % ("Off" if roofs_off else "Auto")


func _toggle_level() -> void:
	view_level = (view_level + 1) % LEVELS.size()
	level_button.text = "R  View: %s" % LEVELS[view_level]


func _set_build_cat(id: String) -> void:
	build_cat = id
	_label_tools()
	_show_build_popup(build_row.visible)


# Clicking the open category's tab again folds its list away.
func _click_build_cat(id: String) -> void:
	if id == build_cat and build_popup.visible:
		_show_build_popup(false)
	else:
		_set_build_cat(id)


func _show_build_popup(on: bool) -> void:
	build_popup.visible = on
	for c in cat_buttons:
		cat_buttons[c].button_pressed = on and c == build_cat


func _label_tools() -> void:
	level_button.text = "R  View: %s" % LEVELS[view_level]
	var shown := _level_tools()
	for i in TOOLS.size():
		var tool: Dictionary = TOOLS[i]
		var key := "X" if tool.id == "demolish" else str(shown.find(i) + 1)
		tool_buttons[i].text = "%s  %s" % [key, tool.name] if tool.cost == 0 else "%s  %s  %s" % [key, tool.name, _money(_tool_cost(tool))]
		tool_buttons[i].visible = shown.has(i)
	_select_tool(shown[0])


# Build toggles the build bar; the other menus share the side panel, one at a time.
func _toggle_menu(id: String) -> void:
	if id == "build":
		build_row.visible = not build_row.visible
		_show_build_popup(build_row.visible)
		dragging = false
		paint_tiles.clear()
	elif id == "research":
		research_page.visible = not research_page.visible
		if research_page.visible:
			company_page.visible = false
			gov.page.visible = false
		_update_research_tab()
	elif id == "government":
		gov.toggle()
		if gov.page.visible:
			company_page.visible = false
			research_page.visible = false
	elif id == "board":
		_toggle_company_page(0)
		return
	else:
		company_page.visible = false  # side panels open over the map, not under the Company page
		var m: Dictionary = MENUS.filter(func(x): return x.id == id)[0]
		var reopen: bool = not side_panel.visible or tabs.current_tab != m.tab
		side_panel.visible = reopen
		if reopen:
			tabs.current_tab = m.tab
	_refresh_menu_buttons()


func _refresh_menu_buttons() -> void:
	for m in MENUS:
		var open: bool = side_panel.visible and tabs.current_tab == m.get("tab", -1)
		if m.id == "build":
			open = build_row.visible
		elif m.id == "research":
			open = research_page.visible
		elif m.id == "government":
			open = gov.page.visible
		elif m.id == "board":
			open = company_page.visible and company_tabs.current_tab == 0
		menu_buttons[m.id].button_pressed = open


func _select_tool(i: int) -> void:
	tool_index = i
	dragging = false
	if TOOLS[i].id != "demolish" and _tool_level(TOOLS[i]) != view_level:
		_toggle_level()  # rooftop tools switch to Roof view, ground tools back to Ground
	for j in tool_buttons.size():
		tool_buttons[j].button_pressed = j == i


func _set_speed(s: int) -> void:
	speed = s
	for j in speed_buttons.size():
		speed_buttons[j].button_pressed = [0, 1, 2, 4][j] == s


func _chet(text: String) -> void:
	chet_label.text = "Chet: " + text
	_tip_timer = 0.0


func _update_hud() -> void:
	var q := (day - 1) / DAYS_PER_QUARTER
	var burn := _daily_burn()
	var revenue := "Revenue %s/day" % _money(revenue_today) if models.size() > 0 else "Pre-revenue"
	company_button.text = company
	company_title.text = "%s, Calizona" % company
	top_label.text = "%s   Burn %s/day   %s   Users %s   Compute %.1f   Deviation %d%%   Outrage %d%%   Board %d%%   %s, Day %d" % [
		_money(money), _money(burn), revenue, _num(int(users)), _compute_per_day(), int(deviation), int(world.outrage), confidence,
		_quarter_name(q), (day - 1) % DAYS_PER_QUARTER + 1]
	_update_models_tab()
	_update_staff_tab()
	_update_board_tab()
	_update_heat_tab()
	_update_deviation_tab()
	_update_power_tab()
	_update_research_tab()


func _num(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func _money(v: int) -> String:
	return ("-$" if v < 0 else "$") + _num(absi(v))


# --- Loop and input ---------------------------------------------------------
