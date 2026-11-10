class_name TrackView
extends Node3D
## 트랙 그림: 도로·연석·출발선·울타리·숲 꾸밈을 트랙 정의로 코드에서 만든다.

const FOREST := "res://assets/forest/%s.glb"

var trk: Dictionary
var def: Dictionary
var rng := RandomNumberGenerator.new()
var _meshes := {}

## 이 점이 땅 위(다리 아님)인가
func ground(i: int) -> bool:
	return Rules.height_at(trk, i) <= Rules.BRIDGE_H

func build(track_def: Dictionary, track: Dictionary, shadows := true) -> void:
	def = track_def
	trk = track
	rng.seed = int(def.get("seed", 1))
	_environment(shadows)
	_ground()
	_road()
	_curbs()
	if trk.get("has_bridge", false):
		_bridges()
	_start()
	_fences()
	_forest()
	_camp()

## glb 안의 메시 하나를 꺼낸다 (여러 번 쓰려고 MultiMesh에)
func forest_mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var inst: Node = (load(FOREST % name) as PackedScene).instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var m := mi.mesh
	inst.free()
	_meshes[name] = m
	return m

func _environment(shadows: bool) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.6, 0.9)
	sm.sky_horizon_color = Color(0.78, 0.88, 0.95)
	sm.ground_horizon_color = Color(0.7, 0.8, 0.75)
	sm.ground_bottom_color = Color(0.3, 0.45, 0.3)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.78)
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_exposure = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.85, 0.92)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

func bounds() -> Rect2:
	var r := Rect2(trk.pts[0], Vector2.ZERO)
	for p in trk.pts:
		r = r.expand(p)
	return r

func _noise_tex(base: Color, amount: float, freq: float, size := 128) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			# 이어지게(타일) 네 귀퉁이를 섞는다
			var u := float(x) / size
			var v := float(y) / size
			var a := n.get_noise_2d(x, y) * (1 - u) * (1 - v) + n.get_noise_2d(x - size, y) * u * (1 - v) \
				+ n.get_noise_2d(x, y - size) * (1 - u) * v + n.get_noise_2d(x - size, y - size) * u * v
			img.set_pixel(x, y, base.lightened(a * amount) if a > 0 else base.darkened(-a * amount))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _ground() -> void:
	var b := bounds().grow(260.0)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = b.size
	mi.mesh = pm
	mi.position = Vector3(b.get_center().x, 0.0, b.get_center().y)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(Color.html(def.get("ground", "#6fae4f")), 0.35, 0.05)
	m.uv1_scale = Vector3(b.size.x / 24.0, b.size.y / 24.0, 1)
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)

## 가운데 선을 따라 띠를 만든다. from/to = 옆 거리(오른쪽 +), y = 높이, keep(i) = 이 칸을 그릴지
func _strip(from: float, to: float, y: float, mat: Material, keep := Callable(), color_of := Callable()) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m: int = trk.n
	for i in m:
		if keep.is_valid() and not keep.call(i):
			continue
		var j := (i + 1) % m
		var a0: Vector2 = trk.pts[i] + trk.nrm[i] * from
		var a1: Vector2 = trk.pts[i] + trk.nrm[i] * to
		var b0: Vector2 = trk.pts[j] + trk.nrm[j] * from
		var b1: Vector2 = trk.pts[j] + trk.nrm[j] * to
		var v0: float = trk.cum[i] / 6.0
		var v1: float = v0 + (trk.pts[i] as Vector2).distance_to(trk.pts[j]) / 6.0
		var c: Color = Color.WHITE if not color_of.is_valid() else color_of.call(i)
		var hi := Rules.height_at(trk, i)
		var hj := Rules.height_at(trk, j)
		for q in [[a0, 0.0, v0, hi], [b0, 0.0, v1, hj], [a1, 1.0, v0, hi], [a1, 1.0, v0, hi], [b0, 0.0, v1, hj], [b1, 1.0, v1, hj]]:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q[1], q[2]))
			st.add_vertex(Vector3(q[0].x, y + q[3], q[0].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _road() -> void:
	var hw: float = trk.half_width
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(Color.html(def.get("road", "#6f6a66")), 0.08, 0.35, 64)
	m.uv1_scale = Vector3(2.0, 1.0, 1)
	m.roughness = 0.9
	_strip(-hw, hw, 0.02, m)
	# 흙 길섶(도로 바로 밖 잔디와 사이)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color.html(def.get("ground", "#6fae4f")).lerp(Color(0.55, 0.45, 0.3), 0.45)
	dirt.roughness = 1.0
	_strip(-hw - 2.2, -hw, 0.012, dirt, ground)
	_strip(hw, hw + 2.2, 0.012, dirt, ground)
	# 흰 가장자리 선과 가운데 점선
	var white := KartView.mat(Color(0.97, 0.97, 0.94))
	_strip(-hw + 0.25, -hw + 0.6, 0.03, white)
	_strip(hw - 0.6, hw - 0.25, 0.03, white)
	_strip(-0.18, 0.18, 0.03, white, func(i: int) -> bool: return (i / 2) % 2 == 0)

func _curbs() -> void:
	var hw: float = trk.half_width
	var bent := func(i: int) -> bool:
		if not ground(i):
			return false
		for o in range(-3, 4):
			if absf(trk.curv[(i + o + trk.n) % trk.n]) > 0.012:
				return true
		return false
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	var col := func(i: int) -> Color: return Color(0.86, 0.2, 0.18) if (i / 2) % 2 == 0 else Color(0.97, 0.97, 0.94)
	_strip(-hw - 1.1, -hw, 0.04, m, bent, col)
	_strip(hw, hw + 1.1, 0.04, m, bent, col)

func _start() -> void:
	var hw: float = trk.half_width
	var p0: Vector2 = trk.pts[0]
	var t0: Vector2 = trk.tan[0]
	var n0: Vector2 = trk.nrm[0]
	var yaw := atan2(t0.x, t0.y)
	# 체크무늬 출발선
	var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 2:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.1, 0.1, 0.1))
	var tex := ImageTexture.create_from_image(img)
	var line := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(hw * 2.0, 2.2)
	q.orientation = PlaneMesh.FACE_Y
	line.mesh = q
	var lm := StandardMaterial3D.new()
	lm.albedo_texture = tex
	lm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	line.material_override = lm
	line.position = Vector3(p0.x, 0.035, p0.y)
	line.rotation.y = yaw
	add_child(line)
	# 출발 자리 표시
	for s in 8:
		var g := Rules.grid_slot(trk, s)
		var mark := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.02, 0.18)
		mark.mesh = bm
		mark.material_override = KartView.mat(Color(0.97, 0.97, 0.94))
		var gp: Vector2 = g.pos + Rules.fwd(g.yaw) * 1.4
		mark.position = Vector3(gp.x, 0.035, gp.y)
		mark.rotation.y = g.yaw
		add_child(mark)
	# 출발 문
	var arch := Node3D.new()
	arch.position = Vector3(p0.x, 0, p0.y)
	arch.rotation.y = yaw
	add_child(arch)
	var red := KartView.mat(Color(0.85, 0.22, 0.2))
	var wood := KartView.mat(Color(0.55, 0.36, 0.2))
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.7, 7.5, 0.7)
		post.mesh = pb
		post.material_override = wood
		post.position = Vector3(sx * (hw + 1.6), 3.75, 0)
		arch.add_child(post)
	var banner := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(hw * 2.0 + 4.6, 1.7, 0.4)
	banner.mesh = bb
	banner.material_override = red
	banner.position = Vector3(0, 7.0, 0)
	arch.add_child(banner)
	for side in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = "토이 레이싱" if side > 0 else "출발"
		lb.font = Game.font_bold
		lb.font_size = 96
		lb.pixel_size = 0.012
		lb.outline_size = 12
		lb.modulate = Color(1, 0.97, 0.85)
		lb.outline_modulate = Color(0.45, 0.1, 0.08)
		lb.position = Vector3(0, 7.0, -side * 0.22)
		lb.rotation.y = 0.0 if side < 0 else PI
		arch.add_child(lb)
	# 깃발 줄
	for k in range(-6, 7):
		if k == 0:
			continue
		var i: int = (k * 3 + trk.n) % trk.n
		for sx in [-1.0, 1.0]:
			var fp: Vector2 = trk.pts[i] + trk.nrm[i] * sx * (trk.wall + 0.6)
			_put("flag", Vector3(fp.x, 0, fp.y), rng.randf() * TAU, 3.2)

func _put(name: String, pos: Vector3, rot: float, scale: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = forest_mesh(name)
	mi.position = pos
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * scale
	add_child(mi)
	return mi

func _multi(name: String, xforms: Array, shadow := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = forest_mesh(name)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _xf(p: Vector2, rot: float, s: float, y := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))

## 이 자리가 어느 도로·잔디 안에도 들지 않는가
func clear_of_track(p: Vector2, margin: float) -> bool:
	var loc := Rules.locate(trk, p)
	return absf(loc.lat) > trk.wall + margin

func _fences() -> void:
	var xs := []
	var step := 2.6
	for side in [-1.0, 1.0]:
		var s := 0.0
		while s < trk.length:
			var i: int = int(s / trk.length * trk.n) % trk.n
			var p: Vector2 = trk.pts[i] + trk.nrm[i] * side * (trk.wall + 0.3)
			if ground(i) and Rules.height_at(trk, i) < 0.2 and clear_of_track(p, -0.1):
				var t: Vector2 = trk.tan[i]
				xs.append(_xf(p, atan2(t.x, t.y) + PI / 2, 2.4))
			# 바깥쪽 곡선은 점 사이가 벌어지니 옆 거리만큼 촘촘하게
			var k: float = 1.0 + float(trk.curv[i]) * side * (trk.wall + 0.3)
			s += step / maxf(0.35, k)
	_multi("fence", xs)

func _forest() -> void:
	var b := bounds().grow(trk.wall + 46.0)
	var kinds := {"tree": [], "tree-high": [], "rocks-high": [], "rocks-low": [], "plant": [], "stones": [], "patch-grass": []}
	var cell := 7.0
	var density: float = {"highway": 0.55, "deep": 1.0, "hills": 0.8}.get(str(def.get("theme", "")), 0.92)
	var y := b.position.y
	while y < b.end.y:
		var x := b.position.x
		while x < b.end.x:
			var p := Vector2(x + rng.randf_range(-3, 3), y + rng.randf_range(-3, 3))
			var loc := Rules.locate(trk, p)
			var d: float = absf(loc.lat) - float(loc.wall)
			var r := rng.randf()
			if d > 2.0 and d < 46.0 and r < density - d * 0.004:
				var rot := rng.randf() * TAU
				var pick := rng.randf()
				if pick < 0.5:
					kinds["tree"].append(_xf(p, rot, rng.randf_range(3.4, 5.4)))
				elif pick < 0.76:
					kinds["tree-high"].append(_xf(p, rot, rng.randf_range(3.6, 5.2)))
				elif pick < 0.82:
					kinds["rocks-high"].append(_xf(p, rot, rng.randf_range(2.0, 3.6), 1.0))
				elif pick < 0.88:
					kinds["rocks-low"].append(_xf(p, rot, rng.randf_range(2.0, 3.4)))
				elif pick < 0.94:
					kinds["stones"].append(_xf(p, rot, rng.randf_range(1.6, 2.6)))
				else:
					kinds["patch-grass"].append(_xf(p, rot, rng.randf_range(3.0, 5.0)))
			elif d > 0.8 and d < 2.0 and r < 0.3:
				kinds["plant"].append(_xf(p, rng.randf() * TAU, rng.randf_range(2.5, 4.0)))
			x += cell
		y += cell
	# 잔디 길섶 안쪽에도 풀 무더기 (달리는 데 막히지는 않음)
	for i in range(0, trk.n, 3):
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.25:
				var lat: float = side * rng.randf_range(trk.half_width + 2.5, trk.wall - 0.5)
				var p2: Vector2 = trk.pts[i] + trk.nrm[i] * lat
				kinds["patch-grass"].append(_xf(p2, rng.randf() * TAU, rng.randf_range(1.5, 2.6)))
	for k in kinds:
		_multi(k, kinds[k], k.begins_with("tree") or k.begins_with("rocks"))

## 출발선 옆 구경꾼 캠프: 텐트·집·과녁
func _camp() -> void:
	var placed := 0
	var i := int(trk.n * 0.04)
	while placed < 5 and i < trk.n * 0.3:
		var side := -1.0 if placed % 2 == 0 else 1.0
		var p: Vector2 = trk.pts[i] + trk.nrm[i] * side * (trk.wall + 6.0)
		if clear_of_track(p, 4.0):
			var t: Vector2 = trk.tan[i]
			var face := atan2(t.x, t.y) + (PI / 2 if side < 0 else -PI / 2)
			match placed:
				0, 3:
					_put("tent", Vector3(p.x, 0, p.y), face, 4.0)
				1:
					_put("building-platform", Vector3(p.x, 0, p.y), face, 4.0)
					_put("building-structure", Vector3(p.x, 2.0, p.y), face, 4.0)
					_put("building-roof", Vector3(p.x, 6.0, p.y), face, 4.0)
				2:
					_put("target", Vector3(p.x, 0, p.y), face, 4.0)
				4:
					_put("platform", Vector3(p.x, 0, p.y), face, 4.0)
			placed += 1
		i += 9

## 다리: 옆 벽(두께), 난간, 기둥
func _bridges() -> void:
	var hw: float = trk.half_width
	var m: int = trk.n
	# 다리 옆면 (도로 가장자리에서 아래로)
	var side_st := SurfaceTool.new()
	side_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in m:
		var j := (i + 1) % m
		var hi := Rules.height_at(trk, i)
		var hj := Rules.height_at(trk, j)
		if hi < 0.3 and hj < 0.3:
			continue
		for sd in [-1.0, 1.0]:
			var a: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw + 0.9)
			var b: Vector2 = trk.pts[j] + trk.nrm[j] * sd * (hw + 0.9)
			var nrm3 := Vector3(trk.nrm[i].x * sd, 0, trk.nrm[i].y * sd)
			var quad := [Vector3(a.x, hi + 0.05, a.y), Vector3(b.x, hj + 0.05, b.y), Vector3(a.x, maxf(0.0, hi - 0.9), a.y),
				Vector3(a.x, maxf(0.0, hi - 0.9), a.y), Vector3(b.x, hj + 0.05, b.y), Vector3(b.x, maxf(0.0, hj - 0.9), b.y)]
			for v in quad:
				side_st.set_normal(nrm3)
				side_st.add_vertex(v)
	var side_mi := MeshInstance3D.new()
	side_mi.mesh = side_st.commit()
	var sm := KartView.mat(Color(0.78, 0.74, 0.68)).duplicate()
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	side_mi.material_override = sm
	add_child(side_mi)
	# 다리 위 길섶 (도로 끝 ~ 난간)
	var deck := KartView.mat(Color(0.6, 0.58, 0.56))
	_strip(-hw - 0.9, -hw, 0.015, deck, func(i: int) -> bool: return not ground(i))
	_strip(hw, hw + 0.9, 0.015, deck, func(i: int) -> bool: return not ground(i))
	# 난간: 빨강·하양 낮은 벽
	var rails := {"r": [], "w": []}
	var posts := []
	for i in m:
		var j := (i + 1) % m
		if ground(i) and ground(j):
			continue
		for sd in [-1.0, 1.0]:
			var a: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw + 0.75)
			var b: Vector2 = trk.pts[j] + trk.nrm[j] * sd * (hw + 0.75)
			var mid := (a + b) * 0.5
			var hmid := (Rules.height_at(trk, i) + Rules.height_at(trk, j)) * 0.5
			var ln := a.distance_to(b)
			var yaw := atan2(b.x - a.x, b.y - a.y)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.3, 0.8, ln + 0.05)), Vector3(mid.x, hmid + 0.4, mid.y))
			rails["r" if (i / 3) % 2 == 0 else "w"].append(xf)
			if i % 4 == 0:
				posts.append(Transform3D(Basis().scaled(Vector3(0.35, 1.2, 0.35)), Vector3(a.x, Rules.height_at(trk, i) + 0.6, a.y)))
	for key in rails:
		_boxes(rails[key], Color(0.88, 0.26, 0.22) if key == "r" else Color(0.96, 0.96, 0.92))
	_boxes(posts, Color(0.35, 0.33, 0.35))
	# 기둥: 높은 곳 아래. 다른 길 위에는 세우지 않는다
	var pillars := []
	for i in range(0, m, 6):
		var h := Rules.height_at(trk, i)
		if h < 1.5:
			continue
		for sd in [-1.0, 1.0]:
			var p: Vector2 = trk.pts[i] + trk.nrm[i] * sd * (hw - 1.2)
			if _over_other_road(p, i):
				continue
			pillars.append(Transform3D(Basis().scaled(Vector3(1.1, h - 0.4, 1.1)), Vector3(p.x, (h - 0.4) * 0.5, p.y)))
	_boxes(pillars, Color(0.72, 0.68, 0.62))

## 다른 구간(번호가 먼) 길 위인가
func _over_other_road(p: Vector2, i: int) -> bool:
	var m: int = trk.n
	for j in range(0, m, 2):
		var di := absi(j - i)
		di = mini(di, m - di)
		if di < 25:
			continue
		if (trk.pts[j] as Vector2).distance_to(p) < trk.half_width + 3.0:
			return true
	return false

func _boxes(xforms: Array, c: Color) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.material = KartView.mat(c)
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
