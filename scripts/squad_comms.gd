extends Control
## Star Fox-style squad comms panel. Shows a character portrait with species
## initial, name, teammate shield bar, and typewriter-effect dialogue text.
## References Star Fox 64 comms: bottom-left box with portrait + health.

var panel: PanelContainer
var portrait_rect: ColorRect
var portrait_initial: Label
var name_label: Label
var dialogue_label: Label
var health_bar: ProgressBar
var health_label: Label

var display_time: float = 4.0
var timer: float = 0.0
var is_showing: bool = false

# Typewriter
var full_text: String = ""
var char_idx: int = 0
var type_speed: float = 0.03
var type_timer: float = 0.0

var queue: Array = []

# Character portrait colours (placeholder for real art)
var portrait_colors: Dictionary = {
	"Raze":  Color(0.3, 0.5, 0.9),
	"Kiro":  Color(0.6, 0.6, 0.7),
	"Nyx":   Color(0.9, 0.5, 0.2),
	"Bront": Color(0.6, 0.4, 0.2),
}

var species: Dictionary = {
	"Raze": "EAGLE", "Kiro": "WOLF", "Nyx": "FOX", "Bront": "BEAR",
}

# Squad health — each teammate has independent shield value
var squad_health: Dictionary = {
	"Kiro":  100.0,
	"Nyx":   100.0,
	"Bront": 100.0,
}
var squad_max_health: float = 100.0

var _current_character: String = ""


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	panel.visible = false


func _process(delta):
	if not is_showing:
		return

	# Typewriter advance
	type_timer -= delta
	if type_timer <= 0 and char_idx < full_text.length():
		char_idx += 1
		dialogue_label.text = full_text.substr(0, char_idx)
		type_timer = type_speed

	timer -= delta
	if timer <= 0:
		_hide()


func show_message(character: String, text: String, color: Color = Color.WHITE):
	if is_showing:
		queue.append({"who": character, "say": text, "clr": color})
		return
	_display(character, text, color)


func set_squad_damage(character: String, amount: float):
	if squad_health.has(character):
		squad_health[character] = maxf(0.0, squad_health[character] - amount)
		# Update bar if this character is currently shown
		if is_showing and _current_character == character:
			_update_health_display(character)


func get_squad_health(character: String) -> float:
	return squad_health.get(character, 0.0)


func _display(character: String, text: String, color: Color):
	is_showing = true
	_current_character = character
	timer = display_time
	full_text = text
	char_idx = 0
	type_timer = 0.0
	dialogue_label.text = ""

	name_label.text = character.to_upper()
	if species.has(character):
		name_label.text += "  [%s]" % species[character]

	portrait_rect.color = portrait_colors.get(character, color)

	# Set portrait initial (first letter of species)
	var sp: String = species.get(character, "?")
	portrait_initial.text = sp[0]

	# Update teammate health bar
	_update_health_display(character)

	panel.visible = true


func _update_health_display(character: String):
	if character == "Raze":
		# Player — hide squad health bar, player has their own HUD bar
		health_bar.visible = false
		health_label.visible = false
	else:
		health_bar.visible = true
		health_label.visible = true
		var hp: float = squad_health.get(character, 100.0)
		health_bar.value = hp
		health_bar.max_value = squad_max_health
		# Color by health ratio
		var fill := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			var ratio := hp / squad_max_health
			if ratio > 0.5:
				fill.bg_color = Color(0.2, 0.8, 0.3)
			elif ratio > 0.25:
				fill.bg_color = Color(1.0, 0.8, 0.1)
			else:
				fill.bg_color = Color(1.0, 0.2, 0.2)


func _hide():
	is_showing = false
	_current_character = ""
	panel.visible = false
	if queue.size() > 0:
		var nxt: Dictionary = queue.pop_front()
		_display(nxt["who"], nxt["say"], nxt["clr"])


func _build_panel():
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Anchor to bottom-left
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_top = -160
	panel.offset_right = 480
	panel.offset_bottom = -20

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.08, 0.94)
	style.border_color = Color(0.25, 0.6, 0.9, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Portrait side — colored square with species initial + health bar
	var pcont := VBoxContainer.new()
	pcont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pcont.custom_minimum_size = Vector2(90, 0)
	pcont.add_theme_constant_override("separation", 4)
	hbox.add_child(pcont)

	# Portrait with initial overlay
	var portrait_container := Control.new()
	portrait_container.custom_minimum_size = Vector2(90, 90)
	portrait_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pcont.add_child(portrait_container)

	portrait_rect = ColorRect.new()
	portrait_rect.custom_minimum_size = Vector2(90, 90)
	portrait_rect.size = Vector2(90, 90)
	portrait_rect.color = Color(0.5, 0.5, 0.5)
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_container.add_child(portrait_rect)

	# Border around portrait
	var portrait_border := ReferenceRect.new()
	portrait_border.custom_minimum_size = Vector2(90, 90)
	portrait_border.size = Vector2(90, 90)
	portrait_border.border_color = Color(0.4, 0.7, 1.0, 0.6)
	portrait_border.border_width = 2.0
	portrait_border.editor_only = false
	portrait_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_container.add_child(portrait_border)

	# Species initial centered in portrait
	portrait_initial = Label.new()
	portrait_initial.text = "?"
	portrait_initial.add_theme_font_size_override("font_size", 40)
	portrait_initial.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
	portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_initial.custom_minimum_size = Vector2(90, 90)
	portrait_initial.size = Vector2(90, 90)
	portrait_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_container.add_child(portrait_initial)

	# Teammate shield bar under portrait
	health_label = Label.new()
	health_label.text = "SHIELD"
	health_label.add_theme_font_size_override("font_size", 10)
	health_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 0.8))
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pcont.add_child(health_label)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(90, 8)
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.show_percentage = false

	var hb_bg := StyleBoxFlat.new()
	hb_bg.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	hb_bg.border_color = Color(0.3, 0.6, 0.3, 0.5)
	hb_bg.set_border_width_all(1)
	health_bar.add_theme_stylebox_override("background", hb_bg)

	var hb_fill := StyleBoxFlat.new()
	hb_fill.bg_color = Color(0.2, 0.8, 0.3)
	health_bar.add_theme_stylebox_override("fill", hb_fill)
	pcont.add_child(health_bar)

	# Text side
	var tcont := VBoxContainer.new()
	tcont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcont.add_theme_constant_override("separation", 6)
	hbox.add_child(tcont)

	name_label = Label.new()
	name_label.text = ""
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcont.add_child(name_label)

	dialogue_label = Label.new()
	dialogue_label.text = ""
	dialogue_label.add_theme_font_size_override("font_size", 18)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcont.add_child(dialogue_label)
