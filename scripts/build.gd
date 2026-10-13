extends "res://scripts/state.gd"
## Building, tiles, placement and access paths. Part of the Main script chain (see scripts/README.md).

func _mouse_tile() -> Vector2i:
	var lift := Vector2(0, WALL_H) if view_level == 1 else Vector2.ZERO  # roofs are drawn raised
	return Vector2i(((get_global_mouse_position() + lift) / TILE).floor())


func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < GRID_W and t.y < GRID_H


func _tile_center(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE


func _is_sub_tool() -> bool:
	if not held.is_empty():
		return _tool_by_id(held.id).get("layer") == "sub"
	return tool_active and TOOLS[tool_index].layer == "sub"


# The cell under the mouse for the current tool: a tile, or a subgrid cell for small items.
func _cursor() -> Vector2i:
	return hover_sub if _is_sub_tool() else hover


func _tile_of_sub(c: Vector2i) -> Vector2i:
	return Vector2i(floori(c.x / 2.0), floori(c.y / 2.0))


# The anchor tile of the Counter with Sink covering t, or NO_SEAT.
func _counter_at(t: Vector2i) -> Vector2i:
	var a: Vector2i = parts.get(t, t)
	return a if objects.get(a) == "counter" else NO_SEAT


# A spot on a counter takes the whole subgrid column (front and back), and the far right is the sink.
func _countertop_free(c: Vector2i) -> bool:
	var a := _counter_at(_tile_of_sub(c))
	if c.x - a.x * 2 >= 3:
		return false
	return not sub_objects.has(Vector2i(c.x, c.y - c.y % 2)) and not sub_objects.has(Vector2i(c.x, c.y - c.y % 2 + 1))


# An Interior Door is a full tile wide: two subgrid cells along the line of the wall it sits in.
func _door_cells(c: Vector2i) -> Array:
	var tl := _tile_of_sub(c)
	var wall := func(n: Vector2i) -> bool: return sub_objects.get(n, "") in ["iwall", "idoor"]
	var hx: bool = wall.call(c + Vector2i.LEFT) or wall.call(c + Vector2i.RIGHT)
	var vy: bool = wall.call(c + Vector2i.UP) or wall.call(c + Vector2i.DOWN)
	if vy and not hx:
		return [Vector2i(c.x, tl.y * 2), Vector2i(c.x, tl.y * 2 + 1)]
	return [Vector2i(tl.x * 2, c.y), Vector2i(tl.x * 2 + 1, c.y)]


# The other half of an existing door.
func _door_partner(c: Vector2i) -> Vector2i:
	for o in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var n: Vector2i = c + o
		if _tile_of_sub(n) == _tile_of_sub(c) and sub_objects.get(n, "") == "idoor":
			return n
	return c


func _subs_in(t: Vector2i) -> Array:
	var out := []
	for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		if sub_objects.has(t * 2 + o):
			out.append(t * 2 + o)
	return out


func _drag_tiles() -> Array:
	var tool: Dictionary = TOOLS[tool_index]
	match tool.drag:
		"single":
			return [_cursor()]
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
	if _tool_by_id(id).get("layer") == "sub":  # t is a subgrid cell
		var tile := _tile_of_sub(t)
		if id == "idoor":  # swaps in for a piece of partition, or stands on its own
			return _in_bounds(tile) and floor_tiles.has(tile) and not wall_tiles.has(tile) \
				and not objects.has(tile) and _door_cells(t).all(func(d): return sub_objects.get(d, "iwall") == "iwall")
		if id in COUNTERTOP and _counter_at(tile) != NO_SEAT:
			return _countertop_free(t)
		return _in_bounds(tile) and floor_tiles.has(tile) and not wall_tiles.has(tile) \
			and not objects.has(tile) and not sub_objects.has(t)
	if not _in_bounds(t):
		return false
	match id:
		"carpet":  # goes on top of a concrete floor
			return floor_tiles.get(t) == "concrete"
		"concrete", "asphalt", "gravel":
			return floor_tiles.get(t) != id and floor_tiles.get(t) != "carpet"
		"wall", "wall_brick", "wall_insulated":
			if _is_wall(t):  # upgrade or downgrade in place
				return wall_tiles[t] != id
			return not wall_tiles.has(t) and not objects.has(t) and _subs_in(t).is_empty()
		"window_ac":
			return _is_wall(t) and _roofed(t) and not window_objects.has(t)
		"door":
			return wall_tiles.get(t) != "door" and not window_objects.has(t) and not objects.has(t) and _subs_in(t).is_empty()
		"solar", "ac":
			return _roofed(t) and not roof_objects.has(t)
		"solar_s", "solar_m", "solar_l":  # on the roof if it's all under one, else on open ground
			var foot := _footprint(id, t)
			if foot.all(func(f): return _roofed(f)):
				return foot.all(func(f): return not roof_objects.has(f)) and not _locked("solar")
			for f in foot:
				if not _in_bounds(f) or _roofed(f) or wall_tiles.has(f) or objects.has(f) or not _subs_in(f).is_empty():
					return false
			return true
		"gen_portable", "gen_diesel", "gen_large", "power_plant", "grid":  # outdoors only, bro. Fumes.
			if id == "grid" and objects.values().has("grid"):
				return false
			for f in _footprint(id, t):
				if not _in_bounds(f) or _roofed(f) or wall_tiles.has(f) or objects.has(f) or not _subs_in(f).is_empty():
					return false
			return _ground_problem(id, t) == ""
		"battery":
			return not wall_tiles.has(t) and not objects.has(t) and _subs_in(t).is_empty()
		"desk", "desk_adv", "cubicle":
			var old: String = objects.get(t, "")
			if DESKS.has(old):  # only upgrades, onto the old desk's spot
				return DESKS[old].tier < DESKS[id].tier and _furniture_fits(id, t, t)
			return _furniture_fits(id, t, NO_SEAT)
		"counter":
			return _furniture_fits(id, t, NO_SEAT)
		"demolish":
			if view_level == 1:
				return roof_objects.has(t)
			return objects.has(t) or wall_tiles.has(t) or window_objects.has(t) or floor_tiles.has(t) or not _subs_in(t).is_empty()
	# furniture
	return floor_tiles.has(t) and not wall_tiles.has(t) and not objects.has(t) and _subs_in(t).is_empty()


# Every tile of the footprint has floor and nothing in the way, apart from the object anchored at `mine`.
func _furniture_fits(id: String, t: Vector2i, mine: Vector2i) -> bool:
	for f in _footprint(id, t):
		if not _in_bounds(f) or not floor_tiles.has(f) or wall_tiles.has(f) or not _subs_in(f).is_empty():
			return false
		if objects.has(f) and parts.get(f, f) != mine:
			return false
	return true


func _is_wall(t: Vector2i) -> bool:
	return WALLS.has(wall_tiles.get(t, ""))


# Why a generator can't go here because of the ground under it, or "" if the ground is fine.
func _ground_problem(id: String, t: Vector2i) -> String:
	if id == "carpet":
		return "" if floor_tiles.get(t) == "concrete" else "Carpet needs a concrete floor underneath"
	if not GEN_GROUND.has(id):
		return ""
	var ok: Array = GEN_GROUND[id]
	for f in _footprint(id, t):
		if not ok.has(floor_tiles.get(f, "")):
			return "Needs %s underneath" % " or ".join(ok.map(func(g): return _tool_by_id(g).name.to_lower()))
	return ""


# Tiles an object covers when its top-left tile is t.
func _footprint(id: String, t: Vector2i) -> Array:
	var size := Vector2i.ONE
	if GENERATORS.has(id):
		size = GENERATORS[id].size
	elif SOLAR_ARRAYS.has(id):
		size = SOLAR_ARRAYS[id].size
	elif DESKS.has(id):
		size = DESKS[id].size
	elif FURNITURE_SIZE.has(id):
		size = FURNITURE_SIZE[id]
	var out := []
	for x in size.x:
		for y in size.y:
			out.append(t + Vector2i(x, y))
	return out


func _tool_by_id(id: String) -> Dictionary:
	for tool in TOOLS:
		if tool.id == id:
			return tool
	return {}


func _commit(tiles: Array, free := false) -> void:  # free: putting down something that was picked up
	var tool: Dictionary = TOOLS[tool_index]
	var valid := tiles.filter(func(t): return _can_place(tool.id, t))
	if valid.is_empty():
		return
	if tool.id == "demolish":
		for t in valid:
			_demolish(t, hover_sub if valid.size() == 1 else NO_SEAT)
		_after_build()
		return
	var cost: int = 0 if free else _tool_cost(tool) * valid.size()
	if cost > money:
		_chet("Bro, that's %s and we have %s. Maybe pitch some VCs first?" % [_money(cost), _money(money)])
		return
	money -= cost
	for t in valid:
		match tool.layer:
			"floor": floor_tiles[t] = tool.id
			"wall": wall_tiles[t] = tool.id
			"object":
				if not _can_place(tool.id, t):  # an earlier big one in this drag took the space
					if not free:
						money += _tool_cost(tool)
					continue
				if DESKS.has(objects.get(t, "")):  # upgrading: the old desk's price counts toward the new one
					var old: String = objects[t]
					money += _tool_cost(_tool_by_id(old))
					for f in _footprint(old, t):
						if parts.get(f) == t:
							objects.erase(f)
							parts.erase(f)
					objects.erase(t)
				var on_roof: bool = SOLAR_ARRAYS.has(tool.id) and _roofed(t)
				var layer: Dictionary = roof_objects if on_roof else objects
				var layer_parts: Dictionary = roof_parts if on_roof else parts
				layer[t] = tool.id
				for f in _footprint(tool.id, t):
					if f != t:
						layer[f] = "part"
						layer_parts[f] = t
			"sub":
				if tool.id == "idoor":  # both halves, replacing the bits of partition under them
					for d in _door_cells(t):
						if sub_objects.has(d) and not free:
							money += int(_tool_by_id(sub_objects[d]).cost / 2)
						sub_objects[d] = "idoor"
					continue
				if sub_objects.has(t) and not free:
					money += int(_tool_by_id(sub_objects[t]).cost / 2)
				sub_objects[t] = tool.id
				sub_rot.erase(t)
				if tool.get("rotate", false):
					sub_rot[t] = place_rot
			"roof": roof_objects[t] = tool.id
			"window": window_objects[t] = tool.id
	_after_build()


func _tool_index_of(id: String) -> int:
	for i in TOOLS.size():
		if TOOLS[i].id == id:
			return i
	return -1


# Pointer mode (nothing selected): pick up whatever is under the mouse. Moving is free.
func _pick_up(t: Vector2i, c: Vector2i) -> void:
	var h := {}
	if view_level == 1:
		if roof_objects.has(t):
			var a: Vector2i = roof_parts.get(t, t)
			h = {"id": roof_objects[a], "origin": a, "rot": 0}
			for f in _footprint(h.id, a):
				if f == a or roof_parts.get(f) == a:
					roof_objects.erase(f)
					roof_parts.erase(f)
	elif sub_objects.has(c):
		h = {"id": sub_objects[c], "origin": c, "rot": sub_rot.get(c, 0)}
		if sub_objects[c] == "idoor":
			var pr := _door_partner(c)
			h.origin = Vector2i(mini(c.x, pr.x), mini(c.y, pr.y))
			sub_objects.erase(pr)
		sub_objects.erase(c)
		sub_rot.erase(c)
	elif objects.has(t) and objects.get(parts.get(t, t), "part") != "part":
		var a: Vector2i = parts.get(t, t)
		h = {"id": objects[a], "origin": a, "rot": 0}
		for f in _footprint(h.id, a):
			if f == a or parts.get(f) == a:
				objects.erase(f)
				parts.erase(f)
	elif window_objects.has(t):
		h = {"id": window_objects[t], "origin": t, "rot": 0}
		window_objects.erase(t)
	if h.is_empty():
		return
	held = h
	place_rot = h.rot
	_after_build()


# Put the held item down at `cell` (or where the mouse is) without paying for it again.
func _drop_held(cell := NO_SEAT) -> bool:
	var id: String = held.id
	var layer: String = _tool_by_id(id).get("layer", "")
	if cell == NO_SEAT:
		cell = hover_sub if layer == "sub" else hover
	if not _can_place(id, cell):
		return false
	var prev := tool_index
	var prev_rot := place_rot
	tool_index = _tool_index_of(id)
	place_rot = held.rot
	_commit([cell], true)
	tool_index = prev
	place_rot = prev_rot
	held = {}
	return true


# Right-click or Esc while carrying something: it goes back where it came from.
func _cancel_held() -> void:
	if held.is_empty():
		return
	if not _drop_held(held.origin):
		money += int(_tool_cost(_tool_by_id(held.id)) / 2)  # its spot got taken: it's lost, half refunded
		held = {}
		_after_build()


func _deselect_tool() -> void:
	_cancel_held()
	tool_active = false
	dragging = false
	paint_tiles.clear()
	for b in tool_buttons:
		b.button_pressed = false
	move_button.button_pressed = true


# Q: turn what you're placing or carrying, or turn a placed chair under the mouse.
func _rotate_key() -> void:
	if tool_active or not held.is_empty():
		place_rot = (place_rot + 1) % 4
		if not held.is_empty():
			held.rot = place_rot
	elif sub_objects.has(hover_sub) and _tool_by_id(sub_objects[hover_sub]).get("rotate", false):
		sub_rot[hover_sub] = (sub_rot.get(hover_sub, 0) + 1) % 4


func _demolish(t: Vector2i, at_sub := NO_SEAT) -> void:
	# Removes the top-most thing on a tile and refunds half its price.
	# Small subgrid items go first: just the one under the mouse, or all of the tile's at once.
	if view_level == 1:
		if roof_objects.has(t):
			_remove_roof_object(roof_parts.get(t, t))
		return
	if window_objects.has(t):
		money += int(_tool_by_id(window_objects[t]).cost / 2)
		window_objects.erase(t)
		return
	var subs := _subs_in(t)
	if subs.has(at_sub):
		subs = [at_sub]
	if not subs.is_empty():
		if sub_objects[subs[0]] == "idoor" and subs.size() == 1:
			subs.append(_door_partner(subs[0]))
		for c in subs:
			if not sub_objects.has(c):
				continue
			money += int(_tool_by_id(sub_objects[c]).cost / 2)
			sub_objects.erase(c)
			sub_rot.erase(c)
		return
	t = parts.get(t, t)  # any tile of a big generator demolishes the whole thing
	for layer in [objects, wall_tiles, floor_tiles]:
		if layer.has(t):
			money += int(_tool_by_id(layer[t]).cost / 2)
			if is_same(layer, floor_tiles) and layer[t] == "carpet":  # pull up the carpet, keep the concrete
				layer[t] = "concrete"
				return
			for f in _footprint(layer[t], t):
				if parts.get(f) == t:
					objects.erase(f)
					parts.erase(f)
			layer.erase(t)
			return


# What someone costs a day: people assigned to Slack off only get SLACK_PAY of their salary.
func _pay(s: Dictionary) -> int:
	return int(s.salary * (SLACK_PAY if s.job == "none" else 1.0))


func _payroll() -> int:
	var payroll := 0
	for s in staff:
		payroll += _pay(s)
	return payroll


# Payroll plus yesterday's power bill (the bill itself is paid as it's run up, see _new_day).
func _daily_burn() -> int:
	return _payroll() + power_bill


# --- Models, users and rivals ------------------------------------------------
