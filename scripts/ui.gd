class_name UI
extends RefCounted
## 메뉴 단추·글자 모양을 한곳에서

const WOOD := Color(0.55, 0.36, 0.2)
const CREAM := Color(1.0, 0.96, 0.86)
const LEAF := Color(0.27, 0.55, 0.3)
const INK := Color(0.16, 0.11, 0.08)

static func box(c: Color, radius := 14, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

static func button(text: String, on_press: Callable, width := 280, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 58)
	b.add_theme_font_override("font", Game.font_bold)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", box(CREAM, 16, WOOD, 4))
	b.add_theme_stylebox_override("hover", box(Color(1.0, 0.9, 0.65), 16, WOOD, 4))
	b.add_theme_stylebox_override("pressed", box(Color(0.98, 0.78, 0.45), 16, WOOD, 4))
	b.add_theme_stylebox_override("focus", box(Color(1, 1, 1, 0), 16, Color(1.0, 0.55, 0.15), 5))
	b.add_theme_stylebox_override("disabled", box(Color(0.75, 0.72, 0.66), 16, Color(0.5, 0.45, 0.4), 4))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, INK)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.37, 0.33))
	b.pressed.connect(func():
		Sound.play("click")
		on_press.call())
	b.focus_entered.connect(func(): Sound.play("tick"))
	return b

static func label(text: String, size := 22, color := CREAM, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if bold:
		l.add_theme_font_override("font", Game.font_bold)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	return l

static func panel(c := Color(0.12, 0.2, 0.13, 0.82)) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(c, 18)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", s)
	return p
