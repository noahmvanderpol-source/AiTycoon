extends "res://scripts/power.gd"
## Heat and cooling. Part of the Main script chain (see scripts/README.md).

func _temp(t: Vector2i) -> float:
	return heat[t.y * GRID_W + t.x] if _in_bounds(t) else outdoor_temp


func _set_temp(t: Vector2i, v: float) -> void:
	heat[t.y * GRID_W + t.x] = clampf(v, 0.0, MAX_TEMP)


func _indoor(t: Vector2i) -> bool:
	return room_of.has(t) and not _is_wall(t)


# Every cooler on the map, roof and wall: [[tile, id], ...]
func _coolers() -> Array:
	var out := []
	for t in roof_objects:
		if COOLERS.has(roof_objects[t]):
			out.append([t, roof_objects[t], 1])
	for t in window_objects:
		out.append([t, window_objects[t], 2])
	for t in objects:  # water chillers stand on the floor
		if COOLERS.has(objects[t]):
			out.append([t, objects[t], 0])
	return out


func _heat_view() -> bool:
	return side_panel.visible and tabs.current_tab == 2


# The temperature outside today: a slow swing over the year, coldest on Jan 1 and hottest at midsummer.
func _outdoor_now() -> float:
	var year_frac := float((day - 1) % DAYS_PER_YEAR) / DAYS_PER_YEAR
	return OUTDOOR_TEMP - OUTDOOR_SWING * cos(year_frac * TAU)


func _tick_heat() -> void:
	outdoor_temp = _outdoor_now()
	_iwall_tiles.clear()
	for c in sub_objects:
		if sub_objects[c] == "iwall":
			var it := _tile_of_sub(c)
			_iwall_tiles[it] = _iwall_tiles.get(it, 0) + 1
	var rack_heat := RACK_HEAT * (1.0 + _research_bonus("rack_heat"))
	for t in objects:
		if RACKS.has(objects[t]) and _indoor(t) and _powered(t) and not racks_off.has(t):
			_set_temp(t, _temp(t) + rack_heat * RACKS[objects[t]].heat)
	for s in staff:  # people are warm, too
		var at := Vector2i((s.pos / TILE).floor())
		if _indoor(at):
			_set_temp(at, _temp(at) + WORKER_HEAT)
	_cool_water()
	for c in _coolers():
		if not COOLERS[c[1]].get("water", false) and _powered(c[0], c[2]):
			_cool_around(c[0], COOLERS[c[1]])
	for i in HEAT_PASSES:
		_spread_heat()
	for t in heat_cells:
		_set_temp(t, _temp(t) + (INDOOR_TEMP - _temp(t)) * HEAT_LEAK)
	for bld in buildings:  # room averages, for the Heat panel and labels
		var total := 0.0
		for t in bld.tiles:
			if not _is_wall(t):
				total += _temp(t)
		bld.temp = total / maxi(bld.area, 1)
	var breaks := _break_bonuses()
	var short := _amenity_penalty()
	for s in staff:
		var at := Vector2i((s.pos / TILE).floor())
		var here := _temp(at) if _indoor(at) else outdoor_temp
		var over := here - COMFORT_TEMP
		var p: float = BASE_PRODUCTIVITY + breaks.get(room_of.get(at, -1), 0.0) - short
		if floor_tiles.get(at) == "carpet":
			p += CARPET_BONUS
		if s.working and DESKS.has(objects.get(s.seat, "")):
			p += DESKS[objects[s.seat]].bonus
		s.hot = here >= COMFORT_TEMP  # sweating, and losing productivity to the heat
		s.productivity = clampf(p - maxf(over, 0.0) * HEAT_PRODUCTIVITY_LOSS, 0.2, 1.0)
	if not _heat_warned:
		for t in objects:
			if RACKS.has(objects[t]) and _temp(t) > RACK_SAFE_TEMP + 10.0:
				_heat_warned = true
				_chet("Bro, the racks are %d degrees. They're thermal throttling. Put an AC Unit on the roof right over them (R in Build). Heat (H) shows the hot spots." % _temp(t))
				break


# How many of each amenity the company has. A kitchenette is a Counter with Sink plus a
# Microwave or Mini-Fridge.
func _amenity_counts() -> Dictionary:
	var n := {"counter": 0, "cook": 0, "toilet": 0, "bath_sink": 0}
	for t in objects:
		match objects[t]:
			"counter": n.counter += 1
			"fridge": n.cook += 1
			"toilet": n.toilet += 1
	for c in sub_objects:
		match sub_objects[c]:
			"microwave": n.cook += 1
			"bath_sink": n.bath_sink += 1
	return {"kitchen": mini(n.counter, n.cook), "toilet": n.toilet, "bath_sink": n.bath_sink}


# Workers each amenity still lacks, e.g. {"toilet": 3}. Empty when there's enough of everything.
func _amenity_shortfall() -> Dictionary:
	var have := _amenity_counts()
	var out := {}
	for k in AMENITIES:
		var missing: int = staff.size() - have[k] * AMENITIES[k].per
		if missing > 0:
			out[k] = missing
	return out


# Productivity lost by everyone, in proportion to how many workers each amenity doesn't cover.
func _amenity_penalty() -> float:
	if staff.is_empty():
		return 0.0
	var total := 0.0
	var lack := _amenity_shortfall()
	for k in lack:
		total += AMENITIES[k].penalty * float(lack[k]) / staff.size()
	return total


# Break room bonus per building index: everything break-roomy inside it, capped.
func _break_bonuses() -> Dictionary:
	var out := {}
	for t in objects:
		if BREAK_ITEMS.has(objects[t]) and room_of.has(t):
			out[room_of[t]] = out.get(room_of[t], 0.0) + BREAK_ITEMS[objects[t]]
	for c in sub_objects:
		var t := _tile_of_sub(c)
		if BREAK_ITEMS.has(sub_objects[c]) and room_of.has(t):
			out[room_of[t]] = out.get(room_of[t], 0.0) + BREAK_ITEMS[sub_objects[c]]
	for k in out:
		out[k] = minf(out[k], BREAK_CAP)
	return out


# A cooler chills the indoor tiles within its radius, most right next to the unit and less the
# further out, never below its target. The spreading passes then carry the cold on from there.
# On a wall or roof edge that's only the inside tiles.
func _cool_around(at: Vector2i, c: Dictionary) -> void:
	var tiles := []
	var weights := []
	var total := 0.0
	for dx in range(-c.radius, c.radius + 1):
		for dy in range(-c.radius, c.radius + 1):
			var t: Vector2i = at + Vector2i(dx, dy)
			if _indoor(t) and room_of[t] == room_of.get(at, -1):
				var w: float = 1.0 - Vector2(dx, dy).length() / (c.radius + 1.0)
				if w > 0.0:
					tiles.append(t)
					weights.append(w)
					total += w
	if tiles.is_empty():
		return
	var power: float = c.cooling * (1.0 + _research_bonus("cooling")) / total
	for i in tiles.size():
		var v := _temp(tiles[i])
		if v > c.target:
			_set_temp(tiles[i], maxf(v - power * weights[i], c.target))


# Partition cells slow the heat passing through their tile a little.
func _partition_factor(t: Vector2i) -> float:
	return 1.0 - IWALL_INSULATION * minf(_iwall_tiles.get(t, 0) / 2.0, 1.0)


# One pass of heat flow. Open neighbours trade freely (interior walls slow that a little); through
# an outside wall a tile trades with the desert, slowed by the wall's insulation; an open door
# lets the desert in far faster.
func _spread_heat() -> void:
	var next := heat.duplicate()
	for t in heat_cells:
		var v := _temp(t)
		var flow := 0.0
		var here := _partition_factor(t)
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = t + d
			if _indoor(n):
				flow += (_temp(n) - v) * HEAT_SPREAD * here * _partition_factor(n)
			else:
				var far: Vector2i = n + d
				var other := _temp(far) if _indoor(far) else outdoor_temp
				if _is_wall(n):  # a window unit is a hole in the wall
					var insulation: float = 0.0 if window_objects.has(n) else WALLS[wall_tiles[n]].insulation
					flow += (other - v) * WALL_CONDUCT * (1.0 - insulation)
				else:  # an open door or gap to the outside
					flow += (other - v) * DOOR_CONDUCT
		next[t.y * GRID_W + t.x] = clampf(v + flow, 0.0, MAX_TEMP)
	heat = next


# --- Water cooling ----------------------------------------------------------
# Cooling Pipes sit in single subgrid cells. A rack takes a pipe on its back or its sides, never
# its front (the side it faces, south unless the build code rotates it). Pipes that touch each
# other make a loop; a loop with a powered Water Chiller on it cools every rack it touches.

func _rack_front(t: Vector2i) -> Vector2i:
	var rot = get("object_rot")  # filled in when racks can be turned: 0 faces down, then clockwise
	var turn: int = rot.get(t, 0) if rot is Dictionary else 0
	return [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT][turn % 4]


func _rebuild_pipe_net() -> void:
	var cell := {}
	var loops := []
	for c in sub_objects:
		if sub_objects[c] != "pipe" or cell.has(c):
			continue
		var loop := {"cells": [], "racks": [], "chillers": [], "blocked": []}
		var stack := [c]
		while not stack.is_empty():
			var s: Vector2i = stack.pop_back()
			if cell.has(s) or sub_objects.get(s) != "pipe":
				continue
			cell[s] = loops.size()
			loop.cells.append(s)
			var ts := _tile_of_sub(s)
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				stack.append(s + d)
				var tn := _tile_of_sub(s + d)
				if tn == ts:
					continue
				var anchor: Vector2i = parts.get(tn, tn)
				var id: String = objects.get(anchor, "")
				if RACKS.has(id):
					if -d == _rack_front(anchor):  # the front has no connection
						if not loop.blocked.has(anchor):
							loop.blocked.append(anchor)
					elif not loop.racks.has(anchor):
						loop.racks.append(anchor)
				elif COOLERS.has(id) and COOLERS[id].get("water", false) and not loop.chillers.has(anchor):
					loop.chillers.append(anchor)
		loops.append(loop)
	pipe_net = {"cell": cell, "loops": loops}


# Each loop's chillers share their cooling between the racks on it, straight out of the rack
# tiles, and warm their own tile with some of what they moved.
func _cool_water() -> void:
	for loop in pipe_net.get("loops", []):
		var chillers := []
		var power := 0.0
		for t in loop.chillers:
			if _powered(t, 0):
				chillers.append(t)
				power += COOLERS[objects[t]].cooling * (1.0 + _research_bonus("cooling"))
		var racks: Array = loop.racks.filter(func(r): return _indoor(r))
		if chillers.is_empty() or racks.is_empty():
			continue
		var each := minf(power / racks.size(), WATER_RACK_MAX)
		var moved := 0.0
		for r in racks:
			var v := _temp(r)
			var target: float = COOLERS[objects[chillers[0]]].target
			var take := clampf(v - target, 0.0, each)
			_set_temp(r, v - take)
			moved += take
		for t in chillers:
			if _indoor(t):
				_set_temp(t, _temp(t) + moved * CHILLER_WASTE / chillers.size())


func _loop_active(loop_index: int) -> bool:
	var loops: Array = pipe_net.get("loops", [])
	if loop_index < 0 or loop_index >= loops.size():
		return false
	for t in loops[loop_index].chillers:
		if _powered(t, 0):
			return true
	return false


func _draw_pipe(p: Vector2) -> void:  # p is the top-left of a 16x16 subgrid cell
	var c := Vector2i((p / SUB).round())
	var idx: int = pipe_net.get("cell", {}).get(c, -1)
	var col := Color(0.35, 0.65, 0.95) if _loop_active(idx) else Color(0.5, 0.56, 0.62)
	var mid := p + Vector2(SUB, SUB) / 2.0
	var ts := _tile_of_sub(c)
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = c + d
		if sub_objects.get(n) == "pipe":
			draw_line(mid, mid + Vector2(d) * SUB, col, 5.0)
			continue
		var tn := _tile_of_sub(n)
		if tn == ts:
			continue
		var anchor: Vector2i = parts.get(tn, tn)
		var id: String = objects.get(anchor, "")
		if RACKS.has(id):
			var ok: bool = -d != _rack_front(anchor)
			draw_line(mid, mid + Vector2(d) * SUB * 0.6, col if ok else Color(0.9, 0.3, 0.25), 5.0 if ok else 2.0)
		elif COOLERS.has(id) and COOLERS[id].get("water", false):
			draw_line(mid, mid + Vector2(d) * SUB * 0.6, col, 5.0)
	draw_circle(mid, 3.5, col.lightened(0.15))


func _draw_chiller(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 13, 4, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(3, 8), Vector2(26, 20)), 14, Color(0.72, 0.8, 0.86), Color(0.45, 0.58, 0.7))
	draw_circle(p + Vector2(16, 2), 7.0, Color(0.25, 0.3, 0.36))  # the fan, on top
	for k in 3:
		draw_line(p + Vector2(16, 2), p + Vector2(16, 2) + Vector2(6, 0).rotated(_time * 6.0 + k * TAU / 3.0), Color(0.75, 0.85, 0.95), 2.0)
	draw_rect(Rect2(p + Vector2(6, 17), Vector2(8, 4)), Color(0.3, 0.7, 1.0))  # coolant light


# Heat as a smooth gradient: each tile corner blends the temperatures of the tiles around it.
const HEAT_STOPS := [
	[58.0, Color(0.2, 0.45, 1.0, 0.5)], [72.0, Color(0.35, 0.8, 0.75, 0.14)],
	[80.0, Color(1.0, 0.92, 0.3, 0.3)], [92.0, Color(1.0, 0.55, 0.15, 0.5)],
	[105.0, Color(0.95, 0.15, 0.1, 0.6)], [125.0, Color(0.55, 0.0, 0.05, 0.75)],
]


func _heat_color(f: float) -> Color:
	if f <= HEAT_STOPS[0][0]:
		return HEAT_STOPS[0][1]
	for i in range(1, HEAT_STOPS.size()):
		if f <= HEAT_STOPS[i][0]:
			var k: float = (f - HEAT_STOPS[i - 1][0]) / (HEAT_STOPS[i][0] - HEAT_STOPS[i - 1][0])
			return HEAT_STOPS[i - 1][1].lerp(HEAT_STOPS[i][1], k)
	return HEAT_STOPS[HEAT_STOPS.size() - 1][1]


func _draw_heat_tint() -> void:
	var sums := {}  # tile corner -> [temperature total, tiles counted]
	for t in heat_cells:
		var v := _temp(t)
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var k: Vector2i = t + o
			var e: Array = sums.get(k, [0.0, 0])
			sums[k] = [e[0] + v, e[1] + 1]
	for t in heat_cells:
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var k: Vector2i = t + o
			var e: Array = sums[k]
			pts.append(Vector2(k) * TILE)
			cols.append(_heat_color(e[0] / e[1]))
		draw_polygon(pts, cols)


func _draw_rack_temps() -> void:
	for t in objects:
		if RACKS.has(objects[t]) and _rack_output(t) < 1.0:
			draw_string(ThemeDB.fallback_font, Vector2(t) * TILE + Vector2(2, -26), "%d%%" % int(_rack_output(t) * 100.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.35, 0.3))
	for bld in buildings:  # each room's temperature on its first floor tile
		for t in bld.tiles:
			if not _is_wall(t):
				draw_string(ThemeDB.fallback_font, Vector2(t) * TILE + Vector2(4, 14), "%d°F" % bld.temp,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
				break


# --- Roofs ------------------------------------------------------------------
