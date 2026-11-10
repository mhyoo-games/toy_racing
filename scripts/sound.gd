extends Node
## 효과음·엔진·끌리는 소리·배경음 (자동 로드 Sound). 소리 파일은 tools/sound/gen.py 가 만든다.

const NAMES := ["screech", "boost", "mini", "gain", "beep", "go", "coin", "bump", "lap", "finish", "click", "tick", "buy", "nope"]

var sfx := {}
var pool: Array[AudioStreamPlayer] = []
var engines := {}
var skids := {}
var bgm: AudioStreamPlayer
var bgm_name := ""
var muted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		sfx[n] = load("res://assets/sfx/%s.wav" % n)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	for who in [1, 2]:
		engines[who] = _loop("res://assets/sfx/engine.wav", -14.0)
		skids[who] = _loop("res://assets/sfx/skid.wav", -16.0)
	bgm = AudioStreamPlayer.new()
	bgm.volume_db = -10.0
	add_child(bgm)

func _looped(path: String) -> AudioStreamWAV:
	var s: AudioStreamWAV = (load(path) as AudioStreamWAV).duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = s.data.size() / 2
	return s

func _loop(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _looped(path)
	p.volume_db = db
	add_child(p)
	return p

func play(n: String, db := 0.0, pitch := 1.0) -> void:
	if muted or not sfx.has(n):
		return
	for p in pool:
		if not p.playing:
			p.stream = sfx[n]
			p.volume_db = db - 4.0
			p.pitch_scale = pitch
			p.play()
			return

func engine_on(who: int, on: bool) -> void:
	var p: AudioStreamPlayer = engines[who]
	if on and not p.playing and not muted:
		p.play()
	elif not on:
		p.stop()

## ratio: 속력 / 최고 속력
func engine(who: int, ratio: float, boost: bool, players: int) -> void:
	var p: AudioStreamPlayer = engines[who]
	p.pitch_scale = lerpf(p.pitch_scale, 0.6 + ratio * 1.25 + (0.25 if boost else 0.0), 0.2)
	p.volume_db = (-15.0 if players == 1 else -19.0) + ratio * 3.0

## amount 0..1: 미끄러지는 정도(미끄러짐 각 × 속도). 크면 소리도 크고 높다. 꺼질 때는 짧게 줄여 끊는다
var _skid_lv := {1: 0.0, 2: 0.0}

func skid(who: int, on: bool, amount := 1.0, players := 1) -> void:
	var p: AudioStreamPlayer = skids[who]
	var want := clampf(amount, 0.0, 1.0) if on else 0.0
	var lv: float = _skid_lv[who]
	lv = move_toward(lv, want, (6.0 if want > lv else 9.0) / 60.0)
	_skid_lv[who] = lv
	if lv > 0.02 and not muted:
		if not p.playing:
			p.play()
		p.volume_db = linear_to_db(lv) - (7.0 if players == 1 else 11.0)
		p.pitch_scale = 0.88 + lv * 0.22
	elif p.playing:
		p.stop()

func pause_loops(paused: bool) -> void:
	for d in [engines, skids]:
		for p in d.values():
			p.stream_paused = paused

func music(n: String) -> void:
	if bgm_name == n and bgm.playing:
		return
	bgm_name = n
	bgm.stream = _looped("res://assets/music/%s.wav" % n)
	if not muted:
		bgm.play()

func set_muted(m: bool) -> void:
	muted = m
	if m:
		bgm.stop()
		for d in [engines, skids]:
			for p in d.values():
				p.stop()
	elif bgm_name != "":
		bgm.play()
