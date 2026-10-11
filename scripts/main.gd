extends Node2D
## First prototype: a tile grid where you place rooms, with money ticking each day.

const TILE := 32
const GRID_W := 40
const GRID_H := 30
const DAY_SECONDS := 2.0
const PAN_SPEED := 600.0
const SERVER_INCOME := 90  # placeholder: each server tile "sells compute" daily

const ROOMS := {
	1: {"name": "Office", "color": Color(0.45, 0.6, 0.85), "cost": 500, "upkeep": 10},
	2: {"name": "Server Hall", "color": Color(0.3, 0.3, 0.35), "cost": 2000, "upkeep": 60},
	3: {"name": "Lab", "color": Color(0.55, 0.8, 0.55), "cost": 1000, "upkeep": 25},
	4: {"name": "Cooling", "color": Color(0.5, 0.85, 0.95), "cost": 800, "upkeep": 15},
}

var tiles := {}  # Vector2i -> room id
var selected := 1
var money := 20000
var day := 1
var hover := Vector2i(-1, -1)
var _day_timer := 0.0

var camera: Camera2D
var hud: Label


func _ready() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(GRID_W, GRID_H) * TILE / 2.0
	add_child(camera)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12, 10)
	layer.add_child(hud)
	_update_hud()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	camera.position += dir * PAN_SPEED * delta / camera.zoom.x

	_day_timer += delta
	if _day_timer >= DAY_SECONDS:
		_day_timer -= DAY_SECONDS
		_next_day()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.keycode - KEY_0
		if ROOMS.has(n):
			selected = n
			_update_hud()
	elif event is InputEventMouseMotion:
		hover = _mouse_tile()
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_place(hover)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_remove(hover)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_place(_mouse_tile())
			MOUSE_BUTTON_RIGHT:
				_remove(_mouse_tile())
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.1)


func _zoom(factor: float) -> void:
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.3, 0.3), Vector2(3, 3))


func _mouse_tile() -> Vector2i:
	return Vector2i((get_global_mouse_position() / TILE).floor())


func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < GRID_W and t.y < GRID_H


func _place(t: Vector2i) -> void:
	if not _in_bounds(t) or tiles.get(t) == selected:
		return
	var cost: int = ROOMS[selected].cost
	if money < cost:
		return
	if tiles.has(t):
		_remove(t)
	money -= cost
	tiles[t] = selected
	_update_hud()
	queue_redraw()


func _remove(t: Vector2i) -> void:
	if not tiles.has(t):
		return
	money += ROOMS[tiles[t]].cost / 2
	tiles.erase(t)
	_update_hud()
	queue_redraw()


func _next_day() -> void:
	day += 1
	var upkeep := 0
	var servers := 0
	for t in tiles:
		upkeep += ROOMS[tiles[t]].upkeep
		if tiles[t] == 2:
			servers += 1
	money += servers * SERVER_INCOME - upkeep
	_update_hud()


func _update_hud() -> void:
	var room: Dictionary = ROOMS[selected]
	hud.text = "Day %d    Money $%d    Building: %s ($%d)\n1-4 pick room | LMB build | RMB demolish | WASD pan | wheel zoom" % [
		day, money, room.name, room.cost]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GRID_W, GRID_H) * TILE), Color(0.82, 0.74, 0.55))  # desert sand
	for t in tiles:
		draw_rect(Rect2(Vector2(t) * TILE, Vector2(TILE, TILE)), ROOMS[tiles[t]].color)
	var line := Color(0, 0, 0, 0.15)
	for x in GRID_W + 1:
		draw_line(Vector2(x * TILE, 0), Vector2(x * TILE, GRID_H * TILE), line)
	for y in GRID_H + 1:
		draw_line(Vector2(0, y * TILE), Vector2(GRID_W * TILE, y * TILE), line)
	if _in_bounds(hover):
		draw_rect(Rect2(Vector2(hover) * TILE, Vector2(TILE, TILE)), Color(1, 1, 1, 0.8), false, 2.0)
