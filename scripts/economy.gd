extends "res://scripts/build.gd"
## Models, users, rivals and the board. Part of the Main script chain (see scripts/README.md).

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
	gov.tick_day()
	_tick_wear()
	_tick_gen_repair()
	if game_over:
		return
	if money < 0:
		_end_game("Fired",
			"You ran out of money. The board fired you by group text, then asked if you could still Venmo them for lunch.")
	elif (day - 1) % DAYS_PER_QUARTER == 0:
		_end_quarter()

func _grid_kw() -> float:
	return GRID_KW + gov.grid_bonus()


# Racks that are switched on. A rack switched off makes no compute, heat, power draw, Deviation or wear.
func _rack_on(t: Vector2i) -> bool:
	return RACKS.has(objects.get(t, "")) and not racks_off.has(t) and not racks_hot.has(t)


func _toggle_rack(t: Vector2i) -> void:
	if racks_off.has(t):
		racks_off.erase(t)
	elif RACKS.has(objects.get(t, "")):
		racks_off[t] = true


func _racks() -> int:
	var n := 0
	for t in objects:
		if _rack_on(t):
			n += 1
	return n


# What all racks would give if none were throttled, in Basic racks.
func _rack_max_compute() -> float:
	var c := 0.0
	for t in objects:
		if _rack_on(t):
			c += RACKS[objects[t]].compute
	return c


# Sum of a per-tier field (heat, power) over all racks, in Basic racks.
func _rack_sum(field: String) -> float:
	var v := 0.0
	for t in objects:
		if _rack_on(t):
			v += RACKS[objects[t]][field]
	return v


# Engineers at a workstation add compute for racks in its radius. Hot racks throttle.
func _compute_per_day() -> float:
	return _rack_compute() + _engineer_compute()


func _in_eng_radius(station: Vector2i, t: Vector2i) -> bool:
	return Vector2(t - station).length() <= ENG_RADIUS


# Each engineer tends one rack in their workstation's radius; extra engineers add nothing.
func _engineer_compute() -> float:
	var total := 0.0
	for st in objects:
		if objects[st] != "eng_station":
			continue
		var crew := 0.0
		for s in staff:
			if s.working and s.job == "engineering" and s.seat == st:
				crew += (1.0 if s.role == "engineer" else 0.5) * s.productivity
		crew *= 1.0 + _research_bonus("productivity")
		var racks := objects.keys().filter(func(r): return _rack_on(r) and _in_eng_radius(st, r)).size()
		total += ENG_RACK_BONUS * minf(crew, racks)
	return minf(total, ENG_RACK_BONUS * _racks())


func _rack_compute() -> float:
	var c := 0.0
	for t in objects:
		if RACKS.has(objects[t]):
			c += _rack_output(t) * RACKS[objects[t]].compute
	return c


func _rack_output(t: Vector2i) -> float:
	if not _reachable(t) or racks_off.has(t) or racks_hot.has(t):
		return 0.0  # switched off, or nobody can get to it to keep it running
	return clampf(1.0 - (_temp(t) - RACK_SAFE_TEMP) * RACK_THROTTLE, RACK_MIN_OUTPUT, 1.0) * (0.0 if not _powered(t) else 1.0) \
		* (1.0 + _research_bonus("compute")) * _rack_cond(t) / 100.0


func _rack_cond(t: Vector2i) -> float:
	return rack_cond.get(t, 100.0)


# Racks the engineers get to today: each engineer covers ENG_MAINT_RACKS racks in their
# workstation's radius, nearest first.
func _maintained_racks() -> Dictionary:
	var done := {}
	for st in objects:
		if objects[st] != "eng_station":
			continue
		var crew := 0.0
		for s in staff:
			if s.working and s.job == "engineering" and s.seat == st:
				crew += (1.0 if s.role == "engineer" else 0.5) * s.productivity
		var slots := int(ceilf(crew * ENG_MAINT_RACKS))
		var near: Array = objects.keys().filter(func(r): return _rack_on(r) and _in_eng_radius(st, r) and not done.has(r))
		near.sort_custom(func(a, b): return Vector2(a - st).length() < Vector2(b - st).length())
		for r in near.slice(0, slots):
			done[r] = true
	return done


func _tick_wear() -> void:
	var fixed := _maintained_racks()
	var worn := 0
	for t in objects:
		if not _rack_on(t):
			continue
		var c := _rack_cond(t)
		c = minf(c + RACK_REPAIR, 100.0) if fixed.has(t) else maxf(c - RACK_WEAR, RACK_MIN_COND)
		rack_cond[t] = c
		if c < 60.0:
			worn += 1
	for t in rack_cond.keys():  # forget racks that were demolished
		if not RACKS.has(objects.get(t, "")):
			rack_cond.erase(t)
	for t in racks_off.keys():
		if not RACKS.has(objects.get(t, "")):
			racks_off.erase(t)
	if worn > 0 and day % 15 == 0:
		_chet("%d rack%s held together with zip ties. Put engineers at a Workstation near them, bro." % [worn, "" if worn == 1 else "s"])


func _gen_cond(t: Vector2i) -> float:
	return gen_cond.get(t, 100.0)


# Generators the mechanics get to today: each working Maintenance mechanic covers up to MECH_GENS
# generators within MECH_RADIUS tiles of where they stand, nearest first.
func _maintained_gens() -> Dictionary:
	var done := {}
	for s in staff:
		if not s.working or s.job != "maintenance":
			continue
		var near: Array = objects.keys().filter(func(g): return GENERATORS.has(objects[g]) and not done.has(g) and Vector2(g - s.spot).length() <= MECH_RADIUS)
		near.sort_custom(func(a, b): return Vector2(a - s.spot).length() < Vector2(b - s.spot).length())
		for g in near.slice(0, ceili(MECH_GENS * s.productivity)):
			done[g] = true
	return done


# Called every power step for a generator that ran at `load` (0-1) of its full rating.
func _wear_gen(t: Vector2i, load: float) -> void:
	if load > 0.0:
		gen_cond[t] = maxf(_gen_cond(t) - GEN_WEAR / HEAT_STEPS_PER_DAY * (0.5 + 0.5 * load), GEN_MIN_COND)


func _tick_gen_repair() -> void:
	var fixed := _maintained_gens()
	var worn := 0
	for t in objects:
		if not GENERATORS.has(objects[t]):
			continue
		if fixed.has(t):
			gen_cond[t] = minf(_gen_cond(t) + GEN_REPAIR, 100.0)
		if _gen_cond(t) < 60.0:
			worn += 1
	for t in gen_cond.keys():  # forget generators that were demolished
		if not GENERATORS.has(objects.get(t, "")):
			gen_cond.erase(t)
	if worn > 0 and day % 15 == 0:
		_chet("%d generator%s running on prayers and duct tape. Hire a Mechanic and put them on Maintenance, bro." % [worn, "" if worn == 1 else "s"])


# The Expenses hover in the top bar: where the money goes each day.
func _expenses_text() -> String:
	var lines := ["Expenses per day: %s" % _money(_daily_burn()), ""]
	var by_role := {}
	var saved := 0
	for s in staff:
		var r: Array = by_role.get(s.role, [0, 0])
		r[0] += 1
		r[1] += _pay(s)
		by_role[s.role] = r
		saved += s.salary - _pay(s)
	lines.append("Payroll: %s" % _money(_payroll()))
	if staff.is_empty():
		lines.append("  nobody on the payroll")
	for role in ROLES:
		if by_role.has(role):
			lines.append("  %d x %s: %s" % [by_role[role][0], ROLES[role].name, _money(by_role[role][1])])
	if saved > 0:
		lines.append("  Slacking off pays %d%%, saving %s" % [int(SLACK_PAY * 100.0), _money(saved)])
	lines.append("Power and fuel: %s (yesterday's bill)" % _money(power_bill))
	return "\n".join(lines)


# The Revenue hover in the top bar: where the money comes from each day.
func _revenue_text() -> String:
	if models.is_empty():
		return "Revenue per day: $0\n\nPre-revenue. Train and release a model, then users show up and pay."
	var bonus := _research_bonus("revenue")
	var lines := ["Revenue per day: %s" % _money(revenue_today), "",
		"%s users x $%.3f each = %s" % [_num(int(users)), REVENUE_PER_USER, _money(int(users * REVENUE_PER_USER))]]
	if absf(bonus) > 0.001:
		lines.append("Research: %+d%% revenue" % int(bonus * 100.0))
	if gov != null and gov.contract_days > 0:
		lines.append("")
		lines.append("Not counted above:")
		lines.append("  State AI Contract: +%s a day" % _money(gov.CONTRACT_PER_DAY))
	return "\n".join(lines)


# Compute is spent in this order: red-team rigs, users, then whatever the AI hides at 75%, then training.
func _redteam_compute() -> float:
	var rigs := objects.keys().filter(func(r): return objects[r] == "redteam" and _powered(r)).size()
	return minf(rigs * REDTEAM_COMPUTE, _compute_per_day())


# Users eat compute every day. They take up to USER_COMPUTE_CAP of what's left after the rigs.
func _user_compute_demand() -> float:
	return users / USERS_PER_COMPUTE


func _user_compute() -> float:
	var free := maxf(_compute_per_day() - _redteam_compute(), 0.0)
	return minf(_user_compute_demand(), free * USER_COMPUTE_CAP)


func _training_compute() -> float:
	var c := _compute_per_day() - _redteam_compute() - _user_compute()
	if deviation >= 75.0:
		c -= _compute_per_day() * HIDDEN_COMPUTE
	return maxf(c, 0.0)


# Researchers make every unit of compute count for more.
func _research_mult() -> float:
	return 1.0 + 0.25 * _workforce("research")


func _training_speed() -> float:
	return _training_compute() * _research_mult()


# Compute a model of this capability needs to train or serve. It's a threshold, not a cost.
func _compute_needed(cap: int) -> float:
	return cap / CAP_PER_COMPUTE


func _can_train(cap: int) -> bool:
	return _racks() > 0 and _compute_per_day() >= _compute_needed(cap)


# Share of users the best model can serve: all of them with enough compute, fewer without.
func _serve_ratio() -> float:
	var need := _compute_needed(_best_cap())
	var r := 1.0 if need <= 0.0 else clampf(_compute_per_day() / need, 0.0, 1.0)
	var demand := _user_compute_demand()  # users who don't get their share of compute drift away
	if demand > 0.0:
		r *= clampf(_user_compute() / demand, 0.0, 1.0)
	return r


func _best_cap() -> int:
	return 0 if models.is_empty() else models.back().cap


# Each step up the capability ladder costs more money and a lot more compute.
func _train_cost(i: int) -> int:
	return int(MODEL_SIZES[i].cost * pow(1.0 + TRAIN_COST_RISE, _best_cap()))


func _train_work(i: int) -> float:
	return MODEL_SIZES[i].work * pow(1.0 + TRAIN_WORK_RISE, _best_cap())


func _train_cost_text(i: int) -> String:
	var cap := _best_cap()
	return "Your best model is capability %d, so training costs money x%.2f and compute work x%.2f (+%d%% and +%d%% per capability point)." % [
		cap, pow(1.0 + TRAIN_COST_RISE, cap), pow(1.0 + TRAIN_WORK_RISE, cap), roundi(TRAIN_COST_RISE * 100.0), roundi(TRAIN_WORK_RISE * 100.0)]


# How much a training run raises the Deviation rate while it runs.
func _train_mod(i: int, rushed: bool) -> float:
	return TRAIN_MOD[i] * (RUSH_MOD if rushed else 1.0)


func _start_training(i: int) -> void:
	var cost := _train_cost(i)
	if not training.is_empty() or not _can_train(_best_cap() + int(MODEL_SIZES[i].gain)) or cost > money:
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
	if not _can_train(training.cap):  # paused until there's enough compute again
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


# Most users you can have: USER_CAP_PER_COMPUTE for each compute you actually have right now
# (powered, switched on, after heat and wear, plus engineers).
func _user_capacity() -> float:
	return _compute_per_day() * USER_CAP_PER_COMPUTE


func _user_target() -> float:
	var cap := _best_cap()
	if cap == 0:
		return 0.0
	# More capable models attract more users, losing to the best rival costs share,
	# and marketers find more people to sell to.
	# Above capacity the target drops to it, and the extra users drift away a little each day.
	return minf(2500.0 * pow(cap, 1.5) * clampf(float(cap) / _rival_cap(), 0.3, 1.5) * (1.0 + 0.2 * _workforce("growth")) * _serve_ratio(), _user_capacity())


func _tick_users() -> void:
	var target := _user_target()
	users += (target - users) * (0.03 if target > users else 0.02)
	revenue_today = int(users * REVENUE_PER_USER * (1.0 + _research_bonus("revenue")))
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
	_show_modal(title, body, "Start over", func():
		var music := get_node_or_null("/root/Music")
		if music and music.has_method("set_tension"):
			music.set_tension(false)  # the music autoload outlives the restart
		get_tree().reload_current_scene())


# --- Staff ------------------------------------------------------------------
