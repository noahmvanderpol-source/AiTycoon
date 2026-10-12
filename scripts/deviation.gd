extends "res://scripts/economy.gd"
## Deviation. Part of the Main script chain (see scripts/README.md).

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
	var rate := _rack_max_compute() * DEVIATION_PER_RACK * maxf(mult, 0.0)
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
			if RACKS.has(objects[t]) and not rack_names.has(t):
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
