class_name MenuStyle
extends RefCounted
## Shared look of the menus (built in code): a soft panel, large friendly buttons and titles.

## Panel background.
const PANEL: Color = Color(0.1, 0.12, 0.1, 0.62)
## Text colour.
const TEXT: Color = Color(1.0, 0.98, 0.92)
## Seconds a menu page takes to fade in.
const FADE_SECONDS: float = 0.15


## A button labelled [param text] named [param node_name].
static func button(text: String, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(280, 52)
	b.add_theme_font_size_override(&"font_size", 24)
	return b


## A label of [param size] points.
static func label(text: String, size: int, node_name: String = "") -> Label:
	var l := Label.new()
	if node_name != "":
		l.name = node_name
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", TEXT)
	l.add_theme_color_override(&"font_outline_color", Color(0.1, 0.12, 0.1, 0.8))
	l.add_theme_constant_override(&"outline_size", maxi(4, size / 6))
	return l


## A centred panel with a vertical box inside (returned).
static func centred_box(parent: Control, node_name: String) -> VBoxContainer:
	var centre := CenterContainer.new()
	centre.name = node_name
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(centre)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(16)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override(&"panel", style)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	panel.add_child(box)
	return box


## Fades [param control] in from transparent (also while the game is paused).
static func fade_in(control: Control) -> Tween:
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, ^"modulate:a", 1.0, FADE_SECONDS)
	return tween
