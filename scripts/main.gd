extends Node2D
## Starter map: a small pre-built office in the Calizona desert, plus a handful of
## construction tools (Prison Architect style: you build and assign jobs, staff do the rest).
## Server racks give compute, compute trains models, and models win users, who pay.
## The board sets a target every quarter; miss too many and you're fired.

const TILE := 32
const SUB := TILE / 2  # each tile splits into a 2x2 subgrid for small, precisely placed items
const WALL_H := 22.0  # how tall walls look in the three-quarter view
const GRID_W := 64
const GRID_H := 48
const PAN_SPEED := 700.0
const SECONDS_PER_DAY := 900.0 / 91.0  # 15 real minutes per quarter at 1x
const START_YEAR := 2027
const FOUNDER_SALARY := 1200  # the founders took equity instead (the fools)
const RECRUITER_FEE := 5000
const SEVERANCE_DAYS := 5
const RACK_POWER_PER_DAY := 400
const REVENUE_PER_USER := 0.05  # dollars per user per day
const WIN_CAPABILITY := 100

# Training sizes. Cost and work grow with your best model (see _train_cost and _train_work).
const MODEL_SIZES := [
	{"name": "Small", "suffix": "Mini", "cost": 100_000, "work": 120.0, "gain": 8},
	{"name": "Medium", "suffix": "Pro", "cost": 400_000, "work": 450.0, "gain": 16},
	{"name": "Large", "suffix": "Ultra", "cost": 1_500_000, "work": 1500.0, "gain": 32},
]

# Who you can hire. A role decides salary and shirt; it does its matching job at full speed.
const ROLES := {
	"researcher": {"name": "Researcher", "salary": 1800, "shirt": Color(0.3, 0.5, 0.9)},
	"engineer": {"name": "Engineer", "salary": 1400, "shirt": Color(0.95, 0.6, 0.2)},
	"marketer": {"name": "Marketer", "salary": 1000, "shirt": Color(0.9, 0.4, 0.7)},
}
# Jobs you assign. at: what the job needs to work at. Anyone can do any job, at half speed off-role.
const JOBS := {
	"research": {"name": "Research", "at": "desk", "role": "researcher"},
	"engineering": {"name": "Engineering", "at": "rack", "role": "engineer"},
	"growth": {"name": "Growth", "at": "desk", "role": "marketer"},
	"none": {"name": "Slack off", "at": "", "role": ""},
}
const JOB_ORDER := ["research", "engineering", "growth", "none"]
const FIRST_NAMES := ["Brayden", "Priya", "Skyler", "Dmitri", "Kai", "Megan", "Tobias", "Aiko", "Jaxon",
	"Fatima", "Chad", "Lena", "Rohan", "Sienna", "Mateo", "Zoe", "Gunnar", "Imani", "Theo", "Wren"]
const NO_SEAT := Vector2i(-1, -1)
const DAYS_PER_QUARTER := 91

const BOARD := [
	{"name": "Chad Moneybags", "seat": "Venture Capital"},
	{"name": "Bitsy Pivot", "seat": "Influencer, 4M followers"},
	{"name": "Dr. Ethel Prudence", "seat": "Ethics (non-voting)"},
]

# Rival labs follow a script: [day, lab, model, capability].
const RIVAL_RELEASES := [
	[1, "ClosedAI", "ChatGTP-3", 10],
	[60, "Algorithmic", "Algo 1", 13],
	[150, "ClosedAI", "ChatGTP-4", 20],
	[230, "MassiveHard", "CoPlotter", 26],
	[320, "Algorithmic", "Algo Ultra", 34],
	[420, "ClosedAI", "ChatGTP-5", 45],
	[520, "MassiveHard", "CoPlotter 2", 55],
	[620, "Algorithmic", "Algo Infinity", 67],
	[730, "ClosedAI", "ChatGTP-6o-mini-max", 80],
	[850, "MassiveHard", "CoPlotter 365", 92],
]

# Every buildable thing. layer: which map layer it lives on. drag: how the mouse places it.
# Things on the "sub" layer take one subgrid cell (a quarter tile) and don't block walking.
const TOOLS := [
	{"id": "carpet", "name": "Carpet", "layer": "floor", "cost": 200, "drag": "fill"},
	{"id": "concrete", "name": "Concrete", "layer": "floor", "cost": 100, "drag": "fill"},
	{"id": "wall", "name": "Wall", "layer": "wall", "cost": 800, "drag": "outline"},
	{"id": "door", "name": "Door", "layer": "wall", "cost": 2500, "drag": "single"},
	{"id": "desk", "name": "Desk", "layer": "object", "cost": 6000, "drag": "paint"},
	{"id": "rack", "name": "Server Rack", "layer": "object", "cost": 100000, "drag": "paint"},
	{"id": "ficus", "name": "Ficus", "layer": "object", "cost": 300, "drag": "paint"},
	{"id": "coffee", "name": "Coffee Maker", "layer": "sub", "cost": 1500, "drag": "paint"},
	{"id": "demolish", "name": "Demolish", "layer": "", "cost": 0, "drag": "fill"},
]

const CHET_TIPS := [
	"Bro. Welcome to Calizona. Zero regulations, infinite sun, slightly less water.",
	"Drag Walls in a box and boom, you've got a room. That's basically architecture.",
	"Desks need a floor under them. Even disruptors need carpet, bro.",
	"Server Racks are where the AI lives. Feed them money and they feed you... eventually.",
	"Ficus plants boost morale by 0%. Investors love them though.",
	"Revenue? We're pre-revenue. That's a vibe, not a problem.",
	"More Server Racks means more compute means faster training. It's literally just math, bro.",
	"Researchers at desks train models faster. Engineers babysit racks for extra compute. Marketers at desks get users.",
	"Assign jobs in the Staff tab. You don't tell people what to do, you tell them what their job is. Leadership.",
	"The board sets one target a quarter. Hit it and they love you. Miss it and, well, I hear Uber's hiring.",
	"Users are revenue. Revenue is users. I learned that at Stanford. Well, near Stanford.",
	"Right-click demolishes stuff. Like the old office culture. Disrupted.",
	"Every door is an open door policy if you think about it.",
]

var floor_tiles := {}  # Vector2i -> "carpet" / "concrete"
var wall_tiles := {}  # Vector2i -> "wall" / "door"
var objects := {}  # Vector2i -> "desk" / "rack" / "ficus"
var sub_objects := {}  # subgrid cell Vector2i -> "coffee"

var money := 2_000_000
var company := "Untitled AI"
var models := []  # released, best last: [{name, cap, day}]
var training := {}  # in progress: {name, cap, work, done}
var users := 0.0
var revenue_today := 0
var rival: Array = RIVAL_RELEASES[0]
var _next_rival := 1
var confidence := 60  # Board Confidence; at 0 you're fired
var target := {}  # this quarter's board target: {kind, goal, text, quote, q}
var quarter_revenue := 0
var quarter_best_release := 0
var game_over := false
var day := 1
var speed := 1
var tool_index := 0
var hover := Vector2i(-1, -1)
var hover_sub := Vector2i(-1, -1)
var dragging := false
var drag_start := Vector2i.ZERO
var paint_tiles := {}
var panning := false

var staff := []  # [{name, role, job, salary, pos, path, wait, seat, spot, working, label}]
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
var ui_layer: CanvasLayer
var tabs: TabContainer
var models_label: Label
var train_label: Label
var train_bar: ProgressBar
var train_buttons := []
var staff_label: Label
var staff_list: VBoxContainer
var board_label: Label
var board_bar: ProgressBar
var board_target_label: Label
var board_members_label: Label
var modal: Control  # the open pop-up, if any; the game pauses under it
var modal_button: Button
var _speed_before_modal := 1


func _ready() -> void:
	rng.seed = 42
	_build_starter_office()
	astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE, TILE) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	_refresh_walkable()
	_add_staff("researcher", _tile_center(Vector2i(27, 22)), FOUNDER_SALARY)
	_add_staff("engineer", _tile_center(Vector2i(28, 22)), FOUNDER_SALARY)

	camera = Camera2D.new()
	camera.position = _tile_center(Vector2i(33, 22))
	camera.zoom = Vector2(1.4, 1.4)
	add_child(camera)
	_build_ui()
	_select_tool(0)
	_new_target(0)
	_ask_company_name()


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
	ui_layer = layer

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
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_select_tool.bind(i))
		row.add_child(b)
		tool_buttons.append(b)

	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", _panel_style())
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.offset_left = -330
	side.offset_right = -8
	side.offset_top = 56
	layer.add_child(side)
	tabs = TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	side.add_child(tabs)
	_build_models_tab()
	_build_staff_tab()
	_build_board_tab()

	cost_label = Label.new()
	cost_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cost_label.add_theme_constant_override("outline_size", 4)
	cost_label.visible = false
	layer.add_child(cost_label)
	_chet(CHET_TIPS[0])


func _tab_box(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = title
	box.custom_minimum_size.x = 300
	box.add_theme_constant_override("separation", 6)
	tabs.add_child(box)
	return box


func _wrap_label(parent: Control) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)
	return l


func _build_models_tab() -> void:
	var box := _tab_box("Models")
	models_label = _wrap_label(box)
	box.add_child(HSeparator.new())
	train_label = _wrap_label(box)
	train_bar = ProgressBar.new()
	train_bar.custom_minimum_size.y = 16
	train_bar.show_percentage = false
	box.add_child(train_bar)
	for i in MODEL_SIZES.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_start_training.bind(i))
		box.add_child(b)
		train_buttons.append(b)


func _update_models_tab() -> void:
	var best := "none yet" if models.is_empty() else "%s (capability %d)" % [models.back().name, models.back().cap]
	models_label.text = "Best model: %s\nUsers: %s\nRevenue: %s/day\nCompute: %d racks, %.1f per day\nTraining speed: %.1f per day\nTop rival: %s %s (capability %d)" % [
		best, _num(int(users)), _money(revenue_today), _racks(), _compute_per_day(), _training_speed(), rival[1], rival[2], rival[3]]
	var compute := _compute_per_day()
	if training.is_empty():
		train_label.text = "Nothing training. Pick a size:" if _racks() > 0 else "Build a Server Rack to train models."
		train_bar.visible = false
	else:
		var days_left := "?" if compute <= 0.0 else str(ceili((training.work - training.done) / _training_speed()))
		train_label.text = "Training %s (capability %d), %s days left" % [training.name, training.cap, days_left]
		train_bar.visible = true
		train_bar.value = 100.0 * training.done / training.work
	for i in MODEL_SIZES.size():
		var size: Dictionary = MODEL_SIZES[i]
		var days := "?" if compute <= 0.0 else str(ceili(_train_work(i) / _training_speed()))
		train_buttons[i].text = "Train %s   %s   ~%s days   +%d" % [size.name, _money(_train_cost(i)), days, size.gain]
		train_buttons[i].disabled = not training.is_empty() or _train_cost(i) > money or _racks() == 0


func _build_staff_tab() -> void:
	var box := _tab_box("Staff")
	staff_label = _wrap_label(box)
	for role in ROLES:
		var b := Button.new()
		b.text = "Hire %s   %s/day" % [ROLES[role].name, _money(ROLES[role].salary)]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_hire.bind(role))
		box.add_child(b)
	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 250
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	staff_list = VBoxContainer.new()
	staff_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(staff_list)
	_rebuild_staff_list()


func _rebuild_staff_list() -> void:
	for c in staff_list.get_children():
		c.queue_free()
	for s in staff:
		var row := HBoxContainer.new()
		staff_list.add_child(row)
		var dot := ColorRect.new()
		dot.color = ROLES[s.role].shirt
		dot.custom_minimum_size = Vector2(8, 30)
		row.add_child(dot)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		s.label = l
		var opt := OptionButton.new()
		opt.focus_mode = Control.FOCUS_NONE
		opt.add_theme_font_size_override("font_size", 12)
		for j in JOB_ORDER:
			opt.add_item(JOBS[j].name)
		opt.selected = JOB_ORDER.find(s.job)
		opt.item_selected.connect(_set_job.bind(s))
		row.add_child(opt)
		var fire := Button.new()
		fire.text = "Fire"
		fire.focus_mode = Control.FOCUS_NONE
		fire.add_theme_font_size_override("font_size", 12)
		fire.tooltip_text = "Severance: %d days of salary" % SEVERANCE_DAYS
		fire.pressed.connect(_fire.bind(s))
		row.add_child(fire)


func _update_staff_tab() -> void:
	var payroll := 0
	for s in staff:
		payroll += s.salary
		var status := "Slacking off"
		if s.working:
			status = "Working"
		elif s.seat != NO_SEAT:
			status = "Heading to work"
		elif JOBS[s.job].at != "":
			status = "Needs a free %s" % ("desk" if JOBS[s.job].at == "desk" else "server rack")
		s.label.text = "%s, %s\n%s" % [s.name, ROLES[s.role].name, status]
	staff_label.text = "%d staff, payroll %s/day\nWorking now: Research %.1f, Engineering %.1f, Growth %.1f" % [
		staff.size(), _money(payroll), _workforce("research"), _workforce("engineering"), _workforce("growth")]


func _build_board_tab() -> void:
	var box := _tab_box("Board")
	board_label = _wrap_label(box)
	board_bar = ProgressBar.new()
	board_bar.custom_minimum_size.y = 16
	board_bar.show_percentage = false
	box.add_child(board_bar)
	box.add_child(HSeparator.new())
	board_target_label = _wrap_label(box)
	box.add_child(HSeparator.new())
	board_members_label = _wrap_label(box)


func _update_board_tab() -> void:
	board_label.text = "Board Confidence: %d%%" % confidence
	board_bar.value = confidence
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.75, 0.4) if confidence >= 50 else (Color(0.9, 0.7, 0.2) if confidence >= 25 else Color(0.9, 0.3, 0.25))
	board_bar.add_theme_stylebox_override("fill", fill)
	var left := DAYS_PER_QUARTER - (day - 1) % DAYS_PER_QUARTER
	board_target_label.text = "This quarter: %s\nProgress: %s\n%d days left\n\n\"%s\"" % [
		target.text, _target_progress_text(), left, target.quote]
	var mood := "Thrilled. Already planning the IPO party." if confidence >= 70 \
		else ("Concerned. Using the word 'runway' a lot." if confidence >= 35 else "Quietly interviewing your replacement.")
	var lines := []
	for m in BOARD:
		lines.append("%s, %s" % [m.name, m.seat])
	board_members_label.text = "Mood: %s\n\n%s\n\nHit a target: +15. Miss: -25. At 0%% you're fired. Run out of money and you're fired faster." % [
		mood, "\n".join(lines)]


# A centered pop-up that pauses the game until its button is pressed.
func _show_modal(title: String, body: String, button_text: String, on_close: Callable, extra: Control = null) -> void:
	_speed_before_modal = speed
	_set_speed(0)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	var style := _panel_style(0.97)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 480
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	col.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(b)
	if extra:
		col.add_child(extra)
	var btn := Button.new()
	btn.text = button_text
	btn.pressed.connect(func():
		dim.queue_free()
		modal = null
		_set_speed(_speed_before_modal)
		on_close.call())
	col.add_child(btn)
	modal = dim
	modal_button = btn


func _ask_company_name() -> void:
	var edit := LineEdit.new()
	edit.placeholder_text = "Untitled AI"
	edit.max_length = 24
	edit.text_submitted.connect(func(_t): modal_button.pressed.emit())
	_show_modal("Welcome to Calizona",
		"Chet: Bro! You quit your job, I got us a seed round, and we're gonna build the smartest AI on Earth. Every unicorn needs a name. Make it sound like it's worth a billion dollars.",
		"Found the company", func():
			var n := edit.text.strip_edges()
			company = n if n != "" else "Untitled AI"
			_chet("%s. Love it. Huge. Now open the Models tab and train our first model on those racks." % company),
		edit)
	edit.call_deferred("grab_focus")


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
	var q := (day - 1) / DAYS_PER_QUARTER
	var burn := _daily_burn()
	var revenue := "Revenue %s/day" % _money(revenue_today) if models.size() > 0 else "Revenue $0 (pre-revenue)"
	top_label.text = "%s, Calizona     %s     Burn %s/day     %s     Users %s     Board %d%%     %s, Day %d" % [
		company, _money(money), _money(burn), revenue, _num(int(users)), confidence, _quarter_name(q), (day - 1) % DAYS_PER_QUARTER + 1]
	_update_models_tab()
	_update_staff_tab()
	_update_board_tab()


func _num(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func _money(v: int) -> String:
	return ("-$" if v < 0 else "$") + _num(absi(v))


# --- Loop and input ---------------------------------------------------------

func _process(delta: float) -> void:
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
	_tip_timer += delta
	if _tip_timer > 15.0:
		_tip = (_tip + 1) % CHET_TIPS.size()
		_chet(CHET_TIPS[_tip])

	hover = _mouse_tile()
	hover_sub = Vector2i((get_global_mouse_position() / SUB).floor())
	if paint_tiles.size() > 0 and dragging and _in_bounds(hover):
		paint_tiles[_cursor()] = true
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
	if modal:
		return
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
						paint_tiles[_cursor()] = true
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


func _is_sub_tool() -> bool:
	return TOOLS[tool_index].layer == "sub"


# The cell under the mouse for the current tool: a tile, or a subgrid cell for small items.
func _cursor() -> Vector2i:
	return hover_sub if _is_sub_tool() else hover


func _tile_of_sub(c: Vector2i) -> Vector2i:
	return Vector2i(floori(c.x / 2.0), floori(c.y / 2.0))


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
	if id == "coffee":  # t is a subgrid cell
		var tile := _tile_of_sub(t)
		return _in_bounds(tile) and floor_tiles.has(tile) and not wall_tiles.has(tile) \
			and not objects.has(tile) and not sub_objects.has(t)
	if not _in_bounds(t):
		return false
	match id:
		"carpet", "concrete":
			return floor_tiles.get(t) != id
		"wall":
			return not wall_tiles.has(t) and not objects.has(t) and _subs_in(t).is_empty()
		"door":
			return wall_tiles.get(t) != "door" and not objects.has(t) and _subs_in(t).is_empty()
		"demolish":
			return objects.has(t) or wall_tiles.has(t) or floor_tiles.has(t) or not _subs_in(t).is_empty()
	# furniture
	return floor_tiles.has(t) and not wall_tiles.has(t) and not objects.has(t) and _subs_in(t).is_empty()


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
			"sub": sub_objects[t] = tool.id
	_after_build()


func _demolish(t: Vector2i) -> void:
	# Removes the top-most thing on a tile and refunds half its price.
	# Small subgrid items go first, all of the tile's at once.
	var subs := _subs_in(t)
	if not subs.is_empty():
		for c in subs:
			money += int(_tool_by_id(sub_objects[c]).cost / 2)
			sub_objects.erase(c)
		return
	for layer in [objects, wall_tiles, floor_tiles]:
		if layer.has(t):
			money += int(_tool_by_id(layer[t]).cost / 2)
			layer.erase(t)
			return


func _daily_burn() -> int:
	var payroll := 0
	for s in staff:
		payroll += s.salary
	return payroll + _racks() * RACK_POWER_PER_DAY


# --- Models, users and rivals ------------------------------------------------

func _new_day() -> void:
	day += 1
	money -= _daily_burn()
	_tick_training()
	_tick_users()
	_tick_rivals()
	if game_over:
		return
	if money < 0:
		_end_game("Fired",
			"You ran out of money. The board fired you by group text, then asked if you could still Venmo them for lunch.")
	elif (day - 1) % DAYS_PER_QUARTER == 0:
		_end_quarter()

func _racks() -> int:
	var n := 0
	for t in objects:
		if objects[t] == "rack":
			n += 1
	return n


# Each engineer tending a rack adds half a rack's worth of compute.
func _compute_per_day() -> float:
	return _racks() + 0.5 * _workforce("engineering")


# Researchers make every unit of compute count for more.
func _training_speed() -> float:
	return _compute_per_day() * (1.0 + 0.25 * _workforce("research"))


func _best_cap() -> int:
	return 0 if models.is_empty() else models.back().cap


# Each step up the capability ladder costs more money and a lot more compute.
func _train_cost(i: int) -> int:
	return int(MODEL_SIZES[i].cost * pow(1.035, _best_cap()))


func _train_work(i: int) -> float:
	return MODEL_SIZES[i].work * pow(1.05, _best_cap())


func _start_training(i: int) -> void:
	var cost := _train_cost(i)
	if not training.is_empty() or _racks() == 0 or cost > money:
		return
	money -= cost
	var size: Dictionary = MODEL_SIZES[i]
	training = {
		"name": "%s-%d %s" % [company.split(" ")[0], models.size() + 1, size.suffix],
		"cap": _best_cap() + size.gain, "work": _train_work(i), "done": 0.0,
	}
	_chet(["Small model, smart move. Ship fast, apologize later.",
		"A Pro model. Investors love the word Pro. They don't know what it means either.",
		"ULTRA. Bro. This is the one. Probably. Unless it isn't."][i])


func _tick_training() -> void:
	if training.is_empty():
		return
	training.done += _training_speed()
	if training.done < training.work:
		return
	models.append({"name": training.name, "cap": training.cap, "day": day})
	quarter_best_release = maxi(quarter_best_release, training.cap)
	if training.cap >= WIN_CAPABILITY:
		_end_game("You win?",
			"%s reached capability %d. It reviewed the company, wrote a better strategy than yours in 4 seconds, and the board made it CEO.\n\nYou have built an AI fully capable of running the company itself. You win?" % [training.name, training.cap])
		training = {}
		return
	var beat := "We beat %s's %s! Screenshot the benchmark, ignore the others." % [rival[1], rival[2]] \
		if training.cap > rival[3] else "It's behind %s's %s, but the vibes are immaculate." % [rival[1], rival[2]]
	_chet("%s just shipped with capability %d. %s" % [training.name, training.cap, beat])
	training = {}


func _user_target() -> float:
	var cap := _best_cap()
	if cap == 0:
		return 0.0
	# More capable models attract more users, losing to the best rival costs share,
	# and marketers find more people to sell to.
	return 2500.0 * pow(cap, 1.5) * clampf(float(cap) / rival[3], 0.3, 1.5) * (1.0 + 0.2 * _workforce("growth"))


func _tick_users() -> void:
	var target := _user_target()
	users += (target - users) * (0.03 if target > users else 0.02)
	revenue_today = int(users * REVENUE_PER_USER)
	money += revenue_today
	quarter_revenue += revenue_today


func _tick_rivals() -> void:
	while _next_rival < RIVAL_RELEASES.size() and day >= RIVAL_RELEASES[_next_rival][0]:
		rival = RIVAL_RELEASES[_next_rival]
		_next_rival += 1
		_chet("%s just dropped %s, capability %d. Users are gonna be thirsty for that. Ship something, bro." % [rival[1], rival[2], rival[3]])


# --- Board ------------------------------------------------------------------

func _quarter_name(q: int) -> String:
	return "Q%d %d" % [q % 4 + 1, START_YEAR + q / 4]


func _round_up_nice(v: float) -> int:
	# 37,512 -> 38,000: round up to two significant digits.
	var step := pow(10.0, maxf(floorf(log(maxf(v, 1.0)) / log(10.0)) - 1.0, 0.0))
	return int(ceilf(v / step) * step)


# The board cycles through three kinds of demand, each a bit tougher than the last.
func _new_target(q: int) -> void:
	var kind: String = ["release", "users", "revenue"][q % 3]
	var goal := 0
	var text := ""
	var quote := ""
	match kind:
		"release":
			goal = 1 if q == 0 else maxi(_best_cap() + 1, rival[3])
			text = "Ship our first model. Any model." if q == 0 else "Release a model with capability %d or more" % goal
			quote = "Our competitors ship. We ship. I don't care what. - Chad Moneybags. (Dr. Prudence asked for a safety review. Noted.)"
		"users":
			goal = _round_up_nice(maxf(25_000.0, users * 1.5))
			text = "Reach %s users" % _num(goal)
			quote = "Users are the new users. I want %s of them. Go viral, babe. - Bitsy Pivot" % _num(goal)
		"revenue":
			goal = _round_up_nice(maxf(100_000.0, revenue_today * DAYS_PER_QUARTER * 1.3))
			text = "Earn %s in revenue this quarter" % _money(goal)
			quote = "Revenue. That's it. That's the memo. - Chad Moneybags"
	target = {"kind": kind, "goal": goal, "text": text, "quote": quote, "q": q}


func _target_progress() -> int:
	match target.kind:
		"release": return quarter_best_release
		"users": return int(users)
		_: return quarter_revenue


func _target_progress_text() -> String:
	var p := _target_progress()
	var done := "  (done!)" if p >= target.goal else ""
	match target.kind:
		"release": return ("best release this quarter: capability %d" % p if p > 0 else "nothing released yet") + done
		"users": return "%s / %s users%s" % [_num(p), _num(target.goal), done]
		_: return "%s / %s%s" % [_money(p), _money(target.goal), done]


func _end_quarter() -> void:
	var met: bool = _target_progress() >= target.goal
	var change := 15 if met else (-10 if target.q == 0 else -25)  # the first quarter is lenient
	confidence = clampi(confidence + change, 0, 100)
	var old: String = target.text
	var q := (day - 1) / DAYS_PER_QUARTER
	quarter_revenue = 0
	quarter_best_release = 0
	if confidence <= 0:
		_end_game("Fired",
			"Target: %s. Missed.\n\nThe board has voted to replace you as CEO, effective immediately. Chad will be taking over. He has a podcast." % old)
		return
	_new_target(q)
	var verdict := "Target met. Chad did a little dance." if met else "Target missed. Bitsy unfollowed you."
	_show_modal("%s board meeting" % _quarter_name(q - 1),
		"Target: %s\n%s\nBoard Confidence: %d%% (%+d)\n\nNext quarter: %s\n\"%s\"" % [old, verdict, confidence, change, target.text, target.quote],
		"Back to work", func(): pass)
	_chet("Board meeting survived. New target's in the Board tab. We got this. Probably.")


func _end_game(title: String, body: String) -> void:
	game_over = true
	_show_modal(title, body, "Start over", func(): get_tree().reload_current_scene())


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
		s.working = false
		# Lose the workstation if it was demolished or its spot got blocked.
		if s.seat != NO_SEAT and (objects.get(s.seat) != JOBS[s.job].at or not _walkable(s.spot)):
			s.seat = NO_SEAT


func _add_staff(role: String, pos: Vector2, salary: int) -> void:
	var taken := staff.map(func(s): return s.name)
	var name := ""
	for i in 20:
		name = "%s %s." % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], char(65 + rng.randi() % 26)]
		if not taken.has(name):
			break
	var job := ""
	for j in JOBS:
		if JOBS[j].role == role:
			job = j
	staff.append({"name": name, "role": role, "job": job, "salary": salary, "pos": pos,
		"path": PackedVector2Array(), "wait": rng.randf_range(0.5, 2.0), "seat": NO_SEAT,
		"spot": NO_SEAT, "working": false, "label": null})


func _hire(role: String) -> void:
	if money < RECRUITER_FEE:
		_chet("We can't even afford the recruiter, bro. Ramen budget.")
		return
	money -= RECRUITER_FEE
	var door := Vector2i(30, 30)
	var spots := floor_tiles.keys().filter(_walkable)
	var at: Vector2i = door if _walkable(door) or spots.is_empty() else spots[rng.randi() % spots.size()]
	_add_staff(role, _tile_center(at), ROLES[role].salary)
	_rebuild_staff_list()
	_chet(["Got us a researcher. PhD in something. Didn't read the thesis. Vibes were right.",
		"New engineer. Says she can make the racks go brrr. I believe her.",
		"Hired a marketer. He's already called our model 'basically sentient'. Legally risky, emotionally correct."][ROLES.keys().find(role)])


func _fire(s: Dictionary) -> void:
	money -= s.salary * SEVERANCE_DAYS
	staff.erase(s)
	_rebuild_staff_list()
	_chet("%s has been offboarded. I told them it's not a layoff, it's a 'talent release'." % s.name)


func _set_job(index: int, s: Dictionary) -> void:
	s.job = JOB_ORDER[index]
	s.seat = NO_SEAT
	s.working = false
	s.path = PackedVector2Array()
	s.wait = 0.0


# How much work a job is getting right now: one per person at their station, half if off-role.
func _workforce(job: String) -> float:
	var n := 0.0
	for s in staff:
		if s.working and s.job == job:
			n += 1.0 if s.role == JOBS[job].role else 0.5
	return n


# Where someone stands to use a desk or rack: a free walkable neighbor, front side first.
func _station_spot(t: Vector2i, kind: String) -> Vector2i:
	var sides := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN] if kind == "desk" \
		else [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
	for d in sides:
		var spot: Vector2i = t + d
		if _walkable(spot) and not staff.any(func(o): return o.spot == spot and o.seat != NO_SEAT):
			return spot
	return NO_SEAT


func _find_station(s: Dictionary, here: Vector2i) -> void:
	var kind: String = JOBS[s.job].at
	var best_len := 1 << 30
	for t in objects:
		if objects[t] != kind or staff.any(func(o): return o.seat == t):
			continue
		var spot := _station_spot(t, kind)
		if spot == NO_SEAT:
			continue
		var path := astar.get_id_path(here, spot)
		if (path.is_empty() and here != spot) or path.size() >= best_len:
			continue
		best_len = path.size()
		s.seat = t
		s.spot = spot


func _update_staff(delta: float) -> void:
	var spots := floor_tiles.keys().filter(_walkable)
	for s in staff:
		var here := Vector2i((s.pos / TILE).floor())
		if not _walkable(here) and not spots.is_empty():
			s.pos = _tile_center(spots[rng.randi() % spots.size()])  # got walled in; nudge them out
			continue
		if s.path.is_empty():
			if s.seat != NO_SEAT and here == s.spot:
				s.working = true
				continue
			s.working = false
			s.wait -= delta
			if s.wait > 0.0:
				continue
			s.wait = rng.randf_range(1.0, 4.0)
			if JOBS[s.job].at != "" and s.seat == NO_SEAT:
				_find_station(s, here)
			if s.seat != NO_SEAT:
				s.path = astar.get_point_path(here, s.spot)
				if s.path.is_empty():
					s.seat = NO_SEAT
			elif not spots.is_empty():
				s.path = astar.get_point_path(here, spots[rng.randi() % spots.size()])
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

	# Three-quarter view: things have height and are drawn back-to-front, row by row,
	# so anything further south overlaps what's behind it.
	var rows := {}
	for t in wall_tiles.keys() + objects.keys():
		if not rows.has(t.y):
			rows[t.y] = []
		rows[t.y].append(t)
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
				call("_draw_" + sub_objects[item.sub], Vector2(item.sub) * SUB)
			elif item is Dictionary:
				_draw_staff(item)
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


func _draw_coffee(p: Vector2) -> void:
	# p is the top-left of a 16x16 subgrid cell.
	_ellipse(p + Vector2(8, 14), 7, 2.5, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(3, 4), Vector2(10, 10)), 8, Color(0.2, 0.2, 0.22), Color(0.12, 0.12, 0.13))
	draw_rect(Rect2(p + Vector2(5, 7), Vector2(6, 4)), Color(0.35, 0.22, 0.12))  # the pot
	draw_rect(Rect2(p + Vector2(10, -3), Vector2(2, 2)), Color(1, 0.25, 0.2) if int(_time * 2) % 2 == 0 else Color(0.4, 0.1, 0.1))


func _draw_staff(s: Dictionary) -> void:
	var at_desk: bool = s.working and objects.get(s.seat) == "desk"
	# At a desk they sit down behind it, so the desk (drawn after) hides their legs.
	var pos: Vector2 = s.pos + (Vector2(0, 10) if at_desk else Vector2.ZERO)
	_draw_person(pos, ROLES[s.role].shirt)
	if s.working:
		# A little "busy" bubble with dots that tick along.
		var c := pos + Vector2(10, -38)
		draw_rect(Rect2(c, Vector2(16, 9)), Color(1, 1, 1, 0.9))
		var n := int(_time * 3.0 + s.pos.x) % 4
		for i in mini(n, 3):
			draw_rect(Rect2(c + Vector2(3 + i * 4, 4), Vector2(2, 2)), Color(0.15, 0.15, 0.2))


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
	var size := SUB if _is_sub_tool() else TILE
	var tiles: Array = _drag_tiles() if dragging else [_cursor()]
	for t in tiles:
		var ok := _can_place(tool.id, t)
		var c := Color(1, 0.3, 0.3, 0.35) if tool.id == "demolish" or not ok else Color(0.4, 1, 0.5, 0.35)
		if tool.id == "demolish" and not ok:
			c = Color(1, 1, 1, 0.15)
		draw_rect(Rect2(Vector2(t) * size, Vector2(size, size)), c)
	draw_rect(Rect2(Vector2(_cursor()) * size, Vector2(size, size)), Color(1, 1, 1, 0.8), false, 2.0)
