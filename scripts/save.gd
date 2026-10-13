extends "res://scripts/tutorial.gd"
## Saving and loading. Part of the Main script chain (see scripts/README.md).
## Saves are JSON in user://saves/. Every script variable is saved automatically (new ones too),
## except UI nodes and the per-frame stuff in SAVE_SKIP; each value is stored with var_to_str
## so Vector2i keys, packed arrays and ints come back exactly.

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves/"
const SAVE_SLOT := "save"  # the Save button
const AUTOSAVE_SLOT := "autosave"
const AUTOSAVE_DAYS := 7  # an in-game week, about a minute at 1x
const LOAD_META := "aitycoon_load_slot"  # survives the scene reload a load does
const ORDER_TAG := "__dict__"  # var_to_str sorts dictionary keys; order decides who gets power first
# Mouse, camera and per-frame state, and things rebuilt from the map after loading.
const SAVE_SKIP := ["hover", "hover_sub", "dragging", "drag_start", "paint_tiles", "panning",
	"_tip_timer", "_tip", "_time", "modal", "_speed_before_modal", "view_level", "tool_index",
	"build_cat", "buildings", "room_of", "reach", "tool_active", "held", "zoom_level", "tilt_on", "research_scrolled"]

var save_button: Button


# Called from _ready instead of asking for a company name straight away.
func _start_game() -> void:
	_add_save_button()
	if Engine.has_meta(LOAD_META):
		var slot: String = Engine.get_meta(LOAD_META)
		Engine.remove_meta(LOAD_META)
		if _apply_save(slot):
			return
	var latest := _latest_slot()
	if latest == "":
		_ask_company_name()
		return
	var info := _slot_info(latest)
	var new_btn := Button.new()
	new_btn.text = "New company"
	new_btn.pressed.connect(func():
		_close_modal()
		_ask_company_name())
	_show_modal("Welcome back",
		"Chet: Bro, you're back! %s is right where you left it.\n\n%s" % [info.get("company", "The company"), _slot_text(latest)],
		"Continue", func(): _load_slot(latest), new_btn)


func _add_save_button() -> void:
	var row := company_button.get_parent()
	save_button = Button.new()
	save_button.text = "Game"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.tooltip_text = "Save, load or start over (Ctrl+S saves)"
	save_button.pressed.connect(_open_game_menu)
	row.add_child(save_button)
	row.move_child(save_button, company_button.get_index() + 1)


func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S and event.ctrl_pressed:
		if not modal and not game_over:
			_save_slot(SAVE_SLOT)
			_chet("Saved. Like a VC who backed us at the seed round.")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not game_over and top_label:
		_save_slot(AUTOSAVE_SLOT)


func _new_day() -> void:
	super()
	if day % AUTOSAVE_DAYS == 0 and not game_over:
		_save_slot(AUTOSAVE_SLOT)


func _open_game_menu() -> void:
	if modal:
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var save := Button.new()
	save.text = "Save game"
	save.disabled = game_over
	save.pressed.connect(func():
		_close_modal()
		_save_slot(SAVE_SLOT)
		_chet("Saved. Like a VC who backed us at the seed round."))
	box.add_child(save)
	for slot in [SAVE_SLOT, AUTOSAVE_SLOT]:
		var b := Button.new()
		b.text = ("Load save: " if slot == SAVE_SLOT else "Load autosave: ") + _slot_text(slot)
		b.disabled = not FileAccess.file_exists(_slot_path(slot))
		b.pressed.connect(func():
			_close_modal()
			_load_slot(slot))
		box.add_child(b)
	var restart := Button.new()
	restart.text = "New company (unsaved progress is lost)"
	restart.pressed.connect(func():
		_close_modal()
		_save_slot(AUTOSAVE_SLOT)  # just in case
		get_tree().reload_current_scene())
	box.add_child(restart)
	_show_modal("Game", "Autosaves every week and when you quit.", "Back", func(): pass, box)


# Same as pressing the modal's own button, without running its on_close.
func _close_modal() -> void:
	if modal:
		modal.queue_free()
	modal = null
	_set_speed(_speed_before_modal)


# --- Files ------------------------------------------------------------------

func _slot_path(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


func _slot_info(slot: String) -> Dictionary:
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if not f:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


func _slot_text(slot: String) -> String:
	var info := _slot_info(slot)
	if info.is_empty():
		return "empty"
	return "%s, %s, %s" % [info.get("company", "?"), info.get("date", "?"), info.get("saved_at", "")]


# The most recently written slot, or "" if there are no saves.
func _latest_slot() -> String:
	var best := ""
	var best_time := -1
	for slot in [SAVE_SLOT, AUTOSAVE_SLOT]:
		if FileAccess.file_exists(_slot_path(slot)):
			var t := FileAccess.get_modified_time(_slot_path(slot))
			if t > best_time:
				best_time = t
				best = slot
	return best


func _save_slot(slot: String) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {
		"version": SAVE_VERSION,
		"company": company,
		"date": _save_date(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"main": _pack(self, SAVE_SKIP),
		"rng": var_to_str(rng.state),
	}
	if gov:
		data["gov"] = _pack(gov, [])
		data["gov_rng"] = var_to_str(gov._rng.state)
	if world:
		data["world"] = _pack(world, [])
	var tmp := _slot_path(slot) + ".tmp"  # write then rename, so a crash can't eat the old save
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if not f:
		_chet("Couldn't save, bro. The disk said no.")
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, _slot_path(slot))
	return true


func _save_date() -> String:
	return "%s, Day %d" % [_quarter_name((day - 1) / DAYS_PER_QUARTER), day]


# Loading rebuilds the whole scene, then _start_game applies the save.
func _load_slot(slot: String) -> void:
	if not FileAccess.file_exists(_slot_path(slot)):
		return
	Engine.set_meta(LOAD_META, slot)
	var music := get_node_or_null("/root/Music")
	if music and music.has_method("set_tension"):
		music.set_tension(false)  # the save sets it again if things were tense
	get_tree().reload_current_scene()


func _apply_save(slot: String) -> bool:
	var data := _slot_info(slot)
	if data.is_empty() or int(data.get("version", 0)) > SAVE_VERSION:
		_chet("That save is busted, bro. Starting fresh.")
		return false
	_unpack(self, data.get("main", {}), SAVE_SKIP)
	rng.state = _decode(data.get("rng", "0"), rng.state)
	if gov and data.has("gov"):
		_unpack(gov, data.gov, [])
		gov._rng.state = _decode(data.get("gov_rng", "0"), gov._rng.state)
	if world and data.has("world"):
		_unpack(world, data.world, [])
	for s in staff:
		_clear_staff_transient(s)
	_refresh_walkable()  # not _after_build: that would stand everyone up from their desks
	_find_buildings()
	_refresh_access()
	_rebuild_staff_list()
	_label_tools()
	_refresh_menu_buttons()
	_update_research_tab()
	if gov:
		gov.refresh()
	if tutorial_step >= 0 and tutorial_step < TUTORIAL.size():  # mid-tour: put Chet's panel back
		_build_tutorial_panel()
		_set_tutorial_step(tutorial_step)
	_set_speed(speed)
	var music := get_node_or_null("/root/Music")
	if music and music.has_method("set_tension"):
		music.set_tension(tension)
	_chet("Welcome back to %s, bro. Everything's where you left it. Even the smell." % company)
	return true


# --- Packing ----------------------------------------------------------------

# Every saveable script variable on obj as {name: var_to_str(value)}.
func _pack(obj: Object, skip: Array) -> Dictionary:
	var out := {}
	for p in obj.get_property_list():
		if not p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or skip.has(p.name) or p.type == TYPE_OBJECT:
			continue
		var v = obj.get(p.name)
		if p.name == "staff":
			v = _staff_for_save()
		elif _has_object(v):  # UI: buttons, labels, cards
			continue
		out[p.name] = var_to_str(_keep_order(v))
	return out


func _unpack(obj: Object, vars: Dictionary, skip: Array) -> void:
	var names := {}
	for p in obj.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.type != TYPE_OBJECT:
			names[p.name] = true
	for k in vars:
		if names.has(k) and not skip.has(k):  # vars that no longer exist are ignored
			var current = obj.get(k)
			var v = _decode(vars[k], current)
			if current == null or typeof(v) == typeof(current) or (typeof(current) in [TYPE_INT, TYPE_FLOAT] and typeof(v) in [TYPE_INT, TYPE_FLOAT]):
				obj.set(k, v)


# str_to_var, refusing anything that would build an object.
func _decode(text, fallback):
	if not text is String or text.contains("Object(") or text.contains("Resource("):
		return fallback
	return _restore_order(str_to_var(text))


# Dictionaries become [ORDER_TAG, keys, values] so they come back in the same order.
func _keep_order(v):
	if v is Dictionary:
		return [ORDER_TAG, v.keys(), v.values().map(_keep_order)]
	if v is Array and not v.is_typed():
		return v.map(_keep_order)
	return v


func _restore_order(v):
	if v is Array and not v.is_typed():
		if v.size() == 3 and v[0] is String and v[0] == ORDER_TAG and v[1] is Array and v[2] is Array:
			var d := {}
			for i in v[1].size():
				d[v[1][i]] = _restore_order(v[2][i])
			return d
		return v.map(_restore_order)
	return v


func _has_object(v) -> bool:
	if v is Object:
		return true
	if v is Dictionary:
		for k in v:
			if _has_object(k) or _has_object(v[k]):
				return true
	elif v is Array:
		for x in v:
			if _has_object(x):
				return true
	return false


func _staff_for_save() -> Array:
	var out := []
	for s in staff:
		var c: Dictionary = s.duplicate()
		_clear_staff_transient(c)
		out.append(c)
	return out


# Node refs and walking paths, rebuilt after loading.
func _clear_staff_transient(s: Dictionary) -> void:
	s["label"] = null
	s["path"] = PackedVector2Array()
