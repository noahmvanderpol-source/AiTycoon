extends "res://scripts/ui.gd"
## Startup, loop and input. Part of the Main script chain (see scripts/README.md).

func _ready() -> void:
	rng.seed = 42
	smog.resize(GRID_W * GRID_H)
	heat.resize(GRID_W * GRID_H)
	heat.fill(OUTDOOR_TEMP)
	_build_starter_office()
	astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE, TILE) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	_refresh_walkable()
	_find_buildings()
	_refresh_access()
	power_bill = int(_power_demand() * 24.0 * GENERATORS.gen_portable.fuel)  # a first guess until day 1's bill is in
	_add_staff("researcher", _tile_center(Vector2i(28, 23)), FOUNDER_SALARY)
	_add_staff("engineer", _tile_center(Vector2i(29, 23)), FOUNDER_SALARY)

	world = preload("res://scripts/world.gd").new()
	world.show_behind_parent = true
	add_child(world)
	camera = Camera2D.new()
	camera.position = _tile_center(Vector2i(31, 23))
	camera.zoom = Vector2(1.4, 1.4)
	add_child(camera)
	_build_ui()
	view_level = LEVELS.size() - 1
	_toggle_level()  # wraps round to the ground floor
	_set_build_cat(BUILD_CATS[0].id)
	_new_target(0)
	_ask_company_name()


func _build_starter_office() -> void:
	# A garage, like the root of the research tree: bare concrete, cheap walls, one of everything.
	var r := Rect2i(26, 20, 9, 7)  # walls included
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var t := Vector2i(x, y)
			floor_tiles[t] = "concrete"
			if x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1:
				wall_tiles[t] = "wall"
	wall_tiles[Vector2i(30, 26)] = "door"
	for y in range(27, 33):  # walkway out to the parking lot
		for x in range(29, 32):
			floor_tiles[Vector2i(x, y)] = "concrete"
	objects[Vector2i(28, 21)] = "desk"
	objects[Vector2i(30, 21)] = "eng_station"
	objects[Vector2i(33, 21)] = "rack"
	objects[Vector2i(33, 22)] = "rack"
	window_objects[Vector2i(34, 21)] = "window_ac"  # in the side wall, next to the racks
	window_objects[Vector2i(34, 22)] = "window_ac"  # one per rack, or they cook
	objects[Vector2i(36, 24)] = "gen_portable"  # round the side, humming


# --- UI ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if INFINITE_MONEY:
		money = maxi(money, 1_000_000_000)
	if build_popup.visible:  # sits just above the bottom bar, whose height changes
		build_popup.position = Vector2(8, bottom_bar.position.y - build_popup.size.y - 4)
	_time += delta
	var dir := Vector2.ZERO
	if modal:
		pass
	elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	camera.position += dir * PAN_SPEED * delta / camera.zoom.x

	_day_timer += delta * speed
	while _day_timer >= SECONDS_PER_DAY and not modal and not game_over:
		_day_timer -= SECONDS_PER_DAY
		_new_day()
	_heat_timer += delta * speed
	while _heat_timer >= SECONDS_PER_DAY / HEAT_STEPS_PER_DAY and not modal and not game_over:
		_heat_timer -= SECONDS_PER_DAY / HEAT_STEPS_PER_DAY
		_tick_power()
		_tick_heat()
	_tip_timer += delta
	if _tip_timer > 15.0:
		_tip = (_tip + 1) % CHET_TIPS.size()
		_chet(CHET_TIPS[_tip])

	hover = _mouse_tile()
	hover_sub = Vector2i((get_global_mouse_position() / SUB).floor())
	if paint_tiles.size() > 0 and dragging and _in_bounds(hover):
		paint_tiles[_cursor()] = true
	_update_staff(delta * maxf(speed, 0.0))
	var inside := -1  # roofs fade out while the mouse is inside any room of the building
	for bld in buildings:
		if bld.tiles.has(hover):
			inside = bld.group
	for bld in buildings:
		var hide: bool = view_level == 0 and (roofs_off or bld.group == inside or _heat_view())
		bld.alpha = move_toward(bld.alpha, 0.0 if hide else 1.0, delta * 5.0)
	_update_hud()
	_update_cost_label()
	_update_hover_tip()
	queue_redraw()


func _input(event: InputEvent) -> void:
	# Releases are caught here so a drag that ends over the UI still finishes.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and dragging:
			var tiles := _drag_tiles()
			dragging = false
			_commit(tiles)
			paint_tiles.clear()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = false


func _unhandled_input(event: InputEvent) -> void:
	if modal:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		for m in MENUS:
			if event.keycode == m.key:
				_toggle_menu(m.id)
				return
		var shown := _level_tools()
		if not build_row.visible:
			shown = []
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + shown.size() - 1:
			_select_tool(shown[event.keycode - KEY_1])
		elif event.keycode == KEY_Q and build_row.visible:
			place_rot = (place_rot + 1) % 4
		elif event.keycode == KEY_R and event.shift_pressed:
			_toggle_roofs()
		elif event.keycode == KEY_R:
			_toggle_level()
		elif event.keycode == KEY_TAB and build_row.visible:  # next build category
			var ids := BUILD_CATS.map(func(c): return c.id)
			_set_build_cat(ids[(ids.find(build_cat) + 1) % ids.size()])
		elif event.keycode == KEY_X and build_row.visible:
			_select_tool(TOOLS.size() - 1)
		elif event.keycode == KEY_SPACE:
			_set_speed(1 if speed == 0 else 0)
		elif event.keycode == KEY_ESCAPE and research_page.visible:
			_toggle_menu("research")
		elif event.keycode == KEY_ESCAPE and gov.page.visible:
			_toggle_menu("government")
		elif event.keycode == KEY_ESCAPE:
			if company_page.visible:
				_set_company_page(false)
			dragging = false
			paint_tiles.clear()
	elif event is InputEventMouseMotion and panning:
		camera.position -= event.relative / camera.zoom.x
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if build_row.visible and _in_bounds(hover):
					dragging = true
					drag_start = hover
					paint_tiles.clear()
					if TOOLS[tool_index].drag == "paint":
						paint_tiles[_cursor()] = true
			MOUSE_BUTTON_RIGHT:
				if dragging:
					dragging = false
					paint_tiles.clear()
				elif build_row.visible:
					_demolish(hover, hover_sub)
					_after_build()
			MOUSE_BUTTON_MIDDLE:
				panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.1)


func _mouse_over_ui() -> bool:
	var vp := get_viewport()
	return vp.has_method("gui_get_hovered_control") and vp.call("gui_get_hovered_control") != null


func _zoom(factor: float) -> void:
	if _mouse_over_ui():  # scrolling a menu shouldn't zoom the map
		return
	var before := get_global_mouse_position()
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.4, 0.4), Vector2(3, 3))
	camera.force_update_scroll()
	camera.position += before - get_global_mouse_position()


# --- Building ---------------------------------------------------------------
