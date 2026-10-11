extends Node2D
## Starter map: a small pre-built office in the Calizona desert, plus a handful of
## construction tools (Prison Architect style: you build, staff wander around).

const TILE := 32
const WALL_H := 22.0  # how tall walls look in the three-quarter view
const GRID_W := 64
const GRID_H := 48
const PAN_SPEED := 700.0
const SECONDS_PER_DAY := 900.0 / 91.0  # 15 real minutes per quarter at 1x
const START_YEAR := 2027
const SALARY_PER_DAY := 1200
const RACK_POWER_PER_DAY := 400

# Every buildable thing. layer: which map layer it lives on. drag: how the mouse places it.
const TOOLS := [
	{"id": "carpet", "name": "Carpet", "layer": "floor", "cost": 200, "drag": "fill"},
	{"id": "concrete", "name": "Concrete", "layer": "floor", "cost": 100, "drag": "fill"},
	{"id": "wall", "name": "Wall", "layer": "wall", "cost": 800, "drag": "outline"},
	{"id": "door", "name": "Door", "layer": "wall", "cost": 2500, "drag": "single"},
	{"id": "desk", "name": "Desk", "layer": "object", "cost": 6000, "drag": "paint"},
	{"id": "rack", "name": "Server Rack", "layer": "object", "cost": 40000, "drag": "paint"},
	{"id": "ficus", "name": "Morale Ficus", "layer": "object", "cost": 300, "drag": "paint"},
	{"id": "demolish", "name": "Demolish", "layer": "", "cost": 0, "drag": "fill"},
]

const CHET_TIPS := [
	"Bro. Welcome to Calizona. Zero regulations, infinite sun, slightly less water.",
	"Drag Walls in a box and boom, you've got a room. That's basically architecture.",
	"Desks need a floor under them. Even disruptors need carpet, bro.",
	"Server Racks are where the AI lives. Feed them money and they feed you... eventually.",
	"Ficus plants boost morale by 0%. Investors love them though.",
	"Revenue? We're pre-revenue. That's a vibe, not a problem.",
	"Right-click demolishes stuff. Like the old office culture. Disrupted.",
	"Every door is an open door policy if you think about it.",
]

var floor_tiles := {}  # Vector2i -> "carpet" / "concrete"
var wall_tiles := {}  # Vector2i -> "wall" / "door"
var objects := {}  # Vector2i -> "desk" / "rack" / "ficus"

var money := 2_000_000
var day := 1
var speed := 1
var tool_index := 0
var hover := Vector2i(-1, -1)
var dragging := false
var drag_start := Vector2i.ZERO
var paint_tiles := {}
var panning := false

var staff := []  # [{pos, path, wait, shirt}]
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var _day_timer := 0.0
var _tip_timer := 0.0
var _tip := 0
var _time := 0.0

var camera: Camera2D
var top_label: Label
var chet_label: Label
var cost_label: Label
var tool_buttons := []
var speed_buttons := []


func _ready() -> void:
	rng.seed = 42
	_build_starter_office()
	astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE, TILE) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	_refresh_walkable()
	for shirt in [Color(0.85, 0.35, 0.3), Color(0.3, 0.65, 0.45)]:
		staff.append({"pos": _tile_center(Vector2i(27, 22)), "path": PackedVector2Array(), "wait": rng.randf_range(0.5, 2.0), "shirt": shirt})

	camera = Camera2D.new()
	camera.position = _tile_center(Vector2i(30, 22))
	camera.zoom = Vector2(1.4, 1.4)
	add_child(camera)
	_build_ui()
	_select_tool(0)


func _build_starter_office() -> void:
	var r := Rect2i(24, 17, 13, 10)  # walls included
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var t := Vector2i(x, y)
			floor_tiles[t] = "carpet"
			if x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1:
				wall_tiles[t] = "wall"
	wall_tiles[Vector2i(30, 26)] = "door"
	for y in range(27, 33):  # walkway out to the parking lot
		for x in range(29, 32):
			floor_tiles[Vector2i(x, y)] = "concrete"
	objects[Vector2i(26, 19)] = "desk"
	objects[Vector2i(28, 19)] = "desk"
	objects[Vector2i(34, 19)] = "rack"
	objects[Vector2i(34, 20)] = "rack"
	objects[Vector2i(25, 25)] = "ficus"


# --- UI ---------------------------------------------------------------------

func _panel_style(alpha := 0.85) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.09, 0.08, alpha)
	s.set_content_margin_all(8)
	s.set_corner_radius_all(6)
	return s


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style())
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	layer.add_child(top)
	var top_row := HBoxContainer.new()
	top.add_child(top_row)
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
	var col := VBoxContainer.new()
	bottom.add_child(col)
	chet_label = Label.new()
	chet_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	chet_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(chet_label)
	var row := HBoxContainer.new()
	col.add_child(row)
	for i in TOOLS.size():
		var tool: Dictionary = TOOLS[i]
		var b := Button.new()
		var key := "X" if tool.id == "demolish" else str(i + 1)
		b.text = "%s  %s" % [key, tool.name] if tool.cost == 0 else "%s  %s  %s" % [key, tool.name, _money(tool.cost)]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_tool.bind(i))
		row.add_child(b)
		tool_buttons.append(b)

	cost_label = Label.new()
	cost_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cost_label.add_theme_constant_override("outline_size", 4)
	cost_label.visible = false
	layer.add_child(cost_label)
	_chet(CHET_TIPS[0])


func _select_tool(i: int) -> void:
	tool_index = i
	dragging = false
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
	var q := (day - 1) / 91
	var burn := _daily_burn()
	top_label.text = "Untitled AI Startup, Calizona     %s     Burn %s/day     Revenue $0 (pre-revenue)     Q%d %d, Day %d" % [
		_money(money), _money(burn), q % 4 + 1, START_YEAR + q / 4, (day - 1) % 91 + 1]


func _money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-$" if v < 0 else "$") + s + out


# --- Loop and input ---------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	camera.position += dir * PAN_SPEED * delta / camera.zoom.x

	_day_timer += delta * speed
	while _day_timer >= SECONDS_PER_DAY:
		_day_timer -= SECONDS_PER_DAY
		day += 1
		money -= _daily_burn()
	_tip_timer += delta
	if _tip_timer > 15.0:
		_tip = (_tip + 1) % CHET_TIPS.size()
		_chet(CHET_TIPS[_tip])

	hover = _mouse_tile()
	if paint_tiles.size() > 0 and dragging and _in_bounds(hover):
		paint_tiles[hover] = true
	_update_staff(delta * maxf(speed, 0.0))
	_update_hud()
	_update_cost_label()
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + TOOLS.size() - 1:
			_select_tool(event.keycode - KEY_1)
		elif event.keycode == KEY_X:
			_select_tool(TOOLS.size() - 1)
		elif event.keycode == KEY_SPACE:
			_set_speed(1 if speed == 0 else 0)
		elif event.keycode == KEY_ESCAPE:
			dragging = false
			paint_tiles.clear()
	elif event is InputEventMouseMotion and panning:
		camera.position -= event.relative / camera.zoom.x
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _in_bounds(hover):
					dragging = true
					drag_start = hover
					paint_tiles.clear()
					if TOOLS[tool_index].drag == "paint":
						paint_tiles[hover] = true
			MOUSE_BUTTON_RIGHT:
				if dragging:
					dragging = false
					paint_tiles.clear()
				else:
					_demolish(hover)
					_after_build()
			MOUSE_BUTTON_MIDDLE:
				panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.1)


func _zoom(factor: float) -> void:
	var before := get_global_mouse_position()
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.4, 0.4), Vector2(3, 3))
	camera.force_update_scroll()
	camera.position += before - get_global_mouse_position()


# --- Building ---------------------------------------------------------------

func _mouse_tile() -> Vector2i:
	return Vector2i((get_global_mouse_position() / TILE).floor())


func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < GRID_W and t.y < GRID_H


func _tile_center(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE


func _drag_tiles() -> Array:
	var tool: Dictionary = TOOLS[tool_index]
	match tool.drag:
		"single":
			return [hover]
		"paint":
			return paint_tiles.keys()
	var a := Vector2i(mini(drag_start.x, hover.x), mini(drag_start.y, hover.y))
	var b := Vector2i(maxi(drag_start.x, hover.x), maxi(drag_start.y, hover.y))
	a = a.clamp(Vector2i.ZERO, Vector2i(GRID_W - 1, GRID_H - 1))
	b = b.clamp(Vector2i.ZERO, Vector2i(GRID_W - 1, GRID_H - 1))
	var out := []
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			if tool.drag == "fill" or x == a.x or x == b.x or y == a.y or y == b.y:
				out.append(Vector2i(x, y))
	return out


func _can_place(id: String, t: Vector2i) -> bool:
	if not _in_bounds(t):
		return false
	match id:
		"carpet", "concrete":
			return floor_tiles.get(t) != id
		"wall":
			return not wall_tiles.has(t) and not objects.has(t)
		"door":
			return wall_tiles.get(t) != "door" and not objects.has(t)
		"demolish":
			return objects.has(t) or wall_tiles.has(t) or floor_tiles.has(t)
	# furniture
	return floor_tiles.has(t) and not wall_tiles.has(t) and not objects.has(t)


func _tool_by_id(id: String) -> Dictionary:
	for tool in TOOLS:
		if tool.id == id:
			return tool
	return {}


func _commit(tiles: Array) -> void:
	var tool: Dictionary = TOOLS[tool_index]
	var valid := tiles.filter(func(t): return _can_place(tool.id, t))
	if valid.is_empty():
		return
	if tool.id == "demolish":
		for t in valid:
			_demolish(t)
		_after_build()
		return
	var cost: int = tool.cost * valid.size()
	if cost > money:
		_chet("Bro, that's %s and we have %s. Maybe pitch some VCs first?" % [_money(cost), _money(money)])
		return
	money -= cost
	for t in valid:
		match tool.layer:
			"floor": floor_tiles[t] = tool.id
			"wall": wall_tiles[t] = tool.id
			"object": objects[t] = tool.id
	_after_build()


func _demolish(t: Vector2i) -> void:
	# Removes the top-most thing on a tile and refunds half its price.
	for layer in [objects, wall_tiles, floor_tiles]:
		if layer.has(t):
			money += int(_tool_by_id(layer[t]).cost / 2)
			layer.erase(t)
			return


func _daily_burn() -> int:
	var racks := 0
	for t in objects:
		if objects[t] == "rack":
			racks += 1
	return staff.size() * SALARY_PER_DAY + racks * RACK_POWER_PER_DAY


# --- Staff ------------------------------------------------------------------

func _walkable(t: Vector2i) -> bool:
	var door: bool = wall_tiles.get(t) == "door"
	return (floor_tiles.has(t) or door) and (door or not wall_tiles.has(t)) and not objects.has(t)


func _refresh_walkable() -> void:
	for x in GRID_W:
		for y in GRID_H:
			astar.set_point_solid(Vector2i(x, y), not _walkable(Vector2i(x, y)))


func _after_build() -> void:
	_refresh_walkable()
	for s in staff:
		s.path = PackedVector2Array()


func _update_staff(delta: float) -> void:
	var spots := floor_tiles.keys().filter(_walkable)
	for s in staff:
		var here := Vector2i((s.pos / TILE).floor())
		if not _walkable(here) and not spots.is_empty():
			s.pos = _tile_center(spots[rng.randi() % spots.size()])  # got walled in; nudge them out
			continue
		if s.path.is_empty():
			s.wait -= delta
			if s.wait <= 0.0 and not spots.is_empty():
				s.path = astar.get_point_path(here, spots[rng.randi() % spots.size()])
				s.wait = rng.randf_range(1.0, 4.0)
			continue
		var target: Vector2 = s.path[0]
		s.pos = s.pos.move_toward(target, 60.0 * delta)
		if s.pos.distance_to(target) < 0.5:
			s.path.remove_at(0)


# --- Drawing ----------------------------------------------------------------

func _hash(t: Vector2i, salt := 0) -> int:
	return absi(hash(Vector3i(t.x, t.y, salt)))


func _update_cost_label() -> void:
	var tool: Dictionary = TOOLS[tool_index]
	if not dragging or tool.cost == 0:
		cost_label.visible = false
		return
	var n := _drag_tiles().filter(func(t): return _can_place(tool.id, t)).size()
	cost_label.text = _money(n * tool.cost)
	cost_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4) if n * tool.cost > money else Color.WHITE)
	cost_label.position = get_viewport().get_mouse_position() + Vector2(18, 10)
	cost_label.visible = true


func _draw() -> void:
	var view := get_viewport_rect().size / camera.zoom
	var a := Vector2i(((camera.position - view / 2) / TILE).floor()).clamp(Vector2i.ZERO, Vector2i(GRID_W, GRID_H))
	var b := Vector2i(((camera.position + view / 2) / TILE).ceil()).clamp(Vector2i.ZERO, Vector2i(GRID_W, GRID_H))

	draw_rect(Rect2(Vector2.ZERO, Vector2(GRID_W, GRID_H) * TILE), Color(0.84, 0.72, 0.5))
	for x in range(a.x, b.x):
		for y in range(a.y, b.y):
			var t := Vector2i(x, y)
			if floor_tiles.has(t):
				_draw_floor(t)
			else:
				_draw_sand(t)
	var grid := Color(0, 0, 0, 0.06)
	for x in range(a.x, b.x + 1):
		draw_line(Vector2(x, a.y) * TILE, Vector2(x, b.y) * TILE, grid)
	for y in range(a.y, b.y + 1):
		draw_line(Vector2(a.x, y) * TILE, Vector2(b.x, y) * TILE, grid)

	# Three-quarter view: things have height and are drawn back-to-front, row by row,
	# so anything further south overlaps what's behind it.
	var rows := {}
	for t in wall_tiles.keys() + objects.keys():
		if not rows.has(t.y):
			rows[t.y] = []
		rows[t.y].append(t)
	for s in staff:
		var r := int(s.pos.y / TILE)
		if not rows.has(r):
			rows[r] = []
		rows[r].append(s)
	for y in range(a.y, b.y + 2):
		for item in rows.get(y, []):
			if item is Dictionary:
				_draw_person(item.pos, item.shirt)
			elif wall_tiles.get(item) == "wall":
				_draw_wall(item)
			elif wall_tiles.has(item):
				_draw_door(item)
			else:
				call("_draw_" + objects[item], Vector2(item) * TILE, item)
	_draw_preview()


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var ang := TAU * i / 16.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, col)


# A box standing on the ground: top face lifted by `h`, front face below it.
func _box(base: Rect2, h: float, top: Color, front: Color) -> void:
	draw_rect(Rect2(base.position - Vector2(0, h), base.size), top)
	draw_rect(Rect2(Vector2(base.position.x, base.end.y - h), Vector2(base.size.x, h)), front)


func _draw_sand(t: Vector2i) -> void:
	var h := _hash(t)
	if h % 5 == 0:
		draw_circle(Vector2(t) * TILE + Vector2(h % 23 + 4, (h / 23) % 23 + 4), 1.5, Color(0.7, 0.58, 0.38))
	if h % 37 == 0:  # the occasional scrappy desert shrub
		var c := Vector2(t) * TILE + Vector2(16, 20)
		_ellipse(c + Vector2(2, 4), 9, 4, Color(0, 0, 0, 0.15))
		draw_circle(c - Vector2(0, 4), 6, Color(0.48, 0.53, 0.28))
		draw_circle(c + Vector2(4, -8), 4, Color(0.58, 0.64, 0.35))


func _draw_floor(t: Vector2i) -> void:
	var r := Rect2(Vector2(t) * TILE, Vector2(TILE, TILE))
	if floor_tiles[t] == "carpet":
		var alt := (t.x + t.y) % 2 == 0
		draw_rect(r, Color(0.35, 0.4, 0.52) if alt else Color(0.38, 0.43, 0.55))
	else:
		draw_rect(r, Color(0.66, 0.65, 0.62))
		draw_rect(r, Color(0.55, 0.54, 0.51), false, 1.0)
	if wall_tiles.get(t + Vector2i.UP) == "wall":  # shadow cast by the wall behind
		draw_rect(Rect2(r.position, Vector2(TILE, 8)), Color(0, 0, 0, 0.2))


func _draw_wall(t: Vector2i) -> void:
	var p := Vector2(t) * TILE
	_box(Rect2(p, Vector2(TILE, TILE)), WALL_H, Color(0.5, 0.48, 0.47), Color(0.3, 0.29, 0.32))
	var edge := Color(0.2, 0.19, 0.21)
	var top := p - Vector2(0, WALL_H)
	if wall_tiles.get(t + Vector2i.UP) != "wall":
		draw_line(top, top + Vector2(TILE, 0), edge, 2.0)
	if wall_tiles.get(t + Vector2i.LEFT) != "wall":
		draw_line(top, top + Vector2(0, TILE + WALL_H), edge, 2.0)
	if wall_tiles.get(t + Vector2i.RIGHT) != "wall":
		draw_line(top + Vector2(TILE, 0), top + Vector2(TILE, TILE + WALL_H), edge, 2.0)


func _draw_door(t: Vector2i) -> void:
	var p := Vector2(t) * TILE
	var top := Color(0.5, 0.48, 0.47)
	var front := Color(0.3, 0.29, 0.32)
	var wood := Color(0.62, 0.43, 0.25)
	if wall_tiles.has(t + Vector2i.LEFT) or wall_tiles.has(t + Vector2i.RIGHT):
		# Door in a horizontal wall: two posts, a lintel, and the door swung open.
		draw_rect(Rect2(p + Vector2(6, TILE - WALL_H - 4), Vector2(7, WALL_H + 2)), wood.darkened(0.25))
		_box(Rect2(p, Vector2(5, TILE)), WALL_H, top, front)
		_box(Rect2(p + Vector2(TILE - 5, 0), Vector2(5, TILE)), WALL_H, top, front)
		draw_rect(Rect2(p - Vector2(0, WALL_H), Vector2(TILE, 6)), top)
	else:
		# Door in a vertical wall: a thin wooden slab in line with the wall.
		_box(Rect2(p + Vector2(0, 0), Vector2(TILE, 5)), WALL_H, top, front)
		_box(Rect2(p + Vector2(13, 5), Vector2(6, TILE - 5)), WALL_H * 0.8, wood, wood.darkened(0.3))


func _draw_desk(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 15, 4, Color(0, 0, 0, 0.2))
	draw_circle(p + Vector2(16, 5), 6, Color(0.22, 0.22, 0.25))  # chair behind the desk
	_box(Rect2(p + Vector2(2, 14), Vector2(28, 14)), 8, Color(0.62, 0.44, 0.27), Color(0.42, 0.29, 0.17))
	draw_rect(Rect2(p + Vector2(14, 6), Vector2(4, 4)), Color(0.12, 0.12, 0.14))  # monitor stand
	draw_rect(Rect2(p + Vector2(7, -4), Vector2(18, 12)), Color(0.12, 0.12, 0.14))
	draw_rect(Rect2(p + Vector2(9, -2), Vector2(14, 8)), Color(0.45, 0.75, 1.0))


func _draw_rack(p: Vector2, t: Vector2i) -> void:
	_ellipse(p + Vector2(18, 28), 14, 4, Color(0, 0, 0, 0.25))
	_box(Rect2(p + Vector2(4, 8), Vector2(24, 22)), 22, Color(0.32, 0.33, 0.37), Color(0.08, 0.08, 0.1))
	var tick := int(_time * 5.0)
	for i in 4:
		var y := p.y + 10 + i * 5
		draw_line(Vector2(p.x + 7, y + 2), Vector2(p.x + 21, y + 2), Color(0.25, 0.25, 0.3))
		var on := _hash(t, i * 1000 + tick) % 3 != 0
		draw_rect(Rect2(Vector2(p.x + 23, y), Vector2(3, 3)), Color(0.3, 1.0, 0.5) if on else Color(0.1, 0.3, 0.15))


func _draw_ficus(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(17, 28), 9, 3, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(10, 16), Vector2(12, 12)), 6, Color(0.35, 0.22, 0.14), Color(0.6, 0.36, 0.2))
	for o in [Vector2(-7, 0), Vector2(6, -2), Vector2(0, -8), Vector2(-4, -14), Vector2(5, -12), Vector2(0, -2)]:
		draw_circle(p + Vector2(16, 6) + o, 6, Color(0.22, 0.5, 0.25))
	draw_circle(p + Vector2(18, -6), 4, Color(0.32, 0.62, 0.32))


func _draw_person(pos: Vector2, shirt: Color) -> void:
	var feet := pos + Vector2(0, 8)
	_ellipse(feet, 8, 3, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(feet + Vector2(-5, -6), Vector2(4, 6)), Color(0.2, 0.22, 0.3))
	draw_rect(Rect2(feet + Vector2(1, -6), Vector2(4, 6)), Color(0.2, 0.22, 0.3))
	draw_rect(Rect2(feet + Vector2(-7, -19), Vector2(14, 14)), shirt)
	draw_circle(feet + Vector2(0, -24), 6, Color(0.93, 0.78, 0.62))
	draw_rect(Rect2(feet + Vector2(-6, -31), Vector2(12, 4)), Color(0.3, 0.2, 0.12))


func _draw_preview() -> void:
	if not _in_bounds(hover):
		return
	var tool: Dictionary = TOOLS[tool_index]
	var tiles: Array = _drag_tiles() if dragging else [hover]
	for t in tiles:
		var ok := _can_place(tool.id, t)
		var c := Color(1, 0.3, 0.3, 0.35) if tool.id == "demolish" or not ok else Color(0.4, 1, 0.5, 0.35)
		if tool.id == "demolish" and not ok:
			c = Color(1, 1, 1, 0.15)
		draw_rect(Rect2(Vector2(t) * TILE, Vector2(TILE, TILE)), c)
	draw_rect(Rect2(Vector2(hover) * TILE, Vector2(TILE, TILE)), Color(1, 1, 1, 0.8), false, 2.0)
