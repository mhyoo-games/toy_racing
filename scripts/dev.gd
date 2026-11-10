extends Node
## 개발용 자동 조작: godot -- --dev=<장면> --out=<폴더> 으로 실행하면 화면을 찍고 끝낸다. 평소에는 아무것도 안 함.
## 장면: title, tracks, garage, help, race(컴퓨터가 대신 몰기), duo, time, results

var plan := ""
var out := "/tmp/toy_racing"
var track := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dev="):
			plan = a.substr(6)
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--track="):
			track = a.substr(8)
	if plan == "":
		queue_free()
		return
	DirAccess.make_dir_recursive_absolute(out)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var wh := a.substr(7).split("x")
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sound.set_muted(true)
	Engine.max_physics_steps_per_frame = 40
	_run()

func shot(n: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("shot(그림 없음) ", n)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)

func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func main() -> Node:
	return get_tree().get_first_node_in_group("main")

func _race(mode: String, shots: Array) -> void:
	Game.mode = mode
	if track != "":
		Game.track_id = track
	main().start_race()
	await wait(0.3)
	var r = main().race
	r.autopilot = true
	await wait(1.0)
	await shot(mode + "_count")
	for s in shots:
		# 화면이 느려도 경주 시계 기준으로 찍는다
		while r.state == "count" or r.clock < s:
			await get_tree().process_frame
		await shot("%s_%02d" % [mode, int(s)])

func _run() -> void:
	await wait(1.0)
	match plan:
		"title":
			await shot("title")
		"tracks":
			Game.mode = "race"
			main().menu.show_screen("tracks"); await wait(0.5); await shot("tracks")
		"garage":
			Game.save.coins = 900
			main().menu.show_screen("garage"); await wait(0.5); await shot("garage")
			main().menu.garage_pick = "pinwheel"; main().menu.show_screen("garage"); await wait(0.5); await shot("garage2")
		"help":
			main().menu.show_screen("help"); await wait(0.4); await shot("help")
		"race":
			await _race("race", [4.0, 7.0, 11.0, 16.0])
		"duo":
			await _race("duo", [5.0, 9.0])
		"time":
			await _race("time", [5.0])
		"pause":
			await _race("race", [2.0])
			main().race.pause_menu.open()
			await wait(0.5)
			await shot("pause")
		"results":
			Game.mode = "race"
			main().start_race()
			await wait(0.3)
			var r = main().race
			r.autopilot = true
			Engine.time_scale = 4.0
			while is_instance_valid(main().race):
				await wait(1.0)
			Engine.time_scale = 1.0
			await wait(0.6)
			await shot("results")
	get_tree().quit()
