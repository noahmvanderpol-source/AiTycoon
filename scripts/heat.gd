extends "res://scripts/power.gd"
## Heat and cooling. Part of the Main script chain (see scripts/README.md).

func _temp(t: Vector2i) -> float:
	return heat[t.y * GRID_W + t.x] if _in_bounds(t) else OUTDOOR_TEMP


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
	return out


func _heat_view() -> bool:
	return side_panel.visible and tabs.current_tab == 2


func _tick_heat() -> void:
	var rack_heat := RACK_HEAT * (1.0 + _research_bonus("rack_heat"))
	for t in objects:
		if RACKS.has(objects[t]) and _indoor(t) and _powered(t):
			_set_temp(t, _temp(t) + rack_heat * RACKS[objects[t]].heat)
	for c in _coolers():
		if _powered(c[0], c[2]):
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
		var over := _temp(at) - COMFORT_TEMP if _indoor(at) else OUTDOOR_TEMP - COMFORT_TEMP
		var p: float = BASE_PRODUCTIVITY + breaks.get(room_of.get(at, -1), 0.0) - short
		if floor_tiles.get(at) == "carpet":
			p += CARPET_BONUS
		if s.working and DESKS.has(objects.get(s.seat, "")):
			p += DESKS[objects[s.seat]].bonus
		s.hot = over > 0.0  # above COMFORT_TEMP: losing productivity to heat
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


# A cooler shares its cooling over the indoor tiles within its radius. On a wall or roof edge
# that's only the inside tiles, so a Window AC cools the strip of room next to it.
func _cool_around(at: Vector2i, c: Dictionary) -> void:
	var tiles := []
	for dx in range(-c.radius, c.radius + 1):
		for dy in range(-c.radius, c.radius + 1):
			var t: Vector2i = at + Vector2i(dx, dy)
			if _indoor(t) and room_of[t] == room_of.get(at, -1):
				tiles.append(t)
	if tiles.is_empty():
		return
	var each: float = c.cooling * (1.0 + _research_bonus("cooling")) / tiles.size()
	for t in tiles:
		var v := _temp(t)
		if v > c.target:
			_set_temp(t, maxf(v - each, c.target))


# One pass of heat flow. Open neighbours (floor, doors) trade freely; through a wall a tile
# trades a little with whatever is on the far side, the desert if it's outside.
func _spread_heat() -> void:
	var next := heat.duplicate()
	for t in heat_cells:
		var v := _temp(t)
		var flow := 0.0
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = t + d
			if _indoor(n):
				flow += (_temp(n) - v) * HEAT_SPREAD
			elif _is_wall(n):
				var far: Vector2i = n + d
				var other := _temp(far) if _indoor(far) else OUTDOOR_TEMP
				flow += (other - v) * WALL_CONDUCT * (1.0 - WALLS[wall_tiles[n]].insulation)
			else:  # an open door or gap to the outside
				flow += (OUTDOOR_TEMP - v) * WALL_CONDUCT
		next[t.y * GRID_W + t.x] = clampf(v + flow, 0.0, MAX_TEMP)
	heat = next


func _heat_color(f: float) -> Color:
	# Blue when cool, clear around room temperature, then orange and red.
	if f < INDOOR_TEMP:
		return Color(0.3, 0.6, 1.0, clampf((INDOOR_TEMP - f) / 10.0, 0.0, 1.0) * 0.4)
	var k := clampf((f - INDOOR_TEMP) / 40.0, 0.0, 1.0)
	return Color(1.0, 0.8 - 0.6 * k, 0.2, 0.1 + 0.45 * k)


func _draw_heat_tint() -> void:
	for t in heat_cells:
		draw_rect(Rect2(Vector2(t) * TILE, Vector2(TILE, TILE)), _heat_color(_temp(t)))


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
