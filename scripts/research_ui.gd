extends "res://scripts/hover.gd"
## Research page. Part of the Main script chain (see scripts/README.md).

# Research tree layout: the garage at the bottom, each branch grows upward in two lanes.
# The tree is bigger than the screen, so it sits in a scroll box you can drag around.
const RT_NODE := Vector2(215, 72)
const RT_COL := 235.0  # distance between lanes
const RT_ROW := 112.0  # distance between rows
const RT_BRANCH := 2 * RT_COL + 50.0  # width of one branch, two lanes and a gap
const RT_PAD := 30.0  # margin round the tree
const RT_ROOT_H := 140.0  # room under the bottom row for the branch names and the garage


func _build_research_page() -> void:
	var page := ColorRect.new()
	page.color = Color(0.07, 0.07, 0.09, 0.97)
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	page.visible = false
	var page_layer := CanvasLayer.new()
	page_layer.layer = 60  # above the music controls
	add_child(page_layer)
	page_layer.add_child(page)
	research_page = page
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	col.add_theme_constant_override("separation", 10)
	page.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "Research"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Close (E)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_toggle_menu.bind("research"))
	head.add_child(close)
	research_label = Label.new()
	col.add_child(research_label)
	research_bar = ProgressBar.new()
	research_bar.custom_minimum_size = Vector2(420, 14)
	research_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	research_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.35)
	research_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(research_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	research_scroll = scroll
	var tree := Control.new()
	tree.custom_minimum_size = _rt_size()
	tree.draw.connect(_draw_research_lines)
	tree.gui_input.connect(_research_drag)
	scroll.add_child(tree)
	research_tree = tree
	var root := Label.new()
	root.text = "Garage Startup"
	root.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.size = Vector2(200, 44)
	root.position = _rt_root() - Vector2(100, 0)
	var rs := _panel_style(1.0)
	rs.bg_color = Color(0.2, 0.18, 0.15)
	root.add_theme_stylebox_override("normal", rs)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.add_child(root)
	for i in RESEARCH_BRANCHES.size():
		var br: Dictionary = RESEARCH_BRANCHES[i]
		var h := Label.new()
		h.text = br.name
		h.add_theme_font_size_override("font_size", 18)
		h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.size = Vector2(RT_BRANCH - 50.0, 24)
		h.position = Vector2(RT_PAD + i * RT_BRANCH, _rt_size().y - RT_ROOT_H + 4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tree.add_child(h)
		for r in RESEARCH:
			if r.branch != br.id:
				continue
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 14)
			b.tooltip_text = r.desc
			b.size = RT_NODE
			b.position = _rt_node_pos(r)
			b.pressed.connect(_pick_research.bind(r.id))
			tree.add_child(b)
			research_buttons[r.id] = b
			var icon := Control.new()
			icon.position = Vector2(10, (RT_NODE.y - 32) / 2.0)
			icon.size = Vector2(32, 32)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.draw.connect(_draw_research_icon.bind(icon, r.id))
			b.add_child(icon)
			if r.has("con"):  # the drawback, in red along the bottom
				var con := Label.new()
				con.text = r.con
				con.add_theme_font_size_override("font_size", 12)
				con.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
				con.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				con.position = Vector2(46, RT_NODE.y - 22)
				con.size = Vector2(RT_NODE.x - 52, 18)
				con.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(con)


# Row of a node, counted up from the bottom: one above the deepest thing it needs.
func _rt_tier(r: Dictionary) -> int:
	var t := 0
	for id in r.get("req", []):
		t = maxi(t, _rt_tier(_research_by_id(id)) + 1)
	return t


func _rt_tiers() -> int:
	var n := 0
	for r in RESEARCH:
		n = maxi(n, _rt_tier(r) + 1)
	return n


func _rt_size() -> Vector2:
	return Vector2(RT_PAD * 2 + RESEARCH_BRANCHES.size() * RT_BRANCH - 50.0,
		RT_PAD + (_rt_tiers() - 1) * RT_ROW + RT_NODE.y + RT_ROOT_H)


# Top-left corner of a node: its branch and lane pick the column, its tier the row (bottom up).
func _rt_node_pos(r: Dictionary) -> Vector2:
	var bi := RESEARCH_BRANCHES.map(func(b): return b.id).find(r.branch)
	var x: float = RT_PAD + bi * RT_BRANCH + r.get("lane", 0) * RT_COL
	var y := _rt_size().y - RT_ROOT_H - RT_NODE.y - _rt_tier(r) * RT_ROW
	return Vector2(x, y)


# Top middle of the garage box.
func _rt_root() -> Vector2:
	return Vector2(_rt_size().x / 2.0, _rt_size().y - RT_ROOT_H + 60.0)


# Drag the tree around with the left or middle mouse button; the wheel scrolls it up and down.
func _research_drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
		research_scroll.scroll_horizontal -= int(event.relative.x)
		research_scroll.scroll_vertical -= int(event.relative.y)


# Little code-drawn icons, 32x32, one per research node.
func _draw_research_icon(c: Control, id: String) -> void:
	id = {"interiors": "prefab", "raised": "insulation", "hyperscale": "modular", "liquid": "hvac", "smartgrid": "lithium",
		"immersion": "hvac", "arxiv": "standups", "tensor": "silicon", "photonic": "lowpower", "quantum": "wafer",
		"kombucha": "hustle", "equity": "snacks", "fourday": "pto"}.get(id, id)
	var grey := Color(0.55, 0.55, 0.58)
	var dark := Color(0.2, 0.2, 0.22)
	var gold := Color(1.0, 0.8, 0.35)
	match id:
		"prefab":  # bricks
			for row in 4:
				for i in 3:
					var x := i * 11 - (5 if row % 2 else 0)
					c.draw_rect(Rect2(maxi(x, 0), 4 + row * 7, mini(10, 10 + x) if x < 0 else mini(10, 32 - x), 6), Color(0.75, 0.38, 0.28))
		"roofs":  # roof with a solar panel
			c.draw_colored_polygon(PackedVector2Array([Vector2(2, 18), Vector2(16, 4), Vector2(30, 18)]), Color(0.6, 0.35, 0.25))
			c.draw_rect(Rect2(6, 18, 20, 12), Color(0.85, 0.8, 0.7))
			c.draw_colored_polygon(PackedVector2Array([Vector2(13, 10), Vector2(19, 6), Vector2(24, 11), Vector2(18, 15)]), Color(0.2, 0.35, 0.7))
		"insulation":  # pink fluffy layers
			for i in 3:
				var pts := PackedVector2Array()
				for x in 9:
					pts.append(Vector2(x * 4, 8 + i * 8 + (2 if x % 2 else -2)))
				c.draw_polyline(pts, Color(0.95, 0.6, 0.7), 4.0)
		"modular":  # stacked rack boxes
			for i in 2:
				c.draw_rect(Rect2(4 + i * 13, 4, 11, 26), dark)
				for j in 4:
					c.draw_rect(Rect2(6 + i * 13, 7 + j * 6, 7, 2), Color(0.3, 0.9, 0.5))
		"diesel":  # generator with smoke
			c.draw_rect(Rect2(3, 14, 26, 15), Color(0.85, 0.65, 0.2))
			c.draw_rect(Rect2(6, 18, 10, 7), dark)
			c.draw_rect(Rect2(22, 8, 4, 6), grey)
			c.draw_circle(Vector2(26, 5), 3, Color(0.45, 0.45, 0.45))
		"hvac":  # fan
			c.draw_circle(Vector2(16, 16), 14, Color(0.35, 0.55, 0.75))
			for a in 3:
				var d := Vector2.from_angle(a * TAU / 3.0)
				c.draw_circle(Vector2(16, 16) + d * 7, 5, Color(0.85, 0.92, 1.0))
			c.draw_circle(Vector2(16, 16), 3, dark)
		"lithium":  # battery
			c.draw_rect(Rect2(3, 9, 24, 14), Color(0.9, 0.9, 0.9), false, 2.0)
			c.draw_rect(Rect2(27, 13, 3, 6), Color(0.9, 0.9, 0.9))
			c.draw_rect(Rect2(6, 12, 13, 8), Color(0.35, 0.85, 0.45))
		"turbines":  # trailer with turbine
			c.draw_rect(Rect2(2, 12, 28, 12), Color(0.7, 0.72, 0.75))
			c.draw_circle(Vector2(9, 27), 3, dark)
			c.draw_circle(Vector2(23, 27), 3, dark)
			c.draw_circle(Vector2(16, 18), 5, dark)
			c.draw_line(Vector2(11, 18), Vector2(21, 18), gold, 2.0)
			c.draw_line(Vector2(16, 13), Vector2(16, 23), gold, 2.0)
		"overclock", "silicon", "lowpower":  # a chip, with a flame, shine or bolt
			var body := Color(0.25, 0.4, 0.3) if id != "silicon" else Color(0.35, 0.3, 0.5)
			for i in 4:
				c.draw_rect(Rect2(8 + i * 5, 2, 2, 28), grey)
				c.draw_rect(Rect2(2, 8 + i * 5, 28, 2), grey)
			c.draw_rect(Rect2(6, 6, 20, 20), body)
			if id == "overclock":
				c.draw_colored_polygon(PackedVector2Array([Vector2(16, 9), Vector2(22, 20), Vector2(16, 24), Vector2(10, 20)]), Color(1.0, 0.5, 0.15))
				c.draw_circle(Vector2(16, 20), 3, gold)
			elif id == "silicon":
				c.draw_rect(Rect2(11, 11, 10, 10), Color(0.75, 0.75, 0.85))
			else:
				c.draw_colored_polygon(PackedVector2Array([Vector2(18, 8), Vector2(11, 17), Vector2(16, 17), Vector2(14, 24), Vector2(21, 15), Vector2(16, 15)]), gold)
		"wafer":  # big round wafer with a grid
			c.draw_circle(Vector2(16, 16), 14, Color(0.6, 0.6, 0.75))
			for i in range(1, 4):
				c.draw_line(Vector2(i * 8, 4), Vector2(i * 8, 28), Color(0.4, 0.4, 0.55), 1.0)
				c.draw_line(Vector2(4, i * 8), Vector2(28, i * 8), Color(0.4, 0.4, 0.55), 1.0)
		"snacks":  # donut
			c.draw_circle(Vector2(16, 16), 13, Color(0.8, 0.55, 0.3))
			c.draw_circle(Vector2(16, 16), 11, Color(0.95, 0.5, 0.7))
			c.draw_circle(Vector2(16, 16), 4, Color(0.1, 0.1, 0.12))
		"standups":  # clock
			c.draw_circle(Vector2(16, 16), 13, Color(0.9, 0.9, 0.85))
			c.draw_line(Vector2(16, 16), Vector2(16, 7), dark, 2.0)
			c.draw_line(Vector2(16, 16), Vector2(23, 16), dark, 2.0)
		"hustle":  # coffee cup with steam
			c.draw_rect(Rect2(6, 12, 15, 17), Color(0.95, 0.95, 0.95))
			c.draw_arc(Vector2(22, 20), 4, -PI / 2, PI / 2, 8, Color(0.95, 0.95, 0.95), 2.0)
			c.draw_rect(Rect2(8, 14, 11, 4), Color(0.45, 0.28, 0.15))
			c.draw_line(Vector2(10, 9), Vector2(12, 3), grey, 2.0)
			c.draw_line(Vector2(16, 9), Vector2(18, 3), grey, 2.0)
		"pto":  # palm tree
			c.draw_line(Vector2(17, 30), Vector2(15, 10), Color(0.55, 0.4, 0.25), 3.0)
			for d in [Vector2(-10, 4), Vector2(10, 4), Vector2(-7, -5), Vector2(7, -5)]:
				c.draw_line(Vector2(15, 10), Vector2(15, 10) + d, Color(0.3, 0.75, 0.35), 3.0)
			c.draw_circle(Vector2(26, 6), 4, gold)
		_:
			c.draw_circle(Vector2(16, 16), 10, grey)


# Lines into each node: green once it's done, gold if it can be researched now, grey if not yet.
# Branch starters hang off the garage; everything else comes up from what it needs.
func _draw_research_lines() -> void:
	for r in RESEARCH:
		var p := _rt_node_pos(r)
		var to := p + Vector2(RT_NODE.x / 2.0, RT_NODE.y)
		var col := Color(0.4, 0.8, 0.45) if research_done.has(r.id) else (Color(1.0, 0.8, 0.35) if _research_open(r) else Color(0.4, 0.4, 0.42))
		var froms := []
		for id in r.get("req", []):
			froms.append(_rt_node_pos(_research_by_id(id)) + Vector2(RT_NODE.x / 2.0, 0))
		if froms.is_empty():
			froms.append(_rt_root())
		for from in froms:
			var mid: float = (from.y + to.y) / 2.0 if froms.size() == 1 or from.x == to.x else to.y + 18.0
			research_tree.draw_polyline(PackedVector2Array([from, Vector2(from.x, mid), Vector2(to.x, mid), to]), col, 3.0)


func _update_research_tab() -> void:
	if not research_page.visible:
		return
	if not research_scrolled:  # first look: the bottom of the tree, centred on the garage
		research_scrolled = true
		(func():
			research_scroll.scroll_vertical = int(research_tree.custom_minimum_size.y)
			research_scroll.scroll_horizontal = int((research_tree.custom_minimum_size.x - research_scroll.size.x) / 2.0)).call_deferred()
	var active := _research_by_id(research_active)
	if active.is_empty():
		research_label.text = "+%.1f points a day     Banked: %d     Nothing picked" % [_research_per_day(), int(research_points)]
		research_bar.value = 0
	else:
		research_label.text = "+%.1f points a day     %s: %d / %d" % [
			_research_per_day(), active.name, mini(int(research_points), active.cost), active.cost]
		research_bar.value = 100.0 * minf(research_points / active.cost, 1.0)
	for r in RESEARCH:
		var b: Button = research_buttons[r.id]
		var done := research_done.has(r.id)
		var open := _research_open(r)
		b.text = "%s\n%s" % [r.name, "Done" if done else ("Researching" if r.id == research_active else "%d pts" % r.cost)]
		b.disabled = done or not open
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(6)
		st.set_border_width_all(2)
		st.content_margin_left = 46  # room for the icon
		st.content_margin_bottom = 16 if r.has("con") else 0
		st.bg_color = Color(0.16, 0.3, 0.18) if done else (Color(0.22, 0.2, 0.15) if open else Color(0.13, 0.13, 0.15))
		st.border_color = Color(1.0, 0.8, 0.35) if r.id == research_active else (Color(0.4, 0.8, 0.45) if done else Color(0.3, 0.3, 0.33))
		for state in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(state, st)
		b.add_theme_color_override("font_disabled_color", Color(0.85, 0.95, 0.85) if done else Color(0.5, 0.5, 0.52))
	research_tree.queue_redraw()


func _research_by_id(id: String) -> Dictionary:
	for r in RESEARCH:
		if r.id == id:
			return r
	return {}


# A node opens once everything in its "req" list is done.
func _research_open(r: Dictionary) -> bool:
	for id in r.get("req", []):
		if not research_done.has(id):
			return false
	return true


func _pick_research(id: String) -> void:
	var r := _research_by_id(id)
	if research_done.has(id) or not _research_open(r):
		return
	research_active = "" if research_active == id else id
	_update_research_tab()


func _research_per_day() -> float:
	return (RESEARCH_BASE + RESEARCH_PER_WORKER * _workforce("research")) * (1.0 + _research_bonus("research_speed"))


func _tick_research() -> void:
	research_points += _research_per_day()
	var r := _research_by_id(research_active)
	if r.is_empty() or research_points < r.cost:
		return
	research_points -= r.cost
	research_done[r.id] = true
	research_active = ""
	for x in RESEARCH:  # carry on up the same branch
		if x.branch == r.branch and not research_done.has(x.id) and _research_open(x) and r.id in x.get("req", []):
			research_active = x.id
			break
	var keep := tool_index
	_label_tools()
	if _level_tools().has(keep):
		_select_tool(keep)
	_chet("Research done: %s. %s" % [r.name, r.desc])


# Sum of one bonus over every finished research node, e.g. 0.4 for +40%.
func _research_bonus(key: String) -> float:
	var v := 0.0
	for r in RESEARCH:
		if research_done.has(r.id):
			v += r.get(key, 0.0)
	return v
