extends Node3D
## 경주 한 판: 트랙 그림·카트·컴퓨터·카메라·화면 나누기·순위

signal done(result: Dictionary)
signal quit_race

const AI_NAMES := ["토끼", "곰돌이", "부엉이", "너구리", "고슴도치", "여우", "오리", "거북이"]
const AI_COLORS := [Color(0.95, 0.5, 0.6), Color(0.6, 0.45, 0.3), Color(0.75, 0.65, 0.9), Color(0.55, 0.55, 0.6), Color(0.85, 0.7, 0.45), Color(1.0, 0.6, 0.2), Color(1.0, 0.95, 0.4), Color(0.4, 0.75, 0.45)]
const P_COLORS := [Color(1.0, 0.9, 0.2), Color(0.35, 0.85, 1.0)]
const COUNT := 3.6

var def: Dictionary
var trk: Dictionary
var line: PackedFloat32Array
var mode := "race"
var racers: Array = []
var humans: Array = []
var state := "count"       # count → run → end
var count_left := COUNT
var clock := 0.0
var end_wait := -1.0
var view: TrackView
var cams: Array = []        # [{cam, yaw, shake, racer}]
var huds: Array = []
var coins: Array = []
var rng := RandomNumberGenerator.new()
var autopilot := false      # 개발용: 사람 카트도 컴퓨터가 몬다
var pause_menu: Control
var touchpad: Control
var _last_beep := 4
var online := false
var is_host := false
var remote_human: Dictionary = {}
var host_order: Array = []   ## 방장이 몰고 보내는 카트들 (방장 사람 + 컴퓨터) 순서
var _send_t := 0.0
var _wait_remote := -1.0
var _lost_said := false

## 컴퓨터 상대 설정 (온라인이면 방장이 만들어 친구에게 보낸다)
static func make_ai_specs(n: int, level: int, r: RandomNumberGenerator) -> Array:
	var ids: Array = Game.kart_ids()
	var names := AI_NAMES.duplicate()
	var out := []
	for i in n:
		var j := r.randi_range(i, names.size() - 1)
		var tmp = names[i]; names[i] = names[j]; names[j] = tmp
		out.append({
			"kart": ids[r.randi_range(0, ids.size() - 1)], "name": names[i], "color": i,
			"skill": clampf(0.45 + 0.5 * float(i) / maxf(1.0, n - 1) + r.randf_range(-0.08, 0.08), 0.3, 1.0) * (0.85 + 0.05 * float(level)),
			"offset": r.randf_range(-2.0, 2.0),
		})
	return out

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mode = Game.mode
	def = Game.track_def(Game.track_id)
	trk = Rules.build_track(def)
	line = Rules.racing_line(trk)
	rng.seed = int(Time.get_ticks_usec())
	var duo := mode == "duo"
	view = TrackView.new()
	add_child(view)
	view.build(def, trk, not duo)
	# 선수들
	online = mode == "online"
	var setup: Dictionary = Game.online_setup if online else {}
	is_host = online and Net.role == "host"
	var n_humans := 2 if (duo or online) else 1
	var specs: Array = []
	if online:
		specs = setup.get("ai", [])
	elif mode == "race":
		specs = make_ai_specs(7, int(def.level), rng)
	elif duo and Game.duo_bots:
		specs = make_ai_specs(6, int(def.level), rng)
	var n_ai := specs.size()
	var total := n_humans + n_ai
	var human_slots: Array = []
	# 사람은 뒷줄에서 출발 (경주) / 맨 앞 (연습). 온라인은 방장이 human_slots[0]
	for i in n_humans:
		human_slots.append(total - 1 - i if n_ai > 0 else i)
	var ref_stats := {}
	if online:
		var mine: String = setup.host_kart if is_host else setup.guest_kart
		var theirs: String = setup.guest_kart if is_host else setup.host_kart
		var me := _make_racer(Game.kart_def(mine), human_slots[0 if is_host else 1], true)
		me.who = 1
		me.name = "나"
		me.color = P_COLORS[0]
		humans.append(me)
		var you := _make_racer(Game.kart_def(theirs), human_slots[1 if is_host else 0], false)
		you.remote = true
		you.name = "친구"
		you.color = P_COLORS[1]
		remote_human = you
		ref_stats = me.st if me.st.max_speed < you.st.max_speed else you.st
		host_order.append(you if not is_host else me)
	else:
		for i in n_humans:
			var kid: String = Game.save.kart if i == 0 else Game.save.kart2
			var r := _make_racer(Game.kart_def(kid), human_slots[i], true)
			r.who = i + 1
			r.name = "%dP" % (i + 1) if duo else "나"
			r.color = P_COLORS[i]
			humans.append(r)
			if ref_stats.is_empty() or r.st.max_speed < ref_stats.max_speed:
				ref_stats = r.st
	var ai_i := 0
	for slot in total:
		if slot in human_slots:
			continue
		var sp: Dictionary = specs[ai_i]
		var r := _make_racer(Game.kart_def(sp.kart), slot, false)
		r.name = sp.name
		r.color = AI_COLORS[int(sp.color) % AI_COLORS.size()]
		r.skill = float(sp.skill)
		r.offset = float(sp.offset)
		r.ref = ref_stats
		r.remote = online and not is_host
		host_order.append(r)
		ai_i += 1
	if online:
		Net.message.connect(_on_net)
	_place_coins()
	_make_views()
	if DisplayServer.is_touchscreen_available() and not duo:
		touchpad = preload("res://scripts/touchpad.gd").new()
		$UI.add_child(touchpad)
		Controls.touch["on"] = true
	_make_pause()
	for r in racers:
		_show(r, 0.0, 0.016)
	Sound.music("race")
	for h in humans:
		Sound.engine_on(h.who, true)

func _make_racer(kdef: Dictionary, slot: int, human: bool) -> Dictionary:
	var g := Rules.grid_slot(trk, slot)
	var k := Rules.new_kart(g.pos, g.yaw)
	var node := KartView.new()
	add_child(node)
	node.setup(kdef, true)
	var r := {
		"k": k, "st": Rules.kart_stats(kdef), "def": kdef, "node": node, "human": human, "who": 0,
		"name": "", "color": Color.WHITE, "skill": 1.0, "offset": 0.0, "ref": {},
		"hint": -1, "dist": Rules.locate(trk, k.pos).s - trk.length, "finish": -1.0, "place": slot + 1,
		"coins": 0, "prev_up": false, "prev_boost": false, "start_press": -1.0, "wrong": 0.0, "steer": 0.0,
		"lap": 1, "offroad_t": 0.0, "remote": false, "net": {},
	}
	racers.append(r)
	return r

func _place_coins() -> void:
	var groups := 6
	for gi in groups:
		var base := int(trk.n * (gi + 0.5) / groups)
		var side: float = rng.randf_range(-0.6, 0.6) * trk.half_width
		for c in 5:
			var i: int = (base + c * 2) % trk.n
			var p: Vector2 = trk.pts[i] + trk.nrm[i] * side
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.55
			cm.bottom_radius = 0.55
			cm.height = 0.14
			cm.radial_segments = 16
			mi.mesh = cm
			mi.rotation.x = PI / 2
			var holder := Node3D.new()
			holder.position = Vector3(p.x, 1.0, p.y)
			holder.add_child(mi)
			mi.material_override = KartView.mat(Color(1.0, 0.8, 0.2), true)
			add_child(holder)
			coins.append({"pos": p, "node": holder, "away": 0.0})

func _make_views() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 4)
	ui.add_child(box)
	for h in humans:
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(svc)
		var sv := SubViewport.new()
		sv.msaa_3d = Viewport.MSAA_2X if humans.size() == 1 else Viewport.MSAA_DISABLED
		sv.audio_listener_enable_3d = false
		svc.add_child(sv)
		var cam := Camera3D.new()
		cam.fov = 70.0
		cam.far = 400.0
		sv.add_child(cam)
		cam.current = true
		var hud := Hud.new()
		hud.race = self
		hud.racer = h
		svc.add_child(hud)
		huds.append(hud)
		h["hud"] = hud
		var k: Dictionary = h.k
		cams.append({"cam": cam, "yaw": k.yaw, "shake": 0.0, "racer": h, "fov": 70.0})

func _make_pause() -> void:
	pause_menu = preload("res://scripts/pause_menu.gd").new()
	pause_menu.race = self
	$UI.add_child(pause_menu)

func _unhandled_input(e: InputEvent) -> void:
	Controls.feed(e)
	if e.is_action_pressed("ui_cancel") or (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_P):
		if state != "end":
			pause_menu.open()
			get_viewport().set_input_as_handled()

func _input(e: InputEvent) -> void:
	Controls.feed(e)

func _physics_process(dt: float) -> void:
	if state == "count":
		_countdown(dt)
	elif state in ["run", "end"]:
		clock += dt
		_drive(dt)
	for r in racers:
		_show(r, r.steer, dt)
	_coins(dt)
	_cameras(dt)
	if online:
		_net_tick(dt)
	if humans.size() > 0:
		for h in humans:
			var k: Dictionary = h.k
			Sound.engine(h.who, absf(Rules.speed_of(k)) / maxf(1.0, h.st.max_speed), Rules.boosting(k), humans.size())
			var slide: float = clampf(absf(float(k.slip)) / 0.4, 0.0, 1.0) * clampf(k.vel.length() / 24.0, 0.0, 1.0)
			Sound.skid(h.who, (k.drift or absf(float(k.slip)) > 0.15) and state != "count", maxf(slide, 0.35 if k.drift else 0.0), humans.size())
	if _wait_remote > 0.0 and end_wait < 0.0:
		_wait_remote -= dt
		if _wait_remote <= 0.0 or remote_human.finish >= 0.0 or not Net.connected():
			_wait_remote = 0.0
			state = "end"
			end_wait = 2.0
	if end_wait >= 0.0:
		end_wait -= dt
		if end_wait < 0.0:
			_finish()

func _countdown(dt: float) -> void:
	var before := count_left
	count_left -= dt
	var n := int(ceil(count_left))
	if n < _last_beep and n >= 1 and n <= 3:
		_last_beep = n
		Sound.play("beep")
	for h in humans:
		var c := Controls.read(h.who, mode == "duo")
		var up: bool = c.throttle > 0.0
		if up and not h.prev_up:
			h.start_press = count_left
		h.prev_up = up
	if before > 0.0 and count_left <= 0.0:
		state = "run"
		clock = 0.0
		Sound.play("go")
		for r in racers:
			var boost := 0.0
			if r.human:
				if r.prev_up:
					boost = Rules.start_boost(r.start_press)
			elif not r.remote and rng.randf() < r.skill * 0.7:
				boost = 1.0
			if boost > 0.0:
				r.k.mini_t = boost
				if r.human:
					r.hud.say("출발 부스터!", Color(0.5, 1.0, 0.6))
					Sound.play("mini")

func _ai_input(r: Dictionary, loc: Dictionary) -> Dictionary:
	return Rules.ai_input(r.k, trk, line, loc, r.skill, r.offset, rng.randf())

func _drive(dt: float) -> void:
	var lead_human := -INF
	for h in humans:
		lead_human = maxf(lead_human, h.dist)
	if not remote_human.is_empty():
		lead_human = maxf(lead_human, remote_human.dist)
	for r in racers:
		var k: Dictionary = r.k
		if r.remote:
			_follow_net(r, dt)
			continue
		var loc := Rules.locate(trk, k.pos, r.hint)
		r.hint = loc.i
		k.offroad = Rules.surface(trk, loc.lat) == "grass"
		var inp: Dictionary
		var st: Dictionary = r.st
		if r.human and r.finish < 0.0 and not autopilot:
			var c := Controls.read(r.who, mode == "duo")
			var up: bool = c.throttle > 0.0
			inp = {"throttle": c.throttle, "steer": c.steer, "drift": c.drift,
				"accel_tap": up and not r.prev_up, "use_boost": c.boost and not r.prev_boost}
			r.prev_up = up
			r.prev_boost = c.boost
		else:
			inp = _ai_input(r, loc)
			if not r.human:
				var behind: float = lead_human - r.dist if humans.size() > 0 else 0.0
				st = Rules.ai_stats(r.ref if not r.ref.is_empty() else r.st, r.skill, behind)
				st.drift_gain = r.st.drift_gain
				st.boost_time = r.st.boost_time
			if r.finish >= 0.0:
				inp.throttle = 0.6 if r.human else inp.throttle
		r.steer = lerpf(r.steer, float(inp.steer), 1.0 - exp(-12.0 * dt))
		Rules.step(k, inp, st, dt)
		if Rules.wall_push(trk, k, Rules.locate(trk, k.pos, r.hint)):
			if absf(Rules.speed_of(k)) > 6.0:
				k.events.append("bump")
	_collide()
	for r in racers:
		var k: Dictionary = r.k
		var loc := Rules.locate(trk, k.pos, r.hint)
		r.hint = loc.i
		if r.remote:
			k.events.clear()
			continue
		var before: float = r.dist
		r.dist = Rules.advance(r.dist, loc.s, trk.length)
		if (k.vel as Vector2).dot(loc.tan) < -3.0:
			r.wrong += dt
		else:
			r.wrong = 0.0
		var lap := Rules.lap_of(r.dist, trk.length)
		if r.finish < 0.0 and r.dist >= trk.length * trk.laps:
			r.finish = clock
			if r.human:
				Sound.play("finish")
				if online:
					Net.send({"y": "fin", "t": clock})
				_check_end()
		elif lap > r.lap and r.human and r.finish < 0.0 and before > 0.0:
			if lap == trk.laps:
				r.hud.say("마지막 바퀴!", Color(1, 0.6, 0.4), 1.8)
			else:
				r.hud.say("%d 바퀴째" % lap, Color(0.9, 0.95, 1.0))
			Sound.play("lap")
		r.lap = maxi(r.lap, lap)
		if r.human:
			_events(r)
		k.events.clear()
	var order := Rules.ranking(racers)
	for p in order.size():
		racers[order[p]].place = p + 1
	if state == "run":
		var all_done := true
		for r in racers:
			if r.finish < 0.0:
				all_done = false
		if all_done:
			_check_end()

func _events(r: Dictionary) -> void:
	var hud: Hud = r.hud
	for e in r.k.events:
		match e:
			"drift_start", "drift_flip":
				Sound.play("screech", -3.0 if humans.size() == 1 else -7.0, randf_range(0.95, 1.06))
			"drift_tap":
				Sound.play("screech", -9.0 if humans.size() == 1 else -12.0, randf_range(1.08, 1.18))
			"mini_boost":
				hud.say("순간부스터!", Color(0.5, 1.0, 0.6))
				Sound.play("mini")
			"boost_gain":
				hud.say("부스터 +1", Color(1.0, 0.7, 0.3))
				Sound.play("gain")
			"boost":
				hud.flash = 1.0
				Sound.play("boost")
				for c in cams:
					if c.racer == r:
						c.shake = 0.25
			"bump":
				Sound.play("bump")
				for c in cams:
					if c.racer == r:
						c.shake = 0.35

## 카트끼리 부딪힘: 무거운 쪽이 덜 밀린다
func _collide() -> void:
	var rad := 1.15
	for i in racers.size():
		for j in range(i + 1, racers.size()):
			var a: Dictionary = racers[i].k
			var b: Dictionary = racers[j].k
			var d: Vector2 = (b.pos as Vector2) - (a.pos as Vector2)
			var dist := d.length()
			if dist >= rad * 2.0 or dist < 0.001:
				continue
			var nrm := d / dist
			var wa: float = racers[i].st.weight
			var wb: float = racers[j].st.weight
			var sa := wb / (wa + wb)
			# 원격 카트는 저쪽이 몰므로 이쪽 카트만 밀린다
			if racers[i].remote and racers[j].remote:
				continue
			if racers[i].remote:
				sa = 0.0
			elif racers[j].remote:
				sa = 1.0
			var push := rad * 2.0 - dist
			a.pos = (a.pos as Vector2) - nrm * push * sa
			b.pos = (b.pos as Vector2) + nrm * push * (1.0 - sa)
			var rel := ((b.vel as Vector2) - (a.vel as Vector2)).dot(nrm)
			if rel < 0.0:
				var imp := -rel * 1.3
				a.vel = (a.vel as Vector2) - nrm * imp * sa
				b.vel = (b.vel as Vector2) + nrm * imp * (1.0 - sa)
				if imp > 4.0:
					if racers[i].human: a.events.append("bump")
					if racers[j].human: b.events.append("bump")

func _coins(dt: float) -> void:
	for c in coins:
		var node: Node3D = c.node
		node.rotation.y += dt * 3.0
		if c.away > 0.0:
			c.away -= dt
			node.visible = c.away <= 0.0
			continue
		for r in racers:
			if (r.k.pos as Vector2).distance_squared_to(c.pos) < 2.2 * 2.2:
				c.away = 6.0
				node.visible = false
				if r.human and r.finish < 0.0:
					r.coins += Rules.COIN_VALUE
					Sound.play("coin")
				break

func _show(r: Dictionary, steer: float, dt: float) -> void:
	(r.node as KartView).show_state(r.k, steer, dt)

func _cameras(dt: float) -> void:
	for c in cams:
		var k: Dictionary = c.racer.k
		var v: Vector2 = k.vel
		var target_yaw: float = k.yaw
		if v.length() > 4.0:
			# 드리프트하면 가는 방향 쪽에서 비스듬히 보이게
			target_yaw = lerp_angle(k.yaw, atan2(v.x, v.y), 0.45)
		# 카메라는 천천히 돌아 따라온다 (회전 속도도 부드럽게)
		var want_rate := wrapf(target_yaw - float(c.yaw), -PI, PI) * 3.6
		c.rate = lerpf(float(c.get("rate", 0.0)), want_rate, 1.0 - exp(-8.0 * dt))
		c.yaw = float(c.yaw) + float(c.rate) * dt
		var p: Vector2 = k.pos
		var f := Rules.fwd(c.yaw)
		var spd := absf(Rules.speed_of(k))
		c.spd = lerpf(float(c.get("spd", 0.0)), spd, 1.0 - exp(-2.0 * dt))
		var back := 6.4 + float(c.spd) * 0.04
		var pos := Vector3(p.x - f.x * back, 2.9 + float(c.spd) * 0.015, p.y - f.y * back)
		var cam: Camera3D = c.cam
		if c.shake > 0.0:
			c.shake = maxf(0.0, c.shake - dt)
			pos += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * c.shake * 0.5
		cam.position = pos
		cam.look_at(Vector3(p.x + f.x * 3.0, 1.0, p.y + f.y * 3.0), Vector3.UP)
		var want := 68.0 + (12.0 if k.boost_t > 0.0 else (6.0 if k.mini_t > 0.0 else 0.0)) + spd * 0.12
		c.fov = lerpf(c.fov, want, 1.0 - exp(-2.2 * dt))
		cam.fov = c.fov

func _check_end() -> void:
	if end_wait >= 0.0 or state == "end":
		return
	var humans_done := true
	for h in humans:
		if h.finish < 0.0:
			humans_done = false
	if online and humans_done and not remote_human.is_empty() and remote_human.finish < 0.0 and Net.connected():
		# 친구가 들어올 때까지 조금 기다린다
		if _wait_remote < 0.0:
			_wait_remote = 25.0
			humans[0].hud.say("친구를 기다리는 중…", Color(0.8, 0.9, 1.0), 3.0)
		humans_done = false
	var all_done := true
	for r in racers:
		if r.finish < 0.0:
			all_done = false
	if humans_done or all_done:
		state = "end"
		end_wait = 3.5 if not all_done else 2.5

func _finish() -> void:
	# 아직 못 들어온 컴퓨터는 남은 거리로 시간을 어림한다
	for r in racers:
		if r.finish < 0.0:
			var left: float = trk.length * trk.laps - r.dist
			r.finish = clock + left / maxf(10.0, absf(Rules.speed_of(r.k)) * 0.9)
	var order := Rules.ranking(racers)
	var table := []
	for p in order.size():
		var r: Dictionary = racers[order[p]]
		r.place = p + 1
		table.append({"name": r.name, "time": r.finish, "human": r.human, "place": p + 1, "kart": r.def.name, "color": r.color})
	var players := []
	for h in humans:
		var reward := Rules.reward(h.place, racers.size(), mode)
		if mode == "time":
			reward = Rules.record_reward(Game.best_of(def.id), h.finish)
		players.append({"who": h.who, "name": h.name, "place": h.place, "time": h.finish, "reward": reward, "coins": h.coins})
	var result := {"mode": mode, "track": def.id, "track_name": def.name, "players": players, "table": table, "racers": racers.size()}
	for h in humans:
		Sound.engine_on(h.who, false)
		Sound.skid(h.who, false)
	Controls.touch.clear()
	done.emit(result)

func leave() -> void:
	if online:
		Net.send({"y": "bye"})
	for h in humans:
		Sound.engine_on(h.who, false)
		Sound.skid(h.who, false)
	Controls.touch.clear()
	quit_race.emit()

# ─────────── 온라인 ───────────

## 카트 상태를 짧은 배열로: x, z, vx, vz, yaw, 표시(1 드리프트, 2 부스터, 4 순간, 8 잔디), 미끄러짐, 거리, 도착 시간, 게이지, 부스터 수
func _pack(r: Dictionary) -> Array:
	var k: Dictionary = r.k
	var f := (1 if k.drift else 0) | (2 if k.boost_t > 0.0 else 0) | (4 if k.mini_t > 0.0 else 0) | (8 if k.offroad else 0)
	return [snappedf(k.pos.x, 0.01), snappedf(k.pos.y, 0.01), snappedf(k.vel.x, 0.01), snappedf(k.vel.y, 0.01),
		snappedf(k.yaw, 0.001), f, snappedf(float(k.slip), 0.01), snappedf(r.dist, 0.01), snappedf(r.finish, 0.001), snappedf(r.steer, 0.01)]

func _apply(r: Dictionary, a: Array) -> void:
	if a.size() < 10:
		return
	r.net = {"pos": Vector2(a[0], a[1]), "vel": Vector2(a[2], a[3]), "yaw": float(a[4]), "age": 0.0}
	var k: Dictionary = r.k
	var f := int(a[5])
	k.drift = f & 1 != 0
	k.boost_t = 0.5 if f & 2 != 0 else 0.0
	k.mini_t = 0.5 if f & 4 != 0 else 0.0
	k.offroad = f & 8 != 0
	k.slip = float(a[6])
	k.drift_time = 1.0 if k.drift else 0.0
	r.dist = float(a[7])
	if r.finish < 0.0 and float(a[8]) >= 0.0:
		r.finish = float(a[8])
	r.steer = float(a[9])
	if absf((k.pos as Vector2).distance_to(r.net.pos)) > 12.0:
		k.pos = r.net.pos
		k.yaw = r.net.yaw

## 받은 상태 쪽으로 부드럽게 (받은 뒤 지난 시간만큼 속도로 앞질러 맞춘다)
func _follow_net(r: Dictionary, dt: float) -> void:
	if r.net.is_empty():
		return
	var k: Dictionary = r.k
	r.net.age = minf(float(r.net.age) + dt, 0.4)
	var want: Vector2 = r.net.pos + r.net.vel * float(r.net.age)
	k.vel = r.net.vel
	k.pos = (k.pos as Vector2).lerp(want, 1.0 - exp(-12.0 * dt))
	k.yaw = lerp_angle(float(k.yaw), float(r.net.yaw), 1.0 - exp(-12.0 * dt))

func _net_tick(dt: float) -> void:
	if not Net.connected():
		if not _lost_said and not humans.is_empty():
			_lost_said = true
			humans[0].hud.say("친구와 연결이 끊겼어요", Color(1, 0.5, 0.4), 4.0)
			if not remote_human.is_empty():
				remote_human.remote = true
			if state == "end" or humans[0].finish >= 0.0:
				_check_end()
		return
	_send_t -= dt
	if _send_t > 0.0:
		return
	_send_t = 0.05   # 1초에 20번
	if is_host:
		var arr := []
		for r in host_order:
			arr.append(_pack(r))
		Net.send({"y": "s", "c": snappedf(clock, 0.01), "k": arr}, true)
	else:
		Net.send({"y": "s", "c": snappedf(clock, 0.01), "k": [_pack(humans[0])]}, true)

func _on_net(m: Dictionary) -> void:
	match m.get("y"):
		"s":
			var arr: Array = m.get("k", [])
			if is_host:
				if arr.size() > 0:
					_apply(remote_human, arr[0])
			else:
				for i in mini(arr.size(), host_order.size()):
					_apply(host_order[i], arr[i])
		"fin":
			if remote_human.finish < 0.0:
				remote_human.finish = float(m.t)
			_check_end()
		"bye":
			if not humans.is_empty():
				humans[0].hud.say("친구가 경주를 그만뒀어요", Color(1, 0.6, 0.4), 3.0)
			remote_human.finish = maxf(remote_human.finish, -1.0)
