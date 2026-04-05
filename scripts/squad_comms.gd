extends Control
## Star Fox-style squad comms panel. Shows a character portrait (coloured
## placeholder) with name and typewriter-effect dialogue text.

var panel: PanelContainer
var portrait_rect: ColorRect
var name_label: Label
var dialogue_label: Label

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


func _display(character: String, text: String, color: Color):
	is_showing = true
	timer = display_time
	full_text = text
	char_idx = 0
	type_timer = 0.0
	dialogue_label.text = ""

	name_label.text = character.to_upper()
	if species.has(character):
		name_label.text += "  [%s]" % species[character]

	portrait_rect.color = portrait_colors.get(character, color)
	panel.visible = true


func _hide():
	is_showing = false
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
	panel.offset_top = -140
	panel.offset_right = 460
	panel.offset_bottom = -20

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.12, 0.92)
	style.border_color = Color(0.3, 0.7, 1.0, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	# Portrait placeholder
	var pcont := VBoxContainer.new()
	pcont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pcont.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(pcont)

	portrait_rect = ColorRect.new()
	portrait_rect.custom_minimum_size = Vector2(80, 80)
	portrait_rect.color = Color(0.5, 0.5, 0.5)
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pcont.add_child(portrait_rect)

	# Text side
	var tcont := VBoxContainer.new()
	tcont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(tcont)

	name_label = Label.new()
	name_label.text = ""
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcont.add_child(name_label)

	dialogue_label = Label.new()
	dialogue_label.text = ""
	dialogue_label.add_theme_font_size_override("font_size", 16)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcont.add_child(dialogue_label)
