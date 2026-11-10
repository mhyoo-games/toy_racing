class_name Controls
extends RefCounted
## 사람이 누르는 키를 주행 입력으로. 키보드·게임패드·화면 버튼(터치).
##
## 혼자: 방향키 또는 WASD / Shift 드리프트 / Ctrl·Space 부스터
## 둘이서 1P: WASD / 왼쪽 Shift 드리프트 / Space 부스터
## 둘이서 2P: 방향키 / 오른쪽 Shift(또는 /) 드리프트 / 오른쪽 Ctrl·Enter(또는 .) 부스터
## 게임패드: 왼쪽 스틱·십자키 / A·RT 가속 / B·LT 브레이크 / X·RB 드리프트 / Y·LB 부스터

static var left_shift := false
static var right_shift := false
static var right_ctrl := false
static var touch := {}       # 화면 버튼: left, right, drift, boost, brake

## 왼쪽·오른쪽 Shift를 나눠 알기 위해 키 사건을 본다
static func feed(e: InputEvent) -> void:
	if e is InputEventKey and not e.echo:
		var k := e as InputEventKey
		if k.keycode == KEY_SHIFT:
			if k.location == KEY_LOCATION_RIGHT:
				right_shift = k.pressed
			else:
				left_shift = k.pressed
		elif k.keycode == KEY_CTRL and k.location == KEY_LOCATION_RIGHT:
			right_ctrl = k.pressed

static func _k(key: Key) -> bool:
	return Input.is_physical_key_pressed(key)

static func _pad(dev: int, b: JoyButton) -> bool:
	return Input.is_joy_button_pressed(dev, b)

static func _axis(dev: int, a: JoyAxis) -> float:
	return Input.get_joy_axis(dev, a)

## who: 1 또는 2. duo: 둘이서 하는지. 돌려주는 것: {throttle, steer, drift, boost(누르고 있는지)}
static func read(who: int, duo: bool) -> Dictionary:
	var up := false
	var down := false
	var left := false
	var right := false
	var drift := false
	var boost := false
	var steer_axis := 0.0
	if not duo:
		up = _k(KEY_UP) or _k(KEY_W)
		down = _k(KEY_DOWN) or _k(KEY_S)
		left = _k(KEY_LEFT) or _k(KEY_A)
		right = _k(KEY_RIGHT) or _k(KEY_D)
		drift = _k(KEY_SHIFT)
		boost = _k(KEY_CTRL) or _k(KEY_SPACE)
	elif who == 1:
		up = _k(KEY_W); down = _k(KEY_S); left = _k(KEY_A); right = _k(KEY_D)
		drift = left_shift
		boost = _k(KEY_SPACE)
	else:
		up = _k(KEY_UP); down = _k(KEY_DOWN); left = _k(KEY_LEFT); right = _k(KEY_RIGHT)
		drift = right_shift or _k(KEY_SLASH)
		boost = right_ctrl or _k(KEY_ENTER) or _k(KEY_KP_ENTER) or _k(KEY_PERIOD)
	# 게임패드: 혼자면 아무 패드나, 둘이면 1P=0번, 2P=1번
	var pads := Input.get_connected_joypads()
	var mine: Array = []
	if not duo:
		mine = pads
	elif pads.size() > who - 1:
		mine = [pads[who - 1]]
	for d in mine:
		var ax := _axis(d, JOY_AXIS_LEFT_X)
		if absf(ax) > 0.2:
			steer_axis = ax
		left = left or _pad(d, JOY_BUTTON_DPAD_LEFT)
		right = right or _pad(d, JOY_BUTTON_DPAD_RIGHT)
		up = up or _pad(d, JOY_BUTTON_A) or _axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or _pad(d, JOY_BUTTON_DPAD_UP)
		down = down or _pad(d, JOY_BUTTON_B) or _axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.4 or _pad(d, JOY_BUTTON_DPAD_DOWN)
		drift = drift or _pad(d, JOY_BUTTON_X) or _pad(d, JOY_BUTTON_RIGHT_SHOULDER)
		boost = boost or _pad(d, JOY_BUTTON_Y) or _pad(d, JOY_BUTTON_LEFT_SHOULDER)
	# 화면 버튼 (혼자일 때만). 터치로 하면 가속은 저절로
	if not duo and touch.get("on", false):
		up = up or not touch.get("brake", false)
		down = down or touch.get("brake", false)
		left = left or touch.get("left", false)
		right = right or touch.get("right", false)
		drift = drift or touch.get("drift", false)
		boost = boost or touch.get("boost", false)
	var steer := (1.0 if right else 0.0) - (1.0 if left else 0.0)
	if steer_axis != 0.0:
		steer = steer_axis
	var thr := (1.0 if up else 0.0) - (1.0 if down else 0.0)
	return {"throttle": thr, "steer": steer, "drift": drift, "boost": boost}
