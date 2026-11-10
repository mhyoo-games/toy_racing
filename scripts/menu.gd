extends Control
## 처음 화면·트랙 고르기·차고(카트 사기)·결과·조작 방법

var bg: Node3D
var screen := "title"
var garage_who := 1
var garage_pick := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("title")

func show_screen(s: String) -> void:
	screen = s
	for c in get_children():
		c.queue_free()
	if bg:
		bg.frame(s == "garage")
		bg.show_kart(Game.save.kart if garage_pick == "" or s != "garage" else garage_pick)
	match s:
		"title": _title()
		"tracks": _tracks()
		"online": _online()
		"garage": _garage()
		"results": _results()
		"help": _help()

## 오른쪽 위·아래에 붙이기 (anchor 기준 offset)
func _pin(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_BOTTOM_RIGHT else Control.GROW_DIRECTION_END

func _coins_badge() -> void:
	var p := UI.panel(Color(0.2, 0.13, 0.07, 0.8))
	_pin(p, Control.PRESET_TOP_RIGHT, -280, 18, -24, 70)
	var l := UI.label("● %d 코인" % int(Game.save.coins), 26, Color(1.0, 0.82, 0.3), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(l)
	add_child(p)

func _column(x := 60.0, y := 0.0) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.position = Vector2(x, y)
	add_child(v)
	return v

func _focus_first(v: Control) -> void:
	for c in v.find_children("*", "Button", true, false):
		if not (c as Button).disabled:
			(c as Button).call_deferred("grab_focus")
			return

# ───────── 처음 화면

func _title() -> void:
	_coins_badge()
	var v := _column(70, 34)
	v.add_theme_constant_override("separation", 9)
	var t := UI.label("토이 레이싱", 80, Color(1.0, 0.93, 0.6), true)
	v.add_child(t)
	v.add_child(UI.label("숲속 장난감 카트 경주", 26, UI.CREAM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	v.add_child(UI.button("경주하기", func(): _pick_mode("race"), 340))
	v.add_child(UI.button("혼자 연습 (기록 도전)", func(): _pick_mode("time"), 340))
	v.add_child(UI.button("둘이서 (화면 나누기)", func(): _pick_mode("duo"), 340))
	v.add_child(UI.button("친구와 온라인 (코드로 연결)", func(): Game.mode = "online"; show_screen("online"), 340))
	v.add_child(UI.button("차고 · 카트 상점", func(): garage_who = 1; garage_pick = ""; show_screen("garage"), 340))
	v.add_child(UI.button("조작 방법", func(): show_screen("help"), 340))
	var snd := UI.button("소리: " + ("끔" if Sound.muted else "켬"), func(): pass, 340)
	snd.pressed.connect(func():
		Sound.set_muted(not Sound.muted)
		snd.text = "소리: " + ("끔" if Sound.muted else "켬"))
	v.add_child(snd)
	var k := Game.kart_def(Game.save.kart)
	var info := UI.label("타는 카트: " + k.name, 24, UI.CREAM, true)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(info)
	_pin(info, Control.PRESET_BOTTOM_RIGHT, -420, -70, -30, -30)
	_focus_first(v)

func _pick_mode(m: String) -> void:
	Game.mode = m
	show_screen("tracks")

# ───────── 트랙 고르기

func _tracks() -> void:
	_coins_badge()
	var titles := {"race": "경주하기 — 컴퓨터 7명과 3바퀴", "time": "혼자 연습 — 기록을 깨면 코인", "duo": "둘이서 — 위아래 화면 나누기"}
	var v := _column(60, 40)
	v.add_child(UI.label(titles[Game.mode], 40, Color(1.0, 0.93, 0.6), true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	v.add_child(row)
	for t in Game.tracks:
		var p := UI.panel()
		p.custom_minimum_size = Vector2(360, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		p.add_child(col)
		col.add_child(UI.label(t.name, 32, UI.CREAM, true))
		col.add_child(UI.label("난이도 " + "★".repeat(int(t.level)) + "☆".repeat(3 - int(t.level)), 22, Color(1.0, 0.82, 0.3)))
		var map := TrackMap.new()
		map.def = t
		map.custom_minimum_size = Vector2(300, 190)
		col.add_child(map)
		var d := UI.label(t.desc, 19, Color(0.92, 0.95, 0.88))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 52)
		col.add_child(d)
		col.add_child(UI.label("최고 기록 " + Rules.time_text(Game.best_of(t.id)), 20, Color(0.8, 0.9, 1.0)))
		col.add_child(UI.button("달리기", func(): _go(t.id), 300))
		row.add_child(p)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	bottom.add_child(UI.button("← 뒤로", func(): show_screen("title"), 200))
	if Game.mode == "duo":
		var b := UI.button("", func(): pass, 360)
		var upd := func(): b.text = "컴퓨터도 같이: " + ("함께" if Game.duo_bots else "둘만")
		upd.call()
		b.pressed.connect(func():
			Game.duo_bots = not Game.duo_bots
			upd.call())
		bottom.add_child(b)
		bottom.add_child(UI.button("카트 고르기", func(): garage_who = 1; garage_pick = ""; show_screen("garage"), 220))
	_focus_first(row)

func _go(id: String) -> void:
	Game.track_id = id
	get_tree().get_first_node_in_group("main").start_race()

# ───────── 차고

func _garage() -> void:
	_coins_badge()
	var cur: String = Game.save.kart if garage_who == 1 else Game.save.kart2
	if garage_pick == "":
		garage_pick = cur
	bg.show_kart(garage_pick)
	var v := _column(50, 30)
	v.add_child(UI.label("차고" + ("  —  %dP 카트" % garage_who if Game.mode == "duo" else ""), 44, Color(1.0, 0.93, 0.6), true))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	v.add_child(list)
	var first: Button = null
	for k in Game.karts:
		var owned: bool = k.id in Game.save.owned
		var tag := ("  ★ 타는 중" if k.id == cur else ("  가짐" if owned else "  ● %d" % int(k.price)))
		var b := UI.button(k.name + tag, func(): garage_pick = k.id; show_screen("garage"), 330, 22)
		b.custom_minimum_size.y = 48
		if k.id == garage_pick:
			b.add_theme_stylebox_override("normal", UI.box(Color(1.0, 0.85, 0.55), 16, UI.WOOD, 4))
			first = b
		list.add_child(b)
	# 능력치
	var k := Game.kart_def(garage_pick)
	var p := UI.panel()
	p.custom_minimum_size = Vector2(480, 0)
	add_child(p)
	_pin(p, Control.PRESET_BOTTOM_RIGHT, -500, -420, -30, -24)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	col.add_child(UI.label(k.name, 34, UI.CREAM, true))
	var d := UI.label(k.desc, 19, Color(0.92, 0.95, 0.88))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(420, 0)
	col.add_child(d)
	var names := {"speed": "최고 속도", "accel": "가속", "handling": "핸들링", "drift": "드리프트", "boost": "부스터", "weight": "무게"}
	for s in names:
		var r := HBoxContainer.new()
		var l := UI.label(names[s], 20, UI.CREAM)
		l.custom_minimum_size = Vector2(110, 0)
		r.add_child(l)
		var bar := StatBar.new()
		bar.value = float(k.stats[s]) / 10.0
		bar.custom_minimum_size = Vector2(300, 22)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(bar)
		col.add_child(r)
	var owned2: bool = k.id in Game.save.owned
	var act: Button
	if owned2:
		act = UI.button("이 카트 타기" if k.id != cur else "타는 중", func():
			Game.choose(k.id, garage_who)
			show_screen("garage"), 420)
		act.disabled = k.id == cur
	else:
		act = UI.button("사기  ● %d" % int(k.price), func():
			var p1: String = Game.save.kart
			if Game.try_buy(k.id):
				Sound.play("buy")
				if garage_who == 2:
					Game.save.kart = p1
					Game.choose(k.id, 2)
				show_screen("garage")
			else:
				Sound.play("nope"), 420)
		if int(Game.save.coins) < int(k.price):
			act.text = "코인이 모자라요 (● %d)" % int(k.price)
			act.disabled = true
	col.add_child(act)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	bottom.add_child(UI.button("← 뒤로", func(): show_screen({"duo": "tracks", "online": "online"}.get(Game.mode, "title")), 160))
	if Game.mode == "duo":
		bottom.add_child(UI.button("1P", func(): garage_who = 1; garage_pick = ""; show_screen("garage"), 80))
		bottom.add_child(UI.button("2P", func(): garage_who = 2; garage_pick = ""; show_screen("garage"), 80))
	if first:
		first.call_deferred("grab_focus")

# ───────── 결과

func _results() -> void:
	var r: Dictionary = Game.last_result
	if r.is_empty():
		show_screen("title")
		return
	_coins_badge()
	var v := _column(60, 30)
	v.add_child(UI.label(r.track_name + " — 결과", 42, Color(1.0, 0.93, 0.6), true))
	var p := UI.panel()
	v.add_child(p)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 4)
	p.add_child(grid)
	for h in ["순위", "이름", "카트", "시간"]:
		grid.add_child(UI.label(h, 20, Color(0.8, 0.9, 1.0), true))
	for row in r.table:
		var c: Color = Color(1.0, 0.9, 0.35) if row.human else UI.CREAM
		grid.add_child(UI.label("%d" % row.place, 24, c, row.human))
		grid.add_child(UI.label(row.name, 24, c, row.human))
		grid.add_child(UI.label(row.kart, 22, c))
		grid.add_child(UI.label(Rules.time_text(row.time), 22, c))
	for pl in r.players:
		var txt := "%s  %s" % [pl.name, ("%d등" % pl.place) if r.racers > 1 else Rules.time_text(pl.time)]
		txt += "   보상 ● %d   주운 코인 ● %d" % [pl.reward, pl.coins]
		v.add_child(UI.label(txt, 26, Color(1.0, 0.82, 0.3), true))
	if r.mode == "time":
		v.add_child(UI.label("최고 기록 " + Rules.time_text(Game.best_of(r.track)), 24, Color(0.8, 0.9, 1.0)))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	v.add_child(row2)
	if r.mode == "online":
		row2.add_child(UI.button("대기실로", func(): show_screen("online"), 240))
	else:
		row2.add_child(UI.button("다시 달리기", func(): get_tree().get_first_node_in_group("main").start_race(), 240))
	row2.add_child(UI.button("다른 트랙", func(): show_screen("tracks"), 200))
	row2.add_child(UI.button("차고", func(): garage_who = 1; garage_pick = ""; show_screen("garage"), 140))
	row2.add_child(UI.button("처음 화면", func(): show_screen("title"), 180))
	_focus_first(row2)

# ───────── 조작 방법

func _help() -> void:
	var v := _column(60, 36)
	v.add_child(UI.label("조작 방법", 44, Color(1.0, 0.93, 0.6), true))
	var p := UI.panel()
	v.add_child(p)
	var lines := [
		["혼자", "방향키(또는 WASD) 달리기·핸들 / Shift 드리프트 / Ctrl·Space 부스터"],
		["둘이서 1P", "WASD / 왼쪽 Shift 드리프트 / Space 부스터"],
		["둘이서 2P", "방향키 / 오른쪽 Shift 또는 / 드리프트 / 오른쪽 Ctrl·Enter 또는 . 부스터"],
		["게임패드", "스틱·십자키 핸들 / A·RT 가속 / B·LT 브레이크 / X·RB 드리프트 / Y·LB 부스터"],
		["휴대폰", "◀ ▶ 핸들, 드리프트·부스터·브레이크 버튼 (가속은 저절로)"],
		["", ""],
		["드리프트", "굽이에서 방향키 + Shift. 키를 놓아도 미끄러지고, 반대로 꺾으면 펴진다. 게이지가 차면 부스터 +1 (두 개까지)"],
		["순간부스터", "드리프트가 끝나는 순간(‘지금 ↑!’) ↑를 다시 누르면 짧게 빨라진다"],
		["출발 부스터", "출발 신호가 ‘1’에서 꺼지기 직전에 ↑를 누르고 있으면 빨리 튀어 나간다"],
		["인코스·아웃코스", "굽이 안쪽을 스치면 길이 짧다. 바깥에서 들어가 안쪽을 찍고 다시 바깥으로"],
		["커팅", "잔디는 느리지만 부스터를 쓰면 덜 느리다. 굽이 안쪽 잔디를 부스터로 가로지르자"],
		["멈춤", "Esc 또는 P"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	p.add_child(grid)
	for l in lines:
		grid.add_child(UI.label(l[0], 21, Color(1.0, 0.82, 0.3), true))
		var d := UI.label(l[1], 20, UI.CREAM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(880, 0)
		grid.add_child(d)
	var back := UI.button("← 뒤로", func(): show_screen("title"), 200)
	v.add_child(back)
	back.call_deferred("grab_focus")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and screen != "title" and screen != "online":
		show_screen("title" if screen != "garage" or Game.mode != "duo" else "tracks")
		get_viewport().set_input_as_handled()

# ───────── 친구와 온라인

var _box_in: CodeBox
var _online_track := ""
var _online_bots := true

func _ready_online() -> void:
	if not Net.changed.is_connected(_net_changed):
		Net.changed.connect(_net_changed)

func _net_changed() -> void:
	if screen == "online" and is_inside_tree():
		show_screen("online")

func _online() -> void:
	_ready_online()
	_coins_badge()
	var v := _column(60, 34)
	v.add_theme_constant_override("separation", 12)
	v.add_child(UI.label("친구와 온라인", 44, Color(1.0, 0.93, 0.6), true))
	var p := UI.panel()
	p.custom_minimum_size = Vector2(900, 0)
	v.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	p.add_child(col)
	var say := func(t: String, c := UI.CREAM, size := 22) -> Label:
		var l := UI.label(t, size, c)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(840, 0)
		col.add_child(l)
		return l
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var add_box := func(readonly: bool, ph: String) -> CodeBox:
		var b := CodeBox.new()
		b.readonly = readonly
		b.placeholder = ph
		b.custom_minimum_size = Vector2(840, 120)
		col.add_child(b)
		return b
	var st := Net.status
	if Net.error_text != "":
		say.call(Net.error_text, Color(1.0, 0.6, 0.5))
	if st in ["idle", "error", "closed"] and Net.role == "":
		say.call("서버 없이 브라우저끼리 바로 연결해요. 한 사람이 방을 만들고 초대 코드를 메신저로 보내면, 친구가 답장 코드를 돌려보내요.")
		if st == "closed":
			say.call("친구와 연결이 끊겼어요.", Color(1.0, 0.6, 0.5))
		row.add_child(UI.button("방 만들기", func(): Net.host(), 260))
		row.add_child(UI.button("방 들어가기", func(): Net.role = "join"; show_screen("online"), 260))
		col.add_child(row)
	elif Net.role == "join":
		say.call("① 친구에게 받은 초대 코드를 아래에 붙여 넣으세요.")
		_box_in = add_box.call(false, "TR1- 로 시작하는 초대 코드")
		row.add_child(UI.button("붙여넣기", func(): _box_in.paste(), 180))
		row.add_child(UI.button("확인", func():
			if not Net.join(_box_in.get_text()):
				Net.role = "join"
				show_screen("online"), 180))
		col.add_child(row)
	elif st == "making":
		say.call("연결 코드를 만드는 중이에요…")
	elif st == "code" and Net.role == "host":
		say.call("① 이 초대 코드를 복사해서 친구에게 보내세요.")
		var mine: CodeBox = add_box.call(true, "")
		mine.custom_minimum_size.y = 90
		mine.set_text(Net.my_code)
		var r1 := HBoxContainer.new()
		r1.add_child(UI.button("초대 코드 복사", func(): mine.copy(), 260))
		col.add_child(r1)
		say.call("② 친구가 보낸 답장 코드를 붙여 넣고 ‘연결’을 누르세요.")
		_box_in = add_box.call(false, "TR1- 로 시작하는 답장 코드")
		_box_in.custom_minimum_size.y = 90
		row.add_child(UI.button("붙여넣기", func(): _box_in.paste(), 180))
		row.add_child(UI.button("연결", func(): Net.accept(_box_in.get_text()), 180))
		col.add_child(row)
	elif st == "connecting" and Net.role == "guest" and Net.my_code != "":
		say.call("② 이 답장 코드를 복사해서 방장에게 보내세요. 방장이 넣으면 연결돼요.")
		var mine2: CodeBox = add_box.call(true, "")
		mine2.set_text(Net.my_code)
		row.add_child(UI.button("답장 코드 복사", func(): mine2.copy(), 260))
		col.add_child(row)
		say.call("연결을 기다리는 중…", Color(0.8, 0.9, 1.0))
	elif st == "connecting":
		say.call("연결하는 중이에요…")
	elif st == "connected":
		say.call("연결됐어요!", Color(0.6, 1.0, 0.6), 30)
		var theirs := str(Net.peer.get("kart", ""))
		say.call("내 카트: %s   ·   친구 카트: %s" % [Game.kart_def(Game.save.kart).name, Game.kart_def(theirs).name if theirs != "" else "…"])
		if Net.role == "host":
			if _online_track == "":
				_online_track = Game.tracks[0].id
			say.call("트랙을 고르고 ‘출발’을 누르세요.")
			var tr_row := HBoxContainer.new()
			tr_row.add_theme_constant_override("separation", 10)
			for t in Game.tracks:
				var b := UI.button(("★ " if t.id == _online_track else "") + t.name, func(): _online_track = t.id; show_screen("online"), 270, 22)
				tr_row.add_child(b)
			col.add_child(tr_row)
			var bots := UI.button("컴퓨터도 같이: " + ("함께" if _online_bots else "둘만"), func(): _online_bots = not _online_bots; show_screen("online"), 300, 22)
			row.add_child(bots)
			row.add_child(UI.button("출발!", _online_go, 200))
			col.add_child(row)
		else:
			say.call("방장이 트랙을 고르고 출발하면 바로 시작해요.", Color(0.8, 0.9, 1.0))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	bottom.add_child(UI.button("← 처음 화면", func():
		if Net.status != "connected":
			Net.reset()
		show_screen("title"), 220))
	if st == "connected":
		bottom.add_child(UI.button("카트 바꾸기", func(): garage_who = 1; garage_pick = ""; show_screen("garage"), 220))
	if Net.role != "":
		bottom.add_child(UI.button("연결 끊고 처음부터", func(): Net.reset(); show_screen("online"), 280))
	if not OS.has_feature("web") and not Net.available():
		say.call("(PC판에서는 온라인 연결이 안 돼요. 웹에서 해 주세요.)", Color(1.0, 0.7, 0.5), 18)
	_focus_first(col)

func _online_go() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	var def := Game.track_def(_online_track)
	var setup := {
		"track": _online_track, "host_kart": Game.save.kart, "guest_kart": str(Net.peer.get("kart", "acorn")),
		"ai": bake_ai(6 if _online_bots else 0, int(def.level), r),
	}
	if not (setup.guest_kart in Game.kart_ids()):
		setup.guest_kart = "acorn"
	Game.online_setup = setup
	Game.mode = "online"
	Game.track_id = _online_track
	Net.send({"y": "go", "setup": setup})
	get_tree().get_first_node_in_group("main").start_race()

func bake_ai(n: int, level: int, r: RandomNumberGenerator) -> Array:
	return preload("res://scripts/race.gd").make_ai_specs(n, level, r)
