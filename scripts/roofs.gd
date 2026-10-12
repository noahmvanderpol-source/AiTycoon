extends "res://scripts/heat.gd"
## Roofs. Part of the Main script chain (see scripts/README.md).

func _find_buildings() -> void:
	# Anything the outside can't reach without crossing a wall or door is indoors.
	var outside := {}
	var stack := []
	for x in GRID_W:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, GRID_H - 1))
	for y in GRID_H:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(GRID_W - 1, y))
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		if not _in_bounds(t) or outside.has(t) or wall_tiles.has(t):
			continue
		outside[t] = true
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			stack.append(t + d)

	# Each connected indoor area plus the walls around it is one roof.
	var old := buildings
	buildings = []
	var seen := {}
	for x in GRID_W:
		for y in GRID_H:
			var start := Vector2i(x, y)
			if seen.has(start) or outside.has(start) or wall_tiles.has(start):
				continue
			var tiles := {}
			stack = [start]
			while not stack.is_empty():
				var t: Vector2i = stack.pop_back()
				if seen.has(t) or outside.has(t) or not _in_bounds(t):
					continue
				if wall_tiles.has(t):
					tiles[t] = true
					continue
				seen[t] = true
				tiles[t] = true
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						var n: Vector2i = t + Vector2i(dx, dy)
						if wall_tiles.has(n):
							tiles[n] = true
						elif dx == 0 or dy == 0:
							stack.append(n)
			var alpha := 1.0
			for o in old:  # keep the fade state of a building that already existed
				if o.tiles.has(start):
					alpha = o.alpha
			var area := 0
			for t in tiles:
				if not _is_wall(t):
					area += 1
			buildings.append({"tiles": tiles, "alpha": alpha, "area": area, "temp": INDOOR_TEMP})
	# Rooms that share a wall are one building: its whole roof lifts together.
	var group := range(buildings.size())
	var wall_owner := {}
	for i in buildings.size():
		for t in buildings[i].tiles:
			if not wall_tiles.has(t):
				continue
			if wall_owner.has(t):
				var a: int = group[wall_owner[t]]
				var b: int = group[i]
				for j in group.size():
					if group[j] == b:
						group[j] = a
			wall_owner[t] = i
	var union := {}  # group -> every tile of its rooms: one roof, drawn once
	var led := {}
	for i in buildings.size():
		buildings[i].group = group[i]
		if not union.has(group[i]):
			union[group[i]] = {}
		union[group[i]].merge(buildings[i].tiles)
	for i in buildings.size():
		buildings[i].roof_tiles = union[group[i]]
		buildings[i].lead = not led.has(group[i])  # the first room of a group draws its roof
		led[group[i]] = true
	var was_indoor := {}
	for t in heat_cells:
		was_indoor[t] = true
	room_of = {}
	for i in buildings.size():
		for t in buildings[i].tiles:
			room_of[t] = i
	# Tiles keep their temperature through rebuilds; newly enclosed ones start at room temperature,
	# and anything outdoors is the desert.
	heat_cells = []
	for t in room_of:
		if not _is_wall(t):
			heat_cells.append(t)
			if not was_indoor.has(t):
				_set_temp(t, INDOOR_TEMP)
	for t in was_indoor:
		if not _indoor(t):
			_set_temp(t, outdoor_temp)
	for bld in buildings:
		var total := 0.0
		for t in bld.tiles:
			if not _is_wall(t):
				total += _temp(t)
		bld.temp = total / maxi(bld.area, 1)
	for t in window_objects.keys():  # the wall left the building
		if not _roofed(t) or not _is_wall(t):
			money += int(_tool_by_id(window_objects[t]).cost / 2)
			window_objects.erase(t)
	for t in roof_objects.keys():  # the roof came down, and so did whatever was on it
		if roof_objects.has(t) and not _roofed(t):
			_remove_roof_object(roof_parts.get(t, t))


# Takes a roof object (and all its tiles) off, refunding half.
func _remove_roof_object(a: Vector2i) -> void:
	var id: String = roof_objects.get(a, "")
	money += int(_tool_by_id(id).get("cost", 0) / 2)
	for f in _footprint(id, a):
		if roof_parts.get(f) == a:
			roof_objects.erase(f)
			roof_parts.erase(f)
	roof_objects.erase(a)


func _roofed(t: Vector2i) -> bool:
	for bld in buildings:
		if bld.tiles.has(t):
			return true
	return false


func _draw_roof(bld: Dictionary) -> void:
	if bld.alpha <= 0.01 or not bld.lead:
		return
	var tiles: Dictionary = bld.roof_tiles
	var a: float = bld.alpha
	var lift := Vector2(0, WALL_H)  # the roof sits on top of the walls
	var fill := Color(0.56, 0.5, 0.45, a)
	var seam := Color(0.5, 0.44, 0.4, a)
	var edge := Color(0.32, 0.28, 0.26, a)
	var over := 0.6 if a >= 0.99 else 0.0  # a hair of overlap so neighbours never show a gap at odd zooms
	for t in tiles:
		var p := Vector2(t) * TILE - lift
		var size := Vector2(TILE + (over if tiles.has(t + Vector2i.RIGHT) else 0.0), TILE + (over if tiles.has(t + Vector2i.DOWN) else 0.0))
		draw_rect(Rect2(p, size), fill)
	for t in tiles:  # standing seams, at the same height on every tile so they run on across the join
		var p := Vector2(t) * TILE - lift
		for y in [10.0, 21.0]:
			draw_line(p + Vector2(0, y), p + Vector2(TILE + (over if tiles.has(t + Vector2i.RIGHT) else 0.0), y), seam, 1.0)
	for t in tiles:
		var p := Vector2(t) * TILE - lift
		var l := not tiles.has(t + Vector2i.LEFT)
		var r := not tiles.has(t + Vector2i.RIGHT)
		var u := not tiles.has(t + Vector2i.UP)
		var d := not tiles.has(t + Vector2i.DOWN)
		var x0 := -1.5 if l else 0.0  # edge lines run out past the corner so corners are filled in
		var x1 := TILE + (1.5 if r else 0.0)
		if u: draw_line(p + Vector2(x0, 0), p + Vector2(x1, 0), edge, 3.0)
		if l: draw_line(p + Vector2(0, -1.5 if u else 0.0), p + Vector2(0, TILE), edge, 3.0)
		if r: draw_line(p + Vector2(TILE, -1.5 if u else 0.0), p + Vector2(TILE, TILE), edge, 3.0)
		if d:
			draw_line(p + Vector2(x0, TILE), p + Vector2(x1, TILE), edge, 3.0)
			var front: Color = WALLS[wall_tiles[t]].front if _is_wall(t) else Color(0.3, 0.29, 0.32)
			draw_rect(Rect2(p + Vector2(x0 + (1.5 if l else 0.0) * 0.0, TILE), Vector2(x1 - x0, WALL_H)), Color(front, a))  # wall front below the eaves
			if window_objects.has(t):
				_draw_window_ac(p + Vector2(0, WALL_H), a)
			if wall_tiles.get(t) == "door":  # keep doors visible from outside
				draw_rect(Rect2(p + Vector2(6, TILE + 4), Vector2(TILE - 12, WALL_H - 4)), Color(0.62, 0.43, 0.25, a))
				draw_circle(p + Vector2(TILE - 10, TILE + WALL_H * 0.6), 1.5, Color(0.9, 0.8, 0.4, a))
		elif wall_tiles.get(t) == "door":  # side or back door: mark it on the roof edge
			draw_rect(Rect2(p + Vector2(8, 8), Vector2(TILE - 16, TILE - 16)), Color(0.62, 0.43, 0.25, a))
	for t in tiles:
		if roof_objects.has(t) and roof_objects[t] != "part":
			call("_draw_roof_" + roof_objects[t], Vector2(t) * TILE - lift, a)


func _draw_roof_solar(p: Vector2, a: float) -> void:
	draw_rect(Rect2(p + Vector2(2, 4), Vector2(28, 24)), Color(0.75, 0.75, 0.78, a))
	draw_rect(Rect2(p + Vector2(4, 6), Vector2(24, 20)), Color(0.15, 0.25, 0.5, a))
	for k in 3:
		draw_line(p + Vector2(4 + 8 * k, 6), p + Vector2(4 + 8 * k, 26), Color(0.4, 0.55, 0.85, a))
	draw_line(p + Vector2(4, 16), p + Vector2(28, 16), Color(0.4, 0.55, 0.85, a))


# A window unit on a wall's front face. p is the wall tile's top-left on the ground.
func _draw_window_ac(p: Vector2, a: float) -> void:
	var r := Rect2(p + Vector2(8, TILE - WALL_H + 6), Vector2(16, 12))
	draw_rect(r, Color(0.85, 0.85, 0.82, a))
	for k in 3:
		draw_line(r.position + Vector2(2, 3 + 3 * k), r.position + Vector2(14, 3 + 3 * k), Color(0.45, 0.45, 0.48, a))
	draw_rect(Rect2(r.position + Vector2(0, 12), Vector2(16, 2)), Color(0.3, 0.6, 0.9, a))  # it drips, obviously


func _draw_roof_solar_s(p: Vector2, a: float) -> void:
	_draw_roof_panels(p, Vector2i(1, 1), a)


func _draw_roof_solar_m(p: Vector2, a: float) -> void:
	_draw_roof_panels(p, Vector2i(2, 1), a)


func _draw_roof_solar_l(p: Vector2, a: float) -> void:
	_draw_roof_panels(p, Vector2i(3, 2), a)


# Flat panels bolted to the roof, a 2x3 grid of cells per tile.
func _draw_roof_panels(p: Vector2, size: Vector2i, a: float) -> void:
	var r := Rect2(p + Vector2(2, 3), Vector2(size) * TILE - Vector2(4, 6))
	draw_rect(r, Color(0.75, 0.75, 0.78, a))
	draw_rect(r.grow(-2), Color(0.15, 0.25, 0.5, a))
	var line := Color(0.4, 0.55, 0.85, a)
	for k in range(1, size.x * 3):
		var x := r.position.x + k * r.size.x / (size.x * 3.0)
		draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), line)
	for k in range(1, size.y * 2):
		var y := r.position.y + k * r.size.y / (size.y * 2.0)
		draw_line(Vector2(r.position.x + 2, y), Vector2(r.end.x - 2, y), line)


func _draw_roof_ac(p: Vector2, a: float) -> void:  # because it's Calizona
	draw_rect(Rect2(p + Vector2(3, 10), Vector2(26, 18)), Color(0.55, 0.55, 0.52, a))
	draw_rect(Rect2(p + Vector2(3, 2), Vector2(26, 10)), Color(0.78, 0.78, 0.75, a))
	draw_circle(p + Vector2(16, 7), 4, Color(0.35, 0.35, 0.38, a))


# --- Drawing ----------------------------------------------------------------
