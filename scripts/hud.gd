extends Control
## In-flight HUD: fixed center crosshair, target brackets, lock-on progress,
## shield/boost/laser bars, missile counter, hit counter, lives, phase indicator,
## boost speed lines.

var health_bar: ProgressBar
var boost_bar: ProgressBar
var laser_bar: ProgressBar
var missile_label: Label
var score_label: Label
var hits_label: Label
var lives_label: Label
var phase_bar: ProgressBar
var phase_status_label: Label
var crosshair: Control
var target_overlay: Control
var speed_lines_layer: Control
var threat_bar: ProgressBar
var threat_label: Label
var threat_container: VBoxContainer

# Boost speed lines
var speed_line_data: Array = []
var NUM_SPEED_LINES := 40


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_crosshair()
	_build_target_overlay()
	_build_speed_lines_layer()
	_build_health_bar()
	_build_boost_bar()
	_build_laser_bar()
	_build_missile_counter()
	_build_hits_counter()
	_build_lives_display()
	_build_score_display()
	_build_phase_indicator()
	_build_threat_indicator()
	_init_speed_lines()

	await get_tree().process_frame
	_connect_player()


func _process(delta):
	_update_crosshair()
	if target_overlay:
		target_overlay.queue_redraw()
	_update_speed_lines(delta)


# ── Signal wiring ─────────────────────────────────────────────

func _connect_player():
	var p = GameManager.player
	if p == null:
		return
	if p.has_signal("health_changed"):
		p.health_changed.connect(_on_health)
	if p.has_signal("boost_changed"):
		p.boost_changed.connect(_on_boost)
	if p.has_signal("laser_energy_changed"):
		p.laser_energy_changed.connect(_on_laser_energy)
	if p.has_signal("missiles_changed"):
		p.missiles_changed.connect(_on_missiles)
	if p.has_signal("score_changed"):
		p.score_changed.connect(_on_score)
	if p.has_signal("hits_changed"):
		p.hits_changed.connect(_on_hits)
	if p.has_signal("lives_changed"):
		p.lives_changed.connect(_on_lives)
	if p.has_signal("phase_changed"):
		p.phase_changed.connect(_on_phase)
	# Initialize lives display
	if lives_label and "lives" in p:
		lives_label.text = "x %d" % p.lives


# ── Crosshair (fixed at screen center) ────────────────────────

func _build_crosshair():
	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.custom_minimum_size = Vector2(60, 60)
	crosshair.size = Vector2(60, 60)
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)
	# Position once at center
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	crosshair.position = screen_center - Vector2(30, 30)


func _draw_crosshair():
	var c := crosshair.size / 2.0
	var col := Color(0.3, 0.9, 1.0, 0.8)
	var gap := 8.0
	var ln := 14.0
	crosshair.draw_line(Vector2(c.x - gap - ln, c.y), Vector2(c.x - gap, c.y), col, 2.0)
	crosshair.draw_line(Vector2(c.x + gap, c.y), Vector2(c.x + gap + ln, c.y), col, 2.0)
	crosshair.draw_line(Vector2(c.x, c.y - gap - ln), Vector2(c.x, c.y - gap), col, 2.0)
	crosshair.draw_line(Vector2(c.x, c.y + gap), Vector2(c.x, c.y + gap + ln), col, 2.0)
	crosshair.draw_circle(c, 2.0, col)


func _update_crosshair():
	pass  # crosshair is fixed at center, nothing to update


# ── Target Overlay (brackets + lock-on progress) ─────────────

func _build_target_overlay():
	target_overlay = Control.new()
	target_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	target_overlay.draw.connect(_draw_targets)
	add_child(target_overlay)


func _draw_targets():
	var cam := get_viewport().get_camera_3d()
	var player = GameManager.player
	if cam == null or player == null:
		return

	var vp_size := get_viewport().get_visible_rect().size
	var locked: Array = player.locked_targets
	var candidate = player.lock_candidate
	var lock_progress: float = player.lock_timer / player.lock_time_required if player.lock_time_required > 0 else 0.0

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var cam_fwd := -cam.global_transform.basis.z
		var to_enemy: Vector3 = enemy.global_position - cam.global_position
		if to_enemy.dot(cam_fwd) < 0:
			continue

		var screen_pos := cam.unproject_position(enemy.global_position)
		if screen_pos.x < -50 or screen_pos.x > vp_size.x + 50:
			continue
		if screen_pos.y < -50 or screen_pos.y > vp_size.y + 50:
			continue

		var dist: float = player.global_position.distance_to(enemy.global_position)
		var in_range: bool = dist < player.lock_range
		var is_locked: bool = enemy in locked
		var is_candidate: bool = enemy == candidate

		# Only show brackets for nearby enemies (within 40 units) unless locked/candidate
		if dist > 40.0 and not is_locked and not is_candidate:
			continue

		var col: Color
		if is_locked:
			col = Color(1.0, 0.2, 0.1, 0.9)
		elif is_candidate:
			col = Color(1.0, 0.8, 0.1, 0.9)
		elif in_range:
			col = Color(0.2, 1.0, 0.4, 0.7)
		else:
			col = Color(0.5, 0.6, 0.7, 0.4)

		var bracket_half: float = clampf(remap(dist, 10.0, 80.0, 28.0, 14.0), 14.0, 28.0)
		var corner_len: float = bracket_half * 0.45
		var thickness: float = 3.0 if is_locked else 2.0
		var cx: float = screen_pos.x
		var cy: float = screen_pos.y

		# Corner brackets
		target_overlay.draw_line(Vector2(cx - bracket_half, cy - bracket_half), Vector2(cx - bracket_half + corner_len, cy - bracket_half), col, thickness)
		target_overlay.draw_line(Vector2(cx - bracket_half, cy - bracket_half), Vector2(cx - bracket_half, cy - bracket_half + corner_len), col, thickness)
		target_overlay.draw_line(Vector2(cx + bracket_half, cy - bracket_half), Vector2(cx + bracket_half - corner_len, cy - bracket_half), col, thickness)
		target_overlay.draw_line(Vector2(cx + bracket_half, cy - bracket_half), Vector2(cx + bracket_half, cy - bracket_half + corner_len), col, thickness)
		target_overlay.draw_line(Vector2(cx - bracket_half, cy + bracket_half), Vector2(cx - bracket_half + corner_len, cy + bracket_half), col, thickness)
		target_overlay.draw_line(Vector2(cx - bracket_half, cy + bracket_half), Vector2(cx - bracket_half, cy + bracket_half - corner_len), col, thickness)
		target_overlay.draw_line(Vector2(cx + bracket_half, cy + bracket_half), Vector2(cx + bracket_half - corner_len, cy + bracket_half), col, thickness)
		target_overlay.draw_line(Vector2(cx + bracket_half, cy + bracket_half), Vector2(cx + bracket_half, cy + bracket_half - corner_len), col, thickness)

		# Locked: diamond centre + "LOCK" text
		if is_locked:
			var d := 6.0
			var pts: PackedVector2Array = PackedVector2Array([
				Vector2(cx, cy - d), Vector2(cx + d, cy),
				Vector2(cx, cy + d), Vector2(cx - d, cy),
				Vector2(cx, cy - d),
			])
			target_overlay.draw_polyline(pts, col, 2.0)
			target_overlay.draw_string(ThemeDB.fallback_font, Vector2(cx + bracket_half + 4, cy + 5), "LOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

		# Lock-on progress arc
		if is_candidate and lock_progress > 0.01:
			var arc_r := bracket_half + 6.0
			var arc_col := Color(1.0, 0.8, 0.1, 0.8)
			target_overlay.draw_arc(Vector2(cx, cy), arc_r, -PI / 2.0, -PI / 2.0 + TAU * lock_progress, 32, arc_col, 3.0)


# ── Boost Speed Lines (hyperspace effect) ────────────────────

func _build_speed_lines_layer():
	speed_lines_layer = Control.new()
	speed_lines_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_lines_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_lines_layer.draw.connect(_draw_speed_lines)
	speed_lines_layer.visible = false
	add_child(speed_lines_layer)


func _init_speed_lines():
	speed_line_data.clear()
	for i in NUM_SPEED_LINES:
		speed_line_data.append({
			"angle": randf() * TAU,
			"dist": randf_range(30.0, 500.0),
			"speed": randf_range(400.0, 900.0),
			"length": randf_range(30.0, 80.0),
			"alpha": randf_range(0.3, 0.8),
		})


func _update_speed_lines(delta):
	var player = GameManager.player
	if player == null:
		return

	var boosting: bool = player.is_boosting
	speed_lines_layer.visible = boosting

	if not boosting:
		return

	var max_dist := 700.0
	for line in speed_line_data:
		line["dist"] += line["speed"] * delta
		if line["dist"] > max_dist:
			line["dist"] = randf_range(20.0, 80.0)
			line["angle"] = randf() * TAU
			line["speed"] = randf_range(400.0, 900.0)
			line["alpha"] = randf_range(0.3, 0.8)

	speed_lines_layer.queue_redraw()


func _draw_speed_lines():
	var vp := get_viewport_rect().size
	var center := vp / 2.0

	for line in speed_line_data:
		var angle: float = line["angle"]
		var dist: float = line["dist"]
		var ln: float = line["length"]
		var alpha: float = line["alpha"]

		var dir := Vector2(cos(angle), sin(angle))
		var p1 := center + dir * dist
		var p2 := center + dir * (dist + ln)

		# Fade based on distance from center
		var fade := clampf(dist / 500.0, 0.0, 1.0)
		var col := Color(0.6, 0.8, 1.0, alpha * fade)

		speed_lines_layer.draw_line(p1, p2, col, 1.5)


# ── Health Bar (top-left) ────────────────────────────────────

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


# ── Laser Energy Bar ─────────────────────────────────────────

func _build_laser_bar():
	var box := VBoxContainer.new()
	box.position = Vector2(20, 110)
	box.custom_minimum_size = Vector2(200, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var lbl := Label.new()
	lbl.text = "LASER"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	box.add_child(lbl)

	laser_bar = ProgressBar.new()
	laser_bar.custom_minimum_size = Vector2(200, 12)
	laser_bar.max_value = 100.0
	laser_bar.value = 100.0
	laser_bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	bg.border_color = Color(0.3, 0.9, 1.0, 0.5)
	bg.set_border_width_all(1)
	laser_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.85, 1.0)
	laser_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(laser_bar)


# ── Missile Counter ───────────────────────────────────────────

func _build_missile_counter():
	missile_label = Label.new()
	missile_label.text = "MISSILES: 8"
	missile_label.position = Vector2(20, 118)
	missile_label.add_theme_font_size_override("font_size", 16)
	missile_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	missile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(missile_label)


# ── Hit Counter (top-center) ──────────────────────────────────

func _build_hits_counter():
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 16
	box.offset_left = -60
	box.offset_right = 60
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var title := Label.new()
	title.text = "TOTAL HITS"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	hits_label = Label.new()
	hits_label.text = "000"
	hits_label.add_theme_font_size_override("font_size", 28)
	hits_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	hits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hits_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hits_label)


# ── Lives Display (top-right, ship icon + count) ─────────────

func _build_lives_display():
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_top = 16
	box.offset_right = -20
	box.offset_left = -140
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	# Ship icon (triangle drawn as text placeholder)
	var icon := Label.new()
	icon.text = ">"  # ship silhouette placeholder
	icon.add_theme_font_size_override("font_size", 20)
	icon.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	lives_label = Label.new()
	lives_label.text = "x 3"
	lives_label.add_theme_font_size_override("font_size", 20)
	lives_label.add_theme_color_override("font_color", Color.WHITE)
	lives_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lives_label)


# ── Score ─────────────────────────────────────────────────────

func _build_score_display():
	score_label = Label.new()
	score_label.text = "SCORE: 0"
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.position = Vector2(-160, 46)
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score_label)


# ── Phase Indicator (bar + label) ─────────────────────────────

func _build_phase_indicator():
	var box := VBoxContainer.new()
	box.position = Vector2(20, 145)
	box.custom_minimum_size = Vector2(200, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	phase_status_label = Label.new()
	phase_status_label.text = "PHASE [B]: READY"
	phase_status_label.add_theme_font_size_override("font_size", 14)
	phase_status_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
	box.add_child(phase_status_label)

	phase_bar = ProgressBar.new()
	phase_bar.custom_minimum_size = Vector2(200, 10)
	phase_bar.max_value = 1.0
	phase_bar.value = 1.0
	phase_bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	bg.border_color = Color(0.3, 0.6, 1.0, 0.5)
	bg.set_border_width_all(1)
	phase_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.6, 1.0)
	phase_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(phase_bar)


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


func _on_laser_energy(val: float, val_max: float):
	if laser_bar:
		laser_bar.max_value = val_max
		laser_bar.value = val
		var fill := laser_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			var ratio := val / val_max
			if ratio > 0.3:
				fill.bg_color = Color(0.3, 0.85, 1.0)
			else:
				fill.bg_color = Color(1.0, 0.3, 0.2)


func _on_missiles(count: int):
	if missile_label:
		missile_label.text = "MISSILES: %d" % count


func _on_score(pts: int):
	if score_label:
		score_label.text = "SCORE: %d" % pts


func _on_hits(count: int):
	if hits_label:
		hits_label.text = "%03d" % count


func _on_lives(count: int):
	if lives_label:
		lives_label.text = "x %d" % count


func _on_phase(is_active: bool, ratio: float):
	if phase_bar == null or phase_status_label == null:
		return

	var fill := phase_bar.get_theme_stylebox("fill") as StyleBoxFlat

	if is_active:
		# Draining while active
		phase_bar.value = ratio
		phase_status_label.text = "PHASE [B]: ACTIVE"
		phase_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0))
		if fill:
			fill.bg_color = Color(0.3, 1.0, 1.0)
	elif ratio < 0:
		# Recharging on cooldown (ratio is negative, -1 = just started, 0 = ready)
		phase_bar.value = 1.0 + ratio  # converts -1..0 to 0..1
		phase_status_label.text = "PHASE [B]: RECHARGING"
		phase_status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		if fill:
			fill.bg_color = Color(0.4, 0.4, 0.6)
	else:
		# Ready
		phase_bar.value = 1.0
		phase_status_label.text = "PHASE [B]: READY"
		phase_status_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
		if fill:
			fill.bg_color = Color(0.3, 0.6, 1.0)


# ── Threat Indicator (shockwave proximity) ────────────────────

func _build_threat_indicator():
	threat_container = VBoxContainer.new()
	threat_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	threat_container.offset_top = 80
	threat_container.offset_left = 660
	threat_container.offset_right = -660
	threat_container.alignment = BoxContainer.ALIGNMENT_CENTER
	threat_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threat_container.visible = false
	add_child(threat_container)

	threat_label = Label.new()
	threat_label.text = "THREAT INCOMING — BOOST!"
	threat_label.add_theme_font_size_override("font_size", 18)
	threat_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	threat_container.add_child(threat_label)

	threat_bar = ProgressBar.new()
	threat_bar.custom_minimum_size = Vector2(300, 12)
	threat_bar.max_value = 1.0
	threat_bar.value = 0.5
	threat_bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.05, 0.05, 0.8)
	bg.border_color = Color(1.0, 0.3, 0.2, 0.6)
	bg.set_border_width_all(1)
	threat_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.3, 0.1)
	threat_bar.add_theme_stylebox_override("fill", fill)
	threat_container.add_child(threat_bar)


func update_threat(dist_behind: float, active: bool):
	if threat_container == null:
		return
	threat_container.visible = active
	if not active:
		return

	# dist_behind: how far ahead player is from shockwave (in world units)
	# Show as danger ratio: closer = more red, fuller bar
	var max_safe := 40.0
	var danger := clampf(1.0 - (dist_behind / max_safe), 0.0, 1.0)
	threat_bar.value = danger

	var fill := threat_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		# Green when far, yellow mid, red when close
		if danger < 0.4:
			fill.bg_color = Color(0.2, 0.8, 0.3)
		elif danger < 0.7:
			fill.bg_color = Color(1.0, 0.8, 0.1)
		else:
			fill.bg_color = Color(1.0, 0.2, 0.1)

	# Pulsing text when critical
	if danger > 0.7:
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.4) > 0.2
		threat_label.visible = blink
	else:
		threat_label.visible = true
