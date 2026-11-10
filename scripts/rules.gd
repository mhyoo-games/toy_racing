class_name Rules
extends RefCounted
## 화면과 떨어진 게임 규칙(계산)만 모은 곳. 테스트: godot --headless -s tests/run_tests.gd
##
## 좌표: 바닥은 (x, z) 평면을 Vector2(x, z)로 쓴다. yaw = 0 이면 +z 쪽을 본다.
##   앞 = (sin yaw, cos yaw), 오른쪽 = (-cos yaw, sin yaw). 오른쪽으로 꺾으면 yaw가 줄어든다.

const KMH := 5.0                 ## 화면에 보이는 속도 = 속력 × KMH
const MAX_BOOSTS := 2            ## 부스터는 두 개까지 모은다
const MINI_WINDOW := 0.35        ## 드리프트가 끝난 뒤 순간부스터를 쓸 수 있는 시간(초) — 펴지기 시작할 때부터 열린다
const MINI_EARLY := 0.12         ## 이만큼 일찍 눌러도 순간부스터로 쳐 준다
const MINI_TIME := 0.7           ## 순간부스터 길이
const START_WINDOW := 0.4        ## 출발 직전 이 시간 안에 가속을 누르면 출발 부스터
const DRIFT_MIN_SPEED := 9.0
const STEER_IN := 5.5            ## 핸들이 꺾이는 빠르기 (1/초, 끝까지 약 0.18초)
const STEER_OUT := 9.0           ## 핸들을 놓을 때 돌아오는 빠르기
const STEER_DRIFT := 11.0        ## 드리프트 중 핸들 빠르기
const TAP_BONUS := 0.9           ## 드리프트를 막 건 순간의 게이지 덤 (짧게 여러 번 = 톡톡이·커팅이 빨리 참)
const TAP_TIME := 0.35           ## 그 덤이 줄어드는 시간
const BOOST_GAUGE := 1.5         ## 부스터 중 드리프트하면 게이지 배율
const TAP_CHUNK := 0.14          ## 드리프트를 걸 때·톡 칠 때마다 얹어 주는 게이지 (× 카트 드리프트 능력)
const TAP_COOLDOWN := 0.18       ## 덤은 이 시간에 한 번까지 (연타 막기)
const TAP_KICK := 0.5            ## 톡 칠 때 더 도는 회전 속도
const DRIFT_GRIP := 5.0          ## 드리프트 중 가는 방향이 코를 따라가는 빠르기 (낮을수록 많이 미끄러짐)
const RECOVER_TIME := 0.42       ## 드리프트가 끝난 뒤 접지가 다 돌아오는 시간 (그동안 속도를 거의 안 잃음 = 톡톡이)

# ────────────────────────── 카트 능력치 ──────────────────────────

## 1~10 능력치를 실제 주행 값으로 바꾼다.
static func kart_stats(def: Dictionary) -> Dictionary:
	var s: Dictionary = def.get("stats", {})
	var g := func(k: String) -> float: return clampf(float(s.get(k, 5)), 1.0, 10.0)
	return {
		"max_speed": 27.0 + g.call("speed") * 0.9,      # 27.9 ~ 36
		"accel": 13.0 + g.call("accel") * 1.7,          # 14.7 ~ 30
		"turn": 1.55 + g.call("handling") * 0.11,       # 초당 회전(라디안)
		"grip": 14.0 + g.call("handling") * 0.9,        # 보통 때 가는 방향이 코를 따라가는 빠르기
		"drift_gain": 0.16 + g.call("drift") * 0.055,   # 드리프트 게이지가 차는 빠르기 (능력치 3 → 0.33, 9 → 0.66: 두 배)
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
		"steer_s": 0.0, "recover": 1.0, "prev_key": false, "tap_cd": 0.0, "win_open": false, "tap_buf": 0.0,
		"spin_t": 0.0, "shield_t": 0.0, "items": [], "no_gauge": false,
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
		# 잔디는 느리다. 부스터를 쓰면 덜 느려져서 부스터 지름길이 된다.
		top *= 0.86 if boosting(k) else 0.55
	if k.boost_t > 0.0:
		top *= st.boost_mult
	elif k.mini_t > 0.0:
		top *= 1.2
	return top

## 한 프레임 주행. inp = {throttle: -1..1, steer: -1..1(오른쪽 +), drift: bool, accel_tap: bool, use_boost: bool}
## 소리·글자용 사건은 k.events 에 쌓는다 (부르는 쪽이 비운다).
##
## 모델: 속도는 크기(sp)와 방향(va)으로 나눈다. 핸들은 코(yaw)를 돌리고, 가는 방향(va)은 접지력만큼 코를 따라간다.
##   보통 때는 접지력이 커서 거의 바로 따라가고, 드리프트 중에는 작아서 옆으로 미끄러진다(미끄러짐 각 ≈ 회전 속도 / 접지력).
##   방향만 돌 뿐 속도 크기는 미끄러지는 만큼만 조금씩 준다 → 드리프트해도 속도가 살아 있다.
##   드리프트가 끝나면 접지력이 RECOVER_TIME에 걸쳐 돌아온다 → Shift를 짧게 끊어 치면 속도를 잃지 않고 방향만 꺾인다(톡톡이). 직선에서 좌우로 톡톡 치면 앞으로 가며 게이지가 찬다(커팅).
static func step(k: Dictionary, inp: Dictionary, st: Dictionary, dt: float) -> void:
	if float(k.get("spin_t", 0.0)) > 0.0:
		_spin_step(k, dt)
		return
	k.shield_t = maxf(0.0, float(k.get("shield_t", 0.0)) - dt)
	var throttle: float = clampf(float(inp.get("throttle", 0.0)), -1.0, 1.0)
	var raw: float = clampf(float(inp.get("steer", 0.0)), -1.0, 1.0)
	# ── 핸들을 부드럽게 (키보드도 0 → 1 이 한 번에 가지 않게)
	var cur: float = k.steer_s
	var rate := STEER_OUT
	if raw != 0.0 and (cur == 0.0 or signf(raw) == signf(cur)) and absf(raw) > absf(cur):
		rate = STEER_IN
	if k.drift:
		rate = STEER_DRIFT   # 드리프트 중에는 카운터를 빨리 넣을 수 있게
	k.steer_s = move_toward(cur, raw, rate * dt)
	var steer: float = k.steer_s

	var vel: Vector2 = k.vel
	var sp := vel.length()
	var yaw: float = k.yaw
	var va := atan2(vel.x, vel.y) if sp > 0.3 else yaw
	var backward := sp > 0.3 and vel.dot(fwd(yaw)) < 0.0
	if backward:
		sp = -sp
		va = atan2(-vel.x, -vel.y)   # 뒤로 갈 때는 '움직이는 반대 방향'을 기준으로
	var top := top_speed(k, st)
	# 후진 드리프트: 뒤로 가면서 드리프트 키 + 방향키 → 뒤가 미끄러지며 크게 돈다 (벽에서 돌려 나오기)
	var rev_drift: bool = backward and sp < -1.2 and inp.get("drift", false) and absf(raw) > 0.3
	var brake_drift: bool = k.drift and throttle < 0.0   # 드리프트 중 ↓: 급브레이크 대신 더 크게 돈다 (U턴)

	# ── 드리프트 키를 새로 눌렀나 (톡톡이)
	var key: bool = inp.get("drift", false)
	var key_tap: bool = key and not bool(k.get("prev_key", false))
	k.prev_key = key
	k.tap_cd = maxf(0.0, float(k.get("tap_cd", 0.0)) - dt)
	# ── 드리프트 시작: 드리프트 키 + 방향키 + 어느 정도 속력 (방향은 누른 키 그대로)
	var was_drift: bool = k.drift
	if inp.get("drift", false) and not k.drift and absf(raw) > 0.3 and sp > DRIFT_MIN_SPEED:
		k.drift = true
		k.drift_dir = 1 if raw > 0.0 else -1
		k.drift_time = 0.0
		k.events.append("drift_start")
		_tap_bonus(k, st, sp)
	elif k.drift and key_tap and sp > 18.0 and k.tap_cd <= 0.0:
		# 톡톡이: 드리프트 중에 키를 다시 톡 → 살짝 더 돌고 게이지 덤
		k.yaw_rate = float(k.yaw_rate) - float(k.drift_dir) * TAP_KICK
		k.gauge += TAP_CHUNK * st.drift_gain * (BOOST_GAUGE if boosting(k) else 1.0)
		k.tap_cd = TAP_COOLDOWN
		k.events.append("drift_tap")

	# ── 코를 돌리는 빠르기(목표)와 따라가는 빠르기
	var target_w := 0.0
	var resp := 11.0
	var grip: float = st.grip
	var slide_drag := 6.0
	var ending := false
	if k.drift:
		k.drift_time += dt
		var dir := float(k.drift_dir)
		var push := steer * dir            # +면 미는 쪽, -면 반대(카운터)
		var released: bool = not inp.get("drift", false)
		resp = 6.5
		grip = DRIFT_GRIP
		slide_drag = 2.4
		if not released:
			# 드리프트 키를 누르고 있는 동안에도 방향키가 다 먹는다 (끌기):
			# 미는 쪽은 더 돌고, 반대쪽은 코를 되돌린다. 계속 반대로 누르면 반대쪽 드리프트로 이어진다.
			var amt := 0.62 + 0.42 * push if push >= 0.0 else 0.62 + 1.35 * push
			target_w = -dir * st.turn * 1.08 * amt
			if push < 0.0:
				resp = 9.0
		elif push < -0.2:
			# 키를 떼고 카운터: 코를 가는 방향 쪽으로 되돌리며 빨리 편다
			target_w = dir * st.turn * 0.35
			grip = 9.0
			resp = 10.0
			ending = true
		elif push < 0.3:
			# 손을 다 떼면 천천히 펴진다
			target_w = -dir * st.turn * 0.08
			grip = 7.0
			resp = 9.0
			ending = true
		else:
			var amt2 := 0.62 + 0.42 * push
			target_w = -dir * st.turn * 1.08 * amt2
		if brake_drift and push > -0.2:
			target_w = -dir * st.turn * 1.08 * (1.0 + 0.4 * maxf(push, 0.0)) * 1.3
			grip = DRIFT_GRIP * 0.8
			ending = false
	else:
		var low := clampf(absf(sp) / 7.0, 0.35, 1.0)   # 멈춰 있어도 조금은 돈다
		var high := 1.0 - 0.22 * clampf(sp / st.max_speed, 0.0, 1.2)
		target_w = -steer * st.turn * low * high * (-1.0 if backward else 1.0)
		if rev_drift:
			target_w *= 1.9
			resp = 8.0
		# 드리프트가 막 끝났으면 접지가 천천히 돌아온다
		k.recover = minf(1.0, float(k.recover) + dt / RECOVER_TIME)
		var rc: float = k.recover
		grip = lerpf(DRIFT_GRIP + 1.5, st.grip, rc * rc)
		slide_drag = lerpf(1.5, 6.0, rc)
	k.yaw_rate = lerpf(float(k.yaw_rate), target_w, 1.0 - exp(-resp * dt))
	yaw = wrapf(yaw + float(k.yaw_rate) * dt, -PI, PI)

	# ── 가는 방향이 코를 따라간다
	var slip0 := wrapf(va - yaw, -PI, PI)
	va = yaw + slip0 * exp(-(2.6 if rev_drift else grip) * dt)
	var slip := wrapf(va - yaw, -PI, PI)
	var along := cos(slip)                      # 코 방향으로 힘이 얼마나 실리나

	# ── 가속·감속 (속도 크기에)
	if boosting(k) and throttle >= 0.0:
		sp = move_toward(sp, top, 55.0 * dt)
	elif throttle > 0.0:
		if sp < top:
			var curve := 1.0 - 0.55 * clampf(sp / top, 0.0, 1.0)
			var drift_acc := lerpf(1.0, 0.35, clampf(absf(slip) / 0.4, 0.0, 1.0)) if k.drift else 1.0   # 조금만 미끄러지면 가속이 거의 산다 (톡톡이·커팅)
			sp = minf(top, sp + st.accel * throttle * curve * along * drift_acc * dt)
	elif throttle < 0.0:
		if brake_drift:
			sp = maxf(0.0, sp - 9.0 * dt)
		elif sp > 0.5:
			sp = maxf(0.0, sp - 38.0 * dt)
		else:
			sp = maxf(-10.0, sp - 14.0 * dt)
	else:
		sp = move_toward(sp, 0.0, 5.0 * dt)
	if sp > top:  # 부스터가 끝났거나 잔디에 들어가면 천천히 최고 속력으로
		sp = move_toward(sp, top, (30.0 if k.offroad else 14.0) * dt)
	# 옆으로 미끄러지는 만큼 조금 느려진다
	if sp > 0.0:
		sp = maxf(0.0, sp - slide_drag * absf(sin(slip)) * dt * (sp / 20.0))

	# ── 드리프트 게이지·끝
	if k.drift:
		# 게이지: 미끄러지는 만큼 (작게 미끄러져도 조금씩 찬다 → 직선에서 톡톡 쳐서 모으는 커팅)
		if absf(slip) > 0.03:
			k.gauge += st.drift_gain * gauge_mult(k) * (0.3 + 0.7 * clampf(absf(slip) / 0.4, 0.0, 1.0)) * clampf(sp / 20.0, 0.0, 1.0) * dt
		var dir2 := float(k.drift_dir)
		var held: bool = inp.get("drift", false)
		if held and k.drift_time > 0.1 and slip * dir2 < -0.04 and steer * dir2 < -0.3:
			# 누른 채 반대로 꺾어 코가 넘어가면 반대쪽 드리프트로 이어간다
			k.drift_dir = -int(dir2)
			k.drift_time = 0.0
			k.events.append("drift_flip")
			_tap_bonus(k, st, sp)
		elif (ending and absf(slip) < 0.12) or sp < 6.0 or (not held and k.drift_time > 0.12 and slip * dir2 < -0.05):
			k.drift = false
	# ── 순간부스터 기회: 드리프트가 펴지기 시작하는 순간부터 끝난 뒤 잠깐까지
	var tap_up: bool = inp.get("accel_tap", false)
	if k.drift and ending and k.drift_time > 0.18 and not bool(k.get("win_open", false)):
		k.win_open = true
		k.window_t = MINI_WINDOW + 0.15
	if was_drift and not k.drift:
		k.events.append("drift_end")
		k.recover = 0.0
		if k.drift_time > 0.18 or bool(k.get("win_open", false)):
			k.window_t = maxf(float(k.window_t), MINI_WINDOW)
	if not k.drift:
		k.win_open = false
	# 살짝 일찍 누른 것도 기억해 둔다
	if tap_up and k.window_t <= 0.0 and k.drift:
		k.tap_buf = MINI_EARLY
	k.tap_buf = maxf(0.0, float(k.get("tap_buf", 0.0)) - dt)
	if k.window_t > 0.0 and (tap_up or float(k.tap_buf) > 0.0):
		k.window_t = 0.0
		k.tap_buf = 0.0
		k.mini_t = maxf(k.mini_t, MINI_TIME)
		k.events.append("mini_boost")

	# ── 게이지가 차면 부스터 하나 (아이템전은 게이지 없음)
	if k.get("no_gauge", false):
		k.gauge = 0.0
	if k.gauge >= 1.0:
		k.gauge -= 1.0
		if k.boosts < MAX_BOOSTS:
			k.boosts += 1
			k.events.append("boost_gain")
		else:
			k.gauge = 0.0

	# ── 부스터 쓰기 (아이템전에서는 부르는 쪽이 아이템으로 처리)
	if inp.get("use_boost", false) and k.boosts > 0 and k.boost_t < 0.3 and not k.get("no_gauge", false):
		k.boosts -= 1
		k.boost_t = st.boost_time
		k.events.append("boost")

	k.yaw = yaw
	k.vel = fwd(va) * sp
	k.slip = slip
	k.pos = (k.pos as Vector2) + (k.vel as Vector2) * dt
	k.boost_t = maxf(0.0, k.boost_t - dt)
	k.mini_t = maxf(0.0, k.mini_t - dt)
	k.window_t = maxf(0.0, k.window_t - dt)

## 드리프트를 걸 때(톡톡이·커팅·끌기로 다시 걸 때)마다 덤. 빠를 때만, 바로 전 드리프트가 조금은 가라앉은 뒤에만 (연타 막기)
static func _tap_bonus(k: Dictionary, st: Dictionary, sp: float) -> void:
	if sp > 18.0 and float(k.get("tap_cd", 0.0)) <= 0.0:
		k.gauge += TAP_CHUNK * st.drift_gain * (BOOST_GAUGE if boosting(k) else 1.0)
		k.tap_cd = TAP_COOLDOWN

## 게이지 배율: 드리프트를 건 직후(톡톡이·커팅·끌기로 다시 걸 때)는 더 빨리, 부스터 중에는 1.5배
static func gauge_mult(k: Dictionary) -> float:
	var m := 1.0 + TAP_BONUS * exp(-float(k.drift_time) / TAP_TIME)
	if boosting(k):
		m *= BOOST_GAUGE
	return m

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
## 조절점에 세 번째 값이 있으면 높이(다리·고가). 높이가 BRIDGE_H 넘는 곳은 잔디 없이 난간.
const BRIDGE_H := 0.6

static func build_track(def: Dictionary, spacing := 2.0) -> Dictionary:
	var ctrl: Array[Vector2] = []
	var ch: Array[float] = []
	for p in def.points:
		ctrl.append(Vector2(p[0], p[1]))
		ch.append(float(p[2]) if p.size() > 2 else 0.0)
	var n := ctrl.size()
	var dense: Array[Vector2] = []
	var dense_h: Array[float] = []
	for i in n:
		for j in 24:
			dense.append(_cr(ctrl[(i - 1 + n) % n], ctrl[i], ctrl[(i + 1) % n], ctrl[(i + 2) % n], j / 24.0))
			dense_h.append(_cr(Vector2(ch[(i - 1 + n) % n], 0), Vector2(ch[i], 0), Vector2(ch[(i + 1) % n], 0), Vector2(ch[(i + 2) % n], 0), j / 24.0).x)
	# 같은 간격으로 다시 고르기
	var total := 0.0
	for i in dense.size():
		total += dense[i].distance_to(dense[(i + 1) % dense.size()])
	var count := maxi(16, int(round(total / spacing)))
	var step_len := total / count
	var pts := PackedVector2Array()
	var raw_h := PackedFloat32Array()
	var acc := 0.0
	var want := 0.0
	for i in dense.size():
		var a := dense[i]
		var b := dense[(i + 1) % dense.size()]
		var seg := a.distance_to(b)
		while want <= acc + seg and pts.size() < count:
			var f := (want - acc) / maxf(seg, 0.0001)
			pts.append(a.lerp(b, f))
			raw_h.append(lerpf(dense_h[i], dense_h[(i + 1) % dense.size()], f))
			want += step_len
		acc += seg
	var m := pts.size()
	# 높이를 부드럽게 (꺾이지 않게)
	var hgt := PackedFloat32Array()
	hgt.resize(m)
	for i in m:
		var sum := 0.0
		for o in range(-3, 4):
			sum += raw_h[(i + o + m) % m]
		hgt[i] = maxf(0.0, sum / 7.0)
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
	var ground_wall: float = hw + float(def.get("verge", 7.0))
	var walls := PackedFloat32Array()
	walls.resize(m)
	var bridge := false
	for i in m:
		walls[i] = hw + 0.9 if hgt[i] > BRIDGE_H else ground_wall
		bridge = bridge or hgt[i] > BRIDGE_H
	return {
		"pts": pts, "tan": tang, "nrm": norm, "cum": cum, "curv": curv, "length": s, "n": m,
		"half_width": hw, "wall": ground_wall, "laps": int(def.get("laps", 3)),
		"hgt": hgt, "walls": walls, "has_bridge": bridge,
	}

## 출발선부터 거리 s 인 가운데 선 위치 {pos, tan, nrm, h, i}
static func point_at(tr: Dictionary, s: float) -> Dictionary:
	var L: float = tr.length
	var x := fposmod(s, L)
	var cum: PackedFloat32Array = tr.cum
	var lo := 0
	var hi: int = tr.n - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= x:
			lo = mid
		else:
			hi = mid - 1
	var i := lo
	var j: int = (i + 1) % tr.n
	var seg: float = (cum[j] if j > 0 else L) - cum[i]
	var t := clampf((x - cum[i]) / maxf(seg, 0.001), 0.0, 1.0)
	var p: Vector2 = (tr.pts[i] as Vector2).lerp(tr.pts[j], t)
	return {"pos": p, "tan": tr.tan[i], "nrm": tr.nrm[i], "h": lerpf(height_at(tr, i), height_at(tr, j), t), "i": i}

## i번 점 높이
static func height_at(tr: Dictionary, i: int) -> float:
	return float(tr.hgt[i]) if tr.has("hgt") else 0.0

## 가장 가까운 가운데 선 위치. hint(지난번 번호)가 있으면 그 근처만 본다.
## 돌려주는 것: {i, s(출발선부터 거리), lat(오른쪽 +), point, tan}
static func locate(tr: Dictionary, pos: Vector2, hint := -1, y := -1.0) -> Dictionary:
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
		# 전체에서 찾기. 높이(y)를 알면 다른 층(다리 위·아래)을 덜 고른다
		bd = INF
		var has_h: bool = y >= 0.0 and tr.has("hgt")
		for j in m:
			var d := pts[j].distance_squared_to(pos)
			if has_h:
				var dh: float = float(tr.hgt[j]) - y
				d += dh * dh * 6.0
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
			var h := lerpf(height_at(tr, seg[0]), height_at(tr, seg[1]), t)
			var wl: float = tr.walls[best] if tr.has("walls") else tr.wall
			res = {"i": best, "s": fposmod(s, tr.length), "lat": (pos - q).dot(nn), "point": q, "tan": tn, "h": h, "wall": wl}
	return res

## 바닥 종류: "road" 도로, "grass" 잔디(느림), 울타리 밖은 벽으로 막힌다
static func surface(tr: Dictionary, lat: float) -> String:
	return "road" if absf(lat) <= tr.half_width else "grass"

## 위치로 바닥 종류 (다리 위는 난간까지 다 도로)
static func surface_at(tr: Dictionary, loc: Dictionary) -> String:
	if float(loc.get("wall", tr.wall)) < tr.half_width + 1.5:
		return "road"
	return surface(tr, loc.lat)

## 울타리 밖으로 나가면 안으로 밀고 바깥쪽 속도를 없앤다. 부딪혔으면 true
static func wall_push(tr: Dictionary, k: Dictionary, loc: Dictionary, radius := 0.8) -> bool:
	var lim: float = float(loc.get("wall", tr.wall)) - radius
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
	elif sharp > 0.55 and spd > 18.0 and float(k.recover) >= 1.0 and rnd < 0.25 + skill * 0.6 and (absf(steer) < 0.4 or signf(steer) == signf(bend)):
		# 굽은 쪽으로만 드리프트를 건다
		drift = true
		steer = signf(bend) if absf(steer) < 0.4 else steer
	var throttle := 1.0
	if absf(ang) > 1.2 and spd > 12.0:
		throttle = -1.0
	# 머리핀처럼 아주 급한 굽이: 들어가기 전에 속도를 줄인다
	var hard := 0.0
	for o in [3, 6, 9]:
		hard = maxf(hard, absf(float(tr.curv[(loc.i + o) % m])) * 30.0)
	if hard > 1.25 and not k.drift and spd > 21.0:
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

# ────────────────────────── 방 코드 ──────────────────────────

const ROOM_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   ## 헷갈리는 0·O·1·I·L 뺌
const ROOM_LEN := 6

static func room_new(rng: RandomNumberGenerator) -> String:
	var c := ""
	for i in ROOM_LEN:
		c += ROOM_CHARS[rng.randi_range(0, ROOM_CHARS.length() - 1)]
	return c

## 사람이 친 방 코드를 다듬는다 (소문자·띄어쓰기·하이픈 허용). 맞지 않으면 ""
static func room_clean(t: String) -> String:
	var out := ""
	for ch in t.to_upper():
		if ch in ROOM_CHARS:
			out += ch
	return out if out.length() == ROOM_LEN else ""

## 중계에 쌓인 글 중 마지막 "O:"(초대) 또는 "A:"(답장)
static func relay_pick(body: String, prefix: String) -> String:
	var found := ""
	for line in body.split("\n", false):
		var j := JSON.new()
		if j.parse(line) != OK or typeof(j.data) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = j.data
		if str(d.get("event", "message")) != "message":
			continue
		var m := str(d.get("message", ""))
		if m.begins_with(prefix):
			found = m.substr(prefix.length())
	return found

# ────────────────────────── 아이템전 ──────────────────────────
## 아이템: boost 부스터, pinecone 솔방울(앞으로 던짐), acorn 도토리 함정(뒤에 둠), bees 꿀벌 떼(바로 앞 카트를 쫓음),
##          shield 잎사귀 방패(한 번 막음), wind 회오리바람(앞의 카트가 모두 잠깐 빙글)
const ITEMS := ["boost", "pinecone", "acorn", "bees", "shield", "wind"]
const ITEM_NAMES := {"boost": "부스터", "pinecone": "솔방울", "acorn": "도토리 함정", "bees": "꿀벌 떼", "shield": "잎사귀 방패", "wind": "회오리바람"}
const MAX_ITEMS := 2
const SPIN_TIME := 1.2
const SHIELD_TIME := 6.0

## 순위에 따른 아이템 확률 (앞일수록 지키는 것, 뒤일수록 따라잡는 것). place 1부터, rnd 0..1
static func item_roll(place: int, racers: int, rnd: float) -> String:
	var back := 0.0 if racers <= 1 else clampf(float(place - 1) / float(racers - 1), 0.0, 1.0)   # 0 = 1등, 1 = 꼴찌
	var w := {
		"boost": 1.0 + 2.0 * back,
		"pinecone": 2.0,
		"acorn": 2.2 - 1.6 * back,
		"bees": 0.2 + 2.4 * back if place > 1 else 0.0,
		"shield": 1.6 - 1.0 * back,
		"wind": 0.0 if back < 0.5 else (back - 0.5) * 2.4,
	}
	var total := 0.0
	for k in ITEMS:
		total += float(w[k])
	var x := rnd * total
	for k in ITEMS:
		x -= float(w[k])
		if x <= 0.0:
			return k
	return "boost"

## 아이템 상자를 먹었을 때. 칸이 다 찼으면 아무것도 안 생긴다
static func give_item(k: Dictionary, item: String) -> bool:
	var items: Array = k.get("items", [])
	if items.size() >= MAX_ITEMS:
		return false
	items.append(item)
	k.items = items
	return true

## 맞았다: 방패가 있으면 방패만 깨지고, 아니면 빙글빙글 (돌려주는 것: 실제로 빙글 돌았나)
static func hit(k: Dictionary, time := SPIN_TIME) -> bool:
	if float(k.get("shield_t", 0.0)) > 0.0:
		k.shield_t = 0.0
		k.events.append("shield_break")
		return false
	if float(k.get("spin_t", 0.0)) > 0.0:
		return false
	k.spin_t = time
	k.drift = false
	k.boost_t = 0.0
	k.mini_t = 0.0
	k.events.append("spin")
	return true

## 빙글 도는 동안: 조작 안 되고 빠르게 느려진다
static func _spin_step(k: Dictionary, dt: float) -> void:
	k.spin_t = maxf(0.0, float(k.spin_t) - dt)
	k.yaw = wrapf(float(k.yaw) + 10.0 * dt, -PI, PI)
	k.yaw_rate = 10.0
	var v: Vector2 = k.vel
	v = v.move_toward(Vector2.ZERO, 26.0 * dt) * exp(-0.6 * dt)
	k.vel = v
	k.pos = (k.pos as Vector2) + v * dt
	k.slip = 0.0
	k.steer_s = 0.0
	if k.spin_t <= 0.0:
		# 다 돌고 나면 길 방향 그대로 (속도 방향 쪽을 보게)
		if v.length() > 1.0:
			k.yaw = atan2(v.x, v.y)

## 컴퓨터가 아이템을 쓸지. ahead/behind = 바로 앞·뒤 카트까지 거리(없으면 INF), straight = 앞이 곧은가
static func ai_use_item(item: String, place: int, ahead: float, behind: float, straight: bool, threatened: bool, rnd: float) -> bool:
	match item:
		"boost": return straight and rnd < 0.05
		"pinecone": return ahead < 45.0 and rnd < 0.08
		"bees": return place > 1 and rnd < 0.05
		"acorn": return behind < 25.0 and rnd < 0.08
		"shield": return threatened or rnd < 0.004
		"wind": return place > 2 and rnd < 0.05
	return false
