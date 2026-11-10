class_name Rules
extends RefCounted
## 화면과 떨어진 게임 규칙(계산)만 모은 곳. 테스트: godot --headless -s tests/run_tests.gd
##
## 좌표: 바닥은 (x, z) 평면을 Vector2(x, z)로 쓴다. yaw = 0 이면 +z 쪽을 본다.
##   앞 = (sin yaw, cos yaw), 오른쪽 = (-cos yaw, sin yaw). 오른쪽으로 꺾으면 yaw가 줄어든다.

const KMH := 5.0                 ## 화면에 보이는 속도 = 속력 × KMH
const MAX_BOOSTS := 2            ## 부스터는 두 개까지 모은다
const MINI_WINDOW := 0.35        ## 드리프트가 끝난 뒤 순간부스터를 쓸 수 있는 시간(초)
const START_WINDOW := 0.4        ## 출발 직전 이 시간 안에 가속을 누르면 출발 부스터
const DRIFT_MIN_SPEED := 9.0

# ────────────────────────── 카트 능력치 ──────────────────────────

## 1~10 능력치를 실제 주행 값으로 바꾼다.
static func kart_stats(def: Dictionary) -> Dictionary:
	var s: Dictionary = def.get("stats", {})
	var g := func(k: String) -> float: return clampf(float(s.get(k, 5)), 1.0, 10.0)
	return {
		"max_speed": 27.0 + g.call("speed") * 0.9,      # 27.9 ~ 36
		"accel": 13.0 + g.call("accel") * 1.7,          # 14.7 ~ 30
		"turn": 1.55 + g.call("handling") * 0.11,       # 초당 회전(라디안)
		"grip": 7.0 + g.call("handling") * 0.5,         # 옆으로 미끄러짐이 사라지는 빠르기
		"drift_gain": 0.30 + g.call("drift") * 0.045,   # 드리프트 게이지가 차는 빠르기
		"boost_time": 1.7 + g.call("boost") * 0.09,     # 부스터 길이(초)
		"boost_mult": 1.34,
		"weight": g.call("weight"),
	}

## 새 카트 상태
static func new_kart(pos: Vector2, yaw: float) -> Dictionary:
	return {
		"pos": pos, "vel": Vector2.ZERO, "yaw": yaw, "yaw_rate": 0.0,
		"drift": false, "drift_dir": 0, "drift_time": 0.0,
		"gauge": 0.0, "boosts": 0, "boost_t": 0.0, "mini_t": 0.0, "window_t": 0.0,
		"slip": 0.0, "offroad": false, "events": [],
	}

static func fwd(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))

static func right(yaw: float) -> Vector2:
	return Vector2(-cos(yaw), sin(yaw))

static func speed_of(k: Dictionary) -> float:
	return (k.vel as Vector2).dot(fwd(k.yaw))

static func boosting(k: Dictionary) -> bool:
	return k.boost_t > 0.0 or k.mini_t > 0.0

## 지금 낼 수 있는 최고 속력
static func top_speed(k: Dictionary, st: Dictionary) -> float:
	var top: float = st.max_speed
	if k.offroad:
		# 잔디는 느리다. 부스터를 쓰면 덜 느려져서 부스터 커팅이 된다.
		top *= 0.86 if boosting(k) else 0.55
	if k.boost_t > 0.0:
		top *= st.boost_mult
	elif k.mini_t > 0.0:
		top *= 1.2
	return top

## 한 프레임 주행. inp = {throttle: -1..1, steer: -1..1(오른쪽 +), drift: bool, accel_tap: bool, use_boost: bool}
## 소리·글자용 사건은 k.events 에 쌓는다 (부르는 쪽이 비운다).
static func step(k: Dictionary, inp: Dictionary, st: Dictionary, dt: float) -> void:
	var f := fwd(k.yaw)
	var r := right(k.yaw)
	var vel: Vector2 = k.vel
	var vf := vel.dot(f)
	var vl := vel.dot(r)
	var throttle: float = clampf(float(inp.get("throttle", 0.0)), -1.0, 1.0)
	var steer: float = clampf(float(inp.get("steer", 0.0)), -1.0, 1.0)
	var top := top_speed(k, st)

	# ── 가속·감속
	if boosting(k) and throttle >= 0.0:
		vf = move_toward(vf, top, 55.0 * dt)
	elif throttle > 0.0:
		if vf < top:
			var curve := 1.0 - 0.55 * clampf(vf / top, 0.0, 1.0)
			vf = minf(top, vf + st.accel * throttle * curve * dt)
	elif throttle < 0.0:
		if vf > 0.5:
			vf = maxf(0.0, vf - 38.0 * dt)
		else:
			vf = maxf(-9.0, vf - 14.0 * dt)
	else:
		vf = move_toward(vf, 0.0, 5.0 * dt)
	if vf > top:  # 부스터가 끝났거나 잔디에 들어가면 천천히 최고 속력으로
		vf = move_toward(vf, top, (30.0 if k.offroad else 14.0) * dt)

	# ── 드리프트 시작: 드리프트 키 + 방향키 + 어느 정도 속력
	var was_drift: bool = k.drift
	if inp.get("drift", false) and not k.drift and absf(steer) > 0.3 and vf > DRIFT_MIN_SPEED:
		k.drift = true
		k.drift_dir = 1 if steer > 0.0 else -1
		k.drift_time = 0.0
		k.events.append("drift_start")

	# ── 핸들
	var yaw_rate := 0.0
	var new_yaw: float = k.yaw
	if k.drift:
		k.drift_time += dt
		var dir := float(k.drift_dir)
		var speed := vel.length()
		var va := atan2(vel.x, vel.y)          # 실제로 가는 방향
		var released: bool = not inp.get("drift", false)
		var push := steer * dir                 # +면 미는 쪽, -면 카운터
		# 가는 길이 굽는 빠르기: 미는 쪽으로 꺾을수록 많이, 카운터면 조금
		var amt := clampf(0.55 + 0.5 * push, 0.2, 1.05)
		# 코가 가는 방향보다 안쪽을 보는 각도(미끄러짐 각)
		var cur_slip := wrapf(va - k.yaw, -PI, PI) * dir
		va -= dir * st.turn * 1.12 * amt * dt
		var want := 0.5 * (0.65 + 0.35 * amt)
		var rate := 6.0
		var ending := false
		if released and push < -0.2:
			want = 0.0; rate = 9.0; ending = true     # 카운터: 빨리 펴진다
		elif released and push < 0.3:
			want = 0.0; rate = 3.0; ending = true     # 손을 떼면 천천히 펴진다
		cur_slip = lerpf(cur_slip, want, 1.0 - exp(-rate * dt))
		new_yaw = va - dir * cur_slip
		# 속력: 가속 키로 조금 유지, 미끄러지는 만큼 조금 잃는다
		if throttle > 0.0 and speed < top:
			speed += st.accel * 0.22 * dt
		speed -= (0.8 + 2.2 * cur_slip) * dt
		speed = minf(speed, maxf(top, vf))
		vel = fwd(va) * speed
		k.gauge += st.drift_gain * (0.3 + 0.7 * clampf(cur_slip / 0.45, 0.0, 1.0)) * clampf(speed / 20.0, 0.0, 1.0) * dt
		yaw_rate = wrapf(new_yaw - k.yaw, -PI, PI) / dt
		k.slip = cur_slip * dir
		if (ending and cur_slip < 0.08) or speed < 6.0:
			k.drift = false
			# 남은 옆 미끄러짐은 일반 손잡이로 넘긴다
	else:
		var low := clampf(absf(vf) / 7.0, 0.35, 1.0)   # 멈춰 있어도 조금은 돈다
		var high := 1.0 - 0.22 * clampf(vf / st.max_speed, 0.0, 1.2)
		yaw_rate = -steer * st.turn * low * high * (1.0 if vf >= 0.0 else -1.0)
		new_yaw = k.yaw + yaw_rate * dt
		var nl2 := vl * exp(-st.grip * dt)
		vf += absf(vl - nl2) * 0.25 * signf(vf)
		vl = nl2
		vel = f * vf + r * vl
		k.slip = vl * 0.05
	if was_drift and not k.drift:
		k.events.append("drift_end")
		if k.drift_time > 0.3:
			k.window_t = MINI_WINDOW

	# ── 순간부스터: 드리프트가 끝난 직후 가속 키를 다시 누른다
	if k.window_t > 0.0 and inp.get("accel_tap", false) and not k.drift:
		k.window_t = 0.0
		k.mini_t = maxf(k.mini_t, 0.6)
		k.events.append("mini_boost")

	# ── 게이지가 차면 부스터 하나
	if k.gauge >= 1.0:
		k.gauge -= 1.0
		if k.boosts < MAX_BOOSTS:
			k.boosts += 1
			k.events.append("boost_gain")
		else:
			k.gauge = 0.0

	# ── 부스터 쓰기
	if inp.get("use_boost", false) and k.boosts > 0 and k.boost_t < 0.3:
		k.boosts -= 1
		k.boost_t = st.boost_time
		k.events.append("boost")

	k.yaw = wrapf(new_yaw, -PI, PI)
	k.yaw_rate = yaw_rate
	k.vel = vel
	k.pos = (k.pos as Vector2) + (k.vel as Vector2) * dt
	k.boost_t = maxf(0.0, k.boost_t - dt)
	k.mini_t = maxf(0.0, k.mini_t - dt)
	k.window_t = maxf(0.0, k.window_t - dt)

## 출발 부스터: 출발(0초)까지 남은 시간이 `left`일 때 가속을 처음 눌렀다면 부스터 길이, 아니면 0
static func start_boost(left: float) -> float:
	if left >= 0.0 and left <= START_WINDOW:
		return 1.0
	return 0.0

# ────────────────────────── 트랙 ──────────────────────────

static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

## 트랙 정의(tracks.json의 한 항목)로 가운데 선을 `spacing` 간격 점으로 만든다.
static func build_track(def: Dictionary, spacing := 2.0) -> Dictionary:
	var ctrl: Array[Vector2] = []
	for p in def.points:
		ctrl.append(Vector2(p[0], p[1]))
	var n := ctrl.size()
	var dense: Array[Vector2] = []
	for i in n:
		for j in 24:
			dense.append(_cr(ctrl[(i - 1 + n) % n], ctrl[i], ctrl[(i + 1) % n], ctrl[(i + 2) % n], j / 24.0))
	# 같은 간격으로 다시 고르기
	var total := 0.0
	for i in dense.size():
		total += dense[i].distance_to(dense[(i + 1) % dense.size()])
	var count := maxi(16, int(round(total / spacing)))
	var step_len := total / count
	var pts := PackedVector2Array()
	var acc := 0.0
	var want := 0.0
	for i in dense.size():
		var a := dense[i]
		var b := dense[(i + 1) % dense.size()]
		var seg := a.distance_to(b)
		while want <= acc + seg and pts.size() < count:
			pts.append(a.lerp(b, (want - acc) / maxf(seg, 0.0001)))
			want += step_len
		acc += seg
	var m := pts.size()
	var tang := PackedVector2Array()
	var norm := PackedVector2Array()
	var cum := PackedFloat32Array()
	var curv := PackedFloat32Array()
	tang.resize(m); norm.resize(m); cum.resize(m); curv.resize(m)
	var s := 0.0
	for i in m:
		var t := (pts[(i + 1) % m] - pts[(i - 1 + m) % m]).normalized()
		tang[i] = t
		norm[i] = Vector2(-t.y, t.x)   # 달리는 쪽에서 오른쪽
		cum[i] = s
		s += pts[i].distance_to(pts[(i + 1) % m])
	for i in m:
		# 굽은 정도(+면 오른쪽으로 굽음)
		var a2 := tang[(i - 2 + m) % m]
		var b2 := tang[(i + 2) % m]
		curv[i] = a2.angle_to(b2) / (4.0 * step_len)
	var hw: float = def.get("half_width", 8.0)
	return {
		"pts": pts, "tan": tang, "nrm": norm, "cum": cum, "curv": curv, "length": s, "n": m,
		"half_width": hw, "wall": hw + float(def.get("verge", 7.0)), "laps": int(def.get("laps", 3)),
	}

## 가장 가까운 가운데 선 위치. hint(지난번 번호)가 있으면 그 근처만 본다.
## 돌려주는 것: {i, s(출발선부터 거리), lat(오른쪽 +), point, tan}
static func locate(tr: Dictionary, pos: Vector2, hint := -1) -> Dictionary:
	var pts: PackedVector2Array = tr.pts
	var m: int = tr.n
	var best := -1
	var bd := INF
	if hint >= 0:
		for o in range(-12, 13):
			var j := (hint + o + m) % m
			var d := pts[j].distance_squared_to(pos)
			if d < bd:
				bd = d; best = j
		if bd > 30.0 * 30.0:
			best = -1
	if best < 0:
		bd = INF
		for j in m:
			var d := pts[j].distance_squared_to(pos)
			if d < bd:
				bd = d; best = j
	# 이웃 선분 둘 중 더 가까운 쪽에 비춰 본다
	var res := {}
	var bestd := INF
	for seg in [[(best - 1 + m) % m, best], [best, (best + 1) % m]]:
		var a := pts[seg[0]]
		var b := pts[seg[1]]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_squared_to(pos)
		if d < bestd:
			bestd = d
			var tn := ab.normalized()
			var nn := Vector2(-tn.y, tn.x)
			var s: float = tr.cum[seg[0]] + ab.length() * t
			res = {"i": best, "s": fposmod(s, tr.length), "lat": (pos - q).dot(nn), "point": q, "tan": tn}
	return res

## 바닥 종류: "road" 도로, "grass" 잔디(느림), 울타리 밖은 벽으로 막힌다
static func surface(tr: Dictionary, lat: float) -> String:
	return "road" if absf(lat) <= tr.half_width else "grass"

## 울타리 밖으로 나가면 안으로 밀고 바깥쪽 속도를 없앤다. 부딪혔으면 true
static func wall_push(tr: Dictionary, k: Dictionary, loc: Dictionary, radius := 0.8) -> bool:
	var lim: float = tr.wall - radius
	if absf(loc.lat) <= lim:
		return false
	var tn: Vector2 = loc.tan
	var nn := Vector2(-tn.y, tn.x) * signf(loc.lat)
	k.pos = (loc.point as Vector2) + nn * lim
	var v: Vector2 = k.vel
	var out := v.dot(nn)
	if out > 0.0:
		v -= nn * out * 1.4
	k.vel = v * 0.93
	k.drift = false
	return true

## 이어지는 거리: 지난 거리 `prev`(랩 포함)와 지금 트랙 위 위치 s 로 새 거리
static func advance(prev: float, s: float, length: float) -> float:
	var cur := fposmod(prev, length)
	var d := s - cur
	if d > length * 0.5:
		d -= length
	elif d < -length * 0.5:
		d += length
	return prev + d

## 지금 몇 번째 랩인지 (1부터). 출발선 뒤(음수)면 1
static func lap_of(dist: float, length: float) -> int:
	return maxi(1, int(floor(dist / length)) + 1)

## 순위: 들어온 사람은 들어온 시간 순, 나머지는 간 거리 순. 각 항목 {dist, finish(-1이면 아직)}
static func ranking(rs: Array) -> Array:
	var idx := range(rs.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		var fa: float = rs[a].finish
		var fb: float = rs[b].finish
		if fa >= 0.0 and fb >= 0.0:
			return fa < fb
		if fa >= 0.0 or fb >= 0.0:
			return fa >= 0.0
		return rs[a].dist > rs[b].dist)
	return idx

## 레이싱 라인: 가운데 선에서 옆으로 얼마나 비킬지(점마다). 굽이 안쪽을 스치는 매끈한 길
static func racing_line(tr: Dictionary, margin := 2.0, iters := 400) -> PackedFloat32Array:
	var m: int = tr.n
	var lim: float = tr.half_width - margin
	var off := PackedFloat32Array()
	off.resize(m)
	var pts: PackedVector2Array = tr.pts
	var nrm: PackedVector2Array = tr.nrm
	for _it in iters:
		for i in m:
			var a := pts[(i - 1 + m) % m] + nrm[(i - 1 + m) % m] * off[(i - 1 + m) % m]
			var b := pts[(i + 1) % m] + nrm[(i + 1) % m] * off[(i + 1) % m]
			var mid := (a + b) * 0.5
			off[i] = clampf((mid - pts[i]).dot(nrm[i]), -lim, lim)
	return off

## 출발 자리: 출발선 뒤로 두 줄씩
static func grid_slot(tr: Dictionary, slot: int) -> Dictionary:
	var row := int(slot / 2.0)
	var side := -1.0 if slot % 2 == 0 else 1.0
	var back := 6.0 + row * 5.0
	var m: int = tr.n
	var i := m - 1
	var s := 0.0
	while s < back and i > 0:
		s += (tr.pts[i] as Vector2).distance_to(tr.pts[(i + 1) % m])
		i -= 1
	var t: Vector2 = tr.tan[i]
	var p: Vector2 = tr.pts[i] + tr.nrm[i] * side * tr.half_width * 0.42 + Vector2(0, 0)
	if slot % 2 == 1:
		p -= t * 2.5   # 엇갈리게
	return {"pos": p, "yaw": atan2(t.x, t.y)}

# ────────────────────────── 컴퓨터 상대 ──────────────────────────

## 컴퓨터가 누를 키. line = 레이싱 라인, skill 0..1, offset = 레이싱 라인에서 더 비킬 거리, rnd = 0..1 난수
static func ai_input(k: Dictionary, tr: Dictionary, line: PackedFloat32Array, loc: Dictionary, skill: float, offset: float, rnd: float) -> Dictionary:
	var m: int = tr.n
	var spd := absf(speed_of(k))
	var look := int(clampf(4.0 + spd * 0.32, 4.0, 16.0))
	var j: int = (loc.i + look) % m
	var lim: float = tr.half_width - 1.0
	var target: Vector2 = tr.pts[j] + tr.nrm[j] * clampf(line[j] + offset, -lim, lim)
	var to := target - (k.pos as Vector2)
	var f := fwd(k.yaw)
	var ang := f.angle_to(to)        # 이 좌표에서는 +가 오른쪽
	var steer := clampf(ang * 2.4, -1.0, 1.0)
	if k.drift and (k.vel as Vector2).length() > 1.0:
		# 드리프트 중에는 코가 아니라 실제로 가는 방향을 기준으로 꺾는다
		ang = (k.vel as Vector2).normalized().angle_to(to)
		steer = clampf(ang * 3.0, -1.0, 1.0)
	# 앞쪽이 얼마나 굽었는지
	var bend := 0.0
	for o in [6, 10, 14, 18]:
		bend += float(tr.curv[(loc.i + o) % m])
	bend /= 4.0
	var sharp := absf(bend) * 30.0           # 대략 0(직선) ~ 1.5(머리핀)
	var drift := false
	if k.drift:
		drift = (k.drift_time < 0.45 or (sharp > 0.3 and signf(bend) == float(k.drift_dir))) and steer * k.drift_dir > -0.3
	elif sharp > 0.55 and spd > 18.0 and rnd < 0.25 + skill * 0.6:
		drift = true
		steer = signf(bend) if absf(steer) < 0.4 else steer
	var throttle := 1.0
	if absf(ang) > 1.2 and spd > 12.0:
		throttle = -1.0
	if spd < 3.0 and absf(ang) > 1.4:
		# 벽에 붙어 멈췄으면 뒤로 빼면서 돈다
		throttle = -1.0
		steer = -signf(ang)
	var use: bool = k.boosts > 0 and sharp < 0.25 and not k.drift and rnd < 0.02 + skill * 0.06
	var tap: bool = k.window_t > 0.0 and k.window_t < MINI_WINDOW - 0.08 and rnd < skill
	return {"throttle": throttle, "steer": steer, "drift": drift, "accel_tap": tap, "use_boost": use}

## 컴퓨터 실력에 맞춘 능력치 (조금 느리게, 뒤처지면 살짝 따라잡기)
static func ai_stats(st: Dictionary, skill: float, behind: float) -> Dictionary:
	var out := st.duplicate()
	var catch := clampf(behind / 120.0, -0.4, 1.0) * 0.06
	out.max_speed = st.max_speed * (0.88 + 0.1 * skill + catch)
	out.accel = st.accel * (0.9 + 0.1 * skill)
	return out

# ────────────────────────── 돈·상점·저장 ──────────────────────────

## 순위 보상 (place는 1부터). 연습(혼자)은 기록 보상만
static func reward(place: int, racers: int, mode: String) -> int:
	if mode == "time":
		return 0
	var table := [120, 90, 70, 55, 45, 35, 30, 25]
	var base: int = table[clampi(place - 1, 0, table.size() - 1)]
	if racers <= 1:
		return 0
	return base

## 기록 보상: 처음 달린 트랙이거나 기록을 깼으면 돈
static func record_reward(best: float, time: float) -> int:
	if best <= 0.0:
		return 40
	if time < best:
		return 60
	return 10

const COIN_VALUE := 5

static func can_buy(save: Dictionary, kart: Dictionary) -> bool:
	return not (kart.id in save.owned) and int(save.coins) >= int(kart.price)

## 사면 새 저장 값, 못 사면 그대로
static func buy(save: Dictionary, kart: Dictionary) -> Dictionary:
	if not can_buy(save, kart):
		return save
	var s := save.duplicate(true)
	s.coins = int(s.coins) - int(kart.price)
	s.owned.append(kart.id)
	s.kart = kart.id
	return s

static func default_save() -> Dictionary:
	return {"v": 1, "coins": 0, "owned": ["acorn"], "kart": "acorn", "kart2": "acorn", "best": {}, "races": 0}

## 저장 값 읽기. 망가졌거나 모자란 값도 받아 준다
static func parse_save(raw: Variant, kart_ids: Array) -> Dictionary:
	var s := default_save()
	if typeof(raw) == TYPE_STRING:
		var j := JSON.new()
		raw = j.data if j.parse(raw) == OK else null
	if typeof(raw) != TYPE_DICTIONARY:
		return s
	if typeof(raw.get("coins")) in [TYPE_INT, TYPE_FLOAT]:
		s.coins = maxi(0, int(raw.coins))
	if typeof(raw.get("owned")) == TYPE_ARRAY:
		for id in raw.owned:
			if id in kart_ids and not (id in s.owned):
				s.owned.append(id)
	for key in ["kart", "kart2"]:
		if raw.get(key) in s.owned:
			s[key] = raw[key]
	if typeof(raw.get("best")) == TYPE_DICTIONARY:
		for t in raw.best:
			if typeof(raw.best[t]) in [TYPE_INT, TYPE_FLOAT] and float(raw.best[t]) > 0.0:
				s.best[str(t)] = float(raw.best[t])
	if typeof(raw.get("races")) in [TYPE_INT, TYPE_FLOAT]:
		s.races = maxi(0, int(raw.races))
	return s

## 시간 글자 1:23.45
static func time_text(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var sec := t - m * 60.0
	return "%d:%05.2f" % [m, sec]

# ────────────────────────── 온라인 연결 코드 ──────────────────────────

const NET_PREFIX := "TR1-"

## 코드 = 접두어 + base64(압축(JSON))
static func net_encode(desc: Dictionary, cands: Array) -> String:
	var raw := JSON.stringify({"t": desc.t, "s": desc.s, "c": cands}).to_utf8_buffer()
	return NET_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))

static func net_decode(code: String) -> Dictionary:
	var s := code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	var at := s.find(NET_PREFIX)
	if at < 0:
		return {}
	s = s.substr(at + NET_PREFIX.length())
	# base64 글자만 남긴다 (메신저가 덧붙인 글자 버리기)
	var only := ""
	for ch in s:
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in ["+", "/", "="]:
			only += ch
		else:
			break
	s = only
	if s.length() < 16 or s.length() % 4 != 0:
		return {}
	var bytes := Marshalls.base64_to_raw(s)
	if bytes.is_empty():
		return {}
	var raw := bytes.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return {}
	var j := JSON.new()
	if j.parse(raw.get_string_from_utf8()) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = j.data
	if not (d.has("t") and d.has("s") and d.has("c")) or typeof(d.c) != TYPE_ARRAY:
		return {}
	return d
