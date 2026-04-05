extends Control
## In-flight HUD: shield bar, boost bar, missile counter, score, crosshair,
## and lock-on reticle overlay.

var health_bar: ProgressBar
var boost_bar: ProgressBar
var missile_label: Label
var score_label: Label
var crosshair: Control
var lock_reticle: Control


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_crosshair()
	_build_lock_reticle()
	_build_health_bar()
	_build_boost_bar()
	_build_missile_counter()
	_build_score_display()

	# Wait one frame for player to be ready, then connect signals
	await get_tree().process_frame
	_connect_player()


func _process(_delta):
	_update_crosshair()
	_update_lock_reticle()


# ── Signal wiring ─────────────────────────────────────────────

func _connect_player():
	var p = GameManager.player
	if p == null:
		return
	if p.has_signal("health_changed"):
		p.health_changed.connect(_on_health)
	if p.has_signal("boost_changed"):
		p.boost_changed.connect(_on_boost)
	if p.has_signal("missiles_changed"):
		p.missiles_changed.connect(_on_missiles)
	if p.has_signal("score_changed"):
		p.score_changed.connect(_on_score)


# ── Crosshair ─────────────────────────────────────────────────

func _build_crosshair():
	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.custom_minimum_size = Vector2(60, 60)
	crosshair.size = Vector2(60, 60)
	crosshair.position = -Vector2(30, 30)
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)


func _draw_crosshair():
	var c := crosshair.size / 2.0
	var col := Color(0.3, 1.0, 0.4, 0.8)
	var gap := 8.0
	var ln := 14.0
	crosshair.draw_line(Vector2(c.x - gap - ln, c.y), Vector2(c.x - gap, c.y), col, 2.0)
	crosshair.draw_line(Vector2(c.x + gap, c.y), Vector2(c.x + gap + ln, c.y), col, 2.0)
	crosshair.draw_line(Vector2(c.x, c.y - gap - ln), Vector2(c.x, c.y - gap), col, 2.0)
	crosshair.draw_line(Vector2(c.x, c.y + gap), Vector2(c.x, c.y + gap + ln), col, 2.0)
	crosshair.draw_circle(c, 2.0, col)


func _update_crosshair():
	var p = GameManager.player
	if p == null or crosshair == null:
		return
	var ox: float = p.position.x / p.move_bounds.x * 40.0
	var oy: float = -p.position.y / p.move_bounds.y * 25.0
	crosshair.position = Vector2(-30 + ox, -30 + oy)


# ── Lock-on Reticle ───────────────────────────────────────────

func _build_lock_reticle():
	lock_reticle = Control.new()
	lock_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_reticle.set_anchors_preset(Control.PRESET_CENTER)
	lock_reticle.custom_minimum_size = Vector2(320, 320)
	lock_reticle.size = Vector2(320, 320)
	lock_reticle.position = -Vector2(160, 160)
	lock_reticle.draw.connect(_draw_lock_reticle)
	lock_reticle.visible = false
	add_child(lock_reticle)


func _draw_lock_reticle():
	var c := lock_reticle.size / 2.0
	var col := Color(1.0, 0.6, 0.1, 0.6)
	var r := 130.0
	lock_reticle.draw_arc(c, r, 0, TAU, 64, col, 2.0)
	# Corner tick marks
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var p1 := c + Vector2(cos(a), sin(a)) * r
		var p2 := c + Vector2(cos(a + 0.12), sin(a + 0.12)) * (r + 18.0)
		var p3 := c + Vector2(cos(a - 0.12), sin(a - 0.12)) * (r + 18.0)
		lock_reticle.draw_line(p1, p2, col, 2.0)
		lock_reticle.draw_line(p1, p3, col, 2.0)


func _update_lock_reticle():
	var p = GameManager.player
	if p and lock_reticle:
		lock_reticle.visible = p.is_locking


# ── Health Bar ────────────────────────────────────────────────

func _build_health_bar():
	var box := VBoxContainer.new()
	box.position = Vector2(20, 20)
	box.custom_minimum_size = Vector2(200, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var lbl := Label.new()
	lbl.text = "SHIELD"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	box.add_child(lbl)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(200, 16)
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	bg.border_color = Color(0.3, 0.8, 1.0, 0.5)
	bg.set_border_width_all(1)
	health_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.8, 0.3)
	health_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(health_bar)


# ── Boost Bar ─────────────────────────────────────────────────

func _build_boost_bar():
	var box := VBoxContainer.new()
	box.position = Vector2(20, 68)
	box.custom_minimum_size = Vector2(200, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var lbl := Label.new()
	lbl.text = "BOOST"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	box.add_child(lbl)

	boost_bar = ProgressBar.new()
	boost_bar.custom_minimum_size = Vector2(200, 12)
	boost_bar.max_value = 100.0
	boost_bar.value = 100.0
	boost_bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	bg.border_color = Color(1.0, 0.8, 0.2, 0.5)
	bg.set_border_width_all(1)
	boost_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.7, 0.1)
	boost_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(boost_bar)


# ── Missile Counter ───────────────────────────────────────────

func _build_missile_counter():
	missile_label = Label.new()
	missile_label.text = "MISSILES: 5"
	missile_label.position = Vector2(20, 118)
	missile_label.add_theme_font_size_override("font_size", 16)
	missile_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	missile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(missile_label)


# ── Score ─────────────────────────────────────────────────────

func _build_score_display():
	score_label = Label.new()
	score_label.text = "SCORE: 0"
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.position = Vector2(-160, 20)
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score_label)


# ── Signal Callbacks ──────────────────────────────────────────

func _on_health(hp: float, hp_max: float):
	if health_bar == null:
		return
	health_bar.max_value = hp_max
	health_bar.value = hp
	var fill := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		var ratio := hp / hp_max
		if ratio > 0.5:
			fill.bg_color = Color(0.2, 0.8, 0.3)
		elif ratio > 0.25:
			fill.bg_color = Color(1.0, 0.8, 0.1)
		else:
			fill.bg_color = Color(1.0, 0.2, 0.2)


func _on_boost(val: float, val_max: float):
	if boost_bar:
		boost_bar.max_value = val_max
		boost_bar.value = val


func _on_missiles(count: int):
	if missile_label:
		missile_label.text = "MISSILES: %d" % count


func _on_score(pts: int):
	if score_label:
		score_label.text = "SCORE: %d" % pts
