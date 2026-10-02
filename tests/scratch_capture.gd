extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat()
	game.active_cat._process(100)
	var cat = game.active_cat
	cat._process(cat.POSTURE_BLEND_DURATION)
	cat.position.x = -4.7
	cat.set_process(false)
	cat.scratch_timer.stop()
	cat._scratch()
	cat.scratch_timer.stop()
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.player.camera.look_at(cat.global_position + Vector3.UP * .8)
	for shot in ["scratch-wide", "scratch-high", "scratch-low"]:
		if shot != "scratch-wide":
			game.player.camera.global_position = cat.global_position + Vector3(1.6, 1.5, 1.5)
			game.player.camera.look_at(cat.global_position + Vector3.UP * .8)
		cat.animation.seek(cat.cycle_length * (.6 if shot == "scratch-low" else .4), true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/results/refined-" + shot + ".png")
	cat.animation.seek(0, true)
	cat._process(cat.cycle_length * .401)
	cat.set_process(true)
	await create_timer(.12).timeout
	cat.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/refined-scratch-contact.png")
	game.player.camera.global_position = Vector3(0, 1.6, 2.5)
	game.player.camera.look_at(cat.global_position + Vector3.UP * .8)
	cat.set_process(true)
	root.grab_focus()
	for i in 30: await process_frame
	var intervals: Array[float] = []
	var focused := 0
	var previous := Time.get_ticks_usec()
	var end := previous + 5000000
	while Time.get_ticks_usec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append((now - previous) / 1000.0)
		previous = now
		if root.has_focus(): focused += 1
	intervals.sort()
	var report := {"frames": intervals.size(), "focused_frames": focused,
		"median_ms": intervals[intervals.size()/2], "p95_ms": intervals[int(intervals.size()*.95)],
		"window": str(root.size), "scope": "full room, one scratching cat and marks; player input and shift clock disabled"}
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["os"] = OS.get_name()
	var file := FileAccess.open("res://tests/results/refined-room-performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("LOWPOLY_ROOM_PERFORMANCE ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("SCRATCH_CAPTURE_OK")
	quit()
