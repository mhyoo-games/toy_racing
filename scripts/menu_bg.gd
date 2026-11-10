extends Node3D
## 메뉴 뒤 3D 그림: 숲속 빈터에서 고른 카트가 빙글빙글

var kart: KartView
var kart_id := ""
var spin := 0.0
var cam: Camera3D

func _ready() -> void:
	var tv := TrackView.new()
	tv.rng.seed = 5
	add_child(tv)
	tv._environment(true)
	# 바닥
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = tv._noise_tex(Color("#5a9441"), 0.3, 0.05)
	gm.uv1_scale = Vector3(8, 8, 1)
	g.material_override = gm
	add_child(g)
	# 받침대
	var plat := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.2
	cm.bottom_radius = 3.4
	cm.height = 0.3
	cm.radial_segments = 32
	plat.mesh = cm
	plat.position.y = 0.15
	plat.material_override = KartView.mat(Color(0.62, 0.42, 0.25))
	add_child(plat)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.1
	tm.outer_radius = 3.45
	ring.mesh = tm
	ring.position.y = 0.3
	ring.scale.y = 0.4
	ring.material_override = KartView.mat(Color(0.95, 0.85, 0.6))
	add_child(ring)
	# 둘레 나무
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(9.0, 30.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z > -4.0 and absf(p.x) < 9.0:
			continue   # 카메라 앞은 비운다
		var mi := MeshInstance3D.new()
		mi.mesh = tv.forest_mesh(["tree", "tree-high", "tree", "rocks-low", "stones"][i % 5])
		mi.position = p
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3.ONE * rng.randf_range(2.5, 4.5)
		add_child(mi)
	for i in 6:
		var f := MeshInstance3D.new()
		f.mesh = tv.forest_mesh("flag")
		f.position = Vector3(-7.0 + i * 2.8, 0, -6.0)
		f.scale = Vector3.ONE * 2.6
		add_child(f)
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	frame(false)

## wide = 카트를 오른쪽에 두고 왼쪽에 글자 자리를 남긴다
func frame(wide: bool) -> void:
	if wide:
		cam.position = Vector3(0.2, 2.6, 8.4)
		cam.look_at(Vector3(0.75, 1.1, 0), Vector3.UP)
	else:
		cam.position = Vector3(-1.6, 3.0, 7.2)
		cam.look_at(Vector3(0.3, 0.9, 0), Vector3.UP)

func show_kart(id: String) -> void:
	if id == kart_id:
		return
	kart_id = id
	if kart:
		kart.queue_free()
	kart = KartView.new()
	add_child(kart)
	kart.setup(Game.kart_def(id), true)
	kart.position.y = 0.3
	kart.scale = Vector3.ONE * 1.25

func _process(dt: float) -> void:
	spin += dt * 0.6
	if kart:
		kart.rotation.y = spin
		kart.position.y = 0.28
