extends Node
## 화면 바꾸기: 메뉴(뒤에 3D 카트) ↔ 경주

const RACE := preload("res://scripts/race.gd")
const MENU := preload("res://scripts/menu.gd")
const BG := preload("res://scripts/menu_bg.gd")

var race: Node3D
var menu: Control
var bg: Node3D
var layer: CanvasLayer

func _ready() -> void:
	add_to_group("main")
	open_menu("title")
	Net.message.connect(_on_net)

## 친구(방장)가 출발을 누르면 바로 경주로
func _on_net(m: Dictionary) -> void:
	if m.get("y") == "go" and Net.role == "guest" and typeof(m.get("setup")) == TYPE_DICTIONARY:
		Game.online_setup = m.setup
		Game.mode = "online"
		Game.track_id = str(m.setup.track)
		start_race()

func _clear() -> void:
	for n in [race, bg, layer]:
		if is_instance_valid(n):
			n.queue_free()
	race = null
	bg = null
	layer = null
	menu = null
	get_tree().paused = false

func open_menu(screen: String) -> void:
	_clear()
	bg = BG.new()
	add_child(bg)
	layer = CanvasLayer.new()
	add_child(layer)
	menu = MENU.new()
	menu.bg = bg
	layer.add_child(menu)
	menu.show_screen(screen)
	Sound.music("title")

func start_race() -> void:
	_clear()
	race = RACE.new()
	race.done.connect(func(result: Dictionary):
		Game.finish_race(result)
		open_menu("results"))
	race.quit_race.connect(func(): open_menu("online" if Game.mode == "online" else "tracks"))
	add_child(race)
