class_name KartView
extends Node3D
## 카트 모양 (코드로 조립) + 운전수(Kenney 캐릭터). 앞은 +Z.

const DRIVER := preload("res://assets/forest/character-archer.glb")

var body: Node3D           # 기울어지는 몸통
var wheels: Array[Node3D] = []
var front_pivots: Array[Node3D] = []
var flames: Array[Node3D] = []
var smoke: Array[CPUParticles3D] = []
var sparks: Array[CPUParticles3D] = []
var fire: CPUParticles3D
var driver: Node3D
var wheel_spin := 0.0
var roll := 0.0
var bounce := 0.0
var klen := 2.0
var kwid := 1.25

static var _mats := {}

static func mat(c: Color, emit := false, unshaded := false) -> StandardMaterial3D:
	var key := "%s%s%s" % [c.to_html(), emit, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if top < 0.0 else top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi

## def: karts.json 항목. with_driver = 운전수 태우기
func setup(def: Dictionary, with_driver := true, driver_tint := Color.WHITE) -> void:
	var c := Color.html(def.color)
	var t := Color.html(def.trim)
	var sh: Dictionary = def.get("shape", {})
	klen = float(sh.get("len", 2.0))
	kwid = float(sh.get("wid", 1.25))
	var nose := float(sh.get("nose", 0.5))
	var dark := Color(0.16, 0.15, 0.17)
	body = Node3D.new()
	add_child(body)
	# 바닥판·몸통
	_box(body, Vector3(kwid * 0.92, 0.12, klen), Vector3(0, 0.26, 0), dark)
	_box(body, Vector3(kwid * 0.78, 0.26, klen * 0.62), Vector3(0, 0.42, -klen * 0.05), c)
	# 코
	_box(body, Vector3(kwid * 0.55, 0.2, nose + 0.3), Vector3(0, 0.4, klen * 0.3 + nose * 0.5), c)
	_box(body, Vector3(kwid * 1.02, 0.14, 0.22), Vector3(0, 0.3, klen * 0.5 + 0.02), t)
	# 의자 등받이
	_box(body, Vector3(0.62, 0.5, 0.14), Vector3(0, 0.72, -klen * 0.2), t)
	# 엔진·배기구
	_box(body, Vector3(kwid * 0.6, 0.34, 0.42), Vector3(0, 0.5, -klen * 0.42), Color(0.42, 0.42, 0.45))
	for sx in [-0.18, 0.18]:
		var ex := _cyl(body, 0.07, 0.3, Vector3(sx, 0.52, -klen * 0.5 - 0.08), Color(0.6, 0.6, 0.62), Vector3(PI / 2, 0, 0))
		var fl := _cyl(body, 0.13, 0.7, Vector3(sx, 0.52, -klen * 0.5 - 0.55), Color(1.0, 0.62, 0.15), Vector3(-PI / 2, 0, 0), 0.0)
		fl.material_override = mat(Color(1.0, 0.6, 0.15), true, true)
		fl.visible = false
		flames.append(fl)
	# 옆 상자
	if sh.get("pods", false):
		for sx in [-1.0, 1.0]:
			_box(body, Vector3(0.24, 0.24, klen * 0.46), Vector3(sx * kwid * 0.48, 0.42, 0.0), t)
	# 뒷날개
	if sh.get("wing", false):
		for sx in [-0.3, 0.3]:
			_box(body, Vector3(0.06, 0.45, 0.08), Vector3(sx, 0.78, -klen * 0.47), dark)
		_box(body, Vector3(kwid * 0.95, 0.06, 0.34), Vector3(0, 1.02, -klen * 0.48), t)
	# 핸들
	_cyl(body, 0.15, 0.04, Vector3(0, 0.78, klen * 0.12), dark, Vector3(-1.0, 0, 0))
	# 바퀴
	var wr := 0.3
	for zs in [1.0, -1.0]:
		for sx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sx * (kwid * 0.5 + 0.06), wr, zs * klen * 0.34)
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			_cyl(spin, wr, 0.26, Vector3.ZERO, dark, Vector3(0, 0, PI / 2))
			_cyl(spin, wr * 0.45, 0.28, Vector3.ZERO, t, Vector3(0, 0, PI / 2))
			wheels.append(spin)
			if zs > 0.0:
				front_pivots.append(pivot)
	# 그림자 동그라미
	var sh_mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(kwid * 1.7, klen * 1.35)
	q.orientation = PlaneMesh.FACE_Y
	sh_mi.mesh = q
	sh_mi.position.y = 0.035
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.45))
	gr.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = gr
	sm.albedo_texture = gt
	sh_mi.material_override = sm
	sh_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sh_mi)
	# 운전수
	if with_driver:
		driver = DRIVER.instantiate()
		driver.scale = Vector3.ONE * 1.05
		driver.position = Vector3(0, 0.34, -klen * 0.08)
		body.add_child(driver)
		var ap: AnimationPlayer = driver.find_child("AnimationPlayer", true, false)
		if ap:
			var a := ap.get_animation("drive")
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
			ap.play("drive")
		if driver_tint != Color.WHITE:
			for m in driver.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).material_overlay = _tint(driver_tint)
	# 연기·불꽃
	for sx in [-1.0, 1.0]:
		var p := _particles(Color(0.92, 0.92, 0.9, 0.55), 0.5, 1.2)
		p.position = Vector3(sx * kwid * 0.5, 0.12, -klen * 0.38)
		add_child(p)
		smoke.append(p)
		var s := _particles(Color(1.0, 0.85, 0.3), 0.08, 0.35, true)
		s.position = Vector3(sx * kwid * 0.5, 0.1, -klen * 0.38)
		add_child(s)
		sparks.append(s)
	fire = _particles(Color(1.0, 0.55, 0.15, 0.9), 0.25, 0.4, true)
	fire.position = Vector3(0, 0.52, -klen * 0.55)
	fire.direction = Vector3(0, 0.2, -1)
	add_child(fire)

func _tint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	return m

func _particles(c: Color, size: float, life: float, glow := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 24
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3(0, 1, -0.4)
	p.spread = 30.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 0.6 if not glow else -4.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6 if not glow else 0.0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	m.albedo_texture = gt
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	var cr := Gradient.new()
	cr.set_color(0, c)
	cr.set_color(1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = cr
	return p

## 주행 상태를 그림에 옮긴다
func show_state(k: Dictionary, steer: float, dt: float) -> void:
	var p: Vector2 = k.pos
	position = Vector3(p.x, 0.0, p.y)
	rotation.y = k.yaw
	var spd := Rules.speed_of(k)
	wheel_spin += spd / 0.3 * dt
	for w in wheels:
		w.rotation.x = wheel_spin
	var wheel_turn := -steer * 0.45
	if k.drift:
		wheel_turn = -float(k.slip) * 0.9   # 드리프트 중에는 바퀴가 바깥쪽(카운터)
	for f in front_pivots:
		f.rotation.y = lerp_angle(f.rotation.y, wheel_turn, 1.0 - exp(-14.0 * dt))
	# 몸통 기울기: 드리프트는 바깥으로 크게
	var want_roll := float(k.slip) * 0.22 + steer * 0.04 * clampf(spd / 20.0, 0.0, 1.0)
	roll = lerpf(roll, want_roll, 1.0 - exp(-8.0 * dt))
	bounce += dt * (6.0 + spd * 0.3)
	body.rotation.z = roll
	body.position.y = sin(bounce) * 0.012 * clampf(spd / 10.0, 0.0, 1.0) + (0.03 if k.offroad else 0.0) * sin(bounce * 3.7)
	var boost := Rules.boosting(k)
	for i in flames.size():
		flames[i].visible = boost
		if boost:
			var s := 0.8 + 0.35 * sin(bounce * 9.0 + i)
			flames[i].scale = Vector3(1, (1.4 if k.boost_t > 0.0 else 0.8) * s, 1)
	fire.emitting = boost
	var sliding: bool = (k.drift and spd > 8.0) or (absf(float(k.slip)) > 0.25 and (k.vel as Vector2).length() > 4.0)
	for s in smoke:
		s.emitting = sliding or (k.offroad and spd > 12.0)
	for s in sparks:
		s.emitting = sliding and k.drift_time > 0.35
