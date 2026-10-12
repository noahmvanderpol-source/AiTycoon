extends "res://scripts/research_ui.gd"
## Company page (models, staff, board, policies). Part of the Main script chain (see scripts/README.md).

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
	models_label.text = ("Best model: %s\nUsers: %s (capacity %s)\nRevenue: %s/day\nCompute: %.1f per day\n  %d racks: %.1f\n  Engineers: %.1f\n  Red-team rigs: -%.1f\n  Users: -%.1f%s\n"
		+ "Training: %.1f, x%.2f research = %.1f per day\nTop rival: %s %s (capability %d)") % [
		best, _num(int(users)), _num(int(_user_capacity())), _money(revenue_today), _compute_per_day(), _racks(), _rack_compute(), _engineer_compute(),
		_redteam_compute(), _user_compute(), hidden, _training_compute(), _research_mult(), _training_speed(), rival[1], rival[2], _rival_cap()]
	var serving := ""
	if _best_cap() > 0:
		serving = "\nServing %s needs %.1f compute%s" % [models.back().name, _compute_needed(_best_cap()),
			"" if _serve_ratio() >= 1.0 else ", short! Users get %d%% of it" % int(_serve_ratio() * 100.0)]
	models_label.text += serving
	var compute := _training_speed()
	if training.is_empty():
		train_label.text = "Nothing training. Pick a size:" if _racks() > 0 else "Build a Server Rack to train models."
		train_bar.visible = false
	else:
		var days_left := "?" if compute <= 0.0 else str(ceili((training.work - training.done) / _training_speed()))
		train_label.text = "Training %s (capability %d%s), %s days left" % [training.name, training.cap, ", rushed" if training.rushed else "", days_left]
		if not _can_train(training.cap):
			train_label.text = "Training %s paused: needs %.1f compute, you have %.1f" % [training.name, _compute_needed(training.cap), _compute_per_day()]
		train_bar.visible = true
		train_bar.value = 100.0 * training.done / training.work
	for i in MODEL_SIZES.size():
		var size: Dictionary = MODEL_SIZES[i]
		var work := _train_work(i) * (RUSH_WORK if rush_check.button_pressed else 1.0)
		var days := "?" if compute <= 0.0 else str(ceili(work / compute))
		var cap := _best_cap() + int(size.gain)
		train_buttons[i].text = "Train %s   %s\nNeeds %.1f compute   ~%s days\n+%d capability   +%d%% Deviation rate" % [
			size.name, _money(_train_cost(i)), _compute_needed(cap), days, size.gain, roundi(_train_mod(i, rush_check.button_pressed) * 100.0)]
		train_buttons[i].disabled = not training.is_empty() or _train_cost(i) > money or not _can_train(cap)


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


# The Company page: a mostly full-screen overlay with Board and Policies tabs.
func _build_company_page(layer: CanvasLayer) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	layer.add_child(dim)
	company_page = dim
	var panel := PanelContainer.new()
	var style := _panel_style(0.97)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 64
	panel.offset_bottom = -90
	dim.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	company_title = Label.new()
	company_title.add_theme_font_size_override("font_size", 24)
	company_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(company_title)
	for i in 2:
		var b := Button.new()
		b.text = ["Board", "Policies"][i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.x = 110
		b.pressed.connect(_show_company_tab.bind(i))
		head.add_child(b)
		company_tab_buttons.append(b)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): _set_company_page(false))
	head.add_child(close)
	col.add_child(HSeparator.new())
	company_tabs = TabContainer.new()
	company_tabs.tabs_visible = false
	company_tabs.focus_mode = Control.FOCUS_NONE
	company_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(company_tabs)
	_build_board_tab()
	_build_policies_tab()


func _set_company_page(open: bool) -> void:
	company_page.visible = open
	if open:
		research_page.visible = false
		gov.page.visible = false
	_refresh_menu_buttons()


func _show_company_tab(i: int) -> void:
	company_tabs.current_tab = i
	for j in company_tab_buttons.size():
		company_tab_buttons[j].button_pressed = j == i
	_set_company_page(true)


# Opens the page on tab i, or closes it if it's already showing that tab.
func _toggle_company_page(i: int) -> void:
	if company_page.visible and company_tabs.current_tab == i:
		_set_company_page(false)
	else:
		_show_company_tab(i)


func _build_policies_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Policies"
	company_tabs.add_child(box)
	var l := _wrap_label(box)
	l.add_theme_font_size_override("font_size", 16)
	l.text = "No policies yet.\n\nThis is where you'll make company-wide decisions: return-to-office mandates, unlimited kombucha, \"move fast and break things\" as official policy.\n\nChet: Policies are like rules, but for other people. Coming soon, bro."


func _build_board_tab() -> void:
	var cols := HBoxContainer.new()
	cols.name = "Board"
	cols.add_theme_constant_override("separation", 40)
	company_tabs.add_child(cols)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	cols.add_child(box)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	board_label = _wrap_label(box)
	board_label.add_theme_font_size_override("font_size", 18)
	board_bar = ProgressBar.new()
	board_bar.custom_minimum_size.y = 16
	board_bar.show_percentage = false
	board_bar.custom_minimum_size.y = 22
	box.add_child(board_bar)
	box.add_child(HSeparator.new())
	board_target_label = _wrap_label(box)
	board_target_label.add_theme_font_size_override("font_size", 16)
	board_members_label = _wrap_label(right)
	board_members_label.add_theme_font_size_override("font_size", 16)


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
