extends Control
## 경주 중 멈춤 (Esc / P)

var race: Node
var box: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.06, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var t := Label.new()
	t.text = "잠깐 멈춤"
	t.add_theme_font_override("font", Game.font_bold)
	t.add_theme_font_size_override("font_size", 48)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var items := [["계속 달리기", _resume], ["그만두기", _quit]] if race.online else [["계속 달리기", _resume], ["처음부터 다시", _restart], ["그만두기", _quit]]
	for pair in items:
		var b := UI.button(pair[0], pair[1], 320)
		box.add_child(b)

func open() -> void:
	visible = true
	if not race.online:   # 온라인은 친구 화면이 계속 달리므로 멈추지 않는다
		get_tree().paused = true
		Sound.pause_loops(true)
	(box.get_child(1) as Button).grab_focus()

func _unhandled_input(e: InputEvent) -> void:
	if visible and (e.is_action_pressed("ui_cancel") or (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_P)):
		_resume()
		get_viewport().set_input_as_handled()

func _resume() -> void:
	visible = false
	get_tree().paused = false
	Sound.pause_loops(false)

func _restart() -> void:
	_resume()
	get_tree().get_first_node_in_group("main").start_race()

func _quit() -> void:
	_resume()
	race.leave()
