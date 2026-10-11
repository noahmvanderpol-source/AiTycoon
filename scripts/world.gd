extends Node2D
# The land around your property: the canal and irrigated farms to the north, the highway
# to the west, a small town to the south and open desert to the east. Scenery for now;
# you can only build on your own property (main.gd draws that part).

const TILE := 32
const PROP := Rect2i(0, 0, 64, 48)  # your land, the same grid main.gd builds on
const WORLD := Rect2i(-26, -52, 136, 140)  # the whole map, canal along the top
const SAND := Color(0.84, 0.72, 0.5)
const TOWN := "Dustwater"

# North
const CANAL_TOP := -52  # north bank; water below it; south bank; then the canal road
const FARM_TOP := -45
const FARM_BOTTOM := -15
const FARM_LEFT := -8
const FIELD_W := 17  # 16 tiles of crops then a dirt farm road
const FARM_ROAD_Y := -30
const PIPE_X := 44  # the water pipeline, canal to your north fence
const FARMHOUSES := [Rect2i(-6, -43, 5, 4), Rect2i(64, -28, 5, 4), Rect2i(95, -43, 5, 4)]
const CROPS := ["alfalfa", "cotton", "lettuce", "almonds", "fallow"]

# West
const HWY_LEFT := -20  # shoulder, 2 lanes, median, 2 lanes, shoulder
const HWY_RIGHT := -14
const ACCESS_Y := 30  # two-lane road from the highway to your west fence

# South
const MAIN_ST_Y := 67
const SECOND_ST_Y := 75
const CROSS_X := 29  # two lanes from your south fence through town
const LOTS := [
	{"kind": "gas", "r": Rect2i(-11, 62, 9, 5)},
	{"kind": "house", "r": Rect2i(0, 62, 6, 5)}, {"kind": "house", "r": Rect2i(7, 62, 6, 5)},
	{"kind": "house", "r": Rect2i(14, 62, 6, 5)}, {"kind": "house", "r": Rect2i(21, 62, 6, 5)},
	{"kind": "lot", "r": Rect2i(33, 62, 6, 5)},
	{"kind": "house", "r": Rect2i(40, 62, 6, 5)}, {"kind": "house", "r": Rect2i(47, 62, 6, 5)},
	{"kind": "house", "r": Rect2i(0, 69, 6, 6)}, {"kind": "house", "r": Rect2i(7, 69, 6, 6)},
	{"kind": "lot", "r": Rect2i(14, 69, 6, 6)}, {"kind": "house", "r": Rect2i(21, 69, 6, 6)},
	{"kind": "house", "r": Rect2i(33, 69, 6, 6)}, {"kind": "house", "r": Rect2i(40, 69, 6, 6)},
	{"kind": "lot", "r": Rect2i(47, 69, 6, 6)},
	{"kind": "house", "r": Rect2i(0, 77, 6, 5)}, {"kind": "house", "r": Rect2i(7, 77, 6, 5)},
	{"kind": "house", "r": Rect2i(14, 77, 6, 5)}, {"kind": "lot", "r": Rect2i(21, 77, 6, 5)},
	{"kind": "house", "r": Rect2i(33, 77, 6, 5)},
]
const HOUSE_COLORS := [Color(0.9, 0.85, 0.72), Color(0.78, 0.62, 0.48), Color(0.72, 0.8, 0.82),
		Color(0.88, 0.74, 0.6), Color(0.8, 0.78, 0.66), Color(0.68, 0.72, 0.6)]
const ROOF_COLORS := [Color(0.62, 0.33, 0.25), Color(0.45, 0.42, 0.4), Color(0.55, 0.45, 0.35)]

# Outrage, 0-100: smog drifting off your property onto houses and farmhouses angers the neighbours.
const OUTRAGE_PER_SMOG := 0.03  # per step, per point of smog on the worst tile of each home
const OUTRAGE_DECAY := 0.02  # per step (8 a day), as people find something else to be mad about
const SMOG_SPREAD := 0.5  # same drift as on your property
const SMOG_DECAY := 0.015

var _time := 0.0
var outrage := 0.0
var smog := {}  # Vector2i -> smog on tiles off your property (sparse, 0-100)
var _outrage_warned := false


func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_2d()
	if cam:  # don't let the view wander off the edge of the map
		cam.position = cam.position.clamp(Vector2(WORLD.position) * TILE, Vector2(WORLD.end) * TILE)
	queue_redraw()


# --- Smog and Outrage -----------------------------------------------------------

# Smog that drifts over your fence (main.gd's spread hands it over).
func add_smog(t: Vector2i, v: float) -> void:
	if WORLD.has_point(t) and not PROP.has_point(t):
		smog[t] = minf(smog.get(t, 0.0) + v, 100.0)


func smog_at(t: Vector2i) -> float:
	return smog.get(t, 0.0)


# One step of drift, then the neighbours react. Called with each power/heat step.
func tick_smog() -> void:
	var next := {}
	for t in smog:
		var v: float = smog[t] * (1.0 - SMOG_DECAY)
		var share := v * SMOG_SPREAD / 4.0
		next[t] = next.get(t, 0.0) + v - share * 4.0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if WORLD.has_point(n) and not PROP.has_point(n):  # what drifts back over the fence or off the map is lost
				next[n] = next.get(n, 0.0) + share
	smog = {}
	for t in next:
		if next[t] >= 0.01:
			smog[t] = next[t]
	var rise := 0.0
	for lot in LOTS:
		if lot.kind == "house":
			rise += _worst_smog(lot.r) * OUTRAGE_PER_SMOG
	for fr in FARMHOUSES:
		rise += _worst_smog(fr) * OUTRAGE_PER_SMOG
	outrage = clampf(outrage + rise - OUTRAGE_DECAY, 0.0, 100.0)
	if outrage >= 25.0 and not _outrage_warned:
		_outrage_warned = true
		get_parent()._chet("Bro, the neighbours can taste our generators. %s is mad. Outrage is in the Guide (G)." % TOWN)
	elif outrage < 10.0:
		_outrage_warned = false


func _worst_smog(r: Rect2i) -> float:
	var worst := 0.0
	if smog.is_empty():
		return worst
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			worst = maxf(worst, smog.get(Vector2i(x, y), 0.0))
	return worst


func _home_rect(t: Vector2i) -> Rect2i:
	var i := _farmhouse_at(t)
	if i >= 0:
		return FARMHOUSES[i]
	var lot := _lot_at(t)
	return lot.r if not lot.is_empty() else Rect2i(t, Vector2i.ONE)


# --- What's where -------------------------------------------------------------

func _in_rect(t: Vector2i, x0: int, x1: int, y0: int, y1: int) -> bool:  # inclusive
	return t.x >= x0 and t.x <= x1 and t.y >= y0 and t.y <= y1


func _lot_at(t: Vector2i) -> Dictionary:
	for lot in LOTS:
		if lot.r.has_point(t):
			return lot
	return {}


func _farmhouse_at(t: Vector2i) -> int:
	for i in FARMHOUSES.size():
		if FARMHOUSES[i].has_point(t):
			return i
	return -1


func kind_at(t: Vector2i) -> String:
	if PROP.has_point(t):
		return "property"
	if not WORLD.has_point(t):
		return ""
	if t.x >= HWY_LEFT and t.x <= HWY_RIGHT:
		return "highway"
	if t.y <= CANAL_TOP + 5:
		return "bank" if t.y == CANAL_TOP or t.y == CANAL_TOP + 5 else "canal"
	if t.y == CANAL_TOP + 6 and t.x > HWY_RIGHT:
		return "canal_road"
	if t.x == PIPE_X and t.y < 0 and t.y > CANAL_TOP + 6:
		return "pipeline"
	if _farmhouse_at(t) >= 0:
		return "farmhouse"
	if t.y >= FARM_TOP and t.y <= FARM_BOTTOM and t.x >= FARM_LEFT:
		if t.y == FARM_ROAD_Y or (t.x - FARM_LEFT) % FIELD_W == FIELD_W - 1:
			return "farm_road"
		return "field"
	if _in_rect(t, HWY_RIGHT + 1, -1, ACCESS_Y, ACCESS_Y + 1):
		return "road"
	if _in_rect(t, HWY_RIGHT + 1, 60, MAIN_ST_Y, MAIN_ST_Y + 1) or _in_rect(t, HWY_RIGHT + 1, 56, SECOND_ST_Y, SECOND_ST_Y + 1) \
			or _in_rect(t, CROSS_X, CROSS_X + 1, PROP.end.y, SECOND_ST_Y + 8):
		return "street"
	var lot := _lot_at(t)
	if not lot.is_empty():
		return lot.kind
	return "desert"


func _field_crop(t: Vector2i) -> String:
	var fx := floori(float(t.x - FARM_LEFT) / FIELD_W)
	var fy := 0 if t.y < FARM_ROAD_Y else 1
	return CROPS[absi(hash(Vector2i(fx, fy))) % CROPS.size()]


# Hover text for anything off your property.
func describe(t: Vector2i) -> String:
	var text := _describe_kind(t)
	var kind := kind_at(t)
	if kind == "house" or kind == "farmhouse":
		text += "\nSmog: %d" % int(_worst_smog(_home_rect(t)))
	elif smog_at(t) >= 1.0:
		text += "\nSmog: %d" % int(smog_at(t))
	return text


func _describe_kind(t: Vector2i) -> String:
	match kind_at(t):
		"canal", "bank":
			return "Calizona Aqueduct Canal\nNorthern edge of the map\nWater rights: lobbying needed (later)"
		"canal_road":
			return "Canal service road"
		"pipeline":
			return "Water pipeline\nCanal to your property\nNot flowing yet: needs water rights"
		"field":
			var crop: String = _field_crop(t)
			var what := "Fallow field" if crop == "fallow" else "Irrigated %s" % crop
			return "%s\nFarmland (not yours)\nCan be bought later" % what
		"farm_road":
			return "Farm road\nFarmland (not yours)"
		"farmhouse":
			return "Farmhouse (not yours)\nCan be bought later, with its fields"
		"highway":
			return "Highway CZ-99\nTo the coast, eventually"
		"road":
			return "Access road\nHighway to your property"
		"street":
			return "%s street" % TOWN
		"house":
			return "House in %s\nNeighbors. They have opinions." % TOWN
		"gas":
			return "Gas 'n' Grub\n%s's only gas station" % TOWN
		"lot":
			return "Empty community lot\nFor a park, library or similar\n(later: lowers Outrage)"
		"desert":
			return "Open desert (not yours)"
	return ""


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var view := get_viewport_rect().size / cam.zoom
	var a := Vector2i(((cam.position - view / 2) / TILE).floor()) - Vector2i(1, 1)
	var b := Vector2i(((cam.position + view / 2) / TILE).ceil()) + Vector2i(1, 4)
	a = a.clamp(WORLD.position, WORLD.end)
	b = b.clamp(WORLD.position, WORLD.end)
	for y in range(a.y, b.y):
		for x in range(a.x, b.x):
			var t := Vector2i(x, y)
			if not PROP.has_point(t):
				_draw_ground(t)
	_draw_fence()
	var vis := Rect2i(a, b - a).grow(6)
	for i in FARMHOUSES.size():
		if vis.intersects(FARMHOUSES[i]):
			_draw_farmhouse(FARMHOUSES[i], i)
	if vis.intersects(Rect2i(PIPE_X, CANAL_TOP, 1, -CANAL_TOP)):
		_draw_pipeline()
	if vis.intersects(Rect2i(HWY_LEFT, WORLD.position.y, 7, WORLD.size.y)):
		_draw_traffic(a.y, b.y)
	for lot in LOTS:
		if vis.intersects(lot.r):
			call("_draw_" + lot.kind, lot.r)
	_draw_signs(vis)
	var grid := Color(0, 0, 0, 0.06)  # the same faint tile grid as on your property, over everything
	for x in range(a.x, b.x + 1):
		draw_line(Vector2(x, a.y) * TILE, Vector2(x, b.y) * TILE, grid)
	for y in range(a.y, b.y + 1):
		draw_line(Vector2(a.x, y) * TILE, Vector2(b.x, y) * TILE, grid)
	_draw_smog(a, b)


func _draw_smog(a: Vector2i, b: Vector2i) -> void:
	if smog.is_empty():
		return
	var main := get_parent()
	var strength := 1.0 if main.side_panel.visible and main.tabs.current_tab == 4 else 0.35  # as on your property
	for t in smog:
		var v: float = smog[t]
		if v > 0.5 and t.x >= a.x and t.y >= a.y and t.x < b.x and t.y < b.y:
			draw_rect(_rect(t), Color(0.35, 0.28, 0.2, clampf(v / 50.0, 0.0, 0.7) * strength))


func _rect(t: Vector2i) -> Rect2:
	return Rect2(Vector2(t) * TILE, Vector2(TILE, TILE))


func _hash(t: Vector2i, salt := 0) -> int:
	return absi(hash(Vector3i(t.x, t.y, salt + 99)))


func _draw_ground(t: Vector2i) -> void:
	var r := _rect(t)
	match kind_at(t):
		"canal":
			draw_rect(r, Color(0.2, 0.45, 0.6))
			var shimmer := sin(_time * 1.5 + t.x * 0.7 + t.y * 1.3)
			if shimmer > 0.6:
				draw_line(r.position + Vector2(6, 14), r.position + Vector2(22, 14), Color(0.55, 0.75, 0.85, 0.7), 2.0)
		"bank":
			draw_rect(r, Color(0.6, 0.58, 0.54))  # concrete-lined, as Calizona's finest
			var edge := r.position.y + (TILE - 4.0 if t.y == CANAL_TOP else 0.0)
			draw_rect(Rect2(r.position.x, edge, TILE, 4), Color(0.45, 0.44, 0.42))
		"canal_road", "farm_road":
			draw_rect(r, Color(0.7, 0.58, 0.4))
			if _hash(t) % 3 == 0:
				draw_circle(r.position + Vector2(_hash(t) % 25 + 4, 16), 1.5, Color(0.58, 0.47, 0.32))
		"field":
			_draw_field(t, r)
		"pipeline":  # runs over the fields, then open desert
			if t.y >= FARM_TOP and t.y <= FARM_BOTTOM:
				_draw_field(t, r)
			else:
				draw_rect(r, SAND)
		"farmhouse":
			draw_rect(r, Color(0.66, 0.6, 0.4))
		"highway":
			_draw_highway(t, r)
		"road", "street":
			_draw_street(t, r)
		"house", "lot", "gas":
			draw_rect(r, SAND)  # the lot draws its own yard on top
		_:
			draw_rect(r, SAND)
			_draw_desert_detail(t, r)


func _draw_field(t: Vector2i, r: Rect2) -> void:
	var crop: String = _field_crop(t)
	if crop == "fallow":
		draw_rect(r, Color(0.66, 0.52, 0.36))
		for k in 3:
			draw_line(r.position + Vector2(0, 5 + k * 11), r.position + Vector2(TILE, 5 + k * 11), Color(0.58, 0.45, 0.3), 2.0)
		return
	draw_rect(r, Color(0.5, 0.38, 0.24))  # wet soil between the rows
	var green: Color = {"alfalfa": Color(0.35, 0.6, 0.25), "cotton": Color(0.42, 0.55, 0.3),
			"lettuce": Color(0.5, 0.72, 0.32), "almonds": Color(0.3, 0.48, 0.22)}[crop]
	if crop == "almonds":  # orchard: a tree per tile
		draw_circle(r.position + Vector2(16, 20), 9, Color(0, 0, 0, 0.18))
		draw_circle(r.position + Vector2(16, 14), 10, green)
		draw_circle(r.position + Vector2(13, 11), 4, green.lightened(0.2))
	else:
		for k in 4:  # crop rows
			draw_rect(Rect2(r.position + Vector2(0, 2 + k * 8), Vector2(TILE, 5)), green)
		if crop == "cotton" and _hash(t) % 2 == 0:
			for k in 3:
				draw_circle(r.position + Vector2(5 + k * 11, 4 + (_hash(t, k) % 4) * 8), 1.5, Color(0.97, 0.97, 0.95))
	if (t.y - FARM_TOP) % 8 == 0:  # irrigation ditch
		draw_rect(Rect2(r.position, Vector2(TILE, 3)), Color(0.3, 0.55, 0.7))


func _draw_highway(t: Vector2i, r: Rect2) -> void:
	var col := t.x - HWY_LEFT
	if col == 3:  # median with a concrete barrier
		draw_rect(r, Color(0.62, 0.55, 0.42))
		draw_rect(Rect2(r.position + Vector2(12, 0), Vector2(8, TILE)), Color(0.75, 0.74, 0.7))
		return
	if col == 0 or col == 6:  # shoulders
		draw_rect(r, Color(0.32, 0.31, 0.32))
		var x := r.position.x + (TILE - 3.0 if col == 0 else 1.0)
		draw_rect(Rect2(x, r.position.y, 2, TILE), Color(0.95, 0.95, 0.9))
		return
	draw_rect(r, Color(0.25, 0.25, 0.27))
	if (col == 1 or col == 4) and t.y % 2 == 0:  # dashed lane line
		draw_rect(Rect2(r.end.x - 1, r.position.y + 4, 2, 16), Color(0.95, 0.95, 0.9))
	if col == 2:
		draw_rect(Rect2(r.end.x - 2, r.position.y, 2, TILE), Color(0.95, 0.8, 0.2))
	if col == 4:
		draw_rect(Rect2(r.position.x, r.position.y, 2, TILE), Color(0.95, 0.8, 0.2))


func _draw_street(t: Vector2i, r: Rect2) -> void:
	draw_rect(r, Color(0.3, 0.3, 0.31))
	var vertical := kind_at(t + Vector2i.LEFT) != "street" or kind_at(t + Vector2i.RIGHT) != "street"
	vertical = vertical and t.x >= CROSS_X and t.x <= CROSS_X + 1 and t.y != MAIN_ST_Y and t.y != MAIN_ST_Y + 1 \
			and t.y != SECOND_ST_Y and t.y != SECOND_ST_Y + 1
	if vertical:
		if t.x == CROSS_X and t.y % 2 == 0:
			draw_rect(Rect2(r.end.x - 1, r.position.y + 6, 2, 14), Color(0.92, 0.88, 0.7))
	elif (t.y == MAIN_ST_Y or t.y == SECOND_ST_Y or t.y == ACCESS_Y) and t.x % 2 == 0:
		draw_rect(Rect2(r.position.x + 6, r.end.y - 1, 14, 2), Color(0.92, 0.88, 0.7))


func _draw_desert_detail(t: Vector2i, r: Rect2) -> void:
	var h := _hash(t)
	if h % 5 == 0:
		draw_circle(r.position + Vector2(h % 23 + 4, (h / 23) % 23 + 4), 1.5, Color(0.7, 0.58, 0.38))
	if h % 41 == 0:  # scrub
		var c := r.position + Vector2(16, 20)
		_ellipse(c + Vector2(2, 4), 9, 4, Color(0, 0, 0, 0.15))
		draw_circle(c - Vector2(0, 4), 6, Color(0.48, 0.53, 0.28))
		draw_circle(c + Vector2(4, -8), 4, Color(0.58, 0.64, 0.35))
	elif h % 67 == 1:  # saguaro
		var c := r.position + Vector2(16, 26)
		_ellipse(c + Vector2(3, 2), 7, 3, Color(0, 0, 0, 0.18))
		draw_rect(Rect2(c + Vector2(-3, -26), Vector2(6, 26)), Color(0.33, 0.52, 0.3))
		draw_rect(Rect2(c + Vector2(-10, -18), Vector2(4, 10)), Color(0.33, 0.52, 0.3))
		draw_rect(Rect2(c + Vector2(-10, -10), Vector2(8, 3)), Color(0.33, 0.52, 0.3))
		draw_rect(Rect2(c + Vector2(6, -22), Vector2(4, 8)), Color(0.33, 0.52, 0.3))
		draw_rect(Rect2(c + Vector2(2, -16), Vector2(8, 3)), Color(0.33, 0.52, 0.3))
	elif h % 89 == 2:  # rock
		var c := r.position + Vector2(14, 20)
		_ellipse(c + Vector2(2, 3), 9, 4, Color(0, 0, 0, 0.15))
		_ellipse(c, 8, 6, Color(0.6, 0.5, 0.42))
		_ellipse(c - Vector2(2, 2), 4, 3, Color(0.7, 0.6, 0.5))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var ang := TAU * i / 16.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, col)


func _box(base: Rect2, h: float, top: Color, front: Color) -> void:
	draw_rect(Rect2(base.position - Vector2(0, h), base.size), top)
	draw_rect(Rect2(Vector2(base.position.x, base.end.y - h), Vector2(base.size.x, h)), front)


# A whole-tile rect: x, y, w, h in tiles.
func _tiles(x: int, y: int, w := 1, h := 1) -> Rect2:
	return Rect2(Vector2(x, y) * TILE, Vector2(w, h) * TILE)


# A house filling `base` (whole tiles): walls, a pitched roof seen from the front, a door and windows.
func _draw_home(base: Rect2, h: float, wall: Color, roof: Color) -> void:
	draw_rect(Rect2(base.position + Vector2(4, base.size.y - 6), Vector2(base.size.x, 6)), Color(0, 0, 0, 0.15))
	draw_rect(Rect2(base.position.x, base.end.y - h, base.size.x, h), wall)
	var top := base.end.y - h
	draw_colored_polygon(PackedVector2Array([Vector2(base.position.x, top), Vector2(base.end.x, top),
			Vector2(base.end.x - 8, base.position.y), Vector2(base.position.x + 8, base.position.y)]), roof)
	draw_line(Vector2(base.position.x + 8, base.position.y), Vector2(base.end.x - 8, base.position.y), roof.darkened(0.3), 2.0)
	var mid := base.position.x + base.size.x / 2
	draw_rect(Rect2(mid - 5, base.end.y - 16, 10, 16), wall.darkened(0.45))
	if base.size.x >= TILE * 3:
		for side in [-1, 1]:
			draw_rect(Rect2(mid + side * base.size.x / 4 - 6, base.end.y - h + 6, 12, 9), Color(0.55, 0.7, 0.8))


func _draw_palm(t: Vector2i) -> void:  # a palm tree that drinks more than the house
	var c := Vector2(t) * TILE + Vector2(16, 28)
	draw_line(c, c - Vector2(2, 30), Color(0.5, 0.38, 0.25), 3.0)
	for k in 5:
		var ang := -PI / 2 + (k - 2) * 0.55
		draw_line(c - Vector2(2, 30), c - Vector2(2, 30) + Vector2(cos(ang) * 13, sin(ang) * 8 + 6), Color(0.3, 0.55, 0.25), 3.0)


# Lots are 6 tiles wide. Row by row from the street: a 2-tile path, a 4x2 house, yard.
func _draw_house(lr: Rect2i) -> void:
	var x := lr.position.x
	var y := lr.position.y
	var h := _hash(lr.position, 3)
	draw_rect(_tiles(x, y, lr.size.x, lr.size.y), Color(0.74, 0.7, 0.45) if h % 3 else Color(0.62, 0.66, 0.38))  # yard
	draw_rect(_tiles(x, y, lr.size.x, lr.size.y), Color(0.55, 0.47, 0.32), false, 2.0)  # property line
	var street_below := lr.end.y == MAIN_ST_Y  # face the nearest street
	var house_y := y + 1 if street_below else y + 2
	var path_y := house_y + 2 if street_below else y
	draw_rect(_tiles(x + 2, path_y, 2, lr.end.y - path_y if street_below else 2).grow_individual(-8, 0, -8, 0), Color(0.68, 0.67, 0.64))
	_draw_home(_tiles(x + 1, house_y, 4, 2), 26.0, HOUSE_COLORS[h % HOUSE_COLORS.size()], ROOF_COLORS[(h / 7) % ROOF_COLORS.size()])
	var extra_y := y if street_below else lr.end.y - 1  # the back yard row
	if h % 4 == 0:  # pool, because it's the desert
		var pr := _tiles(x + 4, extra_y, 2, 1).grow(-3)
		draw_rect(pr, Color(0.3, 0.7, 0.85))
		draw_rect(pr, Color(0.9, 0.9, 0.88), false, 2.0)
	elif h % 4 == 1:  # a car that hasn't moved since 2019
		_draw_car(Vector2(x, path_y + (1 if street_below else 0)) * TILE + Vector2(4, 9), Color(0.55, 0.3, 0.2), false)
	else:
		_draw_palm(Vector2i(x + 5, house_y + 1))


func _draw_gas(lr: Rect2i) -> void:
	var x := lr.position.x
	var y := lr.position.y
	draw_rect(_tiles(x, y, lr.size.x, lr.size.y), Color(0.36, 0.36, 0.37))  # forecourt
	_box(_tiles(x + 6, y + 1, 3, 3), 28.0, Color(0.85, 0.83, 0.78), Color(0.75, 0.72, 0.66))  # store, 3x3
	draw_rect(Rect2(Vector2(x + 7, y + 4) * TILE + Vector2(7, -18), Vector2(18, 18)), Color(0.5, 0.65, 0.75))
	for k in 2:  # pumps, one tile each
		_box(_tiles(x + 1 + k * 2, y + 2).grow(-9), 18.0, Color(0.85, 0.2, 0.15), Color(0.65, 0.12, 0.1))
	draw_rect(_tiles(x, y + 1, 5, 1), Color(0.92, 0.92, 0.9, 0.85))  # canopy over the pumps, 5x1
	draw_rect(Rect2(Vector2(x, y + 2) * TILE - Vector2(0, 6), Vector2(5 * TILE, 6)), Color(0.85, 0.2, 0.15))
	for k in [0, 5]:
		draw_rect(Rect2(Vector2(x + k, y + 2) * TILE - Vector2(2 if k else 0, 0), Vector2(3, TILE)), Color(0.8, 0.8, 0.8))
	_label(Vector2(x + 7.5, y + 0.3) * TILE, "GAS 'N' GRUB", 11, Color(1, 0.9, 0.4))
	_label(Vector2(x + 7.5, y + 0.3) * TILE + Vector2(0, 12), "$11.99/gal", 10, Color(1, 1, 1))


func _draw_lot(lr: Rect2i) -> void:
	var r := _tiles(lr.position.x, lr.position.y, lr.size.x, lr.size.y)
	draw_rect(r, Color(0.78, 0.68, 0.48))
	var dash := Color(0.95, 0.9, 0.7, 0.8)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], dash, 2.0, 8.0)
	var sign := _tiles(lr.position.x + 2, lr.position.y + 2, 2, 1)  # a 2-tile sign in the middle
	draw_rect(Rect2(sign.get_center() + Vector2(-2, 0), Vector2(4, 16)), Color(0.45, 0.35, 0.25))
	draw_rect(sign.grow_individual(-2, 0, -2, -12), Color(0.25, 0.45, 0.3))
	draw_rect(sign.grow_individual(-2, 0, -2, -12), Color(0.9, 0.9, 0.85), false, 1.5)
	_label(sign.position + Vector2(TILE, 6), "COMMUNITY", 8, Color(1, 1, 1))
	_label(sign.position + Vector2(TILE, 15), "LOT", 8, Color(1, 1, 1))


# Farmyard, 5x4 tiles: a 2x2 farmhouse, a 2x2 barn, a windmill pump on its own tile.
func _draw_farmhouse(fr: Rect2i, i: int) -> void:
	var x := fr.position.x
	var y := fr.position.y
	draw_rect(_tiles(x, y, fr.size.x, fr.size.y), Color(0.66, 0.6, 0.4))
	_draw_home(_tiles(x, y + 1, 2, 2), 24.0, Color(0.92, 0.9, 0.84), Color(0.4, 0.42, 0.45))
	_draw_home(_tiles(x + 3, y + 1, 2, 2), 34.0, Color(0.65, 0.2, 0.15), Color(0.42, 0.4, 0.38))  # red barn
	var w := Vector2(x + 2.5, y + 4) * TILE - Vector2(0, 4)  # windmill pump on tile (x+2, y+3)
	draw_line(w, w - Vector2(0, 50), Color(0.4, 0.38, 0.36), 2.0)
	var ang := _time * 2.0 + i
	for k in 6:
		var d := Vector2(cos(ang + k * TAU / 6), sin(ang + k * TAU / 6)) * 10
		draw_line(w - Vector2(0, 50), w - Vector2(0, 50) + d, Color(0.75, 0.74, 0.7), 2.0)
	_label(Vector2(x + 2.5, y + 3.5) * TILE, "NOT YOURS (YET)", 9, Color(1, 0.95, 0.8))


func _draw_pipeline() -> void:
	var x := (PIPE_X + 0.5) * TILE
	var top := (CANAL_TOP + 6) * TILE
	var bottom := 0.0
	for y in range(CANAL_TOP + 7, 0, 2):  # a support every other tile
		draw_rect(Rect2(Vector2(PIPE_X, y) * TILE + Vector2(9, 22), Vector2(14, 6)), Color(0.45, 0.43, 0.4))
	draw_line(Vector2(x + 3, top + 6), Vector2(x + 3, bottom + 4), Color(0, 0, 0, 0.2), 10.0)
	draw_line(Vector2(x, top), Vector2(x, bottom), Color(0.55, 0.6, 0.62), 10.0)
	draw_line(Vector2(x - 2, top), Vector2(x - 2, bottom), Color(0.72, 0.77, 0.8), 3.0)
	# pump house where it leaves the canal: 3x1 tiles on the canal road
	_box(_tiles(PIPE_X - 1, CANAL_TOP + 6, 3, 1), 22.0, Color(0.62, 0.64, 0.66), Color(0.5, 0.52, 0.55))
	_label(Vector2(x, (CANAL_TOP + 6) * TILE - 12), "PUMP", 9, Color(1, 1, 1))
	# shut-off valve on the tile outside your fence
	draw_circle(Vector2(x, -TILE * 0.5), 9, Color(0.75, 0.2, 0.15))
	draw_line(Vector2(x - 9, -TILE * 0.5), Vector2(x + 9, -TILE * 0.5), Color(0.5, 0.1, 0.08), 3.0)


func _draw_car(p: Vector2, col: Color, vertical: bool) -> void:
	var size := Vector2(14, 24) if vertical else Vector2(24, 14)
	draw_rect(Rect2(p + Vector2(2, 3), size), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(p, size), col)
	var glass := Rect2(p + Vector2(2, 5), Vector2(10, 6)) if vertical else Rect2(p + Vector2(5, 2), Vector2(6, 10))
	draw_rect(glass, Color(0.6, 0.75, 0.85))


func _draw_traffic(y0: int, y1: int) -> void:
	var span := float(WORLD.size.y * TILE)
	for k in 10:
		var south := k % 2 == 0
		var lane: int = (1 if k % 4 < 2 else 2) if south else (4 if k % 4 < 2 else 5)
		var spd := 90.0 + (k * 37) % 60
		var d := fmod(k * 397.0 + _time * spd, span)
		var y := WORLD.position.y * TILE + (d if south else span - d)
		if y < (y0 - 2) * TILE or y > (y1 + 1) * TILE:
			continue
		var cols := [Color(0.85, 0.85, 0.88), Color(0.2, 0.3, 0.6), Color(0.7, 0.15, 0.15), Color(0.15, 0.15, 0.15), Color(0.9, 0.75, 0.2)]
		_draw_car(Vector2((HWY_LEFT + lane) * TILE + 9, y), cols[k % cols.size()], true)


func _draw_fence() -> void:
	var r := Rect2(Vector2(PROP.position) * TILE, Vector2(PROP.size) * TILE).grow(3)
	var col := Color(0.45, 0.42, 0.4)
	draw_rect(r, col, false, 2.0)
	var x := r.position.x
	while x <= r.end.x:
		draw_rect(Rect2(x - 2, r.position.y - 5, 4, 7), col)
		draw_rect(Rect2(x - 2, r.end.y - 5, 4, 7), col)
		x += TILE * 2
	var y := r.position.y
	while y <= r.end.y:
		draw_rect(Rect2(r.position.x - 2, y - 5, 4, 7), col)
		draw_rect(Rect2(r.end.x - 2, y - 5, 4, 7), col)
		y += TILE * 2


func _draw_signs(vis: Rect2i) -> void:
	if vis.has_point(Vector2i(-24, 12)):  # billboard for the competition
		var p := Vector2(-25, 12) * TILE
		draw_rect(Rect2(p + Vector2(TILE * 0.8, -10), Vector2(4, 40)), Color(0.4, 0.35, 0.3))
		draw_rect(Rect2(p + Vector2(TILE * 2.6, -10), Vector2(4, 40)), Color(0.4, 0.35, 0.3))
		draw_rect(Rect2(p + Vector2(0, -60), Vector2(TILE * 4, 50)), Color(0.95, 0.95, 0.92))
		draw_rect(Rect2(p + Vector2(0, -60), Vector2(TILE * 4, 50)), Color(0.2, 0.2, 0.2), false, 2.0)
		_label(p + Vector2(TILE * 2, -42), "CHAT ABC", 14, Color(0.1, 0.5, 0.4))
		_label(p + Vector2(TILE * 2, -24), "It's probably fine.", 10, Color(0.2, 0.2, 0.2))
		_label(p + Vector2(TILE * 2, -13), "- ClosedAI", 9, Color(0.4, 0.4, 0.4))
	if vis.has_point(Vector2i(-12, MAIN_ST_Y + 4)):  # town sign
		var p := Vector2(-12, MAIN_ST_Y + 4) * TILE
		draw_rect(Rect2(p + Vector2(10, -10), Vector2(4, 30)), Color(0.4, 0.35, 0.3))
		draw_rect(Rect2(p + Vector2(50, -10), Vector2(4, 30)), Color(0.4, 0.35, 0.3))
		draw_rect(Rect2(p + Vector2(0, -40), Vector2(64, 32)), Color(0.2, 0.45, 0.3))
		_label(p + Vector2(32, -26), TOWN.to_upper(), 10, Color(1, 1, 1))
		_label(p + Vector2(32, -14), "Pop. 212", 9, Color(0.9, 0.95, 0.9))


func _label(center: Vector2, text: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, center - Vector2(w / 2, -size / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.6))
	draw_string(font, center - Vector2(w / 2, -size / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
