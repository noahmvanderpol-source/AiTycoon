extends "res://scripts/deviation.gd"
## Staff. Part of the Main script chain (see scripts/README.md).

func _walkable(t: Vector2i) -> bool:
	var door: bool = wall_tiles.get(t) == "door"
	if _subs_in(t).any(func(c): return sub_objects[c] == "iwall"):
		return false
	return (floor_tiles.has(t) or door) and (door or not wall_tiles.has(t)) and not objects.has(t)


func _refresh_walkable() -> void:
	for x in GRID_W:
		for y in GRID_H:
			astar.set_point_solid(Vector2i(x, y), not _walkable(Vector2i(x, y)))


func _after_build() -> void:
	_refresh_walkable()
	_find_buildings()
	_refresh_access()
	for s in staff:
		s.path = PackedVector2Array()
		s.working = false
		# Lose the workstation if it was demolished or its spot got blocked.
		if s.seat != NO_SEAT and (_station_kind(objects.get(s.seat, "")) != JOBS[s.job].at or not _walkable(s.spot)):
			s.seat = NO_SEAT


# Flood out from every door and outdoor floor to find where staff can actually walk to.
func _refresh_access() -> void:
	reach = {}
	var todo: Array[Vector2i] = []
	for t in floor_tiles.keys() + wall_tiles.keys():
		if _walkable(t) and (wall_tiles.get(t) == "door" or not room_of.has(t)):
			reach[t] = true
			todo.append(t)
	while not todo.is_empty():
		var t: Vector2i = todo.pop_back()
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = t + d
			if not reach.has(n) and _walkable(n):
				reach[n] = true
				todo.append(n)


func _needs_access(id: String) -> bool:
	return _tool_by_id(id).get("access", false)


# Staff can walk up to at least one side of it.
func _reachable(t: Vector2i) -> bool:
	return [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT].any(func(d): return reach.has(t + d))


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


# Every desk tier is a "desk" as far as jobs go.
func _station_kind(id: String) -> String:
	return "desk" if DESKS.has(id) else id


# Where someone stands to use a desk or rack: a free walkable neighbor, front side first.
func _station_spot(t: Vector2i, kind: String) -> Vector2i:
	var sides := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN] if kind == "desk" \
		else [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
	var foot := _footprint(objects.get(t, ""), t)  # big desks: any side of any tile
	for d in sides:
		for f in foot:
			var spot: Vector2i = f + d
			if foot.has(spot):
				continue
			if reach.has(spot) and not staff.any(func(o): return o.spot == spot and o.seat != NO_SEAT):
				return spot
	return NO_SEAT


# A free standing spot within an Engineer's Workstation's radius, next to a rack if possible.
func _eng_spot(st: Vector2i) -> Vector2i:
	var best := NO_SEAT
	var best_score := INF
	var r := int(ENG_RADIUS)
	for x in range(st.x - r, st.x + r + 1):
		for y in range(st.y - r, st.y + r + 1):
			var t := Vector2i(x, y)
			if not _in_eng_radius(st, t) or not reach.has(t) \
					or staff.any(func(o): return o.spot == t and o.seat != NO_SEAT):
				continue
			var by_rack := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT].any(
				func(d): return RACKS.has(objects.get(t + d, "")) and _in_eng_radius(st, t + d))
			var score := Vector2(t - st).length() - (10.0 if by_rack else 0.0)
			if score < best_score:
				best_score = score
				best = t
	return best


func _find_station(s: Dictionary, here: Vector2i) -> void:
	var kind: String = JOBS[s.job].at
	var slots := ENG_SLOTS if kind == "eng_station" else 1
	var best_len := 1 << 30
	for t in objects:
		if _station_kind(objects[t]) != kind or not _reachable(t) or staff.filter(func(o): return o.seat == t).size() >= slots:
			continue
		var spot := _eng_spot(t) if kind == "eng_station" else _station_spot(t, kind)
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
