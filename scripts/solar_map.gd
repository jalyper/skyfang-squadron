extends Control
## Solar system map. Player navigates nodes connected by paths, choosing which
## adjacent planet to tackle next. Beaten nodes glow, locked ones are dimmed.
## Must beat adjacent nodes to unlock new ones.
##
## Layout zigzags left-right across rows, from start (bottom) to final boss (top).

const LEVEL_SCENE = "res://scenes/main.tscn"

# ── Node definitions ──
# Each node: {id, name, subtitle, row, col, color, connections:[id...]}
# Row 0 = bottom (start), higher rows = deeper into system
# Col positions: 0=far left, 1=left, 2=center, 3=right, 4=far right
var map_nodes: Array = [
	{
		"id": "aethon", "name": "AETHON", "subtitle": "Homeworld",
		"row": 0, "col": 2, "color": Color(0.3, 0.6, 1.0),
		"connections": ["cindral", "glacivus"],
	},
	{
		"id": "cindral", "name": "CINDRAL", "subtitle": "Asteroid Field",
		"row": 1, "col": 1, "color": Color(0.6, 0.5, 0.4),
		"connections": ["bastion", "rift_alpha"],
	},
	{
		"id": "glacivus", "name": "GLACIVUS", "subtitle": "Ice Planet",
		"row": 1, "col": 3, "color": Color(0.7, 0.85, 1.0),
		"connections": ["bastion", "pyrrhon"],
	},
	{
		"id": "rift_alpha", "name": "RIFT ALPHA", "subtitle": "Combat Zone",
		"row": 2, "col": 0, "color": Color(0.9, 0.3, 0.3),
		"connections": ["forgekeep"],
	},
	{
		"id": "bastion", "name": "BASTION", "subtitle": "Frontline Base",
		"row": 2, "col": 2, "color": Color(0.4, 0.8, 0.4),
		"connections": ["forgekeep", "maravoss"],
	},
	{
		"id": "pyrrhon", "name": "PYRRHON", "subtitle": "Burning Star",
		"row": 2, "col": 4, "color": Color(1.0, 0.6, 0.1),
		"connections": ["maravoss"],
	},
	{
		"id": "forgekeep", "name": "FORGEKEEP", "subtitle": "Weapons Factory",
		"row": 3, "col": 1, "color": Color(0.5, 0.4, 0.3),
		"connections": ["dreadline", "ironveil"],
	},
	{
		"id": "maravoss", "name": "MARAVOSS", "subtitle": "Toxic Sea",
		"row": 3, "col": 3, "color": Color(0.2, 0.7, 0.5),
		"connections": ["ironveil", "rift_omega"],
	},
	{
		"id": "dreadline", "name": "DREADLINE", "subtitle": "Defense Fleet",
		"row": 4, "col": 1, "color": Color(0.7, 0.3, 0.6),
		"connections": ["tyranthos"],
	},
	{
		"id": "ironveil", "name": "IRONVEIL", "subtitle": "Space Station",
		"row": 4, "col": 2, "color": Color(0.5, 0.5, 0.7),
		"connections": ["tyranthos"],
	},
	{
		"id": "rift_omega", "name": "RIFT OMEGA", "subtitle": "Ambush Zone",
		"row": 4, "col": 4, "color": Color(0.8, 0.2, 0.2),
		"connections": ["tyranthos"],
	},
	{
		"id": "tyranthos", "name": "TYRANTHOS", "subtitle": "Final Assault",
		"row": 5, "col": 2, "color": Color(0.9, 0.15, 0.1),
		"connections": [],
	},
]

# Lookup
var node_by_id: Dictionary = {}
var node_positions: Dictionary = {}  # id → Vector2 screen position

# Selection
var selected_index: int = 0
var selectable_ids: Array = []
var cursor_tween: Tween = null

# UI refs
var map_layer: Control
var info_panel: PanelContainer
var info_name: Label
var info_subtitle: Label
var info_status: Label
var info_score: Label
var cursor_ring: Control
var path_overlay: Control

# Layout
var map_origin := Vector2(960, 820)  # bottom-center of map area
var row_spacing := 120.0
var col_width := 180.0
var node_radius := 28.0

# Animation
var _pulse_time: float = 0.0


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_index_nodes()
	_compute_positions()
	_determine_selectable()
	_build_background()
	_build_path_overlay()
	_build_nodes()
	_build_cursor()
	_build_info_panel()
	_build_title()
	_build_instructions()
	_update_selection()


func _process(delta):
	_pulse_time += delta
	if cursor_ring:
		cursor_ring.queue_redraw()
	if path_overlay:
		path_overlay.queue_redraw()
	_handle_input()


func _index_nodes():
	for n in map_nodes:
		node_by_id[n["id"]] = n


func _compute_positions():
	for n in map_nodes:
		var row: int = n["row"]
		var col: int = n["col"]
		var x := map_origin.x + (col - 2) * col_width
		var y := map_origin.y - row * row_spacing
		node_positions[n["id"]] = Vector2(x, y)


func _determine_selectable():
	selectable_ids.clear()

	# Start node is always selectable
	if not GameManager.is_level_beaten("aethon"):
		selectable_ids = ["aethon"]
		selected_index = 0
		return

	# Find all unbeaten nodes adjacent to any beaten node
	for n in map_nodes:
		if GameManager.is_level_beaten(n["id"]):
			continue
		# Check if any parent connects to this node
		var reachable := false
		for other in map_nodes:
			if not GameManager.is_level_beaten(other["id"]):
				continue
			if n["id"] in other["connections"]:
				reachable = true
				break
		if reachable:
			selectable_ids.append(n["id"])

	if selectable_ids.is_empty():
		# All beaten — allow replaying venom or show victory
		selectable_ids = ["tyranthos"]

	selected_index = 0


func _handle_input():
	if selectable_ids.is_empty():
		return

	var changed := false
	if Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("aim_right"):
		selected_index = (selected_index + 1) % selectable_ids.size()
		changed = true
	elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("aim_left"):
		selected_index = (selected_index - 1 + selectable_ids.size()) % selectable_ids.size()
		changed = true
	elif Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("aim_up"):
		# Try to select a node in a higher row
		_select_direction(-1)
		changed = true
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("aim_down"):
		_select_direction(1)
		changed = true

	if changed:
		_update_selection()

	if Input.is_action_just_pressed("ui_select") or Input.is_action_just_pressed("shoot"):
		_launch_level()


func _select_direction(row_delta: int):
	if selectable_ids.is_empty():
		return
	var current_id: String = selectable_ids[selected_index]
	var current_pos: Vector2 = node_positions[current_id]
	var current_row: int = node_by_id[current_id]["row"]
	var target_row := current_row - row_delta  # up = lower y = higher row number

	var best_idx := selected_index
	var best_dist := 99999.0
	for i in selectable_ids.size():
		var nid: String = selectable_ids[i]
		var n = node_by_id[nid]
		if row_delta < 0 and n["row"] > current_row:
			var d: float = absf(node_positions[nid].x - current_pos.x)
			if d < best_dist:
				best_dist = d
				best_idx = i
		elif row_delta > 0 and n["row"] < current_row:
			var d: float = absf(node_positions[nid].x - current_pos.x)
			if d < best_dist:
				best_dist = d
				best_idx = i
	selected_index = best_idx


func _update_selection():
	if selectable_ids.is_empty():
		return
	var sel_id: String = selectable_ids[selected_index]
	var pos: Vector2 = node_positions[sel_id]

	# Animate cursor to position
	if cursor_ring:
		if cursor_tween:
			cursor_tween.kill()
		cursor_tween = create_tween()
		cursor_tween.tween_property(cursor_ring, "position", pos - Vector2(40, 40), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Update info panel
	var n = node_by_id[sel_id]
	if info_name:
		info_name.text = n["name"]
	if info_subtitle:
		info_subtitle.text = n["subtitle"]
	if info_status:
		if GameManager.is_level_beaten(sel_id):
			var data = GameManager.beaten_levels[sel_id]
			info_status.text = "CLEARED"
			info_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
			if info_score:
				info_score.text = "Hits: %d  Score: %d" % [data.get("hits", 0), data.get("score", 0)]
				info_score.visible = true
		else:
			info_status.text = "READY"
			info_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
			if info_score:
				info_score.visible = false


func _launch_level():
	if selectable_ids.is_empty():
		return
	var sel_id: String = selectable_ids[selected_index]
	GameManager.current_level_id = sel_id
	get_tree().change_scene_to_file(LEVEL_SCENE)


# ── Drawing ───────────────────────────────────────────────────

func _build_background():
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.01, 0.04)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Scattered stars
	var star_layer := Control.new()
	star_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	star_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_layer.draw.connect(func():
		for i in 200:
			var sx := hash(i * 31) % 1920
			var sy := hash(i * 47 + 13) % 1080
			var brightness := 0.3 + fmod(float(hash(i * 73)) / 2147483647.0, 0.7)
			var sz := 1.0 + fmod(float(hash(i * 11)) / 2147483647.0, 1.5)
			star_layer.draw_circle(Vector2(sx, sy), sz, Color(brightness, brightness, brightness * 1.1, brightness))
	)
	add_child(star_layer)


func _build_path_overlay():
	path_overlay = Control.new()
	path_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	path_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	path_overlay.draw.connect(_draw_paths)
	add_child(path_overlay)


func _draw_paths():
	# Draw connection lines between nodes
	for n in map_nodes:
		var from_pos: Vector2 = node_positions[n["id"]]
		var from_beaten: bool = GameManager.is_level_beaten(n["id"])

		for conn_id in n["connections"]:
			var to_pos: Vector2 = node_positions[conn_id]
			var to_beaten: bool = GameManager.is_level_beaten(conn_id)

			var col: Color
			if from_beaten and to_beaten:
				# Both beaten — bright blue completed path
				col = Color(0.3, 0.6, 1.0, 0.9)
				path_overlay.draw_line(from_pos, to_pos, col, 3.0)
			elif from_beaten:
				# From beaten, to available — pulsing yellow
				var pulse := 0.5 + sin(_pulse_time * 3.0) * 0.3
				col = Color(1.0, 0.8, 0.2, pulse)
				path_overlay.draw_line(from_pos, to_pos, col, 2.5)
				# Animated dot traveling along the line
				var t := fmod(_pulse_time * 0.5, 1.0)
				var dot_pos := from_pos.lerp(to_pos, t)
				path_overlay.draw_circle(dot_pos, 4.0, Color(1.0, 0.9, 0.3, 0.8))
			else:
				# Both locked — dim gray
				col = Color(0.3, 0.3, 0.4, 0.25)
				path_overlay.draw_dashed_line(from_pos, to_pos, col, 1.5, 8.0)


func _build_nodes():
	for n in map_nodes:
		var pos: Vector2 = node_positions[n["id"]]
		var is_beaten: bool = GameManager.is_level_beaten(n["id"])
		var is_selectable: bool = n["id"] in selectable_ids

		# Planet circle
		var planet := Control.new()
		planet.position = pos - Vector2(node_radius, node_radius)
		planet.custom_minimum_size = Vector2(node_radius * 2, node_radius * 2)
		planet.size = Vector2(node_radius * 2, node_radius * 2)
		planet.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var node_color: Color = n["color"]
		var beaten := is_beaten
		var selectable := is_selectable

		planet.draw.connect(func():
			var center := Vector2(node_radius, node_radius)
			if beaten:
				# Beaten — solid bright with checkmark glow
				planet.draw_circle(center, node_radius, node_color)
				planet.draw_arc(center, node_radius, 0, TAU, 32, Color(0.5, 0.9, 1.0, 0.6), 2.0)
				# Small check mark
				var ck := center + Vector2(-6, 2)
				planet.draw_line(ck, ck + Vector2(4, 4), Color.WHITE, 2.5)
				planet.draw_line(ck + Vector2(4, 4), ck + Vector2(12, -8), Color.WHITE, 2.5)
			elif selectable:
				# Available — solid with pulsing outline
				planet.draw_circle(center, node_radius, node_color * 0.8)
				planet.draw_arc(center, node_radius, 0, TAU, 32, Color(1.0, 0.9, 0.3, 0.7), 2.0)
			else:
				# Locked — dim and gray
				var dim := Color(node_color.r * 0.25, node_color.g * 0.25, node_color.b * 0.25, 0.5)
				planet.draw_circle(center, node_radius * 0.8, dim)
				planet.draw_arc(center, node_radius * 0.8, 0, TAU, 32, Color(0.3, 0.3, 0.3, 0.3), 1.0)
		)
		add_child(planet)

		# Node name label below
		var lbl := Label.new()
		lbl.text = n["name"]
		lbl.add_theme_font_size_override("font_size", 11)
		var label_alpha := 1.0 if (is_beaten or is_selectable) else 0.35
		lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, label_alpha))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(pos.x - 50, pos.y + node_radius + 4)
		lbl.custom_minimum_size = Vector2(100, 0)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)


func _build_cursor():
	cursor_ring = Control.new()
	cursor_ring.custom_minimum_size = Vector2(80, 80)
	cursor_ring.size = Vector2(80, 80)
	cursor_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_ring.draw.connect(func():
		var center := Vector2(40, 40)
		var r := node_radius + 8.0
		var pulse := 0.6 + sin(_pulse_time * 4.0) * 0.4
		var col := Color(1.0, 1.0, 0.3, pulse)
		cursor_ring.draw_arc(center, r, 0, TAU, 48, col, 3.0)
		# Corner brackets
		var bk := r + 6.0
		var bl := 10.0
		var bc := Color(1.0, 0.9, 0.2, 0.8)
		cursor_ring.draw_line(center + Vector2(-bk, -bk), center + Vector2(-bk + bl, -bk), bc, 2.0)
		cursor_ring.draw_line(center + Vector2(-bk, -bk), center + Vector2(-bk, -bk + bl), bc, 2.0)
		cursor_ring.draw_line(center + Vector2(bk, -bk), center + Vector2(bk - bl, -bk), bc, 2.0)
		cursor_ring.draw_line(center + Vector2(bk, -bk), center + Vector2(bk, -bk + bl), bc, 2.0)
		cursor_ring.draw_line(center + Vector2(-bk, bk), center + Vector2(-bk + bl, bk), bc, 2.0)
		cursor_ring.draw_line(center + Vector2(-bk, bk), center + Vector2(-bk, bk - bl), bc, 2.0)
		cursor_ring.draw_line(center + Vector2(bk, bk), center + Vector2(bk - bl, bk), bc, 2.0)
		cursor_ring.draw_line(center + Vector2(bk, bk), center + Vector2(bk, bk - bl), bc, 2.0)
	)
	add_child(cursor_ring)

	# Initial position
	if selectable_ids.size() > 0:
		var pos: Vector2 = node_positions[selectable_ids[0]]
		cursor_ring.position = pos - Vector2(40, 40)


func _build_info_panel():
	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	info_panel.offset_right = -40
	info_panel.offset_bottom = -40
	info_panel.offset_left = -340
	info_panel.offset_top = -160

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.08, 0.92)
	style.border_color = Color(0.25, 0.6, 0.9, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16)
	info_panel.add_theme_stylebox_override("panel", style)
	add_child(info_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	info_panel.add_child(vbox)

	info_name = Label.new()
	info_name.text = ""
	info_name.add_theme_font_size_override("font_size", 28)
	info_name.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	vbox.add_child(info_name)

	info_subtitle = Label.new()
	info_subtitle.text = ""
	info_subtitle.add_theme_font_size_override("font_size", 16)
	info_subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	vbox.add_child(info_subtitle)

	info_status = Label.new()
	info_status.text = ""
	info_status.add_theme_font_size_override("font_size", 20)
	vbox.add_child(info_status)

	info_score = Label.new()
	info_score.text = ""
	info_score.add_theme_font_size_override("font_size", 14)
	info_score.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	info_score.visible = false
	vbox.add_child(info_score)


func _build_title():
	var title := Label.new()
	title.text = "SKYFANG SQUADRON"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 30
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# Total score
	var score_lbl := Label.new()
	score_lbl.text = "TOTAL SCORE: %d" % GameManager.total_score
	score_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	score_lbl.offset_top = 72
	score_lbl.add_theme_font_size_override("font_size", 18)
	score_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.3))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score_lbl)

	# Lives
	var lives_lbl := Label.new()
	lives_lbl.text = "> x %d" % GameManager.lives
	lives_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lives_lbl.offset_top = 30
	lives_lbl.offset_right = -40
	lives_lbl.offset_left = -120
	lives_lbl.add_theme_font_size_override("font_size", 22)
	lives_lbl.add_theme_color_override("font_color", Color.WHITE)
	lives_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lives_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lives_lbl)


func _build_instructions():
	var hint := Label.new()
	hint.text = "[A / Enter] Launch    [D-pad / Stick] Navigate"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_bottom = -12
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
