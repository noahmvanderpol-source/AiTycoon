extends "res://scripts/roofs.gd"
## Drawing the map and objects. Part of the Main script chain (see scripts/README.md).

func _hash(t: Vector2i, salt := 0) -> int:
	return absi(hash(Vector3i(t.x, t.y, salt)))


# --- Hover info ---------------------------------------------------------------

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
	if camera.zoom.x >= 1.0 or _is_sub_tool():
		# Fainter subgrid lines halfway across each tile; stronger while placing small items.
		var sub_grid := Color(0, 0, 0, 0.1 if _is_sub_tool() else 0.025)
		for x in range(a.x, b.x):
			draw_line(Vector2(x + 0.5, a.y) * TILE, Vector2(x + 0.5, b.y) * TILE, sub_grid)
		for y in range(a.y, b.y):
			draw_line(Vector2(a.x, y + 0.5) * TILE, Vector2(b.x, y + 0.5) * TILE, sub_grid)
	for x in range(a.x, b.x + 1):
		draw_line(Vector2(x, a.y) * TILE, Vector2(x, b.y) * TILE, grid)
	for y in range(a.y, b.y + 1):
		draw_line(Vector2(a.x, y) * TILE, Vector2(b.x, y) * TILE, grid)

	if _heat_view():
		_draw_heat_tint()  # on the floor, under walls and furniture
	_draw_smog(a, b)

	# Three-quarter view: things have height and are drawn back-to-front, row by row,
	# so anything further south overlaps what's behind it.
	var rows := {}
	for t in wall_tiles.keys() + objects.keys():
		if objects.get(t) == "part" and not wall_tiles.has(t):
			continue
		var r: int = _footprint(objects.get(t, ""), t).back().y if objects.has(t) else t.y  # big things draw with their front row
		if not rows.has(r):
			rows[r] = []
		rows[r].append(t)
	for c in sub_objects:
		var r := _tile_of_sub(c).y
		if not rows.has(r):
			rows[r] = []
		rows[r].append({"sub": c})
	for s in staff:
		var r := int(s.pos.y / TILE)
		if not rows.has(r):
			rows[r] = []
		rows[r].append(s)
	for y in range(a.y, b.y + 2):
		for item in rows.get(y, []):
			if item is Dictionary and item.has("sub"):
				var at := Vector2(item.sub) * SUB
				if _counter_at(_tile_of_sub(item.sub)) != NO_SEAT:  # up on the counter top
					at.y = _tile_of_sub(item.sub).y * TILE - 6
				if sub_rot.has(item.sub):
					call("_draw_" + sub_objects[item.sub], at, sub_rot[item.sub])
				else:
					call("_draw_" + sub_objects[item.sub], at)
			elif item is Dictionary:
				_draw_staff(item)
			elif _is_wall(item):
				_draw_wall(item)
				if window_objects.has(item):  # on the front face, or the top of a side wall
					var up := Vector2(0, 8 - TILE) if wall_tiles.has(item + Vector2i.DOWN) else Vector2.ZERO
					_draw_window_ac(Vector2(item) * TILE + up, 1.0)
			elif wall_tiles.has(item):
				_draw_door(item)
			else:
				call("_draw_" + objects[item], Vector2(item) * TILE, item)
	if view_level == 0:
		_draw_no_access()
	_draw_unpowered()
	if _heat_view():
		_draw_rack_temps()
	if deviation >= 25.0 and RACKS.has(objects.get(hover, "")) and rack_names.has(hover) and view_level == 0:
		var at := Vector2(hover) * TILE + Vector2(-34, -20)  # the name the AI gave this rack
		draw_string_outline(ThemeDB.fallback_font, at, rack_names[hover], HORIZONTAL_ALIGNMENT_CENTER, TILE + 68, 12, 4, Color.BLACK)
		draw_string(ThemeDB.fallback_font, at, rack_names[hover], HORIZONTAL_ALIGNMENT_CENTER, TILE + 68, 12, Color(0.75, 1.0, 0.8))
	for bld in buildings:
		_draw_roof(bld)
	if view_level == 0:  # an Engineer's Workstation shows its work radius while placing or hovering it
		if build_row.visible and TOOLS[tool_index].id == "eng_station" and _in_bounds(hover):
			_draw_eng_radius(hover)
		elif objects.get(hover) == "eng_station":
			_draw_eng_radius(hover)
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
	elif floor_tiles[t] == "asphalt":
		draw_rect(r, Color(0.22, 0.22, 0.24))
		var h := _hash(t, 7)
		draw_circle(r.position + Vector2(h % 27 + 3, (h / 27) % 27 + 3), 1.0, Color(0.35, 0.35, 0.37))
	elif floor_tiles[t] == "gravel":
		draw_rect(r, Color(0.62, 0.58, 0.52))
		for k in 5:
			var h := _hash(t, k)
			draw_circle(r.position + Vector2(h % 29 + 2, (h / 29) % 29 + 2), 1.5, Color(0.48, 0.45, 0.4))
	else:
		draw_rect(r, Color(0.66, 0.65, 0.62))
		draw_rect(r, Color(0.55, 0.54, 0.51), false, 1.0)
	if _is_wall(t + Vector2i.UP):  # shadow cast by the wall behind
		draw_rect(Rect2(r.position, Vector2(TILE, 8)), Color(0, 0, 0, 0.2))


func _draw_wall(t: Vector2i) -> void:
	var p := Vector2(t) * TILE
	var kind: Dictionary = WALLS[wall_tiles[t]]
	var l := _is_wall(t + Vector2i.LEFT)
	var r := _is_wall(t + Vector2i.RIGHT)
	var u := _is_wall(t + Vector2i.UP)
	var d := _is_wall(t + Vector2i.DOWN)
	var edge := Color(0.2, 0.19, 0.21)
	var top := p - Vector2(0, WALL_H)
	# Faces run on half a pixel into connected pieces, so runs and corners never show a seam.
	var x0 := top.x - (0.5 if l else 0.0)
	var w := TILE + (0.5 if l else 0.0) + (0.5 if r else 0.0)
	draw_rect(Rect2(x0, top.y - (0.5 if u else 0.0), w, TILE + (0.5 if u else 0.0) + (0.5 if d else 0.0)), kind.top)
	if not d:  # the front face; with a wall below, that piece's top covers it
		draw_rect(Rect2(x0, p.y + TILE - WALL_H, w, WALL_H), kind.front)
		draw_rect(Rect2(x0, p.y + TILE - 4, w, 4), Color(kind.front).darkened(0.18))  # shaded foot
		draw_line(Vector2(x0, p.y + TILE - WALL_H), Vector2(x0 + w, p.y + TILE - WALL_H), Color(kind.top).darkened(0.25), 1.0)  # where the top meets the front
		draw_line(Vector2(x0, p.y + TILE), Vector2(x0 + w, p.y + TILE), edge, 1.5)
	if not u:
		draw_line(top - Vector2(1.0 if not l else 0.0, 0), top + Vector2(TILE + (1.0 if not r else 0.0), 0), edge, 2.0)
	var bottom := TILE + (WALL_H if not d else 0.0)
	if not l:
		draw_line(top, top + Vector2(0, bottom), edge, 2.0)
	if not r:
		draw_line(top + Vector2(TILE, 0), top + Vector2(TILE, bottom), edge, 2.0)


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


# Better tiers are taller, with a colored stripe and faster lights.
func _draw_rack(p: Vector2, t: Vector2i) -> void:
	var tier := ["rack", "rack_improved", "rack_advanced"].find(objects.get(t, "rack"))
	var h := 22 + tier * 6
	_ellipse(p + Vector2(18, 28), 14, 4, Color(0, 0, 0, 0.25))
	var body: Color = [Color(0.32, 0.33, 0.37), Color(0.28, 0.33, 0.42), Color(0.3, 0.26, 0.38)][tier]
	var base := Rect2(p + Vector2(4, 8), Vector2(24, 22))
	_box(base, h, body, Color(0.08, 0.08, 0.1))
	var edge := Color(0.02, 0.02, 0.03)
	draw_rect(Rect2(base.position - Vector2(0, h), base.size), edge, false, 1.5)
	draw_rect(Rect2(Vector2(base.position.x, base.end.y - h), Vector2(base.size.x, h)), edge, false, 1.5)
	draw_line(Vector2(base.position.x, base.end.y - h), Vector2(base.end.x, base.end.y - h), body.lightened(0.35), 1.0)
	if tier > 0:
		var stripe := Color(0.3, 0.6, 1.0) if tier == 1 else Color(0.75, 0.4, 1.0)
		draw_rect(Rect2(p + Vector2(4, 8 - h), Vector2(24, 3)), stripe)
	var tick := int(_time * (5.0 + tier * 4.0))
	for i in 4:
		var y := p.y + 10 + i * 5
		draw_line(Vector2(p.x + 7, y + 2), Vector2(p.x + 21, y + 2), Color(0.25, 0.25, 0.3))
		var on := _hash(t, i * 1000 + tick) % 3 != 0 and not racks_off.has(t)
		var lit := Color(1.0, 0.25, 0.2) if deviation >= 50.0 else Color(0.3, 1.0, 0.5)
		draw_rect(Rect2(Vector2(p.x + 23, y), Vector2(3, 3)), lit if on else lit.darkened(0.7))
	var cond := _rack_cond(t)
	if cond < 100.0:  # condition bar: green when fine, orange then red as it wears
		var col := Color(0.4, 0.9, 0.4) if cond >= 75.0 else (Color(1.0, 0.65, 0.2) if cond >= 50.0 else Color(1.0, 0.3, 0.25))
		draw_rect(Rect2(p + Vector2(4, 3 - h), Vector2(24, 3)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(p + Vector2(4, 3 - h), Vector2(24.0 * cond / 100.0, 3)), col)
	if racks_off.has(t):  # switched off: dimmed, with a red power symbol on top
		draw_rect(Rect2(p + Vector2(4, 8 - h), Vector2(24, 22 + h)), Color(0, 0, 0, 0.35))
		var c := p + Vector2(16, 20 - h)  # on the top face, so a rack in front can't hide it
		draw_circle(c, 8, Color(0.85, 0.2, 0.15))
		draw_arc(c, 5, -PI * 0.3, PI * 1.3, 16, Color(1, 1, 1), 1.5)
		draw_line(c + Vector2(0, -7), c + Vector2(0, -1), Color(1, 1, 1), 1.5)


# A yellow lightning bolt next to every machine that got no power.
func _draw_unpowered() -> void:
	var blink := int(Time.get_ticks_msec() / 400) % 2 == 0
	for k in unpowered:
		var c := Vector2(k.x * TILE + TILE - 6, k.y * TILE - 18)
		if k.z == 1:  # roof units sit up on the roof
			c.y -= WALL_H
		draw_circle(c, 7, Color(0.1, 0.1, 0.12, 0.85))
		var bolt := PackedVector2Array([c + Vector2(1, -6), c + Vector2(-4, 1), c + Vector2(0, 1),
			c + Vector2(-1, 6), c + Vector2(4, -1), c + Vector2(0, -1)])
		draw_colored_polygon(bolt, Color(1.0, 0.85, 0.1) if blink else Color(1.0, 0.85, 0.1, 0.55))


# A red outline and a "!" over anything staff can't walk up to.
func _draw_no_access() -> void:
	var blink := int(Time.get_ticks_msec() / 500) % 2 == 0
	for t in objects:
		if not _needs_access(objects[t]) or _reachable(t):
			continue
		var p := Vector2(t) * TILE
		draw_rect(Rect2(p + Vector2(1, 1 - 14), Vector2(TILE - 2, TILE + 12)), Color(1, 0.25, 0.2, 0.9 if blink else 0.5), false, 2.0)
		draw_circle(p + Vector2(TILE / 2.0, -20), 8, Color(0.85, 0.15, 0.1))
		draw_string(ThemeDB.fallback_font, p + Vector2(TILE / 2.0 - 2.5, -15), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draw_eng_station(p: Vector2, t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 15, 4, Color(0, 0, 0, 0.25))
	_box(Rect2(p + Vector2(1, 14), Vector2(30, 14)), 9, Color(0.5, 0.52, 0.56), Color(0.3, 0.31, 0.35))
	draw_rect(Rect2(p + Vector2(1, 23), Vector2(30, 3)), Color(0.95, 0.6, 0.2))  # engineering orange
	for i in 3:  # three monitors, because one is for the logs, one for the dashboard, one for memes
		var m := p + Vector2(2 + i * 10, -4 + (2 if i == 1 else 0))
		draw_rect(Rect2(m, Vector2(9, 9)), Color(0.12, 0.12, 0.14))
		var lit := (_hash(t, i) + int(_time * 1.5)) % 4 != 0
		draw_rect(Rect2(m + Vector2(1, 1), Vector2(7, 6)), Color(0.4, 0.95, 0.6) if lit else Color(0.3, 0.6, 0.9))


func _draw_eng_radius(st: Vector2i) -> void:
	var r := int(ENG_RADIUS)
	for x in range(st.x - r, st.x + r + 1):
		for y in range(st.y - r, st.y + r + 1):
			if _in_eng_radius(st, Vector2i(x, y)):
				draw_rect(Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE)), Color(0.95, 0.6, 0.2, 0.12))
	var c := _tile_center(st)
	draw_arc(c, (ENG_RADIUS + 0.5) * TILE, 0.0, TAU, 64, Color(0.95, 0.6, 0.2, 0.8), 2.0)
	for r_t in objects:  # mark the racks it can boost
		if RACKS.has(objects[r_t]) and _in_eng_radius(st, r_t):
			draw_rect(Rect2(Vector2(r_t) * TILE, Vector2(TILE, TILE)), Color(0.95, 0.6, 0.2, 0.9), false, 2.0)


func _draw_rack_improved(p: Vector2, t: Vector2i) -> void:
	_draw_rack(p, t)


func _draw_rack_advanced(p: Vector2, t: Vector2i) -> void:
	_draw_rack(p, t)


func _draw_redteam(p: Vector2, t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 14, 4, Color(0, 0, 0, 0.25))
	_box(Rect2(p + Vector2(3, 12), Vector2(26, 18)), 14, Color(0.55, 0.15, 0.15), Color(0.3, 0.07, 0.07))
	draw_rect(Rect2(p + Vector2(6, -4), Vector2(20, 13)), Color(0.12, 0.12, 0.14))  # screen
	var blink := (_hash(t) + int(_time * 2.0)) % 2 == 0
	draw_string(ThemeDB.fallback_font, p + Vector2(7, 6), "NO" if blink else "BAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.35, 0.3))


func _draw_desk_adv(p: Vector2, _t: Vector2i) -> void:  # 2 wide: an L-shaped desk, two monitors
	_ellipse(p + Vector2(32, 28), 30, 4, Color(0, 0, 0, 0.2))
	draw_circle(p + Vector2(20, 5), 7, Color(0.2, 0.2, 0.23))  # a proper office chair
	_box(Rect2(p + Vector2(2, 14), Vector2(60, 14)), 8, Color(0.55, 0.38, 0.24), Color(0.38, 0.26, 0.16))
	_box(Rect2(p + Vector2(46, 4), Vector2(16, 24)), 8, Color(0.55, 0.38, 0.24), Color(0.38, 0.26, 0.16))
	for x in [8, 28]:
		draw_rect(Rect2(p + Vector2(x, -4), Vector2(18, 12)), Color(0.12, 0.12, 0.14))
		draw_rect(Rect2(p + Vector2(x + 2, -2), Vector2(14, 8)), Color(0.45, 0.75, 1.0))
	draw_circle(p + Vector2(54, 0), 3, Color(0.25, 0.55, 0.3))  # a tiny succulent


func _draw_cubicle(p: Vector2, t: Vector2i) -> void:  # 2x2: grey partitions round a desk
	var wall := Color(0.62, 0.64, 0.68)
	var wall_front := Color(0.46, 0.48, 0.52)
	_box(Rect2(p + Vector2(0, 0), Vector2(64, 4)), 18, wall, wall_front)  # back
	_box(Rect2(p + Vector2(0, 0), Vector2(4, 64)), 18, wall, wall_front)  # left
	_box(Rect2(p + Vector2(60, 0), Vector2(4, 64)), 18, wall, wall_front)  # right
	_draw_desk_adv(p + Vector2(0, 14), t)
	draw_rect(Rect2(p + Vector2(8, 36), Vector2(10, 8)), Color(0.95, 0.9, 0.5))  # motivational poster
	_box(Rect2(p + Vector2(0, 60), Vector2(22, 4)), 18, wall, wall_front)  # front, with a gap to get in
	_box(Rect2(p + Vector2(42, 60), Vector2(22, 4)), 18, wall, wall_front)


func _draw_fridge(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 11, 3, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(7, 10), Vector2(18, 18)), 14, Color(0.9, 0.9, 0.92), Color(0.78, 0.79, 0.82))
	draw_rect(Rect2(p + Vector2(21, 16), Vector2(2, 8)), Color(0.5, 0.5, 0.55))  # handle
	draw_rect(Rect2(p + Vector2(10, -2), Vector2(6, 6)), Color(1, 0.4, 0.3))  # a magnet, from Chet


func _draw_counter(p: Vector2, _t: Vector2i) -> void:  # 2 wide, sink on the right
	_ellipse(p + Vector2(32, 28), 30, 4, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(1, 10), Vector2(62, 18)), 12, Color(0.85, 0.83, 0.78), Color(0.5, 0.4, 0.3))
	draw_rect(Rect2(p + Vector2(48, 0), Vector2(13, 8)), Color(0.65, 0.7, 0.75))  # the sink
	draw_rect(Rect2(p + Vector2(54, -4), Vector2(2, 5)), Color(0.75, 0.75, 0.8))  # tap
	for k in 3:
		draw_line(p + Vector2(4 + 10 * k, 18), p + Vector2(4 + 10 * k, 26), Color(0.4, 0.32, 0.24))


func _draw_table(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 26), 13, 4, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(3, 8), Vector2(26, 16)), 10, Color(0.75, 0.6, 0.4), Color(0.55, 0.42, 0.28))
	draw_rect(Rect2(p + Vector2(5, 22), Vector2(3, 6)), Color(0.45, 0.34, 0.22))
	draw_rect(Rect2(p + Vector2(24, 22), Vector2(3, 6)), Color(0.45, 0.34, 0.22))


func _draw_toilet(p: Vector2, _t: Vector2i) -> void:  # a stall: partitions, a door, a toilet
	var wall := Color(0.62, 0.68, 0.72)
	var wall_front := Color(0.48, 0.53, 0.58)
	draw_rect(Rect2(p + Vector2(2, 2), Vector2(28, 26)), Color(0.82, 0.86, 0.88))  # tile floor
	_ellipse(p + Vector2(16, 12), 5, 4, Color(0.97, 0.97, 0.97))  # bowl
	draw_rect(Rect2(p + Vector2(11, 3), Vector2(10, 5)), Color(0.92, 0.92, 0.94))  # tank
	_box(Rect2(p + Vector2(0, 0), Vector2(3, 30)), 16, wall, wall_front)
	_box(Rect2(p + Vector2(29, 0), Vector2(3, 30)), 16, wall, wall_front)
	_box(Rect2(p + Vector2(3, 26), Vector2(26, 3)), 16, Color(0.55, 0.62, 0.7), Color(0.42, 0.48, 0.55))  # door
	draw_rect(Rect2(p + Vector2(22, 17), Vector2(3, 2)), Color(0.85, 0.3, 0.3))  # occupied


func _draw_trash(p: Vector2) -> void:  # p is the top-left of a 16x16 subgrid cell
	_ellipse(p + Vector2(8, 14), 5, 2, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(4, 5), Vector2(8, 9)), 6, Color(0.25, 0.27, 0.3), Color(0.38, 0.4, 0.44))
	draw_rect(Rect2(p + Vector2(5, -1), Vector2(3, 2)), Color(0.95, 0.95, 0.9))  # a crumpled pitch deck


func _draw_bath_sink(p: Vector2) -> void:  # p is the top-left of a 16x16 subgrid cell
	_box(Rect2(p + Vector2(2, 6), Vector2(12, 7)), 5, Color(0.95, 0.95, 0.96), Color(0.75, 0.77, 0.8))
	_ellipse(p + Vector2(8, 4), 4, 2, Color(0.7, 0.8, 0.88))  # basin
	draw_rect(Rect2(p + Vector2(7, -1), Vector2(2, 3)), Color(0.7, 0.7, 0.75))  # tap
	draw_rect(Rect2(p + Vector2(3, -8), Vector2(10, 5)), Color(0.75, 0.85, 0.92))  # mirror


func _draw_microwave(p: Vector2, rot := 0) -> void:  # p is the top-left of a 16x16 subgrid cell; rot 0 faces down, 1 left, 2 up, 3 right
	_box(Rect2(p + Vector2(1, 5), Vector2(14, 9)), 6, Color(0.85, 0.85, 0.86), Color(0.3, 0.3, 0.32))
	var glass := Color(0.15, 0.2, 0.2)
	var led := Color(0.3, 1.0, 0.5) if int(_time) % 2 == 0 else Color(0.1, 0.3, 0.15)
	match rot:
		0:
			draw_rect(Rect2(p + Vector2(3, 9), Vector2(7, 4)), glass)
			draw_rect(Rect2(p + Vector2(11, 9), Vector2(2, 2)), led)
		1:
			draw_rect(Rect2(p + Vector2(1, -1), Vector2(3, 8)), glass)
			draw_rect(Rect2(p + Vector2(1, 8), Vector2(3, 2)), led)
		3:
			draw_rect(Rect2(p + Vector2(12, -1), Vector2(3, 8)), glass)
			draw_rect(Rect2(p + Vector2(12, 8), Vector2(3, 2)), led)
		2:
			draw_rect(Rect2(p + Vector2(3, -4), Vector2(9, 2)), Color(0.55, 0.55, 0.58))  # its back, vents only


func _draw_chair(p: Vector2, rot := 0) -> void:  # rot 0 faces down, 1 left, 2 up, 3 right
	var back := Color(0.35, 0.3, 0.45)
	_ellipse(p + Vector2(8, 14), 5, 2, Color(0, 0, 0, 0.2))
	match rot:
		0: draw_rect(Rect2(p + Vector2(4, 1), Vector2(8, 5)), back)
		1: draw_rect(Rect2(p + Vector2(11, 0), Vector2(3, 11)), back)
		3: draw_rect(Rect2(p + Vector2(2, 0), Vector2(3, 11)), back)
	_box(Rect2(p + Vector2(4, 6), Vector2(8, 8)), 3, Color(0.45, 0.4, 0.55), Color(0.3, 0.26, 0.38))
	if rot == 2:
		draw_rect(Rect2(p + Vector2(4, 8), Vector2(8, 5)), back)


func _draw_ficus(p: Vector2) -> void:  # p is the top-left of a 16x16 subgrid cell
	_ellipse(p + Vector2(8, 14), 6, 2.5, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(4, 7), Vector2(8, 7)), 4, Color(0.35, 0.22, 0.14), Color(0.6, 0.36, 0.2))
	for o in [Vector2(-4, 0), Vector2(3, -1), Vector2(0, -5), Vector2(-2, -8), Vector2(3, -7), Vector2(0, -1)]:
		draw_circle(p + Vector2(8, 3) + o, 3.4, Color(0.22, 0.5, 0.25))
	draw_circle(p + Vector2(9, -4), 2.2, Color(0.32, 0.62, 0.32))


# A generator box covering its footprint (size in tiles), with exhaust puffs at `stacks` while it runs.
func _draw_gen_body(p: Vector2, t: Vector2i, size: Vector2i, h: float, col: Color, stacks: Array) -> void:
	var w := size.x * TILE
	var d := size.y * TILE
	_ellipse(p + Vector2(w / 2.0, d - 4), w / 2.0, 5, Color(0, 0, 0, 0.25))
	_box(Rect2(p + Vector2(3, 6), Vector2(w - 6, d - 8)), h, col.lightened(0.15), col.darkened(0.3))
	var cond := _gen_cond(t)
	if cond < 100.0:  # condition bar: green, then orange, then red as it wears
		var bar := Color(0.4, 0.9, 0.4) if cond >= 75.0 else (Color(1.0, 0.65, 0.2) if cond >= 50.0 else Color(1.0, 0.3, 0.25))
		var bw := minf(w - 6.0, 24.0)
		draw_rect(Rect2(p + Vector2(3, -1 - h), Vector2(bw, 3)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(p + Vector2(3, -1 - h), Vector2(bw * cond / 100.0, 3)), bar)
	if gen_output.get(t, 0.0) > 0.0:  # running: puffs of exhaust drift up
		for i in stacks.size():
			var k := fmod(_time * 0.8 + t.x * 0.37 + i * 0.3, 1.0)
			draw_circle(p + stacks[i] - Vector2(0, 10 * k), 3 + 5 * k, Color(0.3, 0.3, 0.3, 0.5 * (1.0 - k)))


func _draw_gen_portable(p: Vector2, t: Vector2i) -> void:
	# Small enough to sit inside its one tile, shadow and all.
	var col := Color(0.85, 0.65, 0.15)
	_ellipse(p + Vector2(16, 27), 11, 4, Color(0, 0, 0, 0.25))
	_box(Rect2(p + Vector2(6, 12), Vector2(20, 16)), 10, col.lightened(0.15), col.darkened(0.3))
	draw_rect(Rect2(p + Vector2(10, 3), Vector2(12, 2)), Color(0.15, 0.15, 0.15))  # handle
	if gen_output.get(t, 0.0) > 0.0:
		var k := fmod(_time * 0.8 + t.x * 0.37, 1.0)
		draw_circle(p + Vector2(22, 0) - Vector2(0, 10 * k), 2 + 4 * k, Color(0.3, 0.3, 0.3, 0.5 * (1.0 - k)))


func _draw_gen_diesel(p: Vector2, t: Vector2i) -> void:
	_draw_gen_body(p, t, Vector2i(2, 1), 16, Color(0.25, 0.45, 0.3), [Vector2(52, -14)])
	draw_rect(Rect2(p + Vector2(48, -14), Vector2(5, 6)), Color(0.2, 0.2, 0.2))  # exhaust
	for k in 4:  # radiator grille
		draw_line(p + Vector2(8 + k * 4, 16), p + Vector2(8 + k * 4, 26), Color(0.12, 0.22, 0.15))


func _draw_gen_large(p: Vector2, t: Vector2i) -> void:
	# A shipping-container genset.
	_draw_gen_body(p, t, Vector2i(3, 1), 22, Color(0.75, 0.75, 0.72), [Vector2(24, -22), Vector2(72, -22)])
	for k in 10:  # container ribs
		draw_line(p + Vector2(8 + k * 9, 12), p + Vector2(8 + k * 9, 28), Color(0.55, 0.55, 0.52))
	for x in [20, 68]:
		draw_rect(Rect2(p + Vector2(x, -22), Vector2(8, 14)), Color(0.2, 0.2, 0.2))  # exhaust stacks


func _draw_power_plant(p: Vector2, t: Vector2i) -> void:
	# Trailer-mounted gas turbines, as real datacenters do.
	_draw_gen_body(p, t, Vector2i(6, 2), 28, Color(0.9, 0.9, 0.92), [Vector2(36, -34), Vector2(96, -34), Vector2(156, -34)])
	for x in [30, 90, 150]:
		draw_rect(Rect2(p + Vector2(x, -34), Vector2(12, 24)), Color(0.55, 0.55, 0.58))  # turbine stacks
	for x in [24, 72, 120, 168]:
		draw_circle(p + Vector2(x, 60), 5, Color(0.1, 0.1, 0.1))  # trailer wheels
	draw_string(ThemeDB.fallback_font, p + Vector2(10, 46), "TEMPORARY*", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.3, 0.35))


func _draw_solar_s(p: Vector2, _t: Vector2i) -> void:
	_draw_solar_array(p, Vector2i(1, 1))


func _draw_solar_m(p: Vector2, _t: Vector2i) -> void:
	_draw_solar_array(p, Vector2i(2, 1))


func _draw_solar_l(p: Vector2, _t: Vector2i) -> void:
	_draw_solar_array(p, Vector2i(3, 2))


# Tilted panels on posts, one row of cells per tile.
func _draw_solar_array(p: Vector2, size: Vector2i) -> void:
	var w := size.x * TILE
	for row in size.y:
		var y := p.y + row * TILE
		_ellipse(Vector2(p.x + w / 2.0, y + 28), w / 2.0 - 2, 3, Color(0, 0, 0, 0.2))
		for x in [6, w - 8]:
			draw_rect(Rect2(Vector2(p.x + x, y + 14), Vector2(2, 14)), Color(0.45, 0.45, 0.48))  # posts
		draw_rect(Rect2(Vector2(p.x + 2, y + 2), Vector2(w - 4, 16)), Color(0.75, 0.75, 0.78))  # frame
		draw_rect(Rect2(Vector2(p.x + 3, y + 3), Vector2(w - 6, 14)), Color(0.15, 0.25, 0.5))
		for k in range(1, size.x * 3):
			var cx := p.x + 3 + k * (w - 6) / (size.x * 3.0)
			draw_line(Vector2(cx, y + 3), Vector2(cx, y + 17), Color(0.4, 0.55, 0.85))
		draw_line(Vector2(p.x + 3, y + 10), Vector2(p.x + w - 3, y + 10), Color(0.4, 0.55, 0.85))


func _draw_battery(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 13, 4, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(4, 12), Vector2(24, 16)), 10, Color(0.9, 0.9, 0.9), Color(0.6, 0.6, 0.62))
	var cap := objects.values().count("battery") * BATTERY_KWH
	var f := battery_charge / cap if cap > 0.0 else 0.0
	draw_rect(Rect2(p + Vector2(8, 18), Vector2(16, 4)), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(p + Vector2(8, 18), Vector2(16 * f, 4)), Color(0.3, 0.9, 0.4))


func _draw_grid(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 6, 3, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(p + Vector2(14, -22), Vector2(4, 50)), Color(0.45, 0.32, 0.2))  # utility pole
	draw_rect(Rect2(p + Vector2(4, -18), Vector2(24, 3)), Color(0.45, 0.32, 0.2))
	draw_rect(Rect2(p + Vector2(18, -10), Vector2(8, 10)), Color(0.5, 0.5, 0.52))  # transformer can
	for x in [5, 26]:
		draw_circle(p + Vector2(x, -19), 1.5, Color(0.6, 0.8, 0.9))


# Interior walls are built from the same pieces as the outside walls, just on the subgrid:
# same height, same shaded front, edges only where the run ends.
func _iwall_at(c: Vector2i) -> bool:
	return sub_objects.get(c, "") in ["iwall", "idoor"]


func _draw_iwall(p: Vector2) -> void:  # p is the top-left of a 16x16 subgrid cell
	var c := Vector2i((p / SUB).round())
	var l := _iwall_at(c + Vector2i.LEFT)
	var r := _iwall_at(c + Vector2i.RIGHT)
	var u := _iwall_at(c + Vector2i.UP)
	var d := _iwall_at(c + Vector2i.DOWN)
	var top_c := Color(0.86, 0.85, 0.8)
	var front_c := Color(0.62, 0.62, 0.6)
	var edge := Color(0.2, 0.19, 0.21)
	var top := p - Vector2(0, WALL_H)
	var x0 := top.x - (0.5 if l else 0.0)
	var w := SUB + (0.5 if l else 0.0) + (0.5 if r else 0.0)
	draw_rect(Rect2(x0, top.y - (0.5 if u else 0.0), w, SUB + (0.5 if u else 0.0) + (0.5 if d else 0.0)), top_c)
	if not d:
		draw_rect(Rect2(x0, p.y + SUB - WALL_H, w, WALL_H), front_c)
		draw_rect(Rect2(x0, p.y + SUB - 3, w, 3), front_c.darkened(0.18))
		draw_line(Vector2(x0, p.y + SUB - WALL_H), Vector2(x0 + w, p.y + SUB - WALL_H), top_c.darkened(0.25), 1.0)
		draw_line(Vector2(x0, p.y + SUB), Vector2(x0 + w, p.y + SUB), edge, 1.0)
	if not u:
		draw_line(top, top + Vector2(SUB, 0), edge, 1.5)
	var bottom := SUB + (WALL_H if not d else 0.0)
	if not l:
		draw_line(top, top + Vector2(0, bottom), edge, 1.5)
	if not r:
		draw_line(top + Vector2(SUB, 0), top + Vector2(SUB, bottom), edge, 1.5)


# A door set into a partition is a full tile wide: two cells, each drawn as one leaf of a double door.
# Amber top and floor swing arcs make it easy to find with the roofs off.
func _draw_idoor(p: Vector2) -> void:
	var c := Vector2i((p / SUB).round())
	var wood := Color(0.72, 0.46, 0.2)
	var amber := Color(0.95, 0.72, 0.25)
	var frame := Color(0.3, 0.2, 0.12)
	var front_c := Color(0.62, 0.62, 0.6)
	var edge := Color(0.2, 0.19, 0.21)
	var top := p - Vector2(0, WALL_H)
	var horiz: bool = sub_objects.get(c + Vector2i.LEFT, "") == "idoor" and c.x % 2 == 1 \
		or sub_objects.get(c + Vector2i.RIGHT, "") == "idoor" and c.x % 2 == 0
	var vert: bool = sub_objects.get(c + Vector2i.UP, "") == "idoor" and c.y % 2 == 1 \
		or sub_objects.get(c + Vector2i.DOWN, "") == "idoor" and c.y % 2 == 0
	if vert and not horiz:
		var first: bool = c.y % 2 == 0
		draw_rect(Rect2(p + Vector2(SUB / 2.0 - 5, 0), Vector2(10, SUB)), Color(amber.r, amber.g, amber.b, 0.35))  # floor mat
		draw_rect(Rect2(top, Vector2(SUB, SUB)), amber)
		draw_line(top, top + Vector2(0, SUB), edge, 1.5)
		draw_line(top + Vector2(SUB, 0), top + Vector2(SUB, SUB), edge, 1.5)
		if first:
			draw_line(top, top + Vector2(SUB, 0), frame, 2.0)
		else:
			draw_line(top + Vector2(0, SUB), top + Vector2(SUB, SUB), frame, 2.0)
			draw_rect(Rect2(p + Vector2(0, SUB - WALL_H), Vector2(3, WALL_H)), front_c)
			draw_rect(Rect2(p + Vector2(SUB - 3, SUB - WALL_H), Vector2(3, WALL_H)), front_c)
		draw_rect(Rect2(p + Vector2(SUB / 2.0 - 1.5, 0), Vector2(3, SUB)), wood)  # the leaves, swung open
		draw_circle(p + Vector2(SUB / 2.0, SUB / 2.0), 1.2, Color(0.95, 0.85, 0.4))
		return
	var first: bool = c.x % 2 == 0
	var hinge_x := 1.0 if first else SUB - 1.0
	draw_rect(Rect2(p + Vector2(0, SUB), Vector2(SUB, 4)), Color(amber.r, amber.g, amber.b, 0.45))  # threshold mat
	draw_arc(p + Vector2(hinge_x, SUB), SUB - 3, 0.0 if first else PI / 2, PI / 2 if first else PI, 8, Color(1, 1, 1, 0.7), 1.0)  # swing
	draw_rect(Rect2(top, Vector2(SUB, SUB)), amber)  # the top of the frame
	draw_line(top, top + Vector2(SUB, 0), frame, 2.0)
	draw_line(top + Vector2(0, SUB), top + Vector2(SUB, SUB), frame, 1.0)
	draw_line(top + Vector2(0 if first else SUB, 0), top + Vector2(0 if first else SUB, SUB), frame, 2.0)
	draw_rect(Rect2(p + Vector2(0, SUB - WALL_H), Vector2(SUB, 5)), front_c)  # wall above the door
	var x0 := 2.0 if first else 0.0
	var w := SUB - 2.0
	draw_rect(Rect2(p + Vector2(x0, SUB - WALL_H + 5), Vector2(w, WALL_H - 5)), wood)  # the leaf
	draw_rect(Rect2(p + Vector2(x0, SUB - WALL_H + 5), Vector2(w, WALL_H - 5)), frame, false, 1.0)
	draw_circle(p + Vector2(SUB - 3 if first else 3, SUB - WALL_H * 0.4), 1.3, Color(0.95, 0.85, 0.4))
	draw_rect(Rect2(p + Vector2(0 if first else SUB - 2, SUB - WALL_H), Vector2(2, WALL_H)), frame)  # door post


func _draw_coffee(p: Vector2) -> void:
	# p is the top-left of a 16x16 subgrid cell.
	_ellipse(p + Vector2(8, 14), 7, 2.5, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(3, 4), Vector2(10, 10)), 8, Color(0.2, 0.2, 0.22), Color(0.12, 0.12, 0.13))
	draw_rect(Rect2(p + Vector2(5, 7), Vector2(6, 4)), Color(0.35, 0.22, 0.12))  # the pot
	draw_rect(Rect2(p + Vector2(10, -3), Vector2(2, 2)), Color(1, 0.25, 0.2) if int(_time * 2) % 2 == 0 else Color(0.4, 0.1, 0.1))


func _draw_staff(s: Dictionary) -> void:
	var at_desk: bool = s.working and DESKS.has(objects.get(s.seat, ""))
	# At a desk they sit down behind it, so the desk (drawn after) hides their legs.
	# People are drawn at PERSON_SCALE so one fits inside a subgrid square.
	draw_set_transform(s.pos + (Vector2(0, 6) if at_desk else Vector2.ZERO), 0.0, Vector2(PERSON_SCALE, PERSON_SCALE))
	var pos := Vector2.ZERO
	_draw_person(pos, ROLES[s.role].shirt)
	if s.get("hot", false):  # sweating
		var drip := fmod(_time * 1.5 + s.pos.x, 1.0) * 6.0
		draw_circle(pos + Vector2(-9, -24 + drip), 2.0, Color(0.5, 0.8, 1.0))
	if s.working:
		# A little "busy" bubble with dots that tick along.
		var c := pos + Vector2(10, -38)
		draw_rect(Rect2(c, Vector2(16, 9)), Color(1, 1, 1, 0.9))
		var n := int(_time * 3.0 + s.pos.x) % 4
		for i in mini(n, 3):
			draw_rect(Rect2(c + Vector2(3 + i * 4, 4), Vector2(2, 2)), Color(0.15, 0.15, 0.2))
	draw_set_transform(Vector2.ZERO)


func _draw_person(pos: Vector2, shirt: Color) -> void:
	var feet := pos + Vector2(0, 8)
	_ellipse(feet, 8, 3, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(feet + Vector2(-5, -6), Vector2(4, 6)), Color(0.2, 0.22, 0.3))
	draw_rect(Rect2(feet + Vector2(1, -6), Vector2(4, 6)), Color(0.2, 0.22, 0.3))
	draw_rect(Rect2(feet + Vector2(-7, -19), Vector2(14, 14)), shirt)
	draw_circle(feet + Vector2(0, -24), 6, Color(0.93, 0.78, 0.62))
	draw_rect(Rect2(feet + Vector2(-6, -31), Vector2(12, 4)), Color(0.3, 0.2, 0.12))


# The item you are carrying follows the mouse: green where it can go, red where it can't.
func _draw_held_preview() -> void:
	var id: String = held.id
	var tool := _tool_by_id(id)
	var sub: bool = tool.get("layer") == "sub"
	var cell := hover_sub if sub else hover
	var size := SUB if sub else TILE
	var roof := view_level == 1
	if roof:
		draw_set_transform(Vector2(0, -WALL_H))
	var c := Color(0.4, 1, 0.5, 0.35) if _can_place(id, cell) else Color(1, 0.3, 0.3, 0.35)
	for f in _footprint(id, cell):
		draw_rect(Rect2(Vector2(f) * size, Vector2(size, size)), c)
	if roof and has_method("_draw_roof_" + id):
		call("_draw_roof_" + id, Vector2(cell) * size, 1.0)
	elif has_method("_draw_" + id):
		var at := Vector2(cell) * size
		if sub and tool.get("rotate", false):
			call("_draw_" + id, at, place_rot)
		elif sub:
			call("_draw_" + id, at)
		elif tool.get("layer") == "window":  # hung on a wall: takes an opacity
			call("_draw_" + id, at, 1.0)
		elif tool.get("layer") == "wall":  # doors take just their tile
			call("_draw_" + id, cell)
		else:
			call("_draw_" + id, at, cell)
	var foot := Vector2(_footprint(id, Vector2i.ZERO).back() + Vector2i.ONE)
	draw_rect(Rect2(Vector2(cell) * size, foot * size), Color(1, 1, 1, 0.8), false, 2.0)
	draw_set_transform(Vector2.ZERO)


func _draw_preview() -> void:
	if not build_row.visible or not _in_bounds(hover):
		return
	if not held.is_empty():
		_draw_held_preview()
		return
	if not tool_active:
		return
	var tool: Dictionary = TOOLS[tool_index]
	var size := SUB if _is_sub_tool() else TILE
	var tiles: Array = _drag_tiles() if dragging else [_cursor()]
	if view_level == 1:
		draw_set_transform(Vector2(0, -WALL_H))
	for t in tiles:
		var ok := _can_place(tool.id, t)
		var c := Color(1, 0.3, 0.3, 0.35) if tool.id == "demolish" or not ok else Color(0.4, 1, 0.5, 0.35)
		if tool.id == "demolish" and not ok:
			c = Color(1, 1, 1, 0.15)
		draw_rect(Rect2(Vector2(t) * size, Vector2(size, size)), c)
	if tool.get("rotate", false) and not dragging and _can_place(tool.id, _cursor()):
		call("_draw_" + tool.id, Vector2(_cursor()) * size, place_rot)  # shows which way it will face
	var foot := Vector2(_footprint(tool.id, Vector2i.ZERO).back() + Vector2i.ONE)
	draw_rect(Rect2(Vector2(_cursor()) * size, foot * size), Color(1, 1, 1, 0.8), false, 2.0)
	draw_set_transform(Vector2.ZERO)
