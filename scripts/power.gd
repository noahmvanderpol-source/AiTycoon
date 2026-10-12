extends "res://scripts/staff.gd"
## Power and pollution. Part of the Main script chain (see scripts/README.md).

func _power_demand() -> float:
	var kw := 0.0
	for m in _machines():
		kw += m[1]
	return kw


# Everything that draws power, in the order it gets fed: coolers first, then racks and rigs
# in the order they were built. [Vector3i(x, y, layer), kW]
func _machines() -> Array:
	var out := []
	for c in _coolers():
		out.append([Vector3i(c[0].x, c[0].y, c[2]), COOLERS[c[1]].power * (1.0 + _research_bonus("cooler_power"))])
	for t in objects:
		if RACKS.has(objects[t]):
			out.append([Vector3i(t.x, t.y, 0), RACKS[objects[t]].power * RACK_KW * (1.0 + _research_bonus("rack_power"))])
		elif objects[t] == "redteam":
			out.append([Vector3i(t.x, t.y, 0), REDTEAM_KW])
	return out


func _powered(t: Vector2i, layer := 0) -> bool:
	return not unpowered.has(Vector3i(t.x, t.y, layer))


func _tick_power() -> void:
	_power_step = (_power_step + 1) % SUN.size()
	var demand := _power_demand()
	var need := demand
	var h := HOURS_PER_STEP
	var solar: float = roof_objects.values().count("solar") * SOLAR_KW
	for t in objects:
		if SOLAR_ARRAYS.has(objects[t]):
			solar += SOLAR_ARRAYS[objects[t]].kw
	for t in roof_objects:
		if SOLAR_ARRAYS.has(roof_objects[t]):
			solar += SOLAR_ARRAYS[roof_objects[t]].kw
	solar *= SUN[_power_step]
	var used_solar := minf(solar, need)
	need -= used_solar
	var bat_cap := objects.values().count("battery") * BATTERY_KWH
	var bat_rate := objects.values().count("battery") * BATTERY_KW
	battery_charge = minf(battery_charge + minf(solar - used_solar, bat_rate) * h, bat_cap)
	var grid := 0.0
	if objects.values().has("grid"):
		grid = minf(need, _grid_kw())
		need -= grid
		_power_cost += grid * h * GRID_PRICE
	var from_bat := minf(need, minf(bat_rate, battery_charge / h))
	battery_charge -= from_bat * h
	need -= from_bat
	var gens := []
	for t in objects:
		if GENERATORS.has(objects[t]):
			gens.append(t)
	gens.sort_custom(func(x, y): return GENERATORS[objects[x]].fuel < GENERATORS[objects[y]].fuel)
	gen_output.clear()
	var made := 0.0
	for t in gens:
		var g: Dictionary = GENERATORS[objects[t]]
		var out := minf(need, g.kw)
		need -= out
		made += out
		gen_output[t] = out
		_power_cost += out * h * g.fuel
		var c: Vector2i = t + GENERATORS[objects[t]].size / 2
		var i: int = c.y * GRID_W + c.x
		smog[i] = minf(smog[i] + out * h * g.smog, 100.0)
	power_ratio = 1.0 if demand <= 0.0 else clampf(1.0 - need / demand, 0.0, 1.0)
	# A machine either gets its full draw or nothing: hand the supply out in order.
	var left := demand - need + 0.001
	unpowered.clear()
	for m in _machines():
		if m[1] <= left:
			left -= m[1]
		else:
			unpowered[m[0]] = true
	power_stats = {"demand": demand, "solar": used_solar, "grid": grid, "battery": from_bat, "gens": made}
	_spread_smog()
	if not unpowered.is_empty() and not _power_warned:
		_power_warned = true
		_chet("Bro, we're browning out. %d machine%s got no power, look for the lightning bolts. Build more generators: Build (B), Power tab." % [unpowered.size(), "" if unpowered.size() == 1 else "s"])
	elif unpowered.is_empty():
		_power_warned = false
	if not _smog_warned and _pollution() > 50:
		_smog_warned = true
		_chet("The generators are making their own weather now. Smog drifts, bro. Power (P) shows where it's going.")


func _spread_smog() -> void:
	# Each tile keeps part of its smog and shares the rest with its four neighbours; the edges leak away.
	var next := PackedFloat32Array()
	next.resize(smog.size())
	for y in GRID_H:
		for x in GRID_W:
			var v := smog[y * GRID_W + x]
			if v < 0.001:
				continue
			v *= 1.0 - SMOG_DECAY
			var share := v * SMOG_SPREAD / 4.0
			next[y * GRID_W + x] += v - share * 4.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if _in_bounds(n):
					next[n.y * GRID_W + n.x] += share
				else:
					world.add_smog(n, share)  # over the fence, onto the neighbours
	smog = next
	world.tick_smog()


# The Pollution meter, 0-100: the air on the worst tile.
func _pollution() -> int:
	var worst := 0.0
	for v in smog:
		worst = maxf(worst, v)
	return int(worst)


func _smog_at(t: Vector2i) -> float:
	return smog[t.y * GRID_W + t.x] if _in_bounds(t) else 0.0


func _draw_smog(a: Vector2i, b: Vector2i) -> void:
	# A faint haze always; a stronger brown tint while the Power panel is open.
	var strength := 1.0 if side_panel.visible and tabs.current_tab == 3 else 0.35
	for x in range(a.x, b.x):
		for y in range(a.y, b.y):
			var v := _smog_at(Vector2i(x, y))
			if v > 0.5:
				draw_rect(Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE)),
					Color(0.35, 0.28, 0.2, clampf(v / 50.0, 0.0, 0.7) * strength))


# --- Heat -------------------------------------------------------------------
