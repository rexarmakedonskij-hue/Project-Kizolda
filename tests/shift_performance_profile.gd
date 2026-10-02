extends SceneTree
# Isolated, unattended performance sample of the first live cat visit.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var report := {"scope": "First live visit with input disabled; next_cat_in shortened to 0.25 s for profiling", "frames": [], "spawn_frame": -1, "source_hashes": {}}
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await RenderingServer.frame_post_draw
	game.verifying_build = true # Keep a hidden window from auto-pausing on focus loss.
	game.player.enabled = false
	game.next_cat_in = 0.25
	game.started = true
	var previous := Time.get_ticks_usec()
	for frame in 480:
		await process_frame
		var now := Time.get_ticks_usec()
		if report.spawn_frame < 0 and is_instance_valid(game.active_cat):
			report.spawn_frame = frame
		report.frames.append({"frame": frame, "interval_ms": (now - previous) / 1000.0, "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "cat": is_instance_valid(game.active_cat)})
		previous = now
	for path in ["main/main.gd", "cats/cat.gd", "player/petting_hand.gd", "room/room.gd", "project.godot", "assets/models/glb/godot_mvp/cat_reference.fbx"]:
		if FileAccess.file_exists("res://" + path):
			report.source_hashes[path] = FileAccess.get_sha256("res://" + path)
	var file := FileAccess.open("res://tests/results/shift-performance-2026-10-02.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("SHIFT_PERFORMANCE frames=", report.frames.size(), " spawn_frame=", report.spawn_frame)
	game.free()
	quit()
