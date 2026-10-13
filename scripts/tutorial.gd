extends "res://scripts/ui.gd"
## Chet's tutorial: a short onboarding checklist. Each step waits until the player has done it.
## Offered after the company is named, skippable at any point. Part of the Main script chain (see scripts/README.md).

# "do" is what finishes the step: a menu id means that menu is open, the rest are checked in _tutorial_done().
const TUTORIAL := [
	{"do": "models", "text": "Okay, onboarding. I made a deck. Step one: open Models (M) down at the bottom. That's where the AI gets made."},
	{"do": "train", "text": "Pick a model size and train it on our racks. Start small. Ship fast, apologize later. That's in our values doc."},
	{"do": "staff", "text": "It's just you, me and two founders' worth of vibes. Open Staff (T). We need headcount."},
	{"do": "hire", "text": "Hire somebody. Researchers train models, marketers get users, engineers keep the racks alive. Give them a job in the same list."},
	{"do": "build", "text": "New hires need a desk or they just stand around like it's a networking event. Open Build (B)."},
	{"do": "desk", "text": "Furniture tab, then drag out a Basic Desk on the floor. Leave a path from the door so people can actually sit down. Fire code, bro."},
	{"do": "heat", "text": "Racks run hot and Calizona runs hotter. Open Heat (H) to see where it's cooking. Red is bad. I think."},
	{"do": "research", "text": "Open Research (E) and pick a project. It's like a skill tree, but with patents."},
	{"do": "board", "text": "Last slide. Click our company name up top (or press O). The board sets one target a quarter. Hit it. Please. I have a mortgage now."},
	{"do": "", "text": "That's the whole deck. Everything else is in the Guide (G). Keep Deviation (V) low, keep the board happy, and build an AI good enough to replace us. That's the exit, bro."},
]

# Chet's welcome on a new game, one click per line, before the company gets its name: [line, button].
const CHET_WELCOME := [
	["Yo, dude! I'm so psyched that you could come on board.", "Thanks, Chet"],
	["And just as a heads up... if you hear any rumors as to why I brought you in, mentioning how you're just a fall guy in case things go wrong...", "...What?"],
	["It's totally not, bro.", "Okay..."],
]


# Runs instead of company_ui's version: the welcome lines first, then the name pop-up.
func _ask_company_name() -> void:
	_chet_welcome(0)


func _chet_welcome(i: int) -> void:
	if i >= CHET_WELCOME.size():
		super._ask_company_name()
		return
	_show_modal("Chet", CHET_WELCOME[i][0], CHET_WELCOME[i][1], _chet_welcome.bind(i + 1))


# Called once from _ready. The offer waits until the company-name pop-up is closed.
func _start_tutorial() -> void:
	var t := Timer.new()
	t.wait_time = 0.25
	t.timeout.connect(_tick_tutorial)
	add_child(t)
	t.start()


func _tick_tutorial() -> void:
	if tutorial_step < 0:
		if modal == null and not game_over:
			_offer_tutorial()
		return
	if tutorial_step >= TUTORIAL.size() or tutorial_panel == null:
		return
	_tip_timer = 0.0  # no rotating tips while Chet is mid-pitch
	if TUTORIAL[tutorial_step].do != "" and _tutorial_done(TUTORIAL[tutorial_step].do):
		_set_tutorial_step(tutorial_step + 1)


func _offer_tutorial() -> void:
	tutorial_step = 0
	var skip := Button.new()
	skip.text = "I've done a startup before, skip it"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func():
		tutorial_step = TUTORIAL.size()
		modal_button.pressed.emit()
		_chet("Respect. You know where the Guide (G) is if you get lost. Not that you will. Probably."))
	_show_modal("Onboarding",
		"Chet: Before we disrupt anything, want the quick tour? Nine slides. I'll tell you what to click and wait while you do it.",
		"Show me around", func():
			if tutorial_step == 0:
				_build_tutorial_panel()
				_set_tutorial_step(0),
		skip)


func _tutorial_done(what: String) -> bool:
	match what:
		"train":
			return not training.is_empty() or models.size() > 0
		"hire":
			return staff.size() > tutorial_base
		"desk":
			return _tutorial_desks() > tutorial_base
		"research":
			return research_page.visible and research_active != ""
		"board":
			return company_page.visible
	return menu_buttons.has(what) and menu_buttons[what].button_pressed


func _tutorial_desks() -> int:
	var n := 0
	for t in objects:
		if DESKS.has(objects[t]):
			n += 1
	return n


func _set_tutorial_step(i: int) -> void:
	tutorial_step = i
	if i >= TUTORIAL.size():
		tutorial_panel.queue_free()
		tutorial_panel = null
		return
	match TUTORIAL[i].do:  # counted now, so the step needs one more than we already have
		"hire":
			tutorial_base = staff.size()
		"desk":
			tutorial_base = _tutorial_desks()
	var last: bool = i == TUTORIAL.size() - 1
	tutorial_title.text = "Chet's onboarding" if last else "Chet's onboarding  %d/%d" % [i + 1, TUTORIAL.size() - 1]
	tutorial_label.text = TUTORIAL[i].text
	tutorial_button.text = "Let's ship it" if last else "Skip tutorial"


func _end_tutorial() -> void:
	var skipped: bool = tutorial_step < TUTORIAL.size() - 1
	_set_tutorial_step(TUTORIAL.size())
	if skipped:
		_chet("Cool, cool. You got this. The Guide (G) has everything if you get lost.")


func _build_tutorial_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	panel.position = Vector2(8, 96)  # left side, under the top bar and the music slider; side panels open on the right
	ui_layer.add_child(panel)
	tutorial_panel = panel
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var face := Control.new()
	face.custom_minimum_size = Vector2(56, 64)
	face.draw.connect(_draw_chet.bind(face))
	row.add_child(face)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 250
	row.add_child(col)
	tutorial_title = Label.new()
	tutorial_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	col.add_child(tutorial_title)
	tutorial_label = Label.new()
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.add_theme_font_size_override("font_size", 14)
	col.add_child(tutorial_label)
	tutorial_button = Button.new()
	tutorial_button.focus_mode = Control.FOCUS_NONE
	tutorial_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	tutorial_button.pressed.connect(_end_tutorial)
	col.add_child(tutorial_button)


# Chet: swoopy hair, sunglasses indoors, fleece vest over a button-down. Code-drawn like everything else.
func _draw_chet(c: Control) -> void:
	var skin := Color(0.96, 0.78, 0.62)
	c.draw_rect(Rect2(10, 46, 36, 18), Color(0.55, 0.7, 0.95))  # shirt
	c.draw_rect(Rect2(10, 46, 12, 18), Color(0.45, 0.47, 0.5))  # vest
	c.draw_rect(Rect2(34, 46, 12, 18), Color(0.45, 0.47, 0.5))
	c.draw_rect(Rect2(24, 38, 8, 9), skin)  # neck
	c.draw_circle(Vector2(28, 26), 15, skin)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(12, 24), Vector2(14, 12), Vector2(26, 7), Vector2(40, 8), Vector2(46, 4), Vector2(44, 16), Vector2(42, 20), Vector2(30, 15), Vector2(18, 20)]),
		Color(0.93, 0.8, 0.4))  # the swoop
	c.draw_rect(Rect2(16, 23, 10, 6), Color(0.08, 0.08, 0.1))  # shades
	c.draw_rect(Rect2(30, 23, 10, 6), Color(0.08, 0.08, 0.1))
	c.draw_line(Vector2(26, 25), Vector2(30, 25), Color(0.08, 0.08, 0.1), 2)
	c.draw_arc(Vector2(28, 31), 6, 0.3, PI - 0.3, 8, Color(0.5, 0.2, 0.2), 2)  # grin
