extends "res://scripts/draw.gd"
## Hover tooltips and cost label. Part of the Main script chain (see scripts/README.md).

func _update_hover_tip() -> void:
	var text := "" if dragging or modal or company_page.visible or _mouse_over_ui() else _describe_hover()
	if build_row.visible and tool_active and not modal and not _mouse_over_ui():  # say why a generator won't fit here
		var why := _ground_problem(TOOLS[tool_index].id, hover)
		if why != "":
			text = why
	hover_tip.visible = text != ""
	if text == "":
		return
	hover_tip.text = text
	hover_tip.reset_size()
	var p := get_viewport().get_mouse_position() + Vector2(16, 18)
	var screen := get_viewport_rect().size
	hover_tip.position = p.clamp(Vector2.ZERO, screen - hover_tip.size)


# What's under the mouse, top-most first, with a stat or two.
func _describe_hover() -> String:
	var mouse := get_global_mouse_position()
	if view_level == 0:
		for s in staff:
			if s.pos.distance_to(mouse - Vector2(0, 8)) < 12.0:
				return "%s, %s\nJob: %s\nProductivity: %d%%" % [s.name, ROLES[s.role].name, JOBS[s.job].name, int(s.productivity * 100.0)]
	var t := hover
	if not _in_bounds(t):
		return world.describe(t)  # off your property
	var lines := []
	if view_level == 1:
		if roof_objects.has(t):
			var rid: String = roof_objects[roof_parts.get(t, t)]
			lines.append(_tool_by_id(rid).name)
			lines.append_array(_effects(rid))
		elif room_of.has(t):
			lines.append("Roof")
	else:
		var id: String = objects.get(t, "")
		var anchor := t
		if id == "part" and parts.has(t):
			anchor = parts[t]
			id = objects.get(anchor, "")
		var sub: String = sub_objects.get(hover_sub, "")
		if id != "" and id != "part":
			lines.append(_tool_by_id(id).get("name", id.capitalize()))
			if RACKS.has(id):
				if rack_names.has(t) and deviation >= 25.0:
					lines[0] += ' "%s"' % rack_names[t]
				if racks_off.has(t):
					lines.append("Disabled. Click it with Build closed to turn it on.")
				else:
					lines.append("Output: %d%%   (click with Build closed to turn off)" % int(_rack_output(t) * 100.0))
				lines.append("Condition: %d%%%s" % [int(_rack_cond(t)), "" if _maintained_racks().has(t) else " (no engineer)"])
			if GENERATORS.has(id):
				lines.append("Condition: %d%%%s" % [int(_gen_cond(anchor)), "" if _maintained_gens().has(anchor) else " (no mechanic)"])
				lines.append("Can make up to %d kW now" % int(GENERATORS[id].kw * _gen_cond(anchor) / 100.0))
			lines.append_array(_effects(id))
			if _needs_access(id) and not _reachable(anchor):
				lines.append("No access! Needs a clear path from a door to one side.")
			if not _powered(anchor):
				lines.append("No power! Build more generators.")
		elif sub != "":
			lines.append(_tool_by_id(sub).get("name", sub.capitalize()))
		elif window_objects.has(t):
			lines.append(COOLERS[window_objects[t]].name)
			lines.append_array(_effects(window_objects[t]))
			if not _powered(t, 2):
				lines.append("No power! Build more generators.")
		elif wall_tiles.has(t):
			lines.append(_tool_by_id(wall_tiles[t]).name)
			lines.append_array(_effects(wall_tiles[t]))
		elif floor_tiles.has(t):
			lines.append(_tool_by_id(floor_tiles[t]).name + " floor")
	if _indoor(t):
		lines.append("Here: %d°F, room average %d°F" % [int(_temp(t)), int(buildings[room_of[t]].temp)])
	return "\n".join(lines)


# What a kind of thing does to heat, cooling, power and smog, for its tooltip.
func _effects(id: String) -> Array:
	if DESKS.has(id):
		return ["Productivity: +%d%% for whoever works here" % int(DESKS[id].bonus * 100.0),
			"Place a better desk on it to upgrade"]
	if id == "trash":
		return ["Break room: +1% productivity for everyone in this building", "Somebody has to take it out"]
	if id == "toilet":
		return ["Bathroom: covers 5 workers. Too few stalls lowers everyone's productivity"]
	if id == "bath_sink":
		return ["Bathroom: covers 10 workers. Too few sinks lowers everyone's productivity"]
	if BREAK_ITEMS.has(id):
		var lines := ["Break room: +%d%% productivity for everyone in this building (up to +%d%% total)" % [
			int(BREAK_ITEMS[id] * 100.0), int(BREAK_CAP * 100.0)]]
		if id in ["counter", "microwave", "fridge"]:
			lines.append("Kitchenette: a Counter with Sink plus a Microwave or Mini-Fridge covers 10 workers")
		if id in COUNTERTOP:
			lines.append("Can sit on a Counter with Sink")
		return lines
	if RACKS.has(id):
		return ["Compute: %.0f" % RACKS[id].compute,
			"Heat: +%.1f a step, radiating out" % (RACK_HEAT * RACKS[id].heat * (1.0 + _research_bonus("rack_heat"))),
			"Power: uses %.1f kW" % (RACK_KW * RACKS[id].power * (1.0 + _research_bonus("rack_power")))]
	if WALLS.has(id):
		return ["Insulation: %d%%" % int(WALLS[id].insulation * 100.0)]
	if id == "pipe":
		return ["Water cooling: carries coolant from a Water Chiller to racks", "Connects to the back or sides of a rack, never the front", "Takes one subgrid cell"]
	if id == "chiller":
		return ["Cooling: %d a step, shared by the racks on its pipe loop (up to %d each)" % [int(COOLERS[id].cooling * (1.0 + _research_bonus("cooling"))), int(WATER_RACK_MAX)],
			"Power: uses %d kW" % COOLERS[id].power, "Gives off %d%% of the heat it moves" % int(CHILLER_WASTE * 100.0), "Needs Cooling Pipes to a rack"]
	if id == "iwall":
		return ["Insulation: %d%%" % int(IWALL_INSULATION * 100.0)]
	if COOLERS.has(id):
		var side: int = COOLERS[id].radius * 2 + 1
		return ["Cooling: %d over a %dx%d area" % [int(COOLERS[id].cooling * (1.0 + _research_bonus("cooling"))), side, side],
			"Power: uses %d kW" % COOLERS[id].power]
	if SOLAR_ARRAYS.has(id):
		return ["Power: makes up to %.1f kW in the sun" % SOLAR_ARRAYS[id].kw, "Smog: none, but smog over it cuts output up to %d%%" % int(SOLAR_SMOG_LOSS * 100)]
	if GENERATORS.has(id):
		var g: Dictionary = GENERATORS[id]
		return ["Power: makes up to %d kW" % g.kw, "Fuel: $%.2f per kWh" % g.fuel, "Smog: %.2f per kWh" % g.smog,
			"Wears out while running; a Mechanic on Maintenance repairs it"]
	match id:
		"eng_station":
			return ["Up to %d engineers work within %d tiles" % [ENG_SLOTS, int(ENG_RADIUS)],
				"Each tends a rack in range: +%.1f compute" % ENG_RACK_BONUS,
				"Each maintains up to %d racks in range" % ENG_MAINT_RACKS]
		"redteam":
			return ["Power: uses %d kW" % REDTEAM_KW, "Eats %.1f compute a day" % REDTEAM_COMPUTE, "Deviation: -%.1f a year" % REDTEAM_ALIGN]
		"solar":
			return ["Power: makes up to %d kW in the sun" % SOLAR_KW, "Smog: none"]
		"battery":
			return ["Stores %d kWh, %d kW in or out" % [BATTERY_KWH, BATTERY_KW]]
		"grid":
			return ["Power: up to %d kW at $%.2f per kWh" % [_grid_kw(), GRID_PRICE], "Smog: someone else's problem"]
	return []


# What the Build list says when you hover an item: price, size, where it goes and what it does.
const TOOL_NOTES := {
	"gravel": ["Cheapest ground. Fills a dragged box", "Diesel generators can stand on it"],
	"asphalt": ["Tougher ground. Fills a dragged box", "Large generators and power plants can stand on it"],
	"concrete": ["Proper floor. Fills a dragged box", "Carpet goes on top of it"],
	"carpet": ["Goes on concrete", "Staff standing on it work 3% better"],
	"iwall": ["Blocks walking and takes a quarter tile", "Set an Interior Door into it so staff can pass"],
	"idoor": ["A full tile wide, set into a line of Interior Wall", "Staff can walk through it", "Replaces the wall pieces it is placed on"],
	"door": ["Stands in an outside wall", "Staff walk through it"],
	"ficus": ["Decoration. Morale boost: 0%", "Investors love it though"],
	"chair": ["Face it at a table"],
}


func _tool_tip(tool: Dictionary) -> String:
	var id: String = tool.id
	var lines := [tool.name]
	lines.append("Cost: %s" % _money(_tool_cost(tool)) if tool.cost > 0 else "Free")
	var layer: String = tool.get("layer", "")
	var foot: Vector2i = _footprint(id, Vector2i.ZERO).back() + Vector2i.ONE
	match layer:
		"sub":
			lines.append("Size: one tile wide" if id == "idoor" else "Size: one subgrid square (a quarter tile)")
		"floor", "wall":
			lines.append("Size: 1 tile")
		"object":
			lines.append("Size: %dx%d tiles" % [foot.x, foot.y])
		"roof":
			lines.append("Goes on a roof (R shows the roof view)")
		"window":
			lines.append("Goes in an outside wall")
	if tool.get("where") == "either":
		lines.append("Goes on a roof, or on open ground")
	if GEN_GROUND.has(id):
		lines.append("Needs %s underneath" % " or ".join(GEN_GROUND[id]))
	if GENERATORS.has(id) or id == "grid":
		lines.append("Outdoors only")
	if tool.get("access", false):
		lines.append("Needs a clear path from a door to one side")
	if tool.get("rotate", false):
		lines.append("Q turns it")
	lines.append_array(TOOL_NOTES.get(id, []))
	lines.append_array(_effects(id))
	return "\n".join(lines)


func _update_cost_label() -> void:
	var tool: Dictionary = TOOLS[tool_index]
	if not dragging or tool.cost == 0:
		cost_label.visible = false
		return
	var n := _drag_tiles().filter(func(t): return _can_place(tool.id, t)).size()
	cost_label.text = _money(n * _tool_cost(tool))
	cost_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4) if n * _tool_cost(tool) > money else Color.WHITE)
	cost_label.position = get_viewport().get_mouse_position() + Vector2(18, 10)
	cost_label.visible = true
