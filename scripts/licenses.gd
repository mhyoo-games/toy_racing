extends Control
## 만든 것들·라이선스 화면 (Godot 엔진과 그 안의 라이브러리, 글꼴, 그림 표시).
## 쓰는 법: var l = preload("res://scripts/licenses.gd").new(); l.credits = [...]; l.font_size = 16; add_child(l)
## 닫히면 `closed` 신호. Esc·X·Z·Enter·Backspace로 닫고 ↑↓ PageUp/PageDown으로 넘긴다.

signal closed

var credits: Array = []
var font_size := 16
var font: Font = null   ## 따로 줄 글꼴 (프로젝트 기본 글꼴이 없을 때)
var text_box: RichTextLabel

func _ready() -> void:
	name = "Licenses"
	# 부모 크기와 상관없이 화면 전체를 덮는다
	top_level = true
	position = Vector2.ZERO
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if font:
		var th := Theme.new()
		th.default_font = font
		theme = th
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := float(font_size)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = m
	col.offset_right = -m
	col.offset_top = m * 0.6
	col.offset_bottom = -m * 0.6
	col.add_theme_constant_override("separation", int(m * 0.4))
	add_child(col)
	var title := Label.new()
	title.text = "만든 것들 · 라이선스"
	title.add_theme_font_size_override("font_size", int(m * 1.4))
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	col.add_child(title)
	text_box = RichTextLabel.new()
	text_box.bbcode_enabled = false
	text_box.scroll_active = true
	text_box.selection_enabled = false
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.add_theme_font_size_override("normal_font_size", int(m))
	text_box.add_theme_color_override("default_color", Color(0.9, 0.92, 0.96))
	text_box.text = full_text(credits)
	col.add_child(text_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(m))
	col.add_child(row)
	var hint := Label.new()
	hint.text = "↑↓ 넘기기 · Esc 닫기"
	hint.add_theme_font_size_override("font_size", int(m * 0.85))
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	var close := Button.new()
	close.text = "닫기"
	close.add_theme_font_size_override("font_size", int(m))
	close.pressed.connect(_close)
	row.add_child(close)

func _close() -> void:
	closed.emit()
	queue_free()

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	var bar := text_box.get_v_scroll_bar()
	match (e as InputEventKey).physical_keycode:
		KEY_ESCAPE, KEY_X, KEY_Z, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE, KEY_SPACE:
			_close()
		KEY_UP:
			bar.value -= font_size * 3
		KEY_DOWN:
			bar.value += font_size * 3
		KEY_PAGEUP:
			bar.value -= text_box.size.y * 0.9
		KEY_PAGEDOWN:
			bar.value += text_box.size.y * 0.9
	get_viewport().set_input_as_handled()

## 보여 줄 글 전부
static func full_text(credits: Array) -> String:
	var t := ""
	for c in credits:
		t += "• " + str(c) + "\n"
	t += "\n────────────────────────\n"
	t += "This game uses Godot Engine, available under the following license:\n\n"
	t += Engine.get_license_text()
	t += "\n\n────────────────────────\n"
	t += "Godot Engine에 들어 있는 다른 소프트웨어 (Third-party licenses)\n"
	t += "Portions of this software are copyright © The FreeType Project (www.freetype.org). All rights reserved.\n"
	for info in Engine.get_copyright_info():
		t += "\n- " + str(info.get("name", ""))
		for part in info.get("parts", []):
			for line in part.get("copyright", []):
				t += "\n    © " + str(line)
			t += "\n    License: " + str(part.get("license", ""))
	var lic: Dictionary = Engine.get_license_info()
	for key in lic:
		t += "\n\n==== " + str(key) + " ====\n" + str(lic[key])
	# 글꼴 라이선스 전문
	for path in ["res://assets/fonts/OFL.txt"]:
		if FileAccess.file_exists(path):
			t += "\n\n────────────────────────\n갈무리(Galmuri) 글꼴 라이선스\n" + FileAccess.get_file_as_string(path)
	return t
