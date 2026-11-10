extends Node
## 저장·카트 목록·트랙 목록·지금 고른 경주 설정 (자동 로드 Game)

const SAVE_PATH := "user://toy_racing_save.json"

var karts: Array = []
var tracks: Array = []
var save: Dictionary = {}
var font: Font
var font_bold: Font

## 다음 경주 설정
var mode := "race"        # race(컴퓨터와 경주) / time(혼자 연습) / duo(둘이서)
var track_id := "acorn_road"
var duo_bots := true      # 둘이서 할 때 컴퓨터도 넣을지
var last_result: Dictionary = {}

func _ready() -> void:
	karts = JSON.parse_string(FileAccess.get_file_as_string("res://data/karts.json")).karts
	tracks = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks.json")).tracks
	font = load("res://assets/fonts/Galmuri11.ttf")
	font_bold = load("res://assets/fonts/Galmuri11-Bold.ttf")
	load_save()
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 20
	get_tree().root.theme = th

func kart_ids() -> Array:
	return karts.map(func(k): return k.id)

func kart_def(id: String) -> Dictionary:
	for k in karts:
		if k.id == id:
			return k
	return karts[0]

func track_def(id: String) -> Dictionary:
	for t in tracks:
		if t.id == id:
			return t
	return tracks[0]

func load_save() -> void:
	var raw: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		raw = FileAccess.get_file_as_string(SAVE_PATH)
	save = Rules.parse_save(raw, kart_ids())

func write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
		f.close()

func add_coins(n: int) -> void:
	save.coins = int(save.coins) + n
	write_save()

func try_buy(id: String) -> bool:
	var k := kart_def(id)
	if not Rules.can_buy(save, k):
		return false
	save = Rules.buy(save, k)
	write_save()
	return true

func choose(id: String, who := 1) -> void:
	if id in save.owned:
		save["kart" if who == 1 else "kart2"] = id
		write_save()

func best_of(track: String) -> float:
	return float(save.best.get(track, -1.0))

func set_best(track: String, t: float) -> void:
	save.best[track] = t
	write_save()

## 경주 끝: 돈과 기록을 저장하고 받은 돈을 돌려준다
func finish_race(result: Dictionary) -> void:
	last_result = result
	var got := 0
	for p in result.players:
		got += int(p.reward) + int(p.coins)
	if result.mode == "time" and result.players.size() > 0 and result.players[0].time > 0.0:
		var t: float = result.players[0].time
		var b := best_of(result.track)
		if b <= 0.0 or t < b:
			set_best(result.track, t)
	save.races = int(save.races) + 1
	add_coins(got)
	result["total"] = got
