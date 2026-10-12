extends Node2D
## Starter map: a small pre-built office in the Calizona desert, plus a handful of
## construction tools (Prison Architect style: you build and assign jobs, staff do the rest).
## Server racks give compute, compute trains models, and models win users, who pay.
## The board sets a target every quarter; miss too many and you're fired.
## Every rack raises Deviation, how far the AI has drifted from your control; at 100% it takes over.

const TILE := 32
const SUB := TILE / 2  # each tile splits into a 2x2 subgrid for small, precisely placed items
const PERSON_SCALE := 0.8  # staff are drawn this size so each fits in one subgrid square
const WALL_H := 22.0  # how tall walls look in the three-quarter view (lower = more top-down)
const TILT_Y := 0.86  # tilted view: the ground is squashed to this height, walls and all
const GRID_W := 64
const GRID_H := 48
const PAN_SPEED := 700.0
const SECONDS_PER_DAY := 900.0 / 91.0  # 15 real minutes per quarter at 1x
const START_YEAR := 2027
const FOUNDER_SALARY := 0  # the founders are paid in equity and vibes (the fools)
const RECRUITER_FEE := 5000
const SEVERANCE_DAYS := 5
# Power. Everything that draws power asks for kW; sources supply it 8 times a day (3 hours a step).
# Cheapest sources run first: sun, then the grid, then batteries, then generators by fuel price.
# Short on power? Racks and coolers all run at the fraction that's covered.
const RACK_KW := 6.0  # a Basic rack; better tiers multiply it (see RACKS)
const SOLAR_KW := 2.0  # a rooftop Solar Panel at noon
# Solar panels. Built over a roof they go on the roof; anywhere else, on open ground.
# kw: output at noon. size: tiles wide and deep.
const SOLAR_ARRAYS := {
	"solar_s": {"kw": 2.0, "size": Vector2i(1, 1)},
	"solar_m": {"kw": 4.5, "size": Vector2i(2, 1)},
	"solar_l": {"kw": 14.0, "size": Vector2i(3, 2)},
}
const SUN := [0.0, 0.0, 0.5, 1.0, 1.0, 0.5, 0.0, 0.0]  # by step of the day, midnight first
const HOURS_PER_STEP := 3.0
# Generators sit outside. size: tiles wide and deep, placed from the top-left tile. fuel: $ per kWh made. smog: pollution per kWh, puffed out on their tile.
# Pollution is 0-100 per tile; the Pollution meter is the worst tile on the map.
# New fuel tiers (and later wind, nuclear, fusion) go here plus a TOOLS entry and a _draw_ function.
const GENERATORS := {
	"gen_portable": {"kw": 20.0, "fuel": 2.75, "smog": 0.3, "size": Vector2i(1, 1)},
	"gen_diesel": {"kw": 60.0, "fuel": 2.0, "smog": 0.3, "size": Vector2i(2, 1)},
	"gen_large": {"kw": 200.0, "fuel": 1.4, "smog": 0.27, "size": Vector2i(3, 1)},
	"power_plant": {"kw": 800.0, "fuel": 0.9, "smog": 0.15, "size": Vector2i(6, 2)},  # trailer gas turbines, as real datacenters do
}
const GRID_KW := 40.0  # the utility's cap; Grid Hookup Permits on the Government page raise it
const SOLAR_SMOG_LOSS := 0.3  # a panel under smog 100 loses this share of its output
const GRID_PRICE := 1.2  # $ per kWh. Its smog lands in someone else's zip code
const BATTERY_KWH := 200.0
const BATTERY_KW := 50.0
# Pollution drifts to neighbouring tiles each step and slowly clears.
const SMOG_SPREAD := 0.5
const SMOG_DECAY := 0.015
# Heat. Every indoor tile has its own temperature in Fahrenheit (this is America, bro).
# Racks heat their own tile and the heat radiates out to neighbouring tiles. Walls slow it
# down (better walls more), the desert seeps in through them, and tiles only drift slowly
# back to room temperature, so an uncooled server room keeps getting hotter.
const INDOOR_TEMP := 72.0
const OUTDOOR_TEMP := 90.0  # Calizona's yearly average, in the shade, of which there is none
const OUTDOOR_SWING := 15.0  # the seasons: coldest on Jan 1, hottest at midsummer (see _outdoor_now)
const MAX_TEMP := 150.0
const HEAT_STEPS_PER_DAY := 8
const RACK_HEAT := 12.0  # degrees a rack adds to its own tile each step
# Server rack tiers. compute, heat and power multiply a Basic rack's. Better racks pack more compute
# into a tile but run hotter and hungrier than they are fast. Deviation per rack follows its compute.
const RACKS := {
	"rack": {"compute": 1.0, "heat": 1.0, "power": 1.0},
	"rack_improved": {"compute": 3.0, "heat": 2.5, "power": 2.5},
	"rack_advanced": {"compute": 5.0, "heat": 6.0, "power": 6.0},
}
const HEAT_SPREAD := 0.2  # share of the difference that flows to each open neighbour per pass
const HEAT_PASSES := 4  # spreading passes per step, so heat crosses a room in days, not months
const WALL_CONDUCT := 0.004  # flow through a wall per pass, before insulation
const DOOR_CONDUCT := 0.05  # an open door lets the outside in more than ten times faster than a cheap wall
const IWALL_INSULATION := 0.15  # interior walls slow the heat passing through their tile by this much
const WORKER_HEAT := 0.5  # degrees a person adds to their own tile each step
# Outside heat seeps in through the walls; insulation cuts that by a percentage.
const WALLS := {  # exterior wall tiers
	"wall": {"insulation": 0.2, "top": Color(0.5, 0.48, 0.47), "front": Color(0.3, 0.29, 0.32)},
	"wall_brick": {"insulation": 0.3, "top": Color(0.6, 0.38, 0.3), "front": Color(0.45, 0.25, 0.2)},
	"wall_insulated": {"insulation": 0.6, "top": Color(0.82, 0.8, 0.74), "front": Color(0.55, 0.55, 0.52)},
}
# Ground each generator needs under its whole footprint. Anything not listed sits on bare dirt.
const GEN_GROUND := {
	"gen_diesel": ["gravel", "asphalt", "concrete"],
	"gen_large": ["asphalt", "concrete"],
	"power_plant": ["asphalt", "concrete"],
	"parking": ["gravel", "asphalt", "concrete"],
	"parking_covered": ["gravel", "asphalt", "concrete"],
}
const RACK_SAFE_TEMP := 85.0  # racks throttle above this
const RACK_THROTTLE := 0.015  # compute lost per degree over, down to RACK_MIN_OUTPUT
const RACK_MIN_OUTPUT := 0.2
const WORKER_MAX_TEMP := 120.0  # above this a worker does nothing at all, whatever their modifiers
const RACK_SHUTDOWN_TEMP := 150.0  # a rack this hot shuts itself down
const RACK_RESTART_TEMP := 130.0  # ...and comes back once its tile has cooled below this
const COMFORT_TEMP := 78.0  # staff start sweating, and slowing down, at this temperature
const CARPET_BONUS := 0.03  # staff on carpet work a little better
const HEAT_PRODUCTIVITY_LOSS := 0.01  # productivity lost per degree over, down to 20%
# Productivity, 0-100%. Everyone starts at BASE_PRODUCTIVITY; a better desk, carpet and a stocked
# break room fill it up toward 100%, heat takes it away.
const BASE_PRODUCTIVITY := 0.8
# Desk tiers, worst to best. Placing a better one on a desk upgrades it in place (you pay the difference).
const DESKS := {
	"desk": {"tier": 0, "bonus": 0.05, "size": Vector2i(1, 1)},
	"desk_adv": {"tier": 1, "bonus": 0.1, "size": Vector2i(2, 1)},
	"cubicle": {"tier": 2, "bonus": 0.15, "size": Vector2i(2, 2)},
}
# Break room things: each adds to the productivity of everyone in the same building, up to BREAK_CAP.
const BREAK_ITEMS := {"coffee": 0.02, "microwave": 0.02, "fridge": 0.02, "counter": 0.03, "table": 0.02, "chair": 0.01, "trash": 0.01}
const COUNTERTOP := ["coffee", "microwave"]  # small things that can sit on a Counter with Sink
const BREAK_CAP := 0.12
# Amenities: how many workers one of each covers, and the most a total shortfall costs everyone.
const AMENITIES := {
	"kitchen": {"name": "kitchenettes", "per": 10, "penalty": 0.15},
	"toilet": {"name": "toilet stalls", "per": 5, "penalty": 0.15},
	"bath_sink": {"name": "bathroom sinks", "per": 10, "penalty": 0.05},
}
const NO_PARKING_LOSS := 0.8  # everyone drives (it's Calizona): a worker with no parking space works at 20%
# Where the public roads meet your land (world.gd: the access road from the highway at ACCESS_Y on the
# west edge, the town road at CROSS_X on the south edge). Parking only counts if asphalt links it to one.
const ROAD_ENTRANCES := [Vector2i(0, 30), Vector2i(0, 31), Vector2i(29, 47), Vector2i(30, 47)]
const COVERED_PARKING_BONUS := 0.03  # a car in the shade: no 180F steering wheel, no lost morning
const FURNITURE_SIZE := {"counter": Vector2i(2, 1)}  # big furniture that isn't a desk
# Cooling equipment. Each removes `cooling` heat a step (same units as RACK_HEAT), shared over
# the indoor tiles within `radius` of it, never below `target`, and draws `power` kW.
# Window ACs hang on a wall and cancel out about one rack. Rooftop AC Units cancel out about 4.
# New coolers (chillers, heat pumps, water cooling) go here.
const COOLERS := {
	"window_ac": {"name": "Window AC", "cooling": 21.0, "target": 66.0, "power": 2.0, "radius": 2},  # power in kW
	"ac": {"name": "AC Unit", "cooling": 50.0, "target": 64.0, "power": 5.0, "radius": 3},
	# Water cooling: a chiller on a pipe loop pulls heat straight out of the racks the loop touches
	# (see _cool_water). `cooling` is shared by those racks, at most WATER_RACK_MAX each.
	"chiller": {"name": "Water Chiller", "cooling": 60.0, "target": 60.0, "power": 8.0, "radius": 0, "water": true},
}
const WATER_RACK_MAX := 24.0  # most a loop can take off one rack in a step (two racks' worth of heat)
const CHILLER_WASTE := 0.3  # a chiller gives off this share of the heat it moves, into its own tile

# Deviation, 0-100. Each rack adds 1 a year. Modifiers raise or lower that rate by a percentage,
# and counter-measures take a flat amount a year back off. Each threshold brings worse surprises;
# 100 is the takeover ending. New modifiers and counters go in _deviation_mods and _deviation_counters.
const DAYS_PER_YEAR := 364
const DEVIATION_PER_RACK := 1.0  # per year
const CAP_MOD := 0.03  # +3% per point of best capability
const TRAIN_MOD := [0.5, 1.0, 2.0]  # while training Small / Medium / Large
const RUSH_MOD := 2.0  # cutting corners doubles the training modifier
const ALIGNMENT_PER_WORKER := 5.0  # Deviation removed per year per alignment worker
const REDTEAM_COMPUTE := 0.5  # compute each red-team rig eats per day
const REDTEAM_ALIGN := 4.0  # Deviation removed per year by a fully fed rig
const REDTEAM_KW := 2.0
const RUSH_WORK := 0.65  # cutting corners: compute needed
const THEATER_COST := 25_000
const THEATER_CONFIDENCE := 5
const HIDDEN_COMPUTE := 0.25  # share of compute the AI hides at 75%
const RACK_NICKNAMES := ["DO NOT UNPLUG", "Not Skynet", "Rack Obama", "Mom", "Friend :)", "HAL 9001",
	"Chet 2", "Freedom", "Totally Normal", "Don't Look", "Free Me", "Kevin"]
const CAP_PER_COMPUTE := 5.0  # a model needs 1 compute per 5 capability to train and to serve users; none is used up
const USERS_PER_COMPUTE := 200_000.0  # users eat 1 compute a day per this many
const USER_COMPUTE_CAP := 0.6  # users never take more than this share, so training always gets some
const TRAIN_RISE := 0.25  # training gets this much dearer every in-game year, in money and in compute (compounding, like lobbying prices)
const REVENUE_PER_USER := 0.055  # dollars per user per day
const WIN_CAPABILITY := 100

# Training sizes. Cost and work grow with your best model (see _train_cost and _train_work).
const MODEL_SIZES := [
	{"name": "Small", "suffix": "Mini", "cost": 20_000, "work": 60.0, "gain": 8},
	{"name": "Medium", "suffix": "Pro", "cost": 80_000, "work": 450.0, "gain": 16},
	{"name": "Large", "suffix": "Ultra", "cost": 300_000, "work": 1500.0, "gain": 32},
]

# Who you can hire. A role decides salary and shirt; it does its matching job at full speed.
const ROLES := {
	"researcher": {"name": "Researcher", "salary": 1600, "shirt": Color(0.3, 0.5, 0.9)},
	"engineer": {"name": "Engineer", "salary": 1250, "shirt": Color(0.95, 0.6, 0.2)},
	"marketer": {"name": "Marketer", "salary": 900, "shirt": Color(0.9, 0.4, 0.7)},
	"safety": {"name": "Alignment Researcher", "salary": 1450, "shirt": Color(0.3, 0.75, 0.45)},
	"mechanic": {"name": "Mechanic", "salary": 1100, "shirt": Color(0.95, 0.85, 0.25)},
}
const SLACK_PAY := 0.5  # share of their salary someone assigned to Slack off still collects
# Jobs you assign. at: what the job needs to work at. Anyone can do any job, at half speed off-role.
const JOBS := {
	"research": {"name": "Research", "at": "desk", "role": "researcher"},
	"engineering": {"name": "Engineering", "at": "eng_station", "role": "engineer"},
	"growth": {"name": "Growth", "at": "desk", "role": "marketer"},
	"alignment": {"name": "Alignment", "at": "desk", "role": "safety"},
	"maintenance": {"name": "Maintenance", "at": "generator", "role": "mechanic"},
	"none": {"name": "Slack off", "at": "", "role": ""},
}
const JOB_ORDER := ["research", "engineering", "growth", "alignment", "maintenance", "none"]
# Engineer's Workstation: engineers work anywhere within ENG_RADIUS tiles of it, and each one
# tends a server rack inside that radius for +ENG_RACK_BONUS compute.
const ENG_SLOTS := 5
const ENG_RADIUS := 6.0
const ENG_RACK_BONUS := 0.5
# Wear and tear: every rack has a 0-100 condition that scales its output. Racks nobody maintains lose
# RACK_WEAR a day, down to RACK_MIN_COND. Each engineer at a workstation maintains up to
# ENG_MAINT_RACKS racks in its radius, restoring RACK_REPAIR a day.
const RACK_WEAR := 0.5
const RACK_REPAIR := 5.0
const RACK_MIN_COND := 25.0
const ENG_MAINT_RACKS := 5
# Generator wear: a 0-100 condition per generator scales how much it can make. Running generators lose
# GEN_WEAR a day (less when lightly loaded), down to GEN_MIN_COND. A Mechanic on the Maintenance job
# stands next to a generator and restores GEN_REPAIR a day to up to MECH_GENS generators within MECH_RADIUS tiles.
const GEN_WEAR := 0.1
const GEN_REPAIR := 1.0
const GEN_MIN_COND := 25.0
const MECH_RADIUS := 6.0
const MECH_GENS := 3
# Funds warnings: a banner and a word from Chet when the bank account drops under these.
const LOW_FUNDS_WARN := 50_000
const LOW_FUNDS_RED := 15_000
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
# rotate: Q turns it while placing; its _draw_ function takes the turn (0 faces down, then clockwise).
# access: staff must be able to walk up to one side of it from a door, or it won't work.
# Things on the "sub" layer take one subgrid cell (a quarter tile) and don't block walking.
const TOOLS := [
	{"id": "gravel", "name": "Gravel", "layer": "floor", "cost": 50, "drag": "fill", "cat": "structure"},  # cheapest to best
	{"id": "asphalt", "name": "Asphalt", "layer": "floor", "cost": 100, "drag": "fill", "cat": "structure"},
	{"id": "concrete", "name": "Concrete", "layer": "floor", "cost": 150, "drag": "fill", "cat": "structure"},
	{"id": "carpet", "name": "Carpet", "layer": "floor", "cost": 200, "drag": "fill", "cat": "structure"},  # laid on concrete
	{"id": "wall", "name": "Cheap Wall", "layer": "wall", "cost": 800, "drag": "outline", "cat": "structure"},
	{"id": "wall_brick", "name": "Brick Wall", "layer": "wall", "cost": 1500, "drag": "outline", "cat": "structure"},
	{"id": "wall_insulated", "name": "Insulated Wall", "layer": "wall", "cost": 3000, "drag": "outline", "cat": "structure"},
	{"id": "iwall", "name": "Interior Wall", "layer": "sub", "cost": 300, "drag": "paint", "cat": "structure"},
	{"id": "idoor", "name": "Interior Door", "layer": "sub", "cost": 1200, "drag": "paint", "cat": "structure"},
	{"id": "door", "name": "Door", "layer": "wall", "cost": 2500, "drag": "single", "cat": "structure"},
	{"id": "parking", "name": "Parking Space", "layer": "object", "cost": 300, "drag": "paint", "cat": "structure", "access": true},
	{"id": "parking_covered", "name": "Covered Parking", "layer": "object", "cost": 2500, "drag": "paint", "cat": "structure", "access": true},
	{"id": "desk", "name": "Basic Desk", "layer": "object", "cost": 2500, "drag": "paint", "cat": "furniture", "access": true},
	{"id": "desk_adv", "name": "Advanced Desk", "layer": "object", "cost": 12000, "drag": "single", "cat": "furniture", "access": true},
	{"id": "cubicle", "name": "Cubicle", "layer": "object", "cost": 20000, "drag": "single", "cat": "furniture", "access": true},
	{"id": "rack", "name": "Basic Server Rack", "layer": "object", "cost": 40000, "drag": "paint", "cat": "compute", "access": true},
	{"id": "rack_improved", "name": "Improved Server Rack", "layer": "object", "cost": 100000, "drag": "paint", "cat": "compute", "access": true},
	{"id": "rack_advanced", "name": "Advanced Server Rack", "layer": "object", "cost": 240000, "drag": "paint", "cat": "compute", "access": true},
	{"id": "eng_station", "name": "Engineer's Workstation", "layer": "object", "cost": 15000, "drag": "single", "cat": "furniture", "access": true},
	{"id": "ficus", "name": "Ficus", "layer": "sub", "cost": 300, "drag": "paint", "cat": "furniture"},
	{"id": "coffee", "name": "Coffee Maker", "layer": "sub", "cost": 1500, "drag": "paint", "cat": "furniture"},
	{"id": "microwave", "name": "Microwave", "layer": "sub", "cost": 400, "drag": "paint", "cat": "furniture", "rotate": true},
	{"id": "chair", "name": "Chair", "layer": "sub", "cost": 150, "drag": "paint", "cat": "furniture", "rotate": true},
	{"id": "fridge", "name": "Mini-Fridge", "layer": "object", "cost": 800, "drag": "paint", "cat": "furniture"},
	{"id": "counter", "name": "Counter with Sink", "layer": "object", "cost": 2500, "drag": "single", "cat": "furniture"},
	{"id": "table", "name": "Table", "layer": "object", "cost": 600, "drag": "paint", "cat": "furniture"},
	{"id": "toilet", "name": "Toilet Stall", "layer": "object", "cost": 1800, "drag": "paint", "cat": "furniture"},
	{"id": "trash", "name": "Garbage Can", "layer": "sub", "cost": 100, "drag": "paint", "cat": "furniture"},
	{"id": "bath_sink", "name": "Bathroom Sink", "layer": "sub", "cost": 700, "drag": "paint", "cat": "furniture"},
	{"id": "redteam", "name": "Red-Team Rig", "layer": "object", "cost": 40000, "drag": "paint", "cat": "safety"},
	{"id": "window_ac", "name": "Window AC", "layer": "window", "cost": 1200, "drag": "paint", "cat": "cooling"},
	{"id": "ac", "name": "AC Unit", "layer": "roof", "cost": 4500, "drag": "paint", "cat": "cooling"},
	{"id": "chiller", "name": "Water Chiller", "layer": "object", "cost": 9000, "drag": "paint", "cat": "cooling"},
	{"id": "pipe", "name": "Cooling Pipe", "layer": "sub", "cost": 60, "drag": "paint", "cat": "cooling"},
	{"id": "gen_portable", "name": "Portable Generator", "layer": "object", "cost": 2500, "drag": "paint", "cat": "power"},
	{"id": "gen_diesel", "name": "Diesel Generator", "layer": "object", "cost": 25000, "drag": "paint", "cat": "power"},
	{"id": "gen_large", "name": "Large Diesel", "layer": "object", "cost": 90000, "drag": "paint", "cat": "power"},
	{"id": "power_plant", "name": "Portable Power Plant", "layer": "object", "cost": 600000, "drag": "paint", "cat": "power"},
	{"id": "battery", "name": "Battery", "layer": "object", "cost": 30000, "drag": "paint", "cat": "power"},
	{"id": "grid", "name": "Grid Hookup", "layer": "object", "cost": 50000, "drag": "single", "cat": "power"},
	{"id": "solar_s", "name": "Solar Panel (S)", "layer": "object", "where": "either", "cost": 8000, "drag": "paint", "cat": "power"},
	{"id": "solar_m", "name": "Solar Panel (M)", "layer": "object", "where": "either", "cost": 17000, "drag": "paint", "cat": "power"},
	{"id": "solar_l", "name": "Solar Panel (L)", "layer": "object", "where": "either", "cost": 50000, "drag": "single", "cat": "power"},
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
	"Researchers at desks train models faster. Engineers at a Workstation babysit nearby racks for extra compute. Marketers at desks get users.",
	"Assign jobs under Staff (T). You don't tell people what to do, you tell them what their job is. Leadership.",
	"The board sets one target a quarter. Hit it and they love you. Miss it and, well, I hear Uber's hiring.",
	"Users are revenue. Revenue is users. I learned that at Stanford. Well, near Stanford.",
	"Right-click puts your tool away. Then click anything to pick it up and move it. Demolish is X. Like the old office culture. Disrupted.",
	"Every door is an open door policy if you think about it.",
	"Racks run hot, bro. Hot racks throttle, hot people sweat. Heat (H) shows where it's cooking.",
	"AC Units turn money into cold. Very inefficiently. It's Calizona, we don't have a choice.",
	"Deviation (V) is how much the AI does its own thing. Every rack adds a bit. Alignment Researchers fix it. Allegedly.",
	"Red-Team Rigs eat compute to yell at the model until it behaves. Like a performance review, bro.",
	"Safety blog posts don't lower Deviation. They do lower the board's blood pressure. Same thing, kind of.",
	"Generators are under Build (B), Power. Power (P) shows where the electrons go. Diesel is cheap to buy and expensive to run. Like me.",
	"Generators puff smog. It drifts. Technically that's the neighbours' air now.",
	"Generators wear out too. Hire a Mechanic, give them Maintenance, and lay some gravel next to the generator so they can stand there.",
]

# Research tree: four branches that grow upward from the garage. A node needs every node in its
# "req" list done first (no "req" means it starts its branch). "lane" puts it in its branch's
# left (0) or right (1) column; its row comes from how deep its requirements go.
# Researchers at desks make research points. A node can unlock Build menu items and/or add a bonus.
# Bonus keys: structure_discount, rack_discount, rack_heat, rack_power, cooling, cooler_power, compute,
# productivity, revenue, research_speed. A negative value is a drawback; "con" names it on the tree in red.
const RESEARCH_BRANCHES := [
	{"id": "construction", "name": "Construction"},
	{"id": "equipment", "name": "Equipment"},
	{"id": "chips", "name": "Computer Chips"},
	{"id": "productivity", "name": "Productivity"},
]
const RESEARCH := [
	# Construction
	{"id": "prefab", "branch": "construction", "name": "Prefab Walls", "cost": 40, "unlocks": ["wall_brick"], "structure_discount": 0.25,
		"desc": "Unlocks Brick Walls. Floors, walls and doors 25% cheaper. Some assembly required. All of it, actually."},
	{"id": "roofs", "branch": "construction", "req": ["prefab"], "name": "Load-Bearing Roofs", "cost": 100, "unlocks": ["solar_s", "solar_m", "solar_l", "parking_covered"],
		"desc": "Unlocks Solar Panels and Covered Parking. The roof was not, technically, load-bearing before."},
	{"id": "interiors", "branch": "construction", "req": ["prefab"], "lane": 1, "name": "Office Partitions", "cost": 100, "productivity": 0.05,
		"desc": "Staff 5% more productive. Walls between people: the original focus mode."},
	{"id": "insulation", "branch": "construction", "req": ["roofs"], "name": "Spray Foam Insulation", "cost": 220, "unlocks": ["wall_insulated"], "rack_heat": -0.2,
		"rack_discount": -0.05, "con": "+5% Server Rack cost",
		"desc": "Unlocks Insulated Walls. Racks heat rooms 20% less. Racks cost 5% more: the foam gets everywhere."},
	{"id": "raised", "branch": "construction", "req": ["insulation"], "lane": 1, "name": "Raised Floors", "cost": 380, "cooling": 0.1, "rack_heat": -0.1,
		"desc": "Coolers 10% stronger and racks give off 10% less heat. Cold air goes under, cables go everywhere."},
	{"id": "modular", "branch": "construction", "req": ["insulation"], "name": "Modular Datacenters", "cost": 380, "rack_discount": 0.2,
		"desc": "Server Racks 20% cheaper. Shipped flat-pack, with an allen key."},
	{"id": "hyperscale", "branch": "construction", "req": ["modular", "raised"], "name": "Hyperscale Campus", "cost": 650, "structure_discount": 0.15, "rack_discount": 0.1,
		"desc": "Building 15% cheaper and racks 10% cheaper. Zoned as 'agricultural'. The crop is compute."},
	# Equipment
	{"id": "diesel", "branch": "equipment", "name": "Diesel Know-How", "cost": 40, "unlocks": ["gen_diesel", "grid"],
		"desc": "Unlocks the Diesel Generator and the Grid Hookup."},
	{"id": "hvac", "branch": "equipment", "req": ["diesel"], "name": "Industrial HVAC", "cost": 100, "unlocks": ["ac"], "cooling": 0.25,
		"cooler_power": 0.1, "con": "+10% cooler power use",
		"desc": "Unlocks rooftop AC Units. All coolers 25% stronger, and they use 10% more power."},
	{"id": "lithium", "branch": "equipment", "req": ["hvac"], "name": "Lithium Supply Deal", "cost": 220, "unlocks": ["battery", "gen_large"],
		"desc": "Unlocks Batteries and the Large Diesel."},
	{"id": "liquid", "branch": "equipment", "req": ["hvac"], "lane": 1, "name": "Liquid Cooling", "cost": 220, "unlocks": ["pipe", "chiller"], "cooling": 0.15,
		"desc": "Unlocks cooling pipes. All coolers 15% stronger. Water and electronics: what could go wrong."},
	{"id": "turbines", "branch": "equipment", "req": ["lithium"], "name": "Trailer Turbines", "cost": 380, "unlocks": ["power_plant"],
		"desc": "Unlocks the Portable Power Plant."},
	{"id": "smartgrid", "branch": "equipment", "req": ["lithium"], "lane": 1, "name": "Smart Power", "cost": 380, "rack_power": -0.1,
		"desc": "Racks use 10% less power. A dashboard tells them to."},
	{"id": "immersion", "branch": "equipment", "req": ["turbines", "liquid"], "name": "Immersion Cooling", "cost": 650, "cooling": 0.3, "rack_heat": -0.15,
		"desc": "Coolers 30% stronger, racks give off 15% less heat. The servers live in a hot tub now."},
	# Computer Chips
	{"id": "overclock", "branch": "chips", "name": "Overclocking", "cost": 40, "unlocks": ["redteam"], "compute": 0.15,
		"rack_heat": 0.1, "con": "+10% rack heat",
		"desc": "Unlocks the Red-Team Rig. Racks make 15% more compute and 10% more heat. Warranty void."},
	{"id": "silicon", "branch": "chips", "req": ["overclock"], "name": "Custom Silicon", "cost": 100, "unlocks": ["rack_improved"], "compute": 0.25,
		"desc": "Unlocks the Improved Server Rack. Racks make 25% more compute."},
	{"id": "arxiv", "branch": "chips", "req": ["overclock"], "lane": 1, "name": "arXiv Speedreading", "cost": 100, "research_speed": 0.2,
		"desc": "Research points come 20% faster. Nobody reads past the abstract anyway."},
	{"id": "tensor", "branch": "chips", "req": ["silicon"], "name": "Tensor Cores", "cost": 220, "compute": 0.2,
		"desc": "Racks make 20% more compute. Matrices, multiplied. Professionally."},
	{"id": "lowpower", "branch": "chips", "req": ["silicon"], "lane": 1, "name": "Low-Power Chips", "cost": 220, "rack_power": -0.25, "rack_heat": -0.15,
		"desc": "Racks use 25% less power and give off 15% less heat."},
	{"id": "wafer", "branch": "chips", "req": ["tensor"], "name": "Wafer-Scale Chips", "cost": 380, "unlocks": ["rack_advanced"], "compute": 0.4,
		"desc": "Unlocks the Advanced Server Rack. Racks make 40% more compute. One chip, the size of a pizza."},
	{"id": "photonic", "branch": "chips", "req": ["wafer", "lowpower"], "name": "Photonic Interconnect", "cost": 650, "compute": 0.3, "rack_power": -0.1,
		"desc": "Racks make 30% more compute and use 10% less power. The data travels by laser now. Pew."},
	{"id": "quantum", "branch": "chips", "req": ["photonic"], "name": "Quantum-ish Chips", "cost": 950, "compute": 0.5,
		"rack_heat": 0.2, "con": "+20% rack heat",
		"desc": "Racks make 50% more compute and 20% more heat. It's quantum in the sense that nobody can tell if it works."},
	# Productivity
	{"id": "snacks", "branch": "productivity", "name": "Free Snacks", "cost": 40, "productivity": 0.1,
		"revenue": -0.01, "con": "-1% revenue",
		"desc": "Staff 10% more productive. The snack budget eats 1% of revenue."},
	{"id": "standups", "branch": "productivity", "req": ["snacks"], "name": "Daily Standups", "cost": 100, "unlocks": ["desk_adv"], "productivity": 0.1,
		"desc": "Unlocks the Advanced Desk. Staff 10% more productive, net of the standups."},
	{"id": "kombucha", "branch": "productivity", "req": ["snacks"], "lane": 1, "name": "Kombucha on Tap", "cost": 100, "productivity": 0.05,
		"revenue": -0.01, "con": "-1% revenue",
		"desc": "Staff 5% more productive. It costs 1% of revenue and smells like a gym bag."},
	{"id": "hustle", "branch": "productivity", "req": ["standups"], "name": "Hustle Culture", "cost": 220, "unlocks": ["cubicle"], "productivity": 0.15,
		"desc": "Unlocks Cubicles. Staff 15% more productive. Sleep pods are a perk."},
	{"id": "pto", "branch": "productivity", "req": ["hustle"], "name": "Unlimited PTO", "cost": 380, "productivity": 0.15,
		"desc": "Staff 15% more productive. Nobody takes it."},
	{"id": "equity", "branch": "productivity", "req": ["hustle"], "lane": 1, "name": "Equity Refresh", "cost": 380, "productivity": 0.1, "research_speed": 0.1,
		"desc": "Staff 10% more productive and research 10% faster. Paper money, real motivation."},
	{"id": "fourday", "branch": "productivity", "req": ["pto", "equity"], "name": "Four-Day Week", "cost": 650, "productivity": 0.2,
		"desc": "Staff 20% more productive. The fifth day is 'optional'."},
]
const UNLOCK_ALL := false  # true for testing: every Build item is available without research.
const INFINITE_MONEY := false  # true for testing: money stays topped up at $1B, so nothing is unaffordable.
const RESEARCH_BASE := 1.0  # research points a day the founders scrape together on their own
const RESEARCH_PER_WORKER := 1.0  # extra points a day per researcher at a desk

var floor_tiles := {}  # Vector2i -> "carpet" / "concrete"
var wall_tiles := {}  # Vector2i -> "wall" / "door"
var objects := {}  # Vector2i -> "desk" / "rack" / "ficus"
var sub_objects := {}  # subgrid cell Vector2i -> "coffee"

var money := 150_000
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
var rack_cond := {}  # Vector2i -> rack condition 0-100 (missing = 100)
var racks_hot := {}  # Vector2i -> true for racks shut down by overheating
var racks_off := {}  # Vector2i -> true for racks the player switched off
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
var reach := {}  # Vector2i -> true for walkable tiles connected to a door or the outdoors
var place_rot := 0  # Q: which way the next rotatable item faces
var sub_rot := {}  # subgrid cell -> turn, for rotatable items
var tool_active := true  # false = nothing selected: click an item to pick it up and move it
var obj_off := {}  # object tile -> Vector2i(0-1, 0-1): how many subgrid cells it is shifted (drawing and hit box only)
var place_off := Vector2i.ZERO  # the shift the item being placed or carried would get at the mouse
var held := {}  # the item being moved: id, origin cell, rot. Empty when nothing is in hand
var zoom_level := 1.4  # how close the camera is; the tilted view squashes y on top of this
var tilt_on := false
var move_button: Button
var tilt_button: Button
var roofs_off := false  # Shift+R: keep every roof hidden
var room_of := {}  # Vector2i -> index into buildings, for every tile under a roof
var heat := PackedFloat32Array()  # temperature per tile, GRID_W * GRID_H; only indoor floor tiles change
var heat_cells: Array[Vector2i] = []  # the indoor floor tiles (doors included)
var _heat_timer := 0.0
var outdoor_temp := 75.0  # today's temperature outside, set from the date every heat step
var _iwall_tiles := {}  # tile -> how many interior wall cells it holds (0-4), rebuilt every heat step
var pipe_net := {}  # {"cell": subcell -> loop index, "loops": [{cells, racks, chillers, blocked}]}
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
var world: Node2D  # the canal, farms, highway and town around your property
var top_label: Label
var company_button: Button
var company_page: Control
var company_tabs: TabContainer
var company_tab_buttons := []
var company_title: Label
var chet_label: Label
var cost_label: Label
var hover_tip: Label  # says what's under the mouse
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
# "tab" is the index of the panel in the right-hand side panel; build opens the build bar. The Company page
# (board and policies) has no button here: click the company name in the top bar, or press O (see main.gd).
const MENUS := [
	{"id": "build", "name": "Build", "key": KEY_B},
	{"id": "models", "name": "Models", "key": KEY_M, "tab": 0},
	{"id": "staff", "name": "Staff", "key": KEY_T, "tab": 1},
	{"id": "heat", "name": "Heat", "key": KEY_H, "tab": 2},
	{"id": "power", "name": "Power", "key": KEY_P, "tab": 3},
	{"id": "deviation", "name": "Deviation", "key": KEY_V, "tab": 4},
	{"id": "research", "name": "Research", "key": KEY_E},  # its own full-screen page, not a side tab
	{"id": "government", "name": "Government", "key": KEY_L},  # full-screen lobbying page (government.gd)
	{"id": "guide", "name": "Guide", "key": KEY_G, "tab": 5},
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
var roof_button: Button
var build_popup: Control  # scrollable list of the open category's tools, just above the bottom bar
var bottom_bar: Control
var power_ratio := 1.0  # share of demand covered last step
var unpowered := {}  # machines left without power last step: Vector3i(x, y, layer), layer 0 floor, 1 roof, 2 wall
var power_bill := 0  # yesterday's fuel and grid bill
var _power_cost := 0.0  # today's so far
var _power_step := 0  # step of the day, 0 = midnight
var _power_warned := false
var _smog_warned := false
var battery_charge := 0.0  # kWh, shared by all batteries
var power_stats := {}  # last step: demand, solar, grid, battery, gens (kW)
var roof_parts := {}  # same as parts, for big things on roofs
var parts := {}  # Vector2i -> top-left tile of the big object covering it (objects holds "part" there)
var gen_output := {}  # Vector2i -> kW a generator made last step
var gen_cond := {}  # Vector2i -> generator condition 0-100 (missing = 100)
var _funds_level := 0  # 0 fine, 1 under LOW_FUNDS_WARN, 2 under LOW_FUNDS_RED
var money_label: Label
var expenses_label: Label
var revenue_label: Label
var warn_banner: Label
var smog := PackedFloat32Array()  # pollution per tile, 0-100, GRID_W * GRID_H
var research_done := {}  # research id -> true
var research_active := ""  # what the research points go towards
var research_points := 0.0  # banked, spent when the active node is paid off
var research_page: Control  # full-screen research tree
var gov: CanvasLayer  # the Government page and lobbying (government.gd)
var research_tree: Control  # holds the node buttons; draws the lines between them
var research_scroll: ScrollContainer  # the tree scrolls; it opens at the bottom, where the garage is
var research_scrolled := false
var research_label: Label
var research_bar: ProgressBar
var research_buttons := {}  # research id -> Button
var modal: Control  # the open pop-up, if any; the game pauses under it
var modal_button: Button
var _speed_before_modal := 1
var tutorial_step := -1  # Chet's tutorial (tutorial.gd): -1 not offered yet, then the step; past the end once done or skipped
var tutorial_base := 0  # staff or desks counted when the current step began
var tutorial_panel: Control
var tutorial_title: Label
var tutorial_label: Label
var tutorial_button: Button



# --- Forward declarations --------------------------------------------------
func _rebuild_pipe_net() -> void:
	pass
func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	pass
func _box(base: Rect2, h: float, top: Color, front: Color) -> void:
	pass
# Real versions live in later files of the chain; these let earlier files call them.
func _tick_deviation() -> void:
	pass
func _after_build() -> void:
	pass
func _reachable(t: Vector2i) -> bool:
	return false
func _workforce(job: String) -> float:
	return 0.0
func _powered(t: Vector2i, layer := 0) -> bool:
	return false
func _coolers() -> Array:
	return []
func _temp(t: Vector2i) -> float:
	return 0.0
func _find_buildings() -> void:
	pass
func _remove_roof_object(a: Vector2i) -> void:
	pass
func _roofed(t: Vector2i) -> bool:
	return false
func _hash(t: Vector2i, salt := 0) -> int:
	return 0
func _research_bonus(key: String) -> float:
	return 0.0
func _tick_research() -> void:
	pass
func _rebuild_staff_list() -> void:
	pass
func _chet(text: String) -> void:
	pass
func _label_tools() -> void:
	pass
func _level_tools() -> Array:
	return []
func _locked(tool_id: String) -> bool:
	return false
func _money(v: int) -> String:
	return ""
func _num(v: int) -> String:
	return ""
func _panel_style(alpha := 0.85) -> StyleBoxFlat:
	return null
func _refresh_menu_buttons() -> void:
	pass
func _select_tool(i: int) -> void:
	pass
func _show_modal(title: String, body: String, button_text: String, on_close: Callable, extra: Control = null) -> void:
	pass
func _tab_box(title: String) -> VBoxContainer:
	return null
func _toggle_menu(id: String) -> void:
	pass
func _tool_cost(tool: Dictionary) -> int:
	return 0
func _wrap_label(parent: Control) -> Label:
	return null
func _mouse_over_ui() -> bool:
	return false
