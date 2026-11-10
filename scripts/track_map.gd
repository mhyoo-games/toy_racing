class_name TrackMap
extends Control
## 트랙 모양 작은 그림 (트랙 고르기 화면)

var def: Dictionary
var _pts := PackedVector2Array()

func _draw() -> void:
	if _pts.is_empty():
		_pts = Rules.build_track(def, 4.0).pts
	var b := Rect2(_pts[0], Vector2.ZERO)
	for p in _pts:
		b = b.expand(p)
	var sc := minf(size.x / b.size.x, size.y / b.size.y) * 0.86
	var off := (size - b.size * sc) * 0.5
	var line := PackedVector2Array()
	for p in _pts:
		line.append(off + (p - b.position) * sc)
	line.append(line[0])
	draw_polyline(line, Color(0.1, 0.08, 0.06, 0.8), 9.0)
	draw_polyline(line, Color(0.93, 0.9, 0.82), 5.0)
	var s0 := line[0]
	var t := (line[1] - line[0]).normalized()
	draw_line(s0 - Vector2(-t.y, t.x) * 9, s0 + Vector2(-t.y, t.x) * 9, Color(0.9, 0.25, 0.2), 4.0)
