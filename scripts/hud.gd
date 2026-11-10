class_name Hud
extends Control
## 한 사람 화면 위 글자·게이지·작은 지도

var race: Node            # race.gd
var racer: Dictionary     # 이 화면의 선수
var msgs: Array = []      # [{text, t, color}]
var map_pts := PackedVector2Array()
var map_rect := Rect2()
var flash := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func say(text: String, color := Color(1, 0.95, 0.6), time := 1.3) -> void:
	for m in msgs:
		if m.text == text:
			m.t = time
			return
	msgs.append({"text": text, "t": time, "color": color, "full": time})
	if msgs.size() > 3:
		msgs.pop_front()

func _process(dt: float) -> void:
	for m in msgs:
		m.t -= dt
	msgs = msgs.filter(func(m): return m.t > 0.0)
	flash = maxf(0.0, flash - dt * 2.5)
	queue_redraw()

func _txt(s: String, pos: Vector2, size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, bold := true) -> void:
	var f: Font = Game.font_bold if bold else Game.font
	draw_string_outline(f, pos, s, align, width, size, maxi(4, size / 6), Color(0.08, 0.06, 0.1, 0.9))
	draw_string(f, pos, s, align, width, size, color)

func _draw() -> void:
	if race == null or racer.is_empty():
		return
	var w := size.x
	var h := size.y
	var u := clampf(minf(w / 1280.0, h / 720.0) * 1.0, 0.45, 1.6)   # 글자 크기 기준
	if h < w * 0.4:
		u = clampf(h / 420.0, 0.45, 1.2)
	var k: Dictionary = racer.k
	# 순위
	var place: int = racer.place
	var total: int = race.racers.size()
	if total > 1:
		_txt("%d" % place, Vector2(24 * u, 86 * u), int(84 * u), Color(1, 0.86, 0.3) if place == 1 else Color.WHITE)
		_txt("/ %d" % total, Vector2((24 + 52 * (2 if place >= 10 else 1)) * u, 86 * u), int(34 * u), Color(0.9, 0.9, 0.9))
	# 랩·시간
	var laps: int = race.trk.laps
	var lap := mini(Rules.lap_of(racer.dist, race.trk.length), laps)
	var y0 := (130.0 if total > 1 else 56.0) * u
	_txt("랩 %d / %d" % [lap, laps], Vector2(26 * u, y0), int(30 * u))
	var t: float = racer.finish if racer.finish >= 0.0 else race.clock
	_txt(Rules.time_text(maxf(t, 0.0)), Vector2(26 * u, y0 + 38 * u), int(26 * u), Color(0.95, 0.95, 0.85), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	if race.mode == "time":
		var best: float = Game.best_of(race.def.id)
		_txt("기록 " + Rules.time_text(best), Vector2(26 * u, y0 + 70 * u), int(20 * u), Color(0.8, 0.9, 1.0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	# 속도
	var kmh := int(absf(Rules.speed_of(k)) * Rules.KMH)
	_txt("%d" % kmh, Vector2(w - 250 * u, h - 40 * u), int(64 * u), Color(1, 0.6, 0.25) if Rules.boosting(k) else Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 150 * u)
	_txt("km/h", Vector2(w - 92 * u, h - 44 * u), int(22 * u), Color(0.9, 0.9, 0.9))
	# 드리프트 게이지와 부스터 칸
	var gw := 300.0 * u
	var gh := 22.0 * u
	var gx := w * 0.5 - gw * 0.5
	var gy := h - 46.0 * u
	draw_rect(Rect2(gx - 3 * u, gy - 3 * u, gw + 6 * u, gh + 6 * u), Color(0.08, 0.06, 0.1, 0.75))
	var g := clampf(float(k.gauge), 0.0, 1.0)
	var gc := Color(0.35, 0.8, 1.0).lerp(Color(1.0, 0.85, 0.25), g)
	draw_rect(Rect2(gx, gy, gw * g, gh), gc)
	if k.drift:
		draw_rect(Rect2(gx, gy, gw * g, gh * 0.35), Color(1, 1, 1, 0.35))
	for i in Rules.MAX_BOOSTS:
		var bx := gx + gw + 14.0 * u + i * 52.0 * u
		var r := Rect2(bx, gy - 18 * u, 44 * u, 40 * u)
		draw_rect(r, Color(0.08, 0.06, 0.1, 0.75))
		if i < int(k.boosts):
			draw_rect(r.grow(-4 * u), Color(1.0, 0.45, 0.2))
			_txt("B", Vector2(bx + 12 * u, gy + 14 * u), int(26 * u), Color(1, 0.95, 0.75))
	_txt("드리프트", Vector2(gx, gy - 8 * u), int(18 * u), Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	# 순간부스터 기회 표시
	if float(k.window_t) > 0.0:
		var a := float(k.window_t) / Rules.MINI_WINDOW
		_txt("지금 ↑!", Vector2(w * 0.5, h * 0.62), int(34 * u), Color(0.5, 1.0, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	# 알림 글자
	var my := h * 0.3
	for m in msgs:
		var a2 := clampf(m.t / 0.25, 0.0, 1.0)
		var grow := 1.0 + 0.25 * clampf((m.full - m.t) / 0.12, 0.0, 1.0) - 0.25 * clampf((m.full - m.t - 0.12) / 0.1, 0.0, 1.0)
		var c: Color = m.color
		c.a = a2
		_txt(m.text, Vector2(0, my), int(44 * u * grow), c, HORIZONTAL_ALIGNMENT_CENTER, w)
		my += 54 * u
	# 출발 신호
	if race.state == "count":
		var left: float = race.count_left
		var n := int(ceil(left))
		var s := str(n) if n > 0 and n <= 3 else ""
		if s != "":
			var sc: float = 1.0 + (ceil(left) - left) * 0.5
			_txt(s, Vector2(0, h * 0.45), int(130 * u * sc), Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)
	elif race.clock < 1.0 and race.state == "run":
		_txt("출발!", Vector2(0, h * 0.45), int(110 * u), Color(0.5, 1.0, 0.5, 1.0 - race.clock), HORIZONTAL_ALIGNMENT_CENTER, w)
	if racer.finish >= 0.0:
		_txt("도착! %d등" % place if total > 1 else "도착!", Vector2(0, h * 0.42), int(84 * u), Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)
	if racer.get("wrong", 0.0) > 1.0 and racer.finish < 0.0:
		_txt("거꾸로 가고 있어요!", Vector2(0, h * 0.55), int(40 * u), Color(1, 0.4, 0.35), HORIZONTAL_ALIGNMENT_CENTER, w)
	_minimap(u)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.8, 0.4, flash * 0.18))

func _minimap(u: float) -> void:
	if map_pts.is_empty():
		var b := Rect2(race.trk.pts[0], Vector2.ZERO)
		for p in race.trk.pts:
			b = b.expand(p)
		map_rect = b
		map_pts = race.trk.pts
	var box := 190.0 * u
	var sc := box / maxf(map_rect.size.x, map_rect.size.y)
	var origin := Vector2(size.x - box - 24 * u, 24 * u)
	var off := (Vector2(box, box) - map_rect.size * sc) * 0.5
	var f := func(p: Vector2) -> Vector2: return origin + off + (p - map_rect.position) * sc
	draw_rect(Rect2(origin - Vector2(10, 10) * u, Vector2(box, box) + Vector2(20, 20) * u), Color(0.05, 0.08, 0.05, 0.45))
	var line := PackedVector2Array()
	for i in range(0, map_pts.size(), 2):
		line.append(f.call(map_pts[i]))
	line.append(line[0])
	draw_polyline(line, Color(0.1, 0.1, 0.1, 0.8), 7.0 * u)
	draw_polyline(line, Color(0.92, 0.9, 0.85), 4.0 * u)
	var s0: Vector2 = f.call(map_pts[0])
	draw_circle(s0, 4 * u, Color(1, 1, 1))
	for r in race.racers:
		if r == racer:
			continue
		draw_circle(f.call(r.k.pos), 4.5 * u, r.color)
	draw_circle(f.call(racer.k.pos), 7 * u, Color(0.05, 0.05, 0.05))
	draw_circle(f.call(racer.k.pos), 5.5 * u, Color(1, 0.9, 0.2))
