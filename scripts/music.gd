extends Node
## Autoload "Music": shuffles through the soundtrack, with a mute button, volume slider and N hotkey.
## Call Music.set_tension(true) when the Deviation meter gets scary to switch to the tense track.

const CALM := [
	"open_plan_build_mode", "hydration_station", "synergy", "lobbying_hours", "calizona_sunset",
	"scaling_laws", "quarterly_earnings", "disrupt", "series_a_title",
]
const TENSION := "deviation_rising"
const SETTINGS_PATH := "user://audio_settings.cfg"

var player := AudioStreamPlayer.new()
var queue: Array = []
var last := ""
var tense := false
var muted := false
var volume := 0.7  # 0..1, linear

var mute_button: Button
var slider: HSlider
var now_playing: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep playing while the game is paused
	add_child(player)
	player.finished.connect(_on_finished)
	_load_settings()
	_build_ui()
	_apply_volume()
	_play_next()


func set_tension(on: bool) -> void:
	if on == tense:
		return
	tense = on
	_play_next()


func toggle_mute() -> void:
	muted = not muted
	_apply_volume()
	_save_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		toggle_mute()


func _on_finished() -> void:
	_play_next()


func _play_next() -> void:
	var track: String = TENSION
	if not tense:
		if queue.is_empty():
			queue = CALM.duplicate()
			queue.shuffle()
			if queue[0] == last and queue.size() > 1:
				queue.push_back(queue.pop_front())  # never repeat the track that just played
		track = queue.pop_front()
	last = track
	var stream = load("res://audio/%s.ogg" % track)
	if stream == null:
		push_warning("Music: missing track %s" % track)
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = tense  # tension music loops until things calm down
	player.stream = stream
	player.play()
	if now_playing:
		now_playing.text = "♪ " + track.replace("_", " ").capitalize()


func _apply_volume() -> void:
	player.volume_db = linear_to_db(maxf(volume, 0.0001))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	if mute_button:
		mute_button.text = "Sound off" if muted else "Sound on"
		mute_button.set_pressed_no_signal(muted)
	if slider:
		slider.set_value_no_signal(volume)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var box := PanelContainer.new()
	box.position = Vector2(8, 56)
	box.modulate = Color(1, 1, 1, 0.92)
	layer.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	mute_button = Button.new()
	mute_button.toggle_mode = true
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.tooltip_text = "Mute / unmute music (N)"
	mute_button.pressed.connect(toggle_mute)
	row.add_child(mute_button)
	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(90, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_slider)
	row.add_child(slider)
	now_playing = Label.new()
	now_playing.add_theme_font_size_override("font_size", 12)
	now_playing.modulate = Color(1, 1, 1, 0.7)
	row.add_child(now_playing)


func _on_slider(v: float) -> void:
	volume = v
	if v > 0.0 and muted:
		muted = false
	_apply_volume()
	_save_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = cfg.get_value("audio", "volume", volume)
		muted = cfg.get_value("audio", "muted", false)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)
