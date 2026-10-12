extends CanvasLayer
# The Government page (L): lobbying the state of Calizona. Three politicians, each with a
# price, a pet issue and a scandal meter, plus the State Legislature for general lobbying.
# Donations buy Favor; Favor buys permits, contracts, water rights and friendlier laws. main.gd ticks it once a day and asks it for the grid cap.

const HISTORY_DAYS := 182  # two quarters on the line graph
const HISTORY_QUARTERS := 8  # bars on the spending graph

const FAVOR_DRIFT := -0.3  # per day, as they forget who you are
const FAVOR_PET_GOOD := 0.1  # per day while their pet issue is going your way
const FAVOR_PET_BAD := -0.6  # per day while it isn't
const DONATION_FAVOR := 20.0
const DONATION_SCANDAL := 8.0  # every check leaves a paper trail
const SCANDAL_RATE := 0.05  # per day, faster with Outrage (+2% per point)
const SCANDAL_COOL := 0.1  # per day while Outrage is under 25
const SCANDAL_SCRUTINY := 15.0  # Scrutiny when a scandal breaks
const SCRUTINY_DECAY := 0.05  # per day
const SCRUTINY_PER_OUTRAGE := 0.004  # per day, per point
const SCRUTINY_PER_DEVIATION := 0.004  # per day, per point
const SCRUTINY_INFLUENCE := 0.003  # per day, per point of Influence, taken off
const FINE_FROM := 50.0  # Scrutiny at a quarter's end that gets you fined
const FINE_PER_POINT := 1000
const CONTRACT_PULL := 75.0  # Scrutiny that gets your state contract cancelled

const OFFICES := ["Governor", "Utilities Commissioner", "Water Board Chair", "State Legislature"]
const LEGISLATURE := 3  # a whole body, not a person: no scandals, nobody resigns
const LOBBY_FAVOR := 10.0  # a donation spread over 117 members goes less far
const DEREG_SCRUTINY := 0.5  # AI-Friendly Regulation: Scrutiny rises at half speed
const TAX_BREAK := 0.1  # Tech Tax Break: this share of the daily burn comes back
const PET_ISSUES := {
	"jobs": "Jobs",
	"clean_air": "Clean Air",
	"donors": "Big Donors",
	"innovation": "Innovation",
	"public_mood": "Public Mood",  # the Legislature's; replacements never get it
}
const NAMES := ["Dale Pumpwell", "Darla Voltz", "Dusty McCreek", "Chip Gerrymander", "Lorna Quidproquo",
	"Hank Pork", "Tammy Filibuster", "Rex Earmark", "Bev Loophole", "Wade Kickback", "Sunny Lobbington"]

# What you can ask for. "by" is the office that grants it; favor is spent when granted.
const ASKS := [
	{"id": "grid", "name": "Grid Hookup Permit", "by": 1, "favor": 30, "cost": 15_000, "max": 4,
		"desc": "+40 kW grid cap"},
	{"id": "contract", "name": "State AI Contract", "by": 0, "favor": 50, "cost": 0, "max": 1,
		"desc": "$1,000 a day for two quarters"},
	{"id": "water", "name": "Water Rights", "by": 2, "favor": 40, "cost": 20_000, "max": 5,
		"desc": "+50 acre-feet a year (for water cooling, coming soon)"},
	{"id": "dereg", "name": "AI-Friendly Regulation", "by": LEGISLATURE, "favor": 40, "cost": 0, "max": 1,
		"desc": "Scrutiny rises half as fast"},
	{"id": "tax", "name": "Tech Tax Break", "by": LEGISLATURE, "favor": 35, "cost": 0, "max": 1,
		"desc": "10% of your daily burn back"},
]
const PRICE_RISE := 0.25  # every price here goes up 25% a year, as politicians learn what we're worth
const GRID_PER_PERMIT := 40.0
const CONTRACT_PER_DAY := 1000
const CONTRACT_DAYS := 182
const WATER_PER_RIGHT := 50

const C_INFLUENCE := Color(1.0, 0.8, 0.35)
const C_OUTRAGE := Color(1.0, 0.45, 0.4)
const C_SCRUTINY := Color(0.55, 0.7, 1.0)
const C_SCANDAL := Color(0.85, 0.45, 0.85)
const C_INCOME := Color(0.45, 0.85, 0.5)

var main  # main.gd
var politicians := []  # [{name, office, pet, price, favor, scandal}]
var scrutiny := 10.0
var granted := {"grid": 0, "contract": 0, "water": 0, "dereg": 0, "tax": 0}
var contract_days := 0  # left on the state contract
var last_donation_day := -999
var history := []  # one [influence, outrage, scrutiny] a day
var spend := [0]  # lobbying spent per quarter, this quarter last
var income := [0]  # contract money per quarter
var _rng := RandomNumberGenerator.new()

var page: Control
var meter_bars := {}  # id -> ProgressBar
var meter_labels := {}  # id -> Label, raised by / lowered by
var meter_values := {}  # id -> Label, name and value
var cards := []  # per politician: {name, pet, favor, favor_label, scandal, scandal_label, donate}
var ask_buttons := {}  # ask id -> Button
var ask_labels := {}  # ask id -> Label
var line_chart: Control
var price_label: Label
var bar_chart: Control


func _ready() -> void:
	layer = 60  # same as the Research page, above the music controls
	_rng.seed = 7
	var prices := [25_000, 10_000, 8_000, 15_000]
	var pets := ["jobs", "clean_air", "donors", "public_mood"]
	for i in OFFICES.size():
		politicians.append({"name": NAMES[i] if i != LEGISLATURE else "117 members", "office": OFFICES[i],
			"pet": pets[i], "price": prices[i], "favor": 10.0, "scandal": 0.0 if i == LEGISLATURE else 5.0})
	_build_page()


# --- Simulation -------------------------------------------------------------

func influence() -> float:
	var total := 0.0
	for p in politicians:
		total += p.favor
	return total / politicians.size()


# Today's price of something that cost `base` in year one, rounded to $500.
func price(base: int) -> int:
	var years: float = float(main.day - 1) / main.DAYS_PER_YEAR
	return int(round(base * (1.0 + PRICE_RISE * years) / 500.0)) * 500


func grid_bonus() -> float:
	return granted.grid * GRID_PER_PERMIT


func water_rights() -> int:
	return granted.water * WATER_PER_RIGHT


# Is this politician's pet issue going your way (1), against you (-1), or neither (0)?
func _pet_mood(p: Dictionary) -> int:
	var outrage: float = main.world.outrage
	match p.pet:
		"jobs":
			return 1 if main.staff.size() >= 8 else (-1 if main.staff.size() < 4 else 0)
		"clean_air":
			return -1 if outrage >= 25.0 else (1 if outrage < 5.0 else 0)
		"donors":
			return 1 if main.day - last_donation_day <= 30 else -1
		"innovation":
			return 1 if main._best_cap() >= main._rival_cap() else -1
		"public_mood":
			return -1 if outrage >= 25.0 else (1 if outrage < 10.0 else 0)
	return 0


func tick_day() -> void:
	var outrage: float = main.world.outrage
	for i in politicians.size():
		var p: Dictionary = politicians[i]
		var mood := _pet_mood(p)
		p.favor = clampf(p.favor + (FAVOR_PET_GOOD if mood > 0 else (FAVOR_PET_BAD if mood < 0 else FAVOR_DRIFT)), 0.0, 100.0)
		if i == LEGISLATURE:
			continue
		p.scandal += SCANDAL_RATE * (1.0 + outrage * 0.02)
		if outrage < 25.0:
			p.scandal -= SCANDAL_COOL
		p.scandal = clampf(p.scandal, 0.0, 100.0)
		if p.scandal >= 100.0:
			_scandal(i)
	scrutiny += (outrage * SCRUTINY_PER_OUTRAGE + main.deviation * SCRUTINY_PER_DEVIATION) * (DEREG_SCRUTINY if granted.dereg > 0 else 1.0)
	scrutiny -= SCRUTINY_DECAY + influence() * SCRUTINY_INFLUENCE
	scrutiny = clampf(scrutiny, 0.0, 100.0)
	if granted.tax > 0:
		main.money += int(main._daily_burn() * TAX_BREAK)
	if contract_days > 0:
		if scrutiny >= CONTRACT_PULL:
			_end_contract("The state cancelled your AI contract \"pending review\". Scrutiny is too high, bro.")
		else:
			main.money += CONTRACT_PER_DAY
			income[-1] += CONTRACT_PER_DAY
			contract_days -= 1
			if contract_days == 0:
				_end_contract("The state AI contract ran out. Time to schmooze the Governor again.")
	history.append([influence(), outrage, scrutiny])
	if history.size() > HISTORY_DAYS:
		history.pop_front()
	if (main.day - 1) % main.DAYS_PER_QUARTER == 0:
		_end_quarter()


func _end_quarter() -> void:
	if scrutiny >= FINE_FROM:
		var fine := int((scrutiny - FINE_FROM + 10.0) * FINE_PER_POINT)
		main.money -= fine
		main._chet("The state fined us %s for \"vibes-based compliance\". Lower Scrutiny on the Government page (L)." % main._money(fine))
	spend.append(0)
	income.append(0)
	if spend.size() > HISTORY_QUARTERS:
		spend.pop_front()
		income.pop_front()


func _end_contract(msg: String) -> void:
	contract_days = 0
	granted.contract = 0
	main._chet(msg)


func _scandal(i: int) -> void:
	var old: Dictionary = politicians[i]
	var taken := politicians.map(func(p): return p.name)
	var free := NAMES.filter(func(n): return not taken.has(n))
	var pets := PET_ISSUES.keys().filter(func(k): return k != "public_mood")
	politicians[i] = {"name": free[_rng.randi() % free.size()], "office": old.office,
		"pet": pets[_rng.randi() % pets.size()], "price": old.price, "favor": 0.0, "scandal": 5.0}
	scrutiny = minf(scrutiny + SCANDAL_SCRUTINY, 100.0)
	var extra := ""
	if i == 0 and contract_days > 0:
		contract_days = 0
		granted.contract = 0
		extra = " Our state contract went down with them."
	main._chet("%s %s resigned in a scandal (allegedly a yacht). %s is in and has never heard of us.%s" % [
		old.office, old.name, politicians[i].name, extra])


func donate(i: int) -> void:
	var p: Dictionary = politicians[i]
	var cost := price(p.price)
	if main.money < cost:
		main._chet("We can't afford to be that generous to %s right now." % p.name)
		return
	main.money -= cost
	spend[-1] += cost
	last_donation_day = main.day
	p.favor = minf(p.favor + (LOBBY_FAVOR if i == LEGISLATURE else DONATION_FAVOR), 100.0)
	if i == LEGISLATURE:
		return  # lobbying a whole legislature is perfectly legal
	p.scandal = minf(p.scandal + DONATION_SCANDAL, 100.0)
	if p.scandal >= 100.0:
		_scandal(i)


func ask(id: String) -> void:
	var a: Dictionary = ASKS.filter(func(x): return x.id == id)[0]
	var p: Dictionary = politicians[a.by]
	var cost := price(a.cost)
	if granted[id] >= a.max or p.favor < a.favor or main.money < cost:
		return
	main.money -= cost
	spend[-1] += cost
	p.favor -= a.favor
	granted[id] += 1
	match id:
		"grid":
			main._chet("Permit approved. The utility says we can pull %d kW now. Our neighbours' lights may flicker." % (main.GRID_KW + grid_bonus()))
		"contract":
			contract_days = CONTRACT_DAYS
			main._chet("We landed a State AI Contract! The DMV wants a chatbot that says no in 40 languages.")
		"water":
			main._chet("Water rights secured: %d acre-feet a year. The farmers are thrilled. (They are not.)" % water_rights())
		"dereg":
			main._chet("The AI Freedom to Innovate Act passed 61-56. Nobody read it. I helped write it, bro.")
		"tax":
			main._chet("Tech Tax Break passed! The schools will be fine. Probably. They have iPads.")


# --- Page -------------------------------------------------------------------

func toggle() -> void:
	page.visible = not page.visible
	refresh()


func refresh() -> void:
	if not page.visible:
		return
	var inf := influence()
	price_label.text = "Lobbying prices +%d%% since %d (+%d%% a year)    " % [
		roundi((price(10_000) / 10_000.0 - 1.0) * 100.0), main.START_YEAR, PRICE_RISE * 100]
	_set_meter("influence", inf, "Influence %d" % inf,
		"Raised by: donations, happy pet issues\nLowered by: time, asking favors, unhappy pet issues, scandals")
	_set_meter("outrage", main.world.outrage, "Outrage %d" % main.world.outrage,
		"Raised by: smog on houses and farmhouses, building on farmland, water use\nLowered by: time, clean air")
	_set_meter("scrutiny", scrutiny, "Scrutiny %d" % scrutiny,
		"Raised by: Outrage, Deviation, scandals\nLowered by: time, Influence\nFines from %d, contract pulled at %d" % [FINE_FROM, CONTRACT_PULL])
	for i in politicians.size():
		var p: Dictionary = politicians[i]
		var c: Dictionary = cards[i]
		c.name.text = "%s: %s" % [p.office, p.name]
		var mood := _pet_mood(p)
		c.pet.text = "Pet issue: %s (%s)" % [PET_ISSUES[p.pet], "happy" if mood > 0 else ("unhappy" if mood < 0 else "meh")]
		c.pet.add_theme_color_override("font_color", C_INCOME if mood > 0 else (C_OUTRAGE if mood < 0 else Color(0.8, 0.8, 0.8)))
		c.favor.value = p.favor
		c.favor_label.text = "Favor %d" % p.favor
		c.scandal.value = p.scandal
		c.scandal_label.text = "Scandal %d" % p.scandal
		c.donate.text = "%s %s" % ["Lobby" if i == LEGISLATURE else "Donate", main._money(price(p.price))]
		c.donate.disabled = main.money < price(p.price)
	for a in ASKS:
		var p: Dictionary = politicians[a.by]
		var b: Button = ask_buttons[a.id]
		var maxed: bool = granted[a.id] >= a.max
		b.disabled = maxed or p.favor < a.favor or main.money < price(a.cost)
		b.text = "%s%s" % [a.name, "" if a.cost == 0 else "  (%s)" % main._money(price(a.cost))]
		var status := ""
		match a.id:
			"grid":
				status = "Grid cap %d kW" % (main.GRID_KW + grid_bonus())
			"contract":
				status = ("%d days left" % contract_days) if contract_days > 0 else "No contract"
			"water":
				status = "%d acre-feet a year" % water_rights()
			"dereg", "tax":
				status = "Passed" if granted[a.id] > 0 else "Not passed"
		ask_labels[a.id].text = "%s. Needs %d Favor: %s.  %s%s" % [
			a.desc, a.favor, OFFICES[a.by], status, "   (maxed)" if maxed and a.max > 1 else ""]
	line_chart.queue_redraw()
	bar_chart.queue_redraw()


func _process(_delta: float) -> void:
	if page and page.visible:
		refresh()


func _set_meter(id: String, v: float, text: String, why: String) -> void:
	meter_bars[id].value = v
	meter_values[id].text = text
	meter_labels[id].text = why


# A name-and-value label with its bar beside it.
func _meter_row(parent: Control, bar: ProgressBar, font_size := 13) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _small("", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = 110
	row.add_child(l)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return l


func _box_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = main._panel_style(1.0)
	s.bg_color = Color(0.12, 0.11, 0.1)
	s.set_content_margin_all(10)
	return s


func _bar(color: Color, height := 12) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _small(text := "", size := 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_page() -> void:
	page = ColorRect.new()
	page.color = Color(0.07, 0.07, 0.09, 0.97)
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	page.visible = false
	add_child(page)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	col.add_theme_constant_override("separation", 10)
	page.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "Government of Calizona"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	price_label = _small("", 14)
	price_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	price_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	head.add_child(price_label)
	var close := Button.new()
	close.text = "Close (L)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(main._toggle_menu.bind("government"))
	head.add_child(close)

	# Meters on the left, their history on the right.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(top)
	var meters := PanelContainer.new()
	meters.add_theme_stylebox_override("panel", _box_style())
	meters.custom_minimum_size.x = 430
	top.add_child(meters)
	var mcol := VBoxContainer.new()
	mcol.add_theme_constant_override("separation", 4)
	meters.add_child(mcol)
	for m in [["influence", C_INFLUENCE], ["outrage", C_OUTRAGE], ["scrutiny", C_SCRUTINY]]:
		var bar := _bar(m[1], 14)
		meter_bars[m[0]] = bar
		meter_values[m[0]] = _meter_row(mcol, bar, 15)
		var l := _small("", 12)
		l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		mcol.add_child(l)
		meter_labels[m[0]] = l
	var graph := PanelContainer.new()
	graph.add_theme_stylebox_override("panel", _box_style())
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(graph)
	line_chart = Control.new()
	line_chart.draw.connect(_draw_line_chart)
	graph.add_child(line_chart)

	# The politicians.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	for i in politicians.size():
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box_style())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 3)
		card.add_child(c)
		var who := _small("", 15)
		who.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		c.add_child(who)
		var pet := _small()
		c.add_child(pet)
		var fb := _bar(C_INFLUENCE)
		var fl := _meter_row(c, fb)
		var sb := _bar(C_SCANDAL)
		var sl := _meter_row(c, sb)
		sl.get_parent().visible = i != LEGISLATURE
		var give := Button.new()
		give.focus_mode = Control.FOCUS_NONE
		give.tooltip_text = ("+%d Favor" % LOBBY_FAVOR) if i == LEGISLATURE else "+%d Favor, +%d Scandal" % [DONATION_FAVOR, DONATION_SCANDAL]
		give.pressed.connect(donate.bind(i))
		c.add_child(give)
		cards.append({"name": who, "pet": pet, "favor": fb, "favor_label": fl, "scandal": sb,
			"scandal_label": sl, "donate": give})

	# Asks on the left, money in and out on the right.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(bottom)
	var asks := PanelContainer.new()
	asks.add_theme_stylebox_override("panel", _box_style())
	asks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asks.size_flags_stretch_ratio = 1.6
	bottom.add_child(asks)
	var acol := VBoxContainer.new()
	acol.add_theme_constant_override("separation", 2)
	asks.add_child(acol)
	acol.add_theme_constant_override("separation", 2)
	for a in ASKS:
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 10)
		acol.add_child(arow)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 250
		b.pressed.connect(ask.bind(a.id))
		arow.add_child(b)
		ask_buttons[a.id] = b
		var l := _small("", 12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arow.add_child(l)
		ask_labels[a.id] = l
	var money_panel := PanelContainer.new()
	money_panel.add_theme_stylebox_override("panel", _box_style())
	money_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(money_panel)
	bar_chart = Control.new()
	bar_chart.draw.connect(_draw_bar_chart)
	money_panel.add_child(bar_chart)


func _draw_legend(c: Control, x: float, items: Array) -> void:
	var font := ThemeDB.fallback_font
	for it in items:
		c.draw_rect(Rect2(x, 6, 10, 10), it[1])
		c.draw_string(font, Vector2(x + 14, 16), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		x += 24 + font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x


# Influence, Outrage and Scrutiny over the last two quarters, 0-100.
func _draw_line_chart() -> void:
	var c := line_chart
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(0, 16), "Last 6 months", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.5))
	_draw_legend(c, 110, [["Influence", C_INFLUENCE], ["Outrage", C_OUTRAGE], ["Scrutiny", C_SCRUTINY]])
	var r := Rect2(28, 26, c.size.x - 32, c.size.y - 30)
	for v in [0, 25, 50, 75, 100]:
		var y: float = r.end.y - r.size.y * v / 100.0
		c.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.08))
		c.draw_string(font, Vector2(0, y + 4), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))
	if history.size() < 2:
		c.draw_string(font, r.get_center() - Vector2(70, 0), "Check back tomorrow", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.4))
		return
	for k in 3:
		var pts := PackedVector2Array()
		for i in history.size():
			pts.append(Vector2(r.position.x + r.size.x * i / (HISTORY_DAYS - 1.0), r.end.y - r.size.y * history[i][k] / 100.0))
		c.draw_polyline(pts, [C_INFLUENCE, C_OUTRAGE, C_SCRUTINY][k], 2.0, true)


# Lobbying spent against state contract money, per quarter.
func _draw_bar_chart() -> void:
	var c := bar_chart
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(0, 16), "Per quarter", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.5))
	_draw_legend(c, 90, [["Lobbying", C_SCANDAL], ["Contracts", C_INCOME]])
	var r := Rect2(0, 26, c.size.x, c.size.y - 42)
	var top := 1
	for i in spend.size():
		top = maxi(top, maxi(spend[i], income[i]))
	c.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Color(1, 1, 1, 0.2))
	var slot := r.size.x / HISTORY_QUARTERS
	var bw := minf(slot * 0.35, 22.0)
	for i in spend.size():
		var x := r.position.x + slot * i + slot / 2.0
		for k in 2:
			var v: int = [spend, income][k][i]
			var h := r.size.y * v / top
			c.draw_rect(Rect2(x - bw + k * bw, r.end.y - h, bw - 1, h), [C_SCANDAL, C_INCOME][k])
		var q: int = (main.day - 1) / main.DAYS_PER_QUARTER - (spend.size() - 1 - i)
		c.draw_string(font, Vector2(x - slot / 2.0, r.end.y + 13), main._quarter_name(q), HORIZONTAL_ALIGNMENT_CENTER, slot, 10, Color(1, 1, 1, 0.5))
	c.draw_string(font, Vector2(r.end.x - 120, 16), main._money(top), HORIZONTAL_ALIGNMENT_RIGHT, 120, 11, Color(1, 1, 1, 0.5))
