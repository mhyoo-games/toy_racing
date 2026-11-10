extends SceneTree
## godot --headless -s tests/run_tests.gd  (주행 규칙·트랙·상점·저장이 맞는지 확인)

var fails := 0
var passes := 0
var karts: Array = []
var tracks: Array = []

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		printerr("실패: ", what)

func _init() -> void:
	karts = JSON.parse_string(FileAccess.get_file_as_string("res://data/karts.json")).karts
	tracks = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks.json")).tracks
	_data()
	_driving()
	_drift_and_boost()
	_smooth_feel()
	_drift_tricks()
	_gauge_balance()
	_brake_and_mini()
	_items()
	_track_geometry()
	_race_rules()
	_shop_and_save()
	_full_laps()
	_net_codes()
	_room_codes()
	print("통과 %d, 실패 %d" % [passes, fails])
	quit(1 if fails > 0 else 0)

func kart(id: String) -> Dictionary:
	for k in karts:
		if k.id == id: return k
	return {}

func _data() -> void:
	var ids := {}
	for k in karts:
		ok(not ids.has(k.id), "카트 id 겹치지 않음: " + k.id)
		ids[k.id] = true
		for s in ["speed", "accel", "handling", "drift", "boost", "weight"]:
			ok(k.stats.has(s) and k.stats[s] >= 1 and k.stats[s] <= 10, "%s 능력치 %s 1~10" % [k.id, s])
		ok(Color.html_is_valid(k.color) and Color.html_is_valid(k.trim), k.id + " 색")
	ok(kart("acorn").price == 0, "처음 카트는 공짜")
	var prices := karts.map(func(k): return int(k.price))
	var sorted := prices.duplicate(); sorted.sort()
	ok(prices == sorted, "카트는 값 순서대로")
	ok(tracks.size() >= 3, "트랙 셋 이상")
	for t in tracks:
		ok(t.points.size() >= 8 and t.half_width >= 6.0 and t.laps >= 1, t.id + " 트랙 정의")

func _driving() -> void:
	var st := Rules.kart_stats(kart("acorn"))
	ok(st.max_speed > 27.0 and st.max_speed < 37.0, "최고 속력 범위")
	var fast := Rules.kart_stats(kart("pinwheel"))
	var quick := Rules.kart_stats(kart("pinecone"))
	ok(fast.max_speed > st.max_speed and quick.accel > st.accel, "능력치가 값에 반영")
	ok(is_equal_approx(Rules.fwd(0.0).y, 1.0) and is_equal_approx(Rules.right(0.0).x, -1.0), "앞은 +z, 오른쪽은 -x")
	# 가속: 3초 안에 최고 속력의 80%
	var k := Rules.new_kart(Vector2.ZERO, 0.0)
	for i in 180:
		Rules.step(k, {"throttle": 1.0}, st, 1.0 / 60.0)
	var v := Rules.speed_of(k)
	ok(v > st.max_speed * 0.8 and v <= st.max_speed + 0.01, "3초 가속 %.1f" % v)
	ok(k.pos.y > 30.0 and absf(k.pos.x) < 0.01, "똑바로 앞(+z)으로 간다")
	# 오른쪽으로 꺾으면 오른쪽(-x)으로
	for i in 60:
		Rules.step(k, {"throttle": 1.0, "steer": 1.0}, st, 1.0 / 60.0)
	ok(k.pos.x < -1.0 and k.yaw < 0.0, "오른쪽 핸들은 오른쪽으로")
	# 브레이크
	for i in 120:
		Rules.step(k, {"throttle": -1.0}, st, 1.0 / 60.0)
	ok(Rules.speed_of(k) < 0.1, "브레이크로 선다")
	# 잔디는 느리다
	var g := Rules.new_kart(Vector2.ZERO, 0.0)
	g.offroad = true
	for i in 300:
		Rules.step(g, {"throttle": 1.0}, st, 1.0 / 60.0)
	ok(Rules.speed_of(g) < st.max_speed * 0.6, "잔디 위 최고 속력은 낮다")
	g.boost_t = 1.0
	ok(Rules.top_speed(g, st) > st.max_speed * 0.8, "부스터면 잔디에서도 빠르다(커팅)")
	ok(Rules.top_speed(g, st) < st.max_speed * st.boost_mult, "그래도 도로보다는 느리다")

func _drift_and_boost() -> void:
	var st := Rules.kart_stats(kart("acorn"))
	var k := Rules.new_kart(Vector2.ZERO, 0.0)
	k.vel = Vector2(0, 28)
	Rules.step(k, {"throttle": 1.0, "steer": 0.1, "drift": true}, st, 1.0 / 60.0)
	ok(not k.drift, "방향키 없이 드리프트 안 됨")
	Rules.step(k, {"throttle": 1.0, "steer": 1.0, "drift": true}, st, 1.0 / 60.0)
	ok(k.drift and k.drift_dir == 1 and "drift_start" in k.events, "드리프트 시작")
	k.events.clear()
	# 키를 놓아도 미는 쪽으로 꺾고 있으면 계속 미끄러진다
	for i in 50:
		Rules.step(k, {"throttle": 1.0, "steer": 1.0, "drift": i < 5}, st, 1.0 / 60.0)
	ok(k.drift, "드리프트는 카운터 전까지 이어진다")
	ok(absf(k.slip) > 0.3, "옆으로 미끄러진다(각도) %.2f" % k.slip)
	ok(k.gauge > 0.2, "드리프트하면 게이지가 찬다 %.2f" % k.gauge)
	ok(Rules.speed_of(k) > 20.0, "드리프트해도 속력을 크게 잃지 않는다 %.1f" % Rules.speed_of(k))
	# 카운터로 끝내면 순간부스터 기회
	var ended := false
	for i in 30:
		Rules.step(k, {"throttle": 1.0, "steer": -1.0}, st, 1.0 / 60.0)
		if not k.drift:
			ended = true
			break
	ok(ended and "drift_end" in k.events and k.window_t > 0.0, "카운터로 드리프트가 끝나고 순간부스터 기회")
	Rules.step(k, {"throttle": 1.0, "accel_tap": true}, st, 1.0 / 60.0)
	ok(k.mini_t > 0.0 and "mini_boost" in k.events, "순간부스터")
	ok(Rules.top_speed(k, st) > st.max_speed, "순간부스터는 더 빠르다")
	# 기회가 지나면 안 된다
	var k2 := Rules.new_kart(Vector2.ZERO, 0.0)
	k2.window_t = Rules.MINI_WINDOW
	for i in 30:
		Rules.step(k2, {"throttle": 1.0}, st, 1.0 / 60.0)
	Rules.step(k2, {"throttle": 1.0, "accel_tap": true}, st, 1.0 / 60.0)
	ok(k2.mini_t == 0.0, "늦게 누르면 순간부스터 없음")
	# 게이지 → 부스터 (두 개까지)
	var k3 := Rules.new_kart(Vector2.ZERO, 0.0)
	k3.gauge = 1.0
	Rules.step(k3, {}, st, 1.0 / 60.0)
	ok(k3.boosts == 1 and "boost_gain" in k3.events, "게이지가 차면 부스터 하나")
	k3.boosts = 2; k3.gauge = 1.2
	Rules.step(k3, {}, st, 1.0 / 60.0)
	ok(k3.boosts == 2, "부스터는 두 개까지")
	k3.vel = Vector2(0, 20)
	Rules.step(k3, {"throttle": 1.0, "use_boost": true}, st, 1.0 / 60.0)
	ok(k3.boosts == 1 and k3.boost_t > 1.0 and "boost" in k3.events, "부스터 쓰기")
	for i in 60:
		Rules.step(k3, {"throttle": 1.0}, st, 1.0 / 60.0)
	ok(Rules.speed_of(k3) > st.max_speed, "부스터면 최고 속력을 넘는다 %.1f" % Rules.speed_of(k3))
	# 드리프트 잘 되는 카트가 게이지를 더 빨리 채운다
	ok(Rules.kart_stats(kart("squirrel")).drift_gain > st.drift_gain, "다람쥐는 게이지가 잘 찬다")
	# 출발 부스터
	ok(Rules.start_boost(0.2) > 0.0 and Rules.start_boost(0.9) == 0.0 and Rules.start_boost(-0.1) == 0.0, "출발 부스터 타이밍")

func _track_geometry() -> void:
	for def in tracks:
		var tr := Rules.build_track(def)
		ok(tr.n > 100 and absf(tr.length - tr.n * 2.0) < tr.n * 0.2, def.id + " 점 간격 %.0f" % tr.length)
		var loc := Rules.locate(tr, tr.pts[10] + tr.nrm[10] * 3.0)
		ok(absf(loc.lat - 3.0) < 0.3 and absf(loc.i - 10) <= 1, def.id + " 옆 거리 재기")
		ok(Rules.surface(tr, 3.0) == "road" and Rules.surface(tr, tr.half_width + 1.0) == "grass", def.id + " 바닥")
		var line := Rules.racing_line(tr)
		var mx := 0.0
		for o in line:
			mx = maxf(mx, absf(o))
		ok(mx <= tr.half_width - 2.0 + 0.01 and mx > 2.0, def.id + " 레이싱 라인은 도로 안에서 굽이 안쪽으로 %.1f" % mx)
		# 굽이 안쪽: 오른쪽으로 굽으면 오른쪽(+)으로 붙는다
		var agree := 0
		var total := 0
		for i in tr.n:
			if absf(tr.curv[i]) > 0.02:
				total += 1
				if signf(line[i]) == signf(tr.curv[i]): agree += 1
		ok(total > 0 and agree > total * 0.6, def.id + " 굽은 곳에서 안쪽을 탄다 %d/%d" % [agree, total])
		# 울타리 밖으로 못 나간다
		var k := Rules.new_kart(tr.pts[20] + tr.nrm[20] * (tr.wall + 4.0), 0.0)
		k.vel = tr.nrm[20] * 10.0
		var l2 := Rules.locate(tr, k.pos)
		ok(Rules.wall_push(tr, k, l2) and absf(Rules.locate(tr, k.pos).lat) < tr.wall, def.id + " 울타리")
		ok(k.vel.dot(tr.nrm[20]) <= 0.0, def.id + " 울타리에 부딪히면 바깥 속도 없음")
		# 출발 자리가 출발선 뒤, 도로 위
		for s in 8:
			var g := Rules.grid_slot(tr, s)
			var gl := Rules.locate(tr, g.pos)
			ok(gl.s > tr.length * 0.7 and absf(gl.lat) < tr.half_width, def.id + " 출발 자리 %d" % s)

func _race_rules() -> void:
	ok(is_equal_approx(Rules.advance(95.0, 5.0, 100.0), 105.0), "출발선을 넘으면 거리가 이어진다")
	ok(is_equal_approx(Rules.advance(105.0, 95.0, 100.0), 95.0), "뒤로 가면 줄어든다")
	ok(is_equal_approx(Rules.advance(-3.0, 98.0, 100.0), -2.0), "출발 전 뒤쪽")
	ok(Rules.lap_of(-2.0, 100.0) == 1 and Rules.lap_of(150.0, 100.0) == 2, "랩")
	var order := Rules.ranking([
		{"dist": 50.0, "finish": -1.0}, {"dist": 300.0, "finish": 62.0},
		{"dist": 80.0, "finish": -1.0}, {"dist": 300.0, "finish": 60.0}])
	ok(order == [3, 1, 2, 0], "순위 %s" % [order])
	ok(Rules.reward(1, 8, "race") > Rules.reward(2, 8, "race") and Rules.reward(8, 8, "race") > 0, "순위 보상")
	ok(Rules.reward(1, 1, "time") == 0, "연습은 순위 보상 없음")
	ok(Rules.record_reward(0.0, 50.0) > 0 and Rules.record_reward(60.0, 55.0) > Rules.record_reward(60.0, 65.0), "기록 보상")
	ok(Rules.time_text(83.456) == "1:23.46" and Rules.time_text(-1.0) == "--:--.--", "시간 글자")

func _shop_and_save() -> void:
	var s := Rules.default_save()
	var sq := kart("squirrel")
	ok(not Rules.can_buy(s, sq), "돈이 없으면 못 산다")
	s.coins = 600
	var s2 := Rules.buy(s, sq)
	ok(s2.coins == 100 and "squirrel" in s2.owned and s2.kart == "squirrel", "사면 돈이 줄고 고른다")
	ok(s.coins == 600 and not ("squirrel" in s.owned), "원래 저장은 그대로")
	ok(not Rules.can_buy(s2, sq), "이미 있으면 다시 못 산다")
	var ids := karts.map(func(k): return k.id)
	var p := Rules.parse_save(JSON.stringify(s2), ids)
	ok(p.coins == 100 and p.kart == "squirrel" and "acorn" in p.owned, "저장 읽기")
	ok(Rules.parse_save("망가진{", ids) == Rules.default_save(), "망가진 저장은 처음부터")
	var bad := Rules.parse_save({"coins": -5, "owned": ["ufo", "squirrel"], "kart": "ufo", "best": {"a": "x", "b": 30}}, ids)
	ok(bad.coins == 0 and bad.owned == ["acorn", "squirrel"] and bad.kart == "acorn" and bad.best == {"b": 30.0}, "이상한 값은 걸러 낸다")

## 컴퓨터가 모든 트랙을 3바퀴 도는지 (막히거나 거꾸로 가지 않는지)
func _full_laps() -> void:
	var st := Rules.kart_stats(kart("acorn"))
	for def in tracks:
		var tr := Rules.build_track(def)
		var line := Rules.racing_line(tr)
		var g := Rules.grid_slot(tr, 0)
		var k := Rules.new_kart(g.pos, g.yaw)
		var dist: float = Rules.locate(tr, k.pos).s - tr.length
		var hint := -1
		var t := 0.0
		var dt := 1.0 / 60.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var walls := 0
		var drifts := 0
		var minis := 0
		var boosts := 0
		var laps: Array = []
		var goal: float = tr.length * tr.laps
		while dist < goal and t < 400.0:
			var loc := Rules.locate(tr, k.pos, hint)
			hint = loc.i
			k.offroad = Rules.surface(tr, loc.lat) == "grass"
			var inp := Rules.ai_input(k, tr, line, loc, 1.0, 0.0, rng.randf())
			Rules.step(k, inp, st, dt)
			for e in k.events:
				if e == "drift_start": drifts += 1
				if e == "mini_boost": minis += 1
				if e == "boost": boosts += 1
			k.events.clear()
			var l2 := Rules.locate(tr, k.pos, hint)
			if Rules.wall_push(tr, k, l2):
				walls += 1
			var before: float = dist
			dist = Rules.advance(dist, Rules.locate(tr, k.pos, hint).s, tr.length)
			if floor(dist / tr.length) > floor(before / tr.length) and dist > 0.0:
				laps.append(t)
			t += dt
		var avg: float = t / tr.laps
		print("  %s: %.1f초 (한 바퀴 %.1f초) 드리프트 %d 순간부스터 %d 부스터 %d 벽 %d" % [def.id, t, avg, drifts, minis, boosts, walls])
		ok(dist >= goal, def.id + " 3바퀴를 다 돈다")
		ok(avg > tr.length / 45.0 and avg < tr.length / 15.0, def.id + " 한 바퀴 시간이 그럴듯하다")
		var sharpest := 0.0
		for c in tr.curv:
			sharpest = maxf(sharpest, absf(c))
		if sharpest > 0.025:
			ok(drifts > 3 * tr.laps and boosts >= 1, def.id + " 컴퓨터도 드리프트하고 부스터를 쓴다")
		ok(walls < 12 * tr.laps, def.id + " 벽에 자주 안 박는다 (%d)" % walls)

## 온라인 연결 코드: 접두어·압축·base64가 돌아오는지, 망가진 코드는 빈 값
func _net_codes() -> void:
	var sdp := "v=0\r\no=- 46117 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\na=group:BUNDLE 0\r\n" + "a=candidate:1 1 udp 2122260223 192.168.0.2 5000 typ host\r\n".repeat(6)
	var code: String = Rules.net_encode({"t": "offer", "s": sdp}, [["0", 0, "candidate:1 1 udp 1 10.0.0.1 9 typ host"]])
	ok(code.begins_with("TR1-") and code.length() < sdp.length(), "코드는 줄여서 TR1- 로 시작 (%d자)" % code.length())
	var d: Dictionary = Rules.net_decode("  보낸 글: " + code.insert(30, "\n") + "  ")
	ok(d.get("t") == "offer" and d.get("s") == sdp and d.c.size() == 1, "앞뒤 글자·줄바꿈이 섞여도 읽는다")
	ok(Rules.net_decode("TR1-망가짐").is_empty() and Rules.net_decode("").is_empty() and Rules.net_decode(code.substr(0, 40)).is_empty(), "망가진 코드는 빈 값")

## 조작감: 핸들·회전이 한 번에 튀지 않는지, 짧게 끊는 드리프트(커팅)가 속도를 안 잃고 방향을 꺾는지
func _smooth_feel() -> void:
	var st := Rules.kart_stats(kart("acorn"))
	var dt := 1.0 / 60.0
	var mk := func() -> Dictionary:
		var k := Rules.new_kart(Vector2.ZERO, 0.0)
		k.vel = Vector2(0, 28)
		return k
	# 핸들: 첫 프레임엔 조금만, 0.5초 뒤엔 다 돈다. 프레임마다 회전 속도가 크게 안 튄다
	var k: Dictionary = mk.call()
	Rules.step(k, {"throttle": 1.0, "steer": 1.0}, st, dt)
	var first := absf(k.yaw_rate)
	var jump := 0.0
	var prev := absf(k.yaw_rate)
	for i in 30:
		Rules.step(k, {"throttle": 1.0, "steer": 1.0}, st, dt)
		jump = maxf(jump, absf(absf(k.yaw_rate) - prev))
		prev = absf(k.yaw_rate)
	ok(first < prev * 0.1, "핸들은 천천히 들어간다 (첫 프레임 %.3f, 0.5초 %.2f)" % [first, prev])
	ok(jump < prev * 0.12, "회전 속도가 프레임마다 튀지 않는다 (최대 %.3f)" % jump)
	# 드리프트를 걸어도 회전이 부드럽게 붙는다
	k = mk.call()
	var jd := 0.0
	prev = 0.0
	var slips := []
	for i in 90:
		Rules.step(k, {"throttle": 1.0, "steer": 1.0, "drift": i < 10}, st, dt)
		jd = maxf(jd, absf(absf(k.yaw_rate) - prev))
		prev = absf(k.yaw_rate)
		slips.append(absf(k.slip))
	ok(jd < 0.25, "드리프트 시작도 부드럽다 (프레임당 최대 %.3f)" % jd)
	var mx: float = slips.max()
	ok(mx > 0.3 and mx < 0.6, "드리프트 미끄러짐 각 %.2f (17°~34°)" % mx)
	ok(Rules.speed_of(k) > 25.0 * 0.85 or k.vel.length() > 24.0, "1.5초 드리프트해도 속도가 남는다 %.1f" % k.vel.length())
	# 커팅: Shift를 0.15초만 끊어 치면, 같은 시간 핸들만 꺾은 것보다 많이 돌고 속도는 거의 그대로
	var cut: Dictionary = mk.call()
	var turn: Dictionary = mk.call()
	for i in 60:
		var on := i < 9
		Rules.step(cut, {"throttle": 1.0, "steer": 1.0 if on else 0.0, "drift": on}, st, dt)
		Rules.step(turn, {"throttle": 1.0, "steer": 1.0 if on else 0.0}, st, dt)
	var cut_ang := absf(atan2(cut.vel.x, cut.vel.y))
	var turn_ang := absf(atan2(turn.vel.x, turn.vel.y))
	ok(cut_ang > turn_ang * 1.3, "끊어 친 드리프트가 더 꺾인다 (%.2f > %.2f rad)" % [cut_ang, turn_ang])
	ok(cut.vel.length() > 28.0 * 0.95, "커팅해도 속도를 거의 안 잃는다 (%.1f)" % cut.vel.length())
	print("  조작감: 핸들 첫 %.3f→%.2f, 드리프트 각 %.2f, 커팅 %.2f vs 핸들 %.2f rad, 속도 %.1f" % [first, prev, mx, cut_ang, turn_ang, cut.vel.length()])
	ok(not cut.drift and absf(cut.slip) < 0.05, "끊어 친 드리프트는 곧 바로 선다 (미끄러짐 %.2f)" % cut.slip)

## 드리프트 기술: 누른 채 방향키(끌기·반대쪽으로 이어가기), 직선에서 톡톡 쳐서 게이지 모으기(톡톡이·커팅)
func _drift_tricks() -> void:
	var st := Rules.kart_stats(kart("acorn"))
	var dt := 1.0 / 60.0
	# 끌기: 누른 채 미는 쪽으로 길게 → 게이지가 많이 찬다
	var k := Rules.new_kart(Vector2.ZERO, 0.0)
	k.vel = Vector2(0, 28)
	for i in 90:
		Rules.step(k, {"throttle": 1.0, "steer": 1.0, "drift": true}, st, dt)
	ok(k.drift and k.gauge > 0.4, "끌기: 1.5초 끌면 게이지가 많이 찬다 (%.2f)" % k.gauge)
	# 누른 채 반대로 꺾으면 코가 돌아오고(드리프트는 이어짐), 더 누르면 반대쪽 드리프트로
	var slip_before := absf(k.slip)
	for i in 15:
		Rules.step(k, {"throttle": 1.0, "steer": -1.0, "drift": true}, st, dt)
	ok(k.drift and absf(k.slip) < slip_before - 0.15, "누른 채 반대 방향키: 코가 돌아온다 (%.2f → %.2f)" % [slip_before, absf(k.slip)])
	var flipped := false
	for i in 50:
		Rules.step(k, {"throttle": 1.0, "steer": -1.0, "drift": true}, st, dt)
		if "drift_flip" in k.events:
			flipped = true
		k.events.clear()
	ok(flipped and k.drift and k.drift_dir == -1 and k.slip < -0.2, "계속 누르면 반대쪽 드리프트로 이어진다 (S자)")
	# 톡톡이·커팅: 직선에서 Shift+방향키를 짧게 좌우로 톡톡 → 앞으로 가면서 게이지를 모은다
	var c := Rules.new_kart(Vector2.ZERO, 0.0)
	c.vel = Vector2(0, st.max_speed)
	var plain := Rules.new_kart(Vector2.ZERO, 0.0)
	plain.vel = Vector2(0, st.max_speed)
	var side := 1.0
	var t := 0.0
	var worst := 0.0
	for i in 240:
		var ph := fmod(t, 0.45)
		if ph < dt:
			# 사람처럼: 가는 방향이 틀어진 반대쪽으로 친다 (거의 똑바르면 번갈아)
			var head := wrapf(atan2(c.vel.x, c.vel.y), -PI, PI)
			side = -side if absf(head) < 0.04 else (1.0 if head > 0.0 else -1.0)
		var inp := {"throttle": 1.0, "steer": 0.0, "drift": false}
		if ph < 0.12:
			inp = {"throttle": 1.0, "steer": side, "drift": true}
		elif ph < 0.3:
			inp = {"throttle": 1.0, "steer": -side, "drift": true}
		Rules.step(c, inp, st, dt)
		Rules.step(plain, {"throttle": 1.0}, st, dt)
		worst = maxf(worst, absf(wrapf(atan2(c.vel.x, c.vel.y), -PI, PI)))
		t += dt
	var gained: float = c.gauge + c.boosts
	print("  톡톡이·커팅 4초: 게이지 %.2f, 속도 %.1f / %.1f, 가장 많이 틀어진 방향 %.2f rad, 앞으로 %.0f / %.0f" % [gained, c.vel.length(), plain.vel.length(), worst, c.pos.y, plain.pos.y])
	ok(gained > 0.6, "커팅: 직선에서 톡톡 쳐서 게이지를 모은다 (%.2f)" % gained)
	ok(worst < 0.35, "커팅해도 거의 앞으로 간다 (%.2f rad)" % worst)
	ok(c.pos.y > plain.pos.y * 0.93, "커팅해도 거리를 크게 안 잃는다 (%.0f / %.0f)" % [c.pos.y, plain.pos.y])

## 방 코드: 6자리, 헷갈리는 글자 없음, 사람이 친 것 다듬기, 중계 글 고르기
func _room_codes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var seen := {}
	for i in 200:
		var c: String = Rules.room_new(r)
		seen[c] = true
		if c.length() != 6 or c.contains("0") or c.contains("O") or c.contains("1") or c.contains("I") or c.contains("L"):
			ok(false, "방 코드 글자 " + c)
	ok(seen.size() > 195, "방 코드가 겹치지 않는다")
	ok(Rules.room_clean(" k7mp-2q ") == "K7MP2Q" and Rules.room_clean("K7MP2") == "" and Rules.room_clean("K7MP2QX") == "", "방 코드 다듬기")
	var body := '{"id":"a","event":"open"}\n{"id":"b","event":"message","message":"O:TR1-first"}\n{"id":"c","event":"message","message":"A:TR1-ans"}\n{"id":"d","event":"message","message":"O:TR1-second"}\n'
	var lst := Rules.relay_list(body)
	ok(lst.size() == 3 and lst[0].id == "b" and lst[2].m == "O:TR1-second", "중계 글 목록 (메시지만, 순서대로)")
	ok(Rules.relay_pick(body, "O:") == "TR1-second" and Rules.relay_pick(body, "A:") == "TR1-ans" and Rules.relay_pick("", "O:") == "", "중계 글에서 마지막 초대·답장 고르기")

## 게이지 밸런스: 톡톡이가 그냥 길게 끄는 것보다 빨리, 부스터 중엔 더 빨리, 비싼 카트일수록 잘 찬다. 후진 드리프트
func _gauge_balance() -> void:
	var dt := 1.0 / 60.0
	var run := func(st: Dictionary, tap: bool, boost: bool) -> float:
		var k := Rules.new_kart(Vector2.ZERO, 0.0)
		k.vel = Vector2(0, 28)
		for i in 90:
			if boost:
				k.boost_t = 1.0
			var key := fmod(i * dt, 0.25) < 0.07 if tap else true
			Rules.step(k, {"throttle": 1.0, "steer": 1.0, "drift": key}, st, dt)
		return k.gauge + k.boosts
	var st := Rules.kart_stats(kart("acorn"))
	var long: float = run.call(st, false, false)
	var tap: float = run.call(st, true, false)
	var boosted: float = run.call(st, false, true)
	print("  게이지 1.5초: 끌기 %.2f, 톡톡이 %.2f, 부스터 중 끌기 %.2f" % [long, tap, boosted])
	ok(tap > long * 1.2, "톡톡이가 길게 끄는 것보다 빨리 찬다 (%.2f > %.2f)" % [tap, long])
	ok(boosted > long * 1.3, "부스터 중 드리프트는 더 잘 찬다 (%.2f > %.2f)" % [boosted, long])
	# 연타로 덤을 끝없이 받지는 못한다 (한 프레임마다 눌렀다 떼도 덤은 쉬는 시간마다 한 번)
	var spam := Rules.new_kart(Vector2.ZERO, 0.0)
	spam.vel = Vector2(0, 28)
	for i in 90:
		Rules.step(spam, {"throttle": 1.0, "steer": 1.0, "drift": i % 2 == 0}, st, dt)
	ok(spam.gauge + spam.boosts < tap * 1.35, "연타해도 덤은 한도가 있다 (%.2f)" % (spam.gauge + spam.boosts))
	# 카트별: 처음 카트가 가장 적게, 비싼 카트일수록 잘 찬다 (두 배쯤 차이)
	var gains := []
	for k in karts:
		gains.append(Rules.kart_stats(k).drift_gain)
	ok(gains[0] == gains.min(), "처음 카트가 드리프트 게이지가 가장 느리다")
	ok(gains.max() > gains[0] * 1.8, "가장 좋은 카트는 처음 카트의 거의 두 배 (%.2f / %.2f)" % [gains.max(), gains[0]])
	ok(Rules.kart_stats(kart("firefly")).drift_gain >= Rules.kart_stats(kart("pinwheel")).drift_gain, "최고급 카트도 잘 찬다")
	# 후진 드리프트: 뒤로 가며 드리프트 키 + 방향키 → 그냥 후진 핸들보다 크게 돈다
	var rev := func(drift: bool) -> float:
		var k := Rules.new_kart(Vector2.ZERO, 0.0)
		k.vel = Vector2(0, -8.5)
		var y0: float = k.yaw
		for i in 40:
			Rules.step(k, {"throttle": -1.0, "steer": 1.0, "drift": drift}, st, dt)
		return absf(wrapf(k.yaw - y0, -PI, PI))
	var r1: float = rev.call(false)
	var r2: float = rev.call(true)
	ok(r2 > r1 * 1.5, "후진 드리프트는 크게 돈다 (%.2f > %.2f rad)" % [r2, r1])

## 브레이크 드리프트(드리프트 중 ↓), 순간부스터 기회가 펴지기 시작할 때 열리고 살짝 일찍 눌러도 됨
func _brake_and_mini() -> void:
	var st := Rules.kart_stats(kart("acorn"))
	var dt := 1.0 / 60.0
	var turn := func(brake: bool) -> Array:
		var k := Rules.new_kart(Vector2.ZERO, 0.0)
		k.vel = Vector2(0, 28)
		for i in 60:
			Rules.step(k, {"throttle": -1.0 if (brake and i > 6) else 1.0, "steer": 1.0, "drift": true}, st, dt)
		return [absf(wrapf(atan2(k.vel.x, k.vel.y), -PI, PI)), k.vel.length(), k.drift]
	var a: Array = turn.call(false)
	var b: Array = turn.call(true)
	ok(b[0] > a[0] * 1.2 and b[2], "드리프트 중 ↓: 더 크게 돈다 (%.2f > %.2f rad), 드리프트는 이어짐" % [b[0], a[0]])
	ok(b[1] > 12.0, "브레이크 드리프트는 급브레이크처럼 서지 않는다 (%.1f)" % b[1])
	# 순간부스터: 카운터를 넣어 펴지기 시작하면 아직 드리프트 중이어도 기회가 열린다
	var k := Rules.new_kart(Vector2.ZERO, 0.0)
	k.vel = Vector2(0, 28)
	for i in 30:
		Rules.step(k, {"throttle": 1.0, "steer": 1.0, "drift": true}, st, dt)
	var opened_in_drift := false
	for i in 12:
		Rules.step(k, {"throttle": 1.0, "steer": -1.0}, st, dt)
		if k.window_t > 0.0 and k.drift:
			opened_in_drift = true
	ok(opened_in_drift, "펴지기 시작하면 (아직 드리프트 중에도) 순간부스터 기회")
	# 살짝 일찍(드리프트 중에) ↑를 눌러도 기회가 열리면 쳐 준다
	var e := Rules.new_kart(Vector2.ZERO, 0.0)
	e.vel = Vector2(0, 28)
	for i in 30:
		Rules.step(e, {"throttle": 1.0, "steer": 1.0, "drift": true}, st, dt)
	Rules.step(e, {"throttle": 1.0, "steer": 1.0, "drift": true, "accel_tap": true}, st, dt)
	var got := false
	for i in 14:
		Rules.step(e, {"throttle": 1.0, "steer": -1.0}, st, dt)
		if "mini_boost" in e.events: got = true
		e.events.clear()
	ok(got, "살짝 일찍 누른 ↑도 순간부스터")
	# 너무 일찍 누른 건 안 된다
	var f := Rules.new_kart(Vector2.ZERO, 0.0)
	f.vel = Vector2(0, 28)
	for i in 10:
		Rules.step(f, {"throttle": 1.0, "steer": 1.0, "drift": true}, st, dt)
	Rules.step(f, {"throttle": 1.0, "steer": 1.0, "drift": true, "accel_tap": true}, st, dt)
	for i in 30:
		Rules.step(f, {"throttle": 1.0, "steer": 1.0, "drift": true}, st, dt)
	var got2 := false
	for i in 20:
		Rules.step(f, {"throttle": 1.0, "steer": -1.0}, st, dt)
		if "mini_boost" in f.events: got2 = true
		f.events.clear()
	ok(not got2, "한참 전에 누른 ↑는 순간부스터가 아니다")

## 아이템전: 순위별 아이템, 칸 두 개, 맞으면 빙글·방패, 빙글 도는 동안 느려지고 조작 안 됨
func _items() -> void:
	var count := func(place: int) -> Dictionary:
		var c := {}
		for i in 2000:
			var it := Rules.item_roll(place, 8, (i + 0.5) / 2000.0)
			c[it] = int(c.get(it, 0)) + 1
		return c
	var first: Dictionary = count.call(1)
	var last: Dictionary = count.call(8)
	ok(int(first.get("bees", 0)) == 0 and int(first.get("wind", 0)) == 0, "1등은 꿀벌·회오리바람을 안 받는다")
	ok(int(last.get("boost", 0)) > int(first.get("boost", 0)) and int(last.get("bees", 0)) > 300, "꼴찌는 부스터·꿀벌을 더 받는다")
	ok(int(first.get("acorn", 0)) + int(first.get("shield", 0)) > int(last.get("acorn", 0)) + int(last.get("shield", 0)), "1등은 지키는 아이템을 더 받는다")
	for it in Rules.ITEMS:
		ok(Rules.ITEM_NAMES.has(it), "아이템 이름 " + it)
	var k := Rules.new_kart(Vector2.ZERO, 0.0)
	ok(Rules.give_item(k, "boost") and Rules.give_item(k, "acorn") and not Rules.give_item(k, "bees") and k.items.size() == 2, "아이템은 두 칸까지")
	k.vel = Vector2(0, 30)
	k.shield_t = 3.0
	ok(not Rules.hit(k) and k.shield_t == 0.0 and "shield_break" in k.events, "방패는 한 번 막는다")
	ok(Rules.hit(k) and k.spin_t > 0.0, "맞으면 빙글")
	var st := Rules.kart_stats(kart("acorn"))
	var y0: float = k.yaw
	Rules.step(k, {"throttle": 1.0, "steer": 1.0, "drift": true}, st, 1.0 / 60.0)
	ok(not k.drift and absf(wrapf(k.yaw - y0, -PI, PI)) > 0.1, "빙글 도는 동안 조작이 안 먹고 돈다")
	for i in 80:
		Rules.step(k, {"throttle": 1.0}, st, 1.0 / 60.0)
	ok(k.spin_t == 0.0 and k.vel.length() < 15.0, "다 돌면 많이 느려져 있다 (%.1f)" % k.vel.length())
	var g := Rules.new_kart(Vector2.ZERO, 0.0)
	g.no_gauge = true
	g.gauge = 1.5
	Rules.step(g, {}, st, 1.0 / 60.0)
	ok(g.boosts == 0 and g.gauge == 0.0, "아이템전은 드리프트 게이지로 부스터가 안 생긴다")
