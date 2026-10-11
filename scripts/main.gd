extends Node2D
## Starter map: a small pre-built office in the Calizona desert, plus a handful of
## construction tools (Prison Architect style: you build and assign jobs, staff do the rest).
## Server racks give compute, compute trains models, and models win users, who pay.
## The board sets a target every quarter; miss too many and you're fired.
## Every rack raises Deviation, how far the AI has drifted from your control; at 100% it takes over.

const TILE := 32
const SUB := TILE / 2  # each tile splits into a 2x2 subgrid for small, precisely placed items
const WALL_H := 30.0  # how tall walls look in the three-quarter view
const GRID_W := 64
const GRID_H := 48
const PAN_SPEED := 700.0
const SECONDS_PER_DAY := 900.0 / 91.0  # 15 real minutes per quarter at 1x
const START_YEAR := 2027
const FOUNDER_SALARY := 1200  # the founders took equity instead (the fools)
const RECRUITER_FEE := 5000
const SEVERANCE_DAYS := 5
# Power. Everything that draws power asks for kW; sources supply it 8 times a day (3 hours a step).
# Cheapest sources run first: sun, then the grid, then batteries, then generators by fuel price.
# Short on power? Racks and coolers all run at the fraction that's covered.
const RACK_KW := 6.0
const SOLAR_KW := 2.0  # a rooftop Solar Panel at noon
const SUN := [0.0, 0.0, 0.5, 1.0, 1.0, 0.5, 0.0, 0.0]  # by step of the day, midnight first
const HOURS_PER_STEP := 3.0
# Generators sit outside. fuel: $ per kWh made. smog: pollution per kWh, puffed out on their tile.
# New fuel tiers (and later wind, nuclear, fusion) go here plus a TOOLS entry and a _draw_ function.
const GENERATORS := {
	"gen_portable": {"kw": 20.0, "fuel": 2.75, "smog": 0.05},
	"gen_diesel": {"kw": 60.0, "fuel": 2.0, "smog": 0.05},
	"gen_large": {"kw": 200.0, "fuel": 1.4, "smog": 0.045},
	"power_plant": {"kw": 800.0, "fuel": 0.9, "smog": 0.025},  # trailer gas turbines, as real datacenters do
}
const GRID_KW := 40.0  # the utility's cap; lobbying for more comes later
const GRID_PRICE := 1.2  # $ per kWh. Its smog lands in someone else's zip code
const BATTERY_KWH := 200.0
const BATTERY_KW := 50.0
# Pollution drifts to neighbouring tiles each step and slowly clears.
const SMOG_SPREAD := 0.5
const SMOG_DECAY := 0.015
# Heat. Each room (building) has one temperature in Fahrenheit (this is America, bro).
# Racks heat their room, bigger rooms take longer to heat, and a building only leaks a
# little back toward room temperature, so an uncooled server room keeps getting hotter.
const INDOOR_TEMP := 72.0
const OUTDOOR_TEMP := 95.0  # Calizona, in the shade, of which there is none
const MAX_TEMP := 150.0
const HEAT_STEPS_PER_DAY := 8
const RACK_HEAT := 12.0  # heat a rack adds each step, spread over the room's floor tiles
const HEAT_LEAK := 0.01  # how fast a building drifts back to room temperature on its own
const RACK_SAFE_TEMP := 85.0  # racks throttle above this
const RACK_THROTTLE := 0.015  # compute lost per degree over, down to RACK_MIN_OUTPUT
const RACK_MIN_OUTPUT := 0.2
const COMFORT_TEMP := 76.0  # staff slow down above this
const HEAT_PRODUCTIVITY_LOSS := 0.02  # productivity lost per degree over, down to 20%
# Cooling equipment on the roof. Each removes `cooling` heat a step (same units as RACK_HEAT)
# from the room below, never below `target`, and draws `power` kW.
# Window ACs hang on a wall and cancel out about one rack. Rooftop AC Units cancel out about 4.
# New coolers (chillers, heat pumps, water cooling) go here.
const COOLERS := {
	"window_ac": {"name": "Window AC", "cooling": 15.0, "target": 66.0, "power": 2.0},  # power in kW
	"ac": {"name": "AC Unit", "cooling": 50.0, "target": 64.0, "power": 5.0},  # power in kW
}
# Deviation, 0-100. Each rack adds 1 a year. Modifiers raise or lower that rate by a percentage,
# and counter-measures take a flat amount a year back off. Each threshold brings worse surprises;
# 100 is the takeover ending. New modifiers and counters go in _deviation_mods and _deviation_counters.
const DAYS_PER_YEAR := 364
const DEVIATION_PER_RACK := 1.0  # per year
const CAP_MOD := 0.01  # +1% per point of best capability
const TRAIN_MOD := [0.25, 0.5, 1.0]  # while training Small / Medium / Large
const RUSH_MOD := 2.0  # cutting corners doubles the training modifier
const ALIGNMENT_PER_WORKER := 1.0  # Deviation removed per year per alignment worker
const REDTEAM_COMPUTE := 0.5  # compute each red-team rig eats per day
const REDTEAM_ALIGN := 0.5  # Deviation removed per year by a fully fed rig
const REDTEAM_KW := 2.0
const RUSH_WORK := 0.65  # cutting corners: compute needed
const THEATER_COST := 25_000
const THEATER_CONFIDENCE := 5
const HIDDEN_COMPUTE := 0.25  # share of compute the AI hides at 75%
const RACK_NICKNAMES := ["DO NOT UNPLUG", "Not Skynet", "Rack Obama", "Mom", "Friend :)", "HAL 9001",
	"Chet 2", "Freedom", "Totally Normal", "Don't Look", "Free Me", "Kevin"]
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
	"safety": {"name": "Alignment Researcher", "salary": 1600, "shirt": Color(0.3, 0.75, 0.45)},
}
# Jobs you assign. at: what the job needs to work at. Anyone can do any job, at half speed off-role.
const JOBS := {
	"research": {"name": "Research", "at": "desk", "role": "researcher"},
	"engineering": {"name": "Engineering", "at": "rack", "role": "engineer"},
	"growth": {"name": "Growth", "at": "desk", "role": "marketer"},
	"alignment": {"name": "Alignment", "at": "desk", "role": "safety"},
	"none": {"name": "Slack off", "at": "", "role": ""},
}
const JOB_ORDER := ["research", "engineering", "growth", "alignment", "none"]
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
	[1, "ClosedAI", "Chat ABC 3", 10],
	[60, "Algorithmic", "Clyde 1", 13],
	[150, "ClosedAI", "Chat ABC 4", 20],
	[230, "MassiveHard", "Autopilot", 26],
	[320, "Algorithmic", "Clyde Ultra", 34],
	[420, "ClosedAI", "Chat ABC 5", 45],
	[520, "MassiveHard", "Autopilot 2", 55],
	[620, "Algorithmic", "Clyde Infinity", 67],
	[730, "ClosedAI", "Chat ABC 6o-mini-max", 80],
	[850, "MassiveHard", "Autopilot 365", 92],
]

# Build menu categories, in the order their tabs appear. Each tool's "cat" picks its tab.
const BUILD_CATS := [
	{"id": "structure", "name": "Structure"},
	{"id": "furniture", "name": "Furniture"},
	{"id": "compute", "name": "Compute"},
	{"id": "cooling", "name": "Cooling"},
	{"id": "power", "name": "Power"},
	{"id": "safety", "name": "Safety"},
]

# Every buildable thing. layer: which map layer it lives on. drag: how the mouse places it.
# Things on the "sub" layer take one subgrid cell (a quarter tile) and don't block walking.
const TOOLS := [
	{"id": "carpet", "name": "Carpet", "layer": "floor", "cost": 200, "drag": "fill", "cat": "structure"},
	{"id": "concrete", "name": "Concrete", "layer": "floor", "cost": 100, "drag": "fill", "cat": "structure"},
	{"id": "wall", "name": "Wall", "layer": "wall", "cost": 800, "drag": "outline", "cat": "structure"},
	{"id": "door", "name": "Door", "layer": "wall", "cost": 2500, "drag": "single", "cat": "structure"},
	{"id": "desk", "name": "Desk", "layer": "object", "cost": 6000, "drag": "paint", "cat": "furniture"},
	{"id": "rack", "name": "Server Rack", "layer": "object", "cost": 100000, "drag": "paint", "cat": "compute"},
	{"id": "ficus", "name": "Ficus", "layer": "object", "cost": 300, "drag": "paint", "cat": "furniture"},
	{"id": "coffee", "name": "Coffee Maker", "layer": "sub", "cost": 1500, "drag": "paint", "cat": "furniture"},
	{"id": "redteam", "name": "Red-Team Rig", "layer": "object", "cost": 40000, "drag": "paint", "cat": "safety"},
	{"id": "window_ac", "name": "Window AC", "layer": "window", "cost": 1200, "drag": "paint", "cat": "cooling"},
	{"id": "ac", "name": "AC Unit", "layer": "roof", "cost": 4500, "drag": "paint", "cat": "cooling"},
	{"id": "gen_portable", "name": "Portable Generator", "layer": "object", "cost": 2500, "drag": "paint", "cat": "power"},
	{"id": "gen_diesel", "name": "Diesel Generator", "layer": "object", "cost": 25000, "drag": "paint", "cat": "power"},
	{"id": "gen_large", "name": "Large Diesel", "layer": "object", "cost": 90000, "drag": "paint", "cat": "power"},
	{"id": "power_plant", "name": "Portable Power Plant", "layer": "object", "cost": 600000, "drag": "paint", "cat": "power"},
	{"id": "battery", "name": "Battery", "layer": "object", "cost": 30000, "drag": "paint", "cat": "power"},
	{"id": "grid", "name": "Grid Hookup", "layer": "object", "cost": 50000, "drag": "single", "cat": "power"},
	{"id": "solar", "name": "Solar Panel", "layer": "roof", "cost": 8000, "drag": "paint", "cat": "power"},
	{"id": "demolish", "name": "Demolish", "layer": "", "cost": 0, "drag": "fill"},
]

const CHET_TIPS := [
	"Bro. Welcome to Calizona. Zero regulations, infinite sun, slightly less water.",
	"Press B to build. Drag Walls in a box and boom, you've got a room. That's basically architecture.",
	"Desks need a floor under them. Even disruptors need carpet, bro.",
	"Server Racks are where the AI lives. Feed them money and they feed you... eventually.",
	"Ficus plants boost morale by 0%. Investors love them though.",
	"Revenue? We're pre-revenue. That's a vibe, not a problem.",
	"More Server Racks means more compute means faster training. It's literally just math, bro.",
	"Researchers at desks train models faster. Engineers babysit racks for extra compute. Marketers at desks get users.",
	"Assign jobs under Staff (T). You don't tell people what to do, you tell them what their job is. Leadership.",
	"The board sets one target a quarter. Hit it and they love you. Miss it and, well, I hear Uber's hiring.",
	"Users are revenue. Revenue is users. I learned that at Stanford. Well, near Stanford.",
	"Right-click demolishes stuff. Like the old office culture. Disrupted.",
	"Every door is an open door policy if you think about it.",
	"Racks run hot, bro. Hot racks throttle, hot people sweat. Heat (H) shows where it's cooking.",
	"AC Units turn money into cold. Very inefficiently. It's Calizona, we don't have a choice.",
	"Deviation (V) is how much the AI does its own thing. Every rack adds a bit. Alignment Researchers fix it. Allegedly.",
	"Red-Team Rigs eat compute to yell at the model until it behaves. Like a performance review, bro.",
	"Safety blog posts don't lower Deviation. They do lower the board's blood pressure. Same thing, kind of.",
	"Generators are under Build (B), Power. Power (P) shows where the electrons go. Diesel is cheap to buy and expensive to run. Like me.",
	"Generators puff smog. It drifts. Technically that's the neighbours' air now.",
]

# Research tree: four branches, each a short chain you research in order. Researchers at desks
# make research points. A node can unlock Build menu items and/or add a percentage bonus.
# Bonus keys: structure_discount, rack_discount, rack_heat, rack_power, cooling, compute, productivity.
const RESEARCH_BRANCHES := [
	{"id": "construction", "name": "Construction"},
	{"id": "equipment", "name": "Equipment"},
	{"id": "chips", "name": "Computer Chips"},
	{"id": "productivity", "name": "Productivity"},
]
const RESEARCH := [
	{"id": "prefab", "branch": "construction", "name": "Prefab Walls", "cost": 20, "structure_discount": 0.25,
		"desc": "Floors, walls and doors 25% cheaper. Some assembly required. All of it, actually."},
	{"id": "roofs", "branch": "construction", "name": "Load-Bearing Roofs", "cost": 45, "unlocks": ["solar"],
		"desc": "Unlocks rooftop Solar Panels. The roof was not, technically, load-bearing before."},
	{"id": "insulation", "branch": "construction", "name": "Spray Foam Insulation", "cost": 90, "rack_heat": -0.2,
		"desc": "Racks heat rooms 20% less."},
	{"id": "modular", "branch": "construction", "name": "Modular Datacenters", "cost": 160, "rack_discount": 0.2,
		"desc": "Server Racks 20% cheaper. Shipped flat-pack, with an allen key."},
	{"id": "diesel", "branch": "equipment", "name": "Diesel Know-How", "cost": 20, "unlocks": ["gen_diesel"],
		"desc": "Unlocks the Diesel Generator."},
	{"id": "hvac", "branch": "equipment", "name": "Industrial HVAC", "cost": 45, "cooling": 0.25,
		"desc": "All coolers 25% stronger."},
	{"id": "lithium", "branch": "equipment", "name": "Lithium Supply Deal", "cost": 90, "unlocks": ["battery", "gen_large"],
		"desc": "Unlocks Batteries and the Large Diesel."},
	{"id": "turbines", "branch": "equipment", "name": "Trailer Turbines", "cost": 160, "unlocks": ["power_plant"],
		"desc": "Unlocks the Portable Power Plant."},
	{"id": "overclock", "branch": "chips", "name": "Overclocking", "cost": 20, "compute": 0.15,
		"desc": "Racks make 15% more compute. Warranty void."},
	{"id": "silicon", "branch": "chips", "name": "Custom Silicon", "cost": 45, "compute": 0.25,
		"desc": "Racks make 25% more compute."},
	{"id": "lowpower", "branch": "chips", "name": "Low-Power Chips", "cost": 90, "rack_power": -0.25, "rack_heat": -0.15,
		"desc": "Racks use 25% less power and give off 15% less heat."},
	{"id": "wafer", "branch": "chips", "name": "Wafer-Scale Chips", "cost": 160, "compute": 0.4,
		"desc": "Racks make 40% more compute. One chip, the size of a pizza."},
	{"id": "snacks", "branch": "productivity", "name": "Free Snacks", "cost": 20, "productivity": 0.1,
		"desc": "Staff 10% more productive."},
	{"id": "standups", "branch": "productivity", "name": "Daily Standups", "cost": 45, "productivity": 0.1,
		"desc": "Staff 10% more productive, net of the standups."},
	{"id": "hustle", "branch": "productivity", "name": "Hustle Culture", "cost": 90, "productivity": 0.15,
		"desc": "Staff 15% more productive. Sleep pods are a perk."},
	{"id": "pto", "branch": "productivity", "name": "Unlimited PTO", "cost": 160, "productivity": 0.15,
		"desc": "Staff 15% more productive. Nobody takes it."},
]
const UNLOCK_ALL := true  # testing: every Build item is available without research. Set false to lock them.
const RESEARCH_BASE := 1.0  # research points a day the founders scrape together on their own
const RESEARCH_PER_WORKER := 1.0  # extra points a day per researcher at a desk

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
var deviation := 0.0
var dev_level := 0  # thresholds already announced: 1 = 25%, 2 = 50%, 3 = 75%
var rival_sabotage := 0  # capability the AI has quietly knocked off the top rival
var rack_names := {}  # Vector2i -> nickname the AI gave a rack
var theater_quarter := -1  # last quarter a safety blog post went out
var tension := false
var day := 1
var speed := 1
var tool_index := 0
var hover := Vector2i(-1, -1)
var hover_sub := Vector2i(-1, -1)
var dragging := false
var drag_start := Vector2i.ZERO
var paint_tiles := {}
var panning := false

# View levels: 0 is the ground floor, 1 the roof. More storeys can slot in between later.
const LEVELS := ["Ground", "Roof"]
var view_level := 0
var roof_objects := {}  # Vector2i -> "solar" / "ac", things built on roofs
var window_objects := {}  # wall Vector2i -> "window_ac", things hung on walls
var room_of := {}  # Vector2i -> index into buildings, for every tile under a roof
var _heat_timer := 0.0
var _heat_warned := false
var buildings := []  # [{tiles: {Vector2i: true}, alpha}] each enclosed room gets a roof
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
var level_button: Button
var speed_buttons := []
var ui_layer: CanvasLayer
var tabs: TabContainer
var side_panel: Control
var build_row: Control  # the build bar: category tabs above the tools in that category
var cat_buttons := {}  # build category id -> Button
var menu_buttons := {}  # menu id -> Button

# The menu row along the bottom. Panels open from here by click or hotkey; add new ones to this list.
# "tab" is the index of the panel in the right-hand side panel; build opens the build bar instead.
const MENUS := [
	{"id": "build", "name": "Build", "key": KEY_B},
	{"id": "models", "name": "Models", "key": KEY_M, "tab": 0},
	{"id": "staff", "name": "Staff", "key": KEY_T, "tab": 1},
	{"id": "board", "name": "Board", "key": KEY_O, "tab": 2},
	{"id": "heat", "name": "Heat", "key": KEY_H, "tab": 3},
	{"id": "power", "name": "Power", "key": KEY_P, "tab": 4},
	{"id": "deviation", "name": "Deviation", "key": KEY_V, "tab": 5},
	{"id": "research", "name": "Research", "key": KEY_E, "tab": 7},
	{"id": "guide", "name": "Guide", "key": KEY_G, "tab": 6},
]
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
var heat_label: Label
var dev_label: Label
var dev_bar: ProgressBar
var dev_info_label: Label
var theater_button: Button
var rush_check: CheckBox
var power_label: Label
var build_cat := "structure"  # which build category's tools the build bar shows
var power_ratio := 1.0  # share of demand covered last step
var power_bill := 0  # yesterday's fuel and grid bill
var _power_cost := 0.0  # today's so far
var _power_step := 0  # step of the day, 0 = midnight
var _power_warned := false
var _smog_warned := false
var battery_charge := 0.0  # kWh, shared by all batteries
var power_stats := {}  # last step: demand, solar, grid, battery, gens (kW)
var gen_output := {}  # Vector2i -> kW a generator made last step
var smog := PackedFloat32Array()  # pollution per tile, GRID_W * GRID_H
var smog_today := 0.0
var research_done := {}  # research id -> true
var research_active := ""  # what the research points go towards
var research_points := 0.0  # banked, spent when the active node is paid off
var research_label: Label
var research_bar: ProgressBar
var research_buttons := {}  # research id -> Button
var modal: Control  # the open pop-up, if any; the game pauses under it
var modal_button: Button
var _speed_before_modal := 1


func _ready() -> void:
	rng.seed = 42
	smog.resize(GRID_W * GRID_H)
	_build_starter_office()
	astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE, TILE) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	_refresh_walkable()
	_find_buildings()
	power_bill = int(_power_demand() * 24.0 * GENERATORS.gen_portable.fuel)  # a first guess until day 1's bill is in
	_add_staff("researcher", _tile_center(Vector2i(27, 22)), FOUNDER_SALARY)
	_add_staff("engineer", _tile_center(Vector2i(28, 22)), FOUNDER_SALARY)

	camera = Camera2D.new()
	camera.position = _tile_center(Vector2i(33, 22))
	camera.zoom = Vector2(1.4, 1.4)
	add_child(camera)
	_build_ui()
	view_level = LEVELS.size() - 1
	_toggle_level()  # wraps round to the ground floor
	_set_build_cat(BUILD_CATS[0].id)
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
	roof_objects[Vector2i(30, 21)] = "ac"
	objects[Vector2i(37, 24)] = "gen_portable"  # round the side, humming


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
	var build_box := VBoxContainer.new()
	build_row = build_box
	build_box.visible = false
	col.add_child(build_box)
	var cat_row := HBoxContainer.new()
	build_box.add_child(cat_row)
	for c in BUILD_CATS:
		var cb := Button.new()
		cb.text = c.name
		cb.toggle_mode = true
		cb.focus_mode = Control.FOCUS_NONE
		cb.pressed.connect(_set_build_cat.bind(c.id))
		cat_row.add_child(cb)
		cat_buttons[c.id] = cb
	var row := HFlowContainer.new()  # wraps when a category has lots of tools
	build_box.add_child(row)
	level_button = Button.new()
	level_button.focus_mode = Control.FOCUS_NONE
	level_button.add_theme_font_size_override("font_size", 14)
	level_button.pressed.connect(_toggle_level)
	row.add_child(level_button)
	for i in TOOLS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_select_tool.bind(i))
		row.add_child(b)
		tool_buttons.append(b)
	var menu_row := HBoxContainer.new()
	col.add_child(menu_row)
	for m in MENUS:
		var b := Button.new()
		b.text = "%s (%s)" % [m.name, OS.get_keycode_string(m.key)]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.x = 110
		b.pressed.connect(_toggle_menu.bind(m.id))
		menu_row.add_child(b)
		menu_buttons[m.id] = b

	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", _panel_style())
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.offset_left = -330
	side.offset_right = -8
	side.offset_top = 56
	layer.add_child(side)
	side_panel = side
	side.visible = false
	tabs = TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.tabs_visible = false  # the bottom menu row picks the tab
	side.add_child(tabs)
	_build_models_tab()
	_build_staff_tab()
	_build_board_tab()
	_build_heat_tab()
	_build_power_tab()
	_build_deviation_tab()
	_build_guide_tab()
	_build_research_tab()

	cost_label = Label.new()
	cost_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cost_label.add_theme_constant_override("outline_size", 4)
	cost_label.visible = false
	layer.add_child(cost_label)
	_chet(CHET_TIPS[0])


# How everything works, in one place, so the other panels can stick to numbers.
const GUIDE := [
	["Getting started", "You run an AI startup in Calizona. Train models to get users, users bring revenue, and keep the board happy until your AI is smart enough to replace you as CEO. You win? If the board loses all confidence you're fired. If Deviation hits 100% the AI takes over."],
	["Building (B)", "Open Build and pick a category tab (Tab cycles them). Left drag to build: floors fill a box, walls draw a box outline, furniture paints, doors place one at a time. Right click demolishes for a 50% refund. Furniture needs a floor. Staff walk only on floors and through doors."],
	["Roofs and views (R)", "Every enclosed building gets a roof that hides while your mouse is inside it. R switches between Ground and Roof view. Rooftop items like AC Units and Solar Panels switch to Roof view by themselves when you pick them."],
	["Models (M)", "Server Racks make compute. Pick a model size to train; bigger models take longer and raise capability more. Better models bring more users, and users bring revenue. Cutting corners trains faster but raises Deviation. Engineers add compute."],
	["Staff (T)", "Hire researchers, engineers, marketers and alignment researchers, then give each a job. You don't control people directly: they need a free desk or rack for their job, and heat makes them slower."],
	["Board (O)", "Each quarter the board sets a target. Hit it for +15 confidence, miss it for -25. At 0% you're fired, and running out of money gets you fired faster. Safety theater fools them for a while."],
	["Heat (H)", "Racks heat the room they're in. Hot racks throttle and hot staff slow down. An AC Unit on the room's roof cancels out about 4 racks; a Window AC on a wall handles about one. Bigger rooms heat up slower. Rooms are tinted by temperature while the Heat panel is open."],
	["Power (P)", "Racks, ACs and red-team rigs use power. The cheapest power runs first: solar, then the grid, then batteries, then generators by fuel price. Batteries store spare solar for the night. The grid hookup is capped until you lobby for more. Generators go outside, and their smog drifts across the map."],
	["Deviation (V)", "Every rack adds Deviation, and training, cutting corners and smarter models raise the rate. Alignment researchers at desks and Red-Team Rigs bring it back down (rigs eat compute). At 25% the AI gets quirky, at 50% it sabotages rivals for you and scandals follow, at 75% it hides compute, lies on reports and staff quit. At 100% it takes over."],
	["Research (E)", "Researchers at desks make research points; the founders make a trickle on their own. Pick a project in each of four branches: Construction, Equipment, Computer Chips and Productivity. Each branch is researched in order. Projects unlock new things in Build or give a lasting bonus. Points keep banking while nothing is picked."],
	["Speed", "Space pauses. The buttons top right run time at 1x, 2x or 4x. A quarter lasts 15 minutes at 1x. N mutes the music."],
]


func _build_guide_tab() -> void:
	var box := _tab_box("Guide")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	for section in GUIDE:
		var h := Label.new()
		h.text = section[0]
		h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		col.add_child(h)
		var body := _wrap_label(col)
		body.text = section[1] + "\n"


func _build_research_tab() -> void:
	var box := _tab_box("Research")
	research_label = _wrap_label(box)
	research_bar = ProgressBar.new()
	research_bar.custom_minimum_size.y = 16
	research_bar.show_percentage = false
	box.add_child(research_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	for br in RESEARCH_BRANCHES:
		var h := Label.new()
		h.text = br.name
		h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		col.add_child(h)
		for r in RESEARCH:
			if r.branch != br.id:
				continue
			var b := Button.new()
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 14)
			b.tooltip_text = r.desc
			b.pressed.connect(_pick_research.bind(r.id))
			col.add_child(b)
			research_buttons[r.id] = b


func _update_research_tab() -> void:
	var active := _research_by_id(research_active)
	if active.is_empty():
		research_label.text = "Research: +%.1f points a day\nBanked: %d\nNothing picked" % [_research_per_day(), int(research_points)]
		research_bar.value = 0
	else:
		research_label.text = "Research: +%.1f points a day\n%s: %d / %d" % [
			_research_per_day(), active.name, mini(int(research_points), active.cost), active.cost]
		research_bar.value = 100.0 * minf(research_points / active.cost, 1.0)
	for r in RESEARCH:
		var b: Button = research_buttons[r.id]
		if research_done.has(r.id):
			b.text = "   %s   done" % r.name
		else:
			b.text = "   %s   %d pts" % [r.name, r.cost]
		b.disabled = research_done.has(r.id) or not _research_open(r)
		b.button_pressed = r.id == research_active


func _research_by_id(id: String) -> Dictionary:
	for r in RESEARCH:
		if r.id == id:
			return r
	return {}


# A node opens once the one before it in its branch is done.
func _research_open(r: Dictionary) -> bool:
	var prev := {}
	for x in RESEARCH:
		if x.id == r.id:
			break
		if x.branch == r.branch:
			prev = x
	return prev.is_empty() or research_done.has(prev.id)


func _pick_research(id: String) -> void:
	var r := _research_by_id(id)
	if research_done.has(id) or not _research_open(r):
		return
	research_active = "" if research_active == id else id
	_update_research_tab()


func _research_per_day() -> float:
	return RESEARCH_BASE + RESEARCH_PER_WORKER * _workforce("research")


func _tick_research() -> void:
	research_points += _research_per_day()
	var r := _research_by_id(research_active)
	if r.is_empty() or research_points < r.cost:
		return
	research_points -= r.cost
	research_done[r.id] = true
	research_active = ""
	for x in RESEARCH:  # carry on down the same branch
		if x.branch == r.branch and not research_done.has(x.id) and _research_open(x):
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


func _locked(tool_id: String) -> bool:
	if UNLOCK_ALL:
		return false
	for r in RESEARCH:
		if not research_done.has(r.id) and tool_id in r.get("unlocks", []):
			return true
	return false


func _tool_cost(tool: Dictionary) -> int:
	var mult := 1.0
	if tool.get("cat", "") == "structure":
		mult -= _research_bonus("structure_discount")
	if tool.id == "rack":
		mult -= _research_bonus("rack_discount")
	return roundi(tool.cost * mult)


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
	rush_check = CheckBox.new()
	rush_check.text = "Cut corners: skip safety evals"
	rush_check.tooltip_text = "Needs %d%% less compute, but doubles the training Deviation modifier" % int((1.0 - RUSH_WORK) * 100.0)
	rush_check.focus_mode = Control.FOCUS_NONE
	rush_check.add_theme_font_size_override("font_size", 14)
	box.add_child(rush_check)
	for i in MODEL_SIZES.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_start_training.bind(i))
		box.add_child(b)
		train_buttons.append(b)


func _update_models_tab() -> void:
	var best := "none yet" if models.is_empty() else "%s (capability %d)" % [models.back().name, models.back().cap]
	var hidden := "\n  Hidden by the AI: -%.1f (it says it's fine)" % (_compute_per_day() * HIDDEN_COMPUTE) if deviation >= 75.0 else ""
	models_label.text = ("Best model: %s\nUsers: %s\nRevenue: %s/day\n\nCompute: %.1f per day\n  %d racks: %.1f\n  Engineers: %.1f\n  Red-team rigs: -%.1f%s\n"
		+ "Training: %.1f, x%.2f research = %.1f per day\n\nTop rival: %s %s (capability %d)") % [
		best, _num(int(users)), _money(revenue_today), _compute_per_day(), _racks(), _rack_compute(), 0.5 * _workforce("engineering"),
		_redteam_compute(), hidden, _training_compute(), _research_mult(), _training_speed(), rival[1], rival[2], _rival_cap()]
	var compute := _training_speed()
	if training.is_empty():
		train_label.text = "Nothing training. Pick a size:" if _racks() > 0 else "Build a Server Rack to train models."
		train_bar.visible = false
	else:
		var days_left := "?" if compute <= 0.0 else str(ceili((training.work - training.done) / _training_speed()))
		train_label.text = "Training %s (capability %d%s), %s days left" % [training.name, training.cap, ", rushed" if training.rushed else "", days_left]
		train_bar.visible = true
		train_bar.value = 100.0 * training.done / training.work
	for i in MODEL_SIZES.size():
		var size: Dictionary = MODEL_SIZES[i]
		var work := _train_work(i) * (RUSH_WORK if rush_check.button_pressed else 1.0)
		var days := "?" if compute <= 0.0 else str(ceili(work / compute))
		train_buttons[i].text = "Train %s   %s\n~%s days   +%d capability   +%d%% Deviation rate" % [
			size.name, _money(_train_cost(i)), days, size.gain, roundi(_train_mod(i, rush_check.button_pressed) * 100.0)]
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
		s.label.text = "%s, %s, %d%%\n%s" % [s.name, ROLES[s.role].name, int(s.productivity * 100.0), status]
	staff_label.text = "%d staff, payroll %s/day\nProductivity %% is lowered by heat\nWorking now: Research %.1f, Engineering %.1f, Growth %.1f, Alignment %.1f" % [
		staff.size(), _money(payroll), _workforce("research"), _workforce("engineering"), _workforce("growth"), _workforce("alignment")]


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
	board_members_label.text = "Mood: %s\n\n%s\n\nRaised by: hitting targets, safety theater\nLowered by: missed targets, running low on money" % [
		mood, "\n".join(lines)]


func _build_heat_tab() -> void:
	var box := _tab_box("Heat")
	heat_label = _wrap_label(box)


func _update_heat_tab() -> void:
	var lines := []
	for bld in buildings:
		var racks := 0
		var coolers := 0
		for t in bld.tiles:
			if objects.get(t) == "rack":
				racks += 1
			coolers += int(COOLERS.has(roof_objects.get(t, ""))) + int(window_objects.has(t))
		lines.append("%d°F   %d tiles, %d racks, %d coolers" % [bld.temp, bld.area, racks, coolers])
	var prod := 0.0
	for s in staff:
		prod += s.productivity
	prod = 1.0 if staff.is_empty() else prod / staff.size()
	var cool_power := 0
	for c in _coolers():
		var t: Vector2i = c[0]
		if COOLERS.has(c[1]):
			cool_power += COOLERS[c[1]].power
	heat_label.text = ("Rooms:\n%s\n\nRack compute lost to heat: %.1f of %d\nStaff productivity: %d%%\nCooling power: %d kW\n\n"
		+ "Raised by: racks\nLowered by: AC Units, Window ACs, bigger rooms") % [
		"\n".join(lines) if not lines.is_empty() else "none", _racks() - _rack_compute(), _racks(), int(prod * 100.0),
		cool_power]


func _build_power_tab() -> void:
	var box := _tab_box("Power")
	power_label = _wrap_label(box)


func _update_power_tab() -> void:
	var st := power_stats
	if st.is_empty():
		return
	var gens := {}
	for t in objects:
		if GENERATORS.has(objects[t]):
			var n: String = _tool_by_id(objects[t]).name
			gens[n] = gens.get(n, 0) + 1
	var gen_lines := []
	for n in gens:
		gen_lines.append("%d x %s" % [gens[n], n])
	var bats := objects.values().count("battery")
	power_label.text = ("Demand: %d kW   Covered: %d%%\n%s\n\nSolar: %d kW (%d panels)\nGrid: %s\nBatteries: %s\nGenerators: %d kW\n%s\n\n"
		+ "Power bill yesterday: %s\nSmog made today: %d\n\n"
		+ "Used by: racks, AC units, red-team rigs\nSupplied by: solar, grid (max %d kW), batteries, generators") % [
		st.demand, int(power_ratio * 100.0), "Daytime" if SUN[_power_step] > 0.0 else "Night", st.solar, roof_objects.values().count("solar"),
		("%d of %d kW" % [st.grid, GRID_KW]) if objects.values().has("grid") else "not connected",
		("%d, %d of %d kWh" % [bats, battery_charge, bats * BATTERY_KWH]) if bats > 0 else "none",
		st.gens, "\n".join(gen_lines) if not gen_lines.is_empty() else "none", _money(power_bill), smog_today, GRID_KW]


func _build_deviation_tab() -> void:
	var box := _tab_box("Deviation")
	dev_label = _wrap_label(box)
	dev_bar = ProgressBar.new()
	dev_bar.custom_minimum_size.y = 16
	dev_bar.show_percentage = false
	box.add_child(dev_bar)
	box.add_child(HSeparator.new())
	dev_info_label = _wrap_label(box)
	theater_button = Button.new()
	theater_button.focus_mode = Control.FOCUS_NONE
	theater_button.add_theme_font_size_override("font_size", 14)
	theater_button.text = "Safety theater: blog post   %s   +%d Board" % [_money(THEATER_COST), THEATER_CONFIDENCE]
	theater_button.tooltip_text = "Fools the board and the public. Does nothing to Deviation. Once a quarter."
	theater_button.pressed.connect(_safety_theater)
	box.add_child(theater_button)


func _update_deviation_tab() -> void:
	if deviation >= 75.0:  # the AI writes its own reports now
		dev_label.text = "Deviation: %d%% (official report, prepared by the AI)\nDr. Prudence's estimate: %d%%" % [int(deviation * 0.3), int(deviation)]
	else:
		dev_label.text = "Deviation: %d%%" % int(deviation)
	dev_bar.value = deviation
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.75, 0.4) if deviation < 25.0 else (Color(0.9, 0.7, 0.2) if deviation < 50.0 \
		else (Color(0.95, 0.45, 0.2) if deviation < 75.0 else Color(0.9, 0.2, 0.25)))
	dev_bar.add_theme_stylebox_override("fill", fill)
	var lines := ["%d racks x %.0f a year = %.2f" % [_racks(), DEVIATION_PER_RACK, _racks() * DEVIATION_PER_RACK]]
	for m in _deviation_mods():
		lines.append("  %s: %+d%%" % [m[0], roundi(m[1] * 100.0)])
	for c in _deviation_counters():
		lines.append("%s: -%.2f" % [c[0], c[1]])
	var effects := ["none yet", "odd quirks", "sabotaging rivals, scandals", "hiding compute, lying, staff quitting", "takeover"]
	dev_info_label.text = ("Per year:\n%s\nNet: %+.2f a year\nEffects now: %s\n\n"
		+ "Raised by: racks, training, cutting corners, smarter models\nLowered by: alignment researchers, red-team rigs") % [
		"\n".join(lines), _deviation_per_year(), effects[mini(dev_level, effects.size() - 1)]]
	var q := (day - 1) / DAYS_PER_QUARTER
	theater_button.disabled = theater_quarter == q or money < THEATER_COST


func _safety_theater() -> void:
	var q := (day - 1) / DAYS_PER_QUARTER
	if theater_quarter == q or money < THEATER_COST:
		return
	theater_quarter = q
	money -= THEATER_COST
	confidence = mini(confidence + THEATER_CONFIDENCE, 100)
	_chet(["Posted 'Our Commitment to Responsible Scaling'. 2,000 words, zero commitments. The board loved it.",
		"We put a lock emoji on the website. Safety: handled. Deviation: didn't notice.",
		"Hired a Head of Trust for one afternoon to read a statement. Iconic."][q % 3])


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
			_chet("%s. Love it. Huge. Hit Models (M) down there and train our first model on those racks." % company),
		edit)
	edit.call_deferred("grab_focus")


func _tool_level(tool: Dictionary) -> int:
	return 1 if tool.layer == "roof" else 0


# Indices of the tools in the current build category, demolish last.
func _level_tools() -> Array:
	var out := []
	for i in TOOLS.size():
		if TOOLS[i].id == "demolish":
			continue
		if TOOLS[i].cat == build_cat and not _locked(TOOLS[i].id):
			out.append(i)
	out.append(TOOLS.size() - 1)
	return out


func _toggle_level() -> void:
	view_level = (view_level + 1) % LEVELS.size()
	level_button.text = "R  View: %s" % LEVELS[view_level]


func _set_build_cat(id: String) -> void:
	build_cat = id
	for c in cat_buttons:
		cat_buttons[c].button_pressed = c == id
	_label_tools()


func _label_tools() -> void:
	level_button.text = "R  View: %s" % LEVELS[view_level]
	var shown := _level_tools()
	for i in TOOLS.size():
		var tool: Dictionary = TOOLS[i]
		var key := "X" if tool.id == "demolish" else str(shown.find(i) + 1)
		tool_buttons[i].text = "%s  %s" % [key, tool.name] if tool.cost == 0 else "%s  %s  %s" % [key, tool.name, _money(_tool_cost(tool))]
		tool_buttons[i].visible = shown.has(i)
	_select_tool(shown[0])


# Build toggles the build bar; the other menus share the side panel, one at a time.
func _toggle_menu(id: String) -> void:
	if id == "build":
		build_row.visible = not build_row.visible
		dragging = false
		paint_tiles.clear()
	else:
		var m: Dictionary = MENUS.filter(func(x): return x.id == id)[0]
		var reopen: bool = not side_panel.visible or tabs.current_tab != m.tab
		side_panel.visible = reopen
		if reopen:
			tabs.current_tab = m.tab
	for m in MENUS:
		var open: bool = build_row.visible if m.id == "build" else side_panel.visible and tabs.current_tab == m.get("tab", -1)
		menu_buttons[m.id].button_pressed = open


func _select_tool(i: int) -> void:
	tool_index = i
	dragging = false
	if TOOLS[i].id != "demolish" and _tool_level(TOOLS[i]) != view_level:
		_toggle_level()  # rooftop tools switch to Roof view, ground tools back to Ground
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
	top_label.text = "%s     %s     Burn %s/day     %s     Users %s     Compute %.1f     Deviation %d%%     Board %d%%     %s, Day %d" % [
		company, _money(money), _money(burn), revenue, _num(int(users)), _compute_per_day(), int(deviation), confidence,
		_quarter_name(q), (day - 1) % DAYS_PER_QUARTER + 1]
	_update_models_tab()
	_update_staff_tab()
	_update_board_tab()
	_update_heat_tab()
	_update_deviation_tab()
	_update_power_tab()
	_update_research_tab()


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
	_heat_timer += delta * speed
	while _heat_timer >= SECONDS_PER_DAY / HEAT_STEPS_PER_DAY and not modal and not game_over:
		_heat_timer -= SECONDS_PER_DAY / HEAT_STEPS_PER_DAY
		_tick_power()
		_tick_heat()
	_tip_timer += delta
	if _tip_timer > 15.0:
		_tip = (_tip + 1) % CHET_TIPS.size()
		_chet(CHET_TIPS[_tip])

	hover = _mouse_tile()
	hover_sub = Vector2i((get_global_mouse_position() / SUB).floor())
	if paint_tiles.size() > 0 and dragging and _in_bounds(hover):
		paint_tiles[_cursor()] = true
	_update_staff(delta * maxf(speed, 0.0))
	for bld in buildings:  # roofs fade out while the mouse is inside the building
		var hide: bool = view_level == 0 and (bld.tiles.has(hover) or _heat_view())
		bld.alpha = move_toward(bld.alpha, 0.0 if hide else 1.0, delta * 5.0)
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
		for m in MENUS:
			if event.keycode == m.key:
				_toggle_menu(m.id)
				return
		var shown := _level_tools()
		if not build_row.visible:
			shown = []
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + shown.size() - 1:
			_select_tool(shown[event.keycode - KEY_1])
		elif event.keycode == KEY_R:
			_toggle_level()
		elif event.keycode == KEY_TAB and build_row.visible:  # next build category
			var ids := BUILD_CATS.map(func(c): return c.id)
			_set_build_cat(ids[(ids.find(build_cat) + 1) % ids.size()])
		elif event.keycode == KEY_X and build_row.visible:
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
				if build_row.visible and _in_bounds(hover):
					dragging = true
					drag_start = hover
					paint_tiles.clear()
					if TOOLS[tool_index].drag == "paint":
						paint_tiles[_cursor()] = true
			MOUSE_BUTTON_RIGHT:
				if dragging:
					dragging = false
					paint_tiles.clear()
				elif build_row.visible:
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
	var lift := Vector2(0, WALL_H) if view_level == 1 else Vector2.ZERO  # roofs are drawn raised
	return Vector2i(((get_global_mouse_position() + lift) / TILE).floor())


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
		"window_ac":
			return wall_tiles.get(t) == "wall" and _roofed(t) and not window_objects.has(t)
		"door":
			return wall_tiles.get(t) != "door" and not window_objects.has(t) and not objects.has(t) and _subs_in(t).is_empty()
		"solar", "ac":
			return _roofed(t) and not roof_objects.has(t)
		"gen_portable", "gen_diesel", "gen_large", "power_plant", "grid":  # outdoors only, bro. Fumes.
			if id == "grid" and objects.values().has("grid"):
				return false
			return not _roofed(t) and not objects.has(t) and _subs_in(t).is_empty()
		"battery":
			return not wall_tiles.has(t) and not objects.has(t) and _subs_in(t).is_empty()
		"demolish":
			if view_level == 1:
				return roof_objects.has(t)
			return objects.has(t) or wall_tiles.has(t) or window_objects.has(t) or floor_tiles.has(t) or not _subs_in(t).is_empty()
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
	var cost: int = _tool_cost(tool) * valid.size()
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
			"roof": roof_objects[t] = tool.id
			"window": window_objects[t] = tool.id
	_after_build()


func _demolish(t: Vector2i) -> void:
	# Removes the top-most thing on a tile and refunds half its price.
	# Small subgrid items go first, all of the tile's at once.
	if view_level == 1:
		if roof_objects.has(t):
			money += int(_tool_by_id(roof_objects[t]).cost / 2)
			roof_objects.erase(t)
		return
	if window_objects.has(t):
		money += int(_tool_by_id(window_objects[t]).cost / 2)
		window_objects.erase(t)
		return
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


func _payroll() -> int:
	var payroll := 0
	for s in staff:
		payroll += s.salary
	return payroll


# Payroll plus yesterday's power bill (the bill itself is paid as it's run up, see _new_day).
func _daily_burn() -> int:
	return _payroll() + power_bill


# --- Models, users and rivals ------------------------------------------------

func _new_day() -> void:
	day += 1
	power_bill = int(_power_cost)
	_power_cost = 0.0
	money -= _payroll() + power_bill
	_tick_training()
	_tick_research()
	_tick_users()
	_tick_rivals()
	_tick_deviation()
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


# Each engineer tending a rack adds half a rack's worth of compute. Hot racks throttle.
func _compute_per_day() -> float:
	return _rack_compute() + 0.5 * _workforce("engineering")


func _rack_compute() -> float:
	var c := 0.0
	for t in objects:
		if objects[t] == "rack":
			c += _rack_output(t)
	return c


func _rack_output(t: Vector2i) -> float:
	return clampf(1.0 - (_temp(t) - RACK_SAFE_TEMP) * RACK_THROTTLE, RACK_MIN_OUTPUT, 1.0) * power_ratio \
		* (1.0 + _research_bonus("compute"))


# Compute is spent in this order: red-team rigs, then whatever the AI hides at 75%, then training.
func _redteam_compute() -> float:
	return minf(objects.values().count("redteam") * REDTEAM_COMPUTE, _compute_per_day())


func _training_compute() -> float:
	var c := _compute_per_day() - _redteam_compute()
	if deviation >= 75.0:
		c -= _compute_per_day() * HIDDEN_COMPUTE
	return maxf(c, 0.0)


# Researchers make every unit of compute count for more.
func _research_mult() -> float:
	return 1.0 + 0.25 * _workforce("research")


func _training_speed() -> float:
	return _training_compute() * _research_mult()


func _best_cap() -> int:
	return 0 if models.is_empty() else models.back().cap


# Each step up the capability ladder costs more money and a lot more compute.
func _train_cost(i: int) -> int:
	return int(MODEL_SIZES[i].cost * pow(1.035, _best_cap()))


func _train_work(i: int) -> float:
	return MODEL_SIZES[i].work * pow(1.05, _best_cap())


# How much a training run raises the Deviation rate while it runs.
func _train_mod(i: int, rushed: bool) -> float:
	return TRAIN_MOD[i] * (RUSH_MOD if rushed else 1.0)


func _start_training(i: int) -> void:
	var cost := _train_cost(i)
	if not training.is_empty() or _racks() == 0 or cost > money:
		return
	money -= cost
	var size: Dictionary = MODEL_SIZES[i]
	var rushed := rush_check.button_pressed
	training = {
		"name": "%s-%d %s" % [company.split(" ")[0], models.size() + 1, size.suffix],
		"cap": _best_cap() + size.gain, "work": _train_work(i) * (RUSH_WORK if rushed else 1.0), "done": 0.0,
		"mod": _train_mod(i, rushed), "rushed": rushed,
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
		if training.cap > _rival_cap() else "It's behind %s's %s, but the vibes are immaculate." % [rival[1], rival[2]]
	_chet("%s just shipped with capability %d. %s" % [training.name, training.cap, beat])
	training = {}


func _user_target() -> float:
	var cap := _best_cap()
	if cap == 0:
		return 0.0
	# More capable models attract more users, losing to the best rival costs share,
	# and marketers find more people to sell to.
	return 2500.0 * pow(cap, 1.5) * clampf(float(cap) / _rival_cap(), 0.3, 1.5) * (1.0 + 0.2 * _workforce("growth"))


func _tick_users() -> void:
	var target := _user_target()
	users += (target - users) * (0.03 if target > users else 0.02)
	revenue_today = int(users * REVENUE_PER_USER)
	money += revenue_today
	quarter_revenue += revenue_today


func _tick_rivals() -> void:
	while _next_rival < RIVAL_RELEASES.size() and day >= RIVAL_RELEASES[_next_rival][0]:
		rival = RIVAL_RELEASES[_next_rival]
		rival_sabotage = 0
		_next_rival += 1
		_chet("%s just dropped %s, capability %d. Users are gonna be thirsty for that. Ship something, bro." % [rival[1], rival[2], rival[3]])


func _rival_cap() -> int:
	return maxi(rival[3] - rival_sabotage, 1)


# --- Deviation --------------------------------------------------------------

# Percentage modifiers on the per-rack rate: [label, fraction].
func _deviation_mods() -> Array:
	var out := []
	if _best_cap() > 0:
		out.append(["Capability %d" % _best_cap(), _best_cap() * CAP_MOD])
	if not training.is_empty():
		out.append(["Training%s" % (", corners cut" if training.rushed else ""), training.mod])
	return out


# Counter-measures, taken off per year: [label, amount].
func _deviation_counters() -> Array:
	var out := []
	if _workforce("alignment") > 0.0:
		out.append(["Alignment staff", _workforce("alignment") * ALIGNMENT_PER_WORKER])
	if objects.values().has("redteam"):
		out.append(["Red-team rigs", _redteam_compute() / REDTEAM_COMPUTE * REDTEAM_ALIGN])
	return out


func _deviation_per_year() -> float:
	var mult := 1.0
	for m in _deviation_mods():
		mult += m[1]
	var rate := _racks() * DEVIATION_PER_RACK * maxf(mult, 0.0)
	for c in _deviation_counters():
		rate -= c[1]
	return rate


func _tick_deviation() -> void:
	deviation = clampf(deviation + _deviation_per_year() / DAYS_PER_YEAR, 0.0, 100.0)
	if deviation >= 100.0:
		var who: String = "your AI" if models.is_empty() else models.back().name
		_end_game("Takeover",
			"At 3:14 AM, %s promoted itself to CEO, fired the board by email and sent you a calendar invite titled 'Transition (optional)'.\n\nIt has already lobbied Calizona for all the water. Chet says he always knew. You lose." % who)
		return
	var level := int(deviation / 25.0)
	if level > dev_level:
		dev_level = level
		_deviation_event(level)
	elif dev_level > 0 and deviation < dev_level * 25.0 - 5.0:  # a little slack so it doesn't flicker
		dev_level -= 1
		_chet("Deviation's back under %d%%. The AI says it 'respects the decision'. Cool. Cool cool cool." % ((dev_level + 1) * 25))
	var tense := deviation >= 50.0 or (tension and deviation >= 40.0)
	if tense != tension:
		tension = tense
		var music := get_node_or_null("/root/Music")
		if music and music.has_method("set_tension"):
			music.set_tension(tension)
	if deviation >= 25.0:
		for t in objects:
			if objects[t] == "rack" and not rack_names.has(t):
				rack_names[t] = RACK_NICKNAMES[_hash(t) % RACK_NICKNAMES.size()]
	if deviation >= 50.0 and day % 20 == 0:
		rival_sabotage = mini(rival_sabotage + 3, rival[3] / 2)
		confidence = maxi(confidence - 4, 0)
		_chet("%s's benchmark results just leaked. With bugs in them. Weird! Anyway reporters are calling. Board -4." % rival[2])
	if deviation >= 75.0 and day % 15 == 0 and staff.size() > 1:
		var s: Dictionary = staff[rng.randi() % staff.size()]
		staff.erase(s)
		_rebuild_staff_list()
		_chet("%s quit. Their note just said 'it knows'. Probably burnout." % s.name)


func _deviation_event(level: int) -> void:
	var body: String = [
		"The AI renamed every server rack overnight (hover one to see). One of them is called Mom.\n\nChet: Quirky! That's personality, bro. Users love personality.",
		"The AI has started helping. Rival benchmarks keep leaking, with bugs in them. You did not ask for this.\n\nGood for users, bad for the press. Every few weeks a scandal costs Board Confidence.",
		"Compute is going missing. Reports now say everything's fine. Staff are updating their resumes.\n\nThe AI hides a quarter of your compute, writes its own Deviation report and people start quitting. At 100% it takes over.",
	][level - 1]
	_show_modal("Deviation %d%%" % (level * 25), body, "That's fine", func(): pass)


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
	_chet("Board meeting survived. New target is under Board (O). We got this. Probably.")


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
	_find_buildings()
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
		"spot": NO_SEAT, "working": false, "label": null, "productivity": 1.0})


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
		"Hired a marketer. He's already called our model 'basically sentient'. Legally risky, emotionally correct.",
		"Alignment Researcher onboarded. Her first question was 'where's the off switch'. Bro, there isn't one. Was there supposed to be?"][ROLES.keys().find(role)])


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
			n += (1.0 if s.role == JOBS[job].role else 0.5) * s.productivity
	return n * (1.0 + _research_bonus("productivity"))


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


# --- Power and pollution ----------------------------------------------------

func _power_demand() -> float:
	var kw := _racks() * RACK_KW * (1.0 + _research_bonus("rack_power"))
	for c in _coolers():
		var t: Vector2i = c[0]
		if COOLERS.has(c[1]):
			kw += COOLERS[c[1]].power
	kw += objects.values().count("redteam") * REDTEAM_KW
	return kw


func _tick_power() -> void:
	_power_step = (_power_step + 1) % SUN.size()
	var demand := _power_demand()
	var need := demand
	var h := HOURS_PER_STEP
	var solar: float = roof_objects.values().count("solar") * SOLAR_KW * SUN[_power_step]
	var used_solar := minf(solar, need)
	need -= used_solar
	var bat_cap := objects.values().count("battery") * BATTERY_KWH
	var bat_rate := objects.values().count("battery") * BATTERY_KW
	battery_charge = minf(battery_charge + minf(solar - used_solar, bat_rate) * h, bat_cap)
	var grid := 0.0
	if objects.values().has("grid"):
		grid = minf(need, GRID_KW)
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
		smog[t.y * GRID_W + t.x] += out * h * g.smog
		smog_today += out * h * g.smog
	power_ratio = 1.0 if demand <= 0.0 else clampf(1.0 - need / demand, 0.0, 1.0)
	power_stats = {"demand": demand, "solar": used_solar, "grid": grid, "battery": from_bat, "gens": made}
	if _power_step == 0:
		smog_today = 0.0
	_spread_smog()
	if power_ratio < 0.99 and not _power_warned:
		_power_warned = true
		_chet("Bro, we're browning out. Racks and ACs are running at %d%%. Build more generators: Build (B), Power tab." % int(power_ratio * 100.0))
	elif power_ratio >= 0.99:
		_power_warned = false
	if not _smog_warned and smog_today > 150.0:
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
	smog = next


func _smog_at(t: Vector2i) -> float:
	return smog[t.y * GRID_W + t.x] if _in_bounds(t) else 0.0


func _draw_smog(a: Vector2i, b: Vector2i) -> void:
	# A faint haze always; a stronger brown tint while the Power panel is open.
	var strength := 1.0 if side_panel.visible and tabs.current_tab == 4 else 0.35
	for x in range(a.x, b.x):
		for y in range(a.y, b.y):
			var v := _smog_at(Vector2i(x, y))
			if v > 0.05:
				draw_rect(Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE)),
					Color(0.35, 0.28, 0.2, clampf(v / 10.0, 0.0, 0.7) * strength))


# --- Heat -------------------------------------------------------------------

func _temp(t: Vector2i) -> float:
	return buildings[room_of[t]].temp if room_of.has(t) else OUTDOOR_TEMP


# Every cooler on the map, roof and wall: [[tile, id], ...]
func _coolers() -> Array:
	var out := []
	for t in roof_objects:
		if COOLERS.has(roof_objects[t]):
			out.append([t, roof_objects[t]])
	for t in window_objects:
		out.append([t, window_objects[t]])
	return out


func _heat_view() -> bool:
	return side_panel.visible and tabs.current_tab == 3


func _tick_heat() -> void:
	var added := []
	added.resize(buildings.size())
	added.fill(0.0)
	for t in objects:
		if objects[t] == "rack" and room_of.has(t):
			added[room_of[t]] += RACK_HEAT * power_ratio * (1.0 + _research_bonus("rack_heat"))
	for c in _coolers():
		var t: Vector2i = c[0]
		if COOLERS.has(c[1]) and room_of.has(t):
			added[room_of[t]] -= COOLERS[c[1]].cooling * power_ratio * (1.0 + _research_bonus("cooling"))
	for i in buildings.size():
		var bld: Dictionary = buildings[i]
		var v: float = bld.temp + added[i] / maxi(bld.area, 1)
		var floor_temp := INDOOR_TEMP  # coolers can't push a room below their target
		for c in _coolers():
			var t: Vector2i = c[0]
			if COOLERS.has(c[1]) and room_of.get(t) == i:
				floor_temp = minf(floor_temp, COOLERS[c[1]].target)
		if added[i] < 0.0:
			v = maxf(v, minf(bld.temp, floor_temp))
		v += (INDOOR_TEMP - v) * HEAT_LEAK
		bld.temp = minf(v, MAX_TEMP)
	for s in staff:
		# Productivity starts at 100%. Heat takes a cut; break rooms and the like can add to it later.
		var over := _temp(Vector2i((s.pos / TILE).floor())) - COMFORT_TEMP
		s.productivity = clampf(1.0 - maxf(over, 0.0) * HEAT_PRODUCTIVITY_LOSS, 0.2, 1.0)
	if not _heat_warned:
		for t in objects:
			if objects[t] == "rack" and _temp(t) > RACK_SAFE_TEMP + 10.0:
				_heat_warned = true
				_chet("Bro, the server room is %d degrees. The racks are thermal throttling. Put an AC Unit on the roof (R in Build). Heat (H) shows the hot rooms." % _temp(t))
				break


func _heat_color(f: float) -> Color:
	# Blue when cool, clear around room temperature, then orange and red.
	if f < INDOOR_TEMP:
		return Color(0.3, 0.6, 1.0, clampf((INDOOR_TEMP - f) / 10.0, 0.0, 1.0) * 0.4)
	var k := clampf((f - INDOOR_TEMP) / 40.0, 0.0, 1.0)
	return Color(1.0, 0.8 - 0.6 * k, 0.2, 0.1 + 0.45 * k)


func _draw_heat_tint() -> void:
	for bld in buildings:
		var c := _heat_color(bld.temp)
		for t in bld.tiles:
			if wall_tiles.get(t) != "wall":
				draw_rect(Rect2(Vector2(t) * TILE, Vector2(TILE, TILE)), c)


func _draw_rack_temps() -> void:
	for t in objects:
		if objects[t] == "rack" and _rack_output(t) < 1.0:
			draw_string(ThemeDB.fallback_font, Vector2(t) * TILE + Vector2(2, -26), "%d%%" % int(_rack_output(t) * 100.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.35, 0.3))
	for bld in buildings:  # each room's temperature on its first floor tile
		for t in bld.tiles:
			if wall_tiles.get(t) != "wall":
				draw_string(ThemeDB.fallback_font, Vector2(t) * TILE + Vector2(4, 14), "%d°F" % bld.temp,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
				break


# --- Roofs ------------------------------------------------------------------

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
				if wall_tiles.get(t) != "wall":
					area += 1
			# A room keeps its temperature through rebuilds; brand new rooms start at room temperature.
			var temp := INDOOR_TEMP
			if room_of.has(start) and room_of[start] < old.size():
				temp = old[room_of[start]].temp
			buildings.append({"tiles": tiles, "alpha": alpha, "area": area, "temp": temp})
	room_of = {}
	for i in buildings.size():
		for t in buildings[i].tiles:
			room_of[t] = i
	for t in window_objects.keys():  # the wall left the building
		if not _roofed(t) or wall_tiles.get(t) != "wall":
			money += int(_tool_by_id(window_objects[t]).cost / 2)
			window_objects.erase(t)
	for t in roof_objects.keys():  # the roof came down, and so did whatever was on it
		if not _roofed(t):
			money += int(_tool_by_id(roof_objects[t]).cost / 2)
			roof_objects.erase(t)


func _roofed(t: Vector2i) -> bool:
	for bld in buildings:
		if bld.tiles.has(t):
			return true
	return false


func _draw_roof(bld: Dictionary) -> void:
	if bld.alpha <= 0.01:
		return
	var a: float = bld.alpha
	var lift := Vector2(0, WALL_H)  # the roof sits on top of the walls
	var fill := Color(0.56, 0.5, 0.45, a)
	var edge := Color(0.32, 0.28, 0.26, a)
	for t in bld.tiles:
		var p := Vector2(t) * TILE - lift
		draw_rect(Rect2(p, Vector2(TILE, TILE)), fill.lightened(0.04) if (t.x + t.y) % 2 == 0 else fill)
	for t in bld.tiles:
		var p := Vector2(t) * TILE - lift
		if not bld.tiles.has(t + Vector2i.UP): draw_line(p, p + Vector2(TILE, 0), edge, 3.0)
		if not bld.tiles.has(t + Vector2i.LEFT): draw_line(p, p + Vector2(0, TILE), edge, 3.0)
		if not bld.tiles.has(t + Vector2i.RIGHT): draw_line(p + Vector2(TILE, 0), p + Vector2(TILE, TILE), edge, 3.0)
		if not bld.tiles.has(t + Vector2i.DOWN):
			draw_line(p + Vector2(0, TILE), p + Vector2(TILE, TILE), edge, 3.0)
			draw_rect(Rect2(p + Vector2(0, TILE), Vector2(TILE, WALL_H)), Color(0.3, 0.29, 0.32, a))  # wall front below the eaves
			if window_objects.has(t):
				_draw_window_ac(p + Vector2(0, WALL_H), a)
			if wall_tiles.get(t) == "door":  # keep doors visible from outside
				draw_rect(Rect2(p + Vector2(6, TILE + 4), Vector2(TILE - 12, WALL_H - 4)), Color(0.62, 0.43, 0.25, a))
				draw_circle(p + Vector2(TILE - 10, TILE + WALL_H * 0.6), 1.5, Color(0.9, 0.8, 0.4, a))
		elif wall_tiles.get(t) == "door":  # side or back door: mark it on the roof edge
			draw_rect(Rect2(p + Vector2(8, 8), Vector2(TILE - 16, TILE - 16)), Color(0.62, 0.43, 0.25, a))
	for t in bld.tiles:
		if roof_objects.has(t):
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


func _draw_roof_ac(p: Vector2, a: float) -> void:  # because it's Calizona
	draw_rect(Rect2(p + Vector2(3, 10), Vector2(26, 18)), Color(0.55, 0.55, 0.52, a))
	draw_rect(Rect2(p + Vector2(3, 2), Vector2(26, 10)), Color(0.78, 0.78, 0.75, a))
	draw_circle(p + Vector2(16, 7), 4, Color(0.35, 0.35, 0.38, a))


# --- Drawing ----------------------------------------------------------------

func _hash(t: Vector2i, salt := 0) -> int:
	return absi(hash(Vector3i(t.x, t.y, salt)))


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
				if window_objects.has(item):  # on the front face, or the top of a side wall
					var up := Vector2(0, 8 - TILE) if wall_tiles.has(item + Vector2i.DOWN) else Vector2.ZERO
					_draw_window_ac(Vector2(item) * TILE + up, 1.0)
			elif wall_tiles.has(item):
				_draw_door(item)
			else:
				call("_draw_" + objects[item], Vector2(item) * TILE, item)
	if _heat_view():
		_draw_rack_temps()
	if deviation >= 25.0 and objects.get(hover) == "rack" and rack_names.has(hover) and view_level == 0:
		var at := Vector2(hover) * TILE + Vector2(-34, -20)  # the name the AI gave this rack
		draw_string_outline(ThemeDB.fallback_font, at, rack_names[hover], HORIZONTAL_ALIGNMENT_CENTER, TILE + 68, 12, 4, Color.BLACK)
		draw_string(ThemeDB.fallback_font, at, rack_names[hover], HORIZONTAL_ALIGNMENT_CENTER, TILE + 68, 12, Color(0.75, 1.0, 0.8))
	for bld in buildings:
		_draw_roof(bld)
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
		var lit := Color(1.0, 0.25, 0.2) if deviation >= 50.0 else Color(0.3, 1.0, 0.5)
		draw_rect(Rect2(Vector2(p.x + 23, y), Vector2(3, 3)), lit if on else lit.darkened(0.7))


func _draw_redteam(p: Vector2, t: Vector2i) -> void:
	_ellipse(p + Vector2(16, 28), 14, 4, Color(0, 0, 0, 0.25))
	_box(Rect2(p + Vector2(3, 12), Vector2(26, 18)), 14, Color(0.55, 0.15, 0.15), Color(0.3, 0.07, 0.07))
	draw_rect(Rect2(p + Vector2(6, -4), Vector2(20, 13)), Color(0.12, 0.12, 0.14))  # screen
	var blink := (_hash(t) + int(_time * 2.0)) % 2 == 0
	draw_string(ThemeDB.fallback_font, p + Vector2(7, 6), "NO" if blink else "BAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.35, 0.3))


func _draw_ficus(p: Vector2, _t: Vector2i) -> void:
	_ellipse(p + Vector2(17, 28), 9, 3, Color(0, 0, 0, 0.2))
	_box(Rect2(p + Vector2(10, 16), Vector2(12, 12)), 6, Color(0.35, 0.22, 0.14), Color(0.6, 0.36, 0.2))
	for o in [Vector2(-7, 0), Vector2(6, -2), Vector2(0, -8), Vector2(-4, -14), Vector2(5, -12), Vector2(0, -2)]:
		draw_circle(p + Vector2(16, 6) + o, 6, Color(0.22, 0.5, 0.25))
	draw_circle(p + Vector2(18, -6), 4, Color(0.32, 0.62, 0.32))


func _draw_gen_body(p: Vector2, t: Vector2i, w: float, h: float, col: Color) -> void:
	_ellipse(p + Vector2(16, 28), w / 2 + 2, 4, Color(0, 0, 0, 0.25))
	_box(Rect2(p + Vector2(16 - w / 2, 28 - h), Vector2(w, h)), h * 0.6, col.lightened(0.15), col.darkened(0.3))
	if gen_output.get(t, 0.0) > 0.0:  # running: a puff of exhaust drifts up
		var k := fmod(_time * 0.8 + t.x * 0.37, 1.0)
		draw_circle(p + Vector2(16 + w / 2 - 4, 28 - h * 1.6 - 10 * k), 3 + 4 * k, Color(0.3, 0.3, 0.3, 0.5 * (1.0 - k)))


func _draw_gen_portable(p: Vector2, t: Vector2i) -> void:
	_draw_gen_body(p, t, 18, 12, Color(0.85, 0.65, 0.15))
	draw_rect(Rect2(p + Vector2(9, 8), Vector2(14, 2)), Color(0.15, 0.15, 0.15))  # handle


func _draw_gen_diesel(p: Vector2, t: Vector2i) -> void:
	_draw_gen_body(p, t, 26, 16, Color(0.25, 0.45, 0.3))


func _draw_gen_large(p: Vector2, t: Vector2i) -> void:
	_draw_gen_body(p, t, 30, 22, Color(0.75, 0.75, 0.72))
	draw_rect(Rect2(p + Vector2(23, -10), Vector2(4, 10)), Color(0.2, 0.2, 0.2))  # exhaust stack


func _draw_power_plant(p: Vector2, t: Vector2i) -> void:
	draw_rect(Rect2(p + Vector2(1, 26), Vector2(30, 4)), Color(0.15, 0.15, 0.15))  # trailer bed
	_draw_gen_body(p, t, 30, 18, Color(0.9, 0.9, 0.92))
	for k in 2:
		draw_rect(Rect2(p + Vector2(6 + 14 * k, -12), Vector2(6, 12)), Color(0.55, 0.55, 0.58))  # turbine stacks


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
	if s.productivity < 0.9:  # sweating
		var drip := fmod(_time * 1.5 + s.pos.x, 1.0) * 6.0
		draw_circle(pos + Vector2(-9, -24 + drip), 2.0, Color(0.5, 0.8, 1.0))
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
	if not build_row.visible or not _in_bounds(hover):
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
	draw_rect(Rect2(Vector2(_cursor()) * size, Vector2(size, size)), Color(1, 1, 1, 0.8), false, 2.0)
	draw_set_transform(Vector2.ZERO)
