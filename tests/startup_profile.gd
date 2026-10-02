extends SceneTree
# One hidden launch, without captures, time scaling, or parallel test processes.
func _initialize(): call_deferred("run")
func run():
	var report := {"scope":"Current source menu startup and idle frame timing; not a measurement of any older packaged executable.", "renderer":DisplayServer.get_name(), "timings_ms":{}, "frames":[]}
	var before := Time.get_ticks_usec()
	var scene := load("res://main/main.tscn")
	report.timings_ms.resource_load = (Time.get_ticks_usec()-before)/1000.0
	before = Time.get_ticks_usec()
	var game = scene.instantiate()
	report.timings_ms.instantiate = (Time.get_ticks_usec()-before)/1000.0
	before = Time.get_ticks_usec()
	root.add_child(game)
	report.timings_ms.ready = (Time.get_ticks_usec()-before)/1000.0
	var preparation=game.player.pet_hand.get("surface_prepare_usec")
	if preparation!=null: report["petting_surface"]={"source":game.player.pet_hand.surface_geometry_source,"prepare_ms":preparation/1000.0}
	before = Time.get_ticks_usec()
	await process_frame
	await RenderingServer.frame_post_draw
	report.timings_ms.first_draw_after_ready = (Time.get_ticks_usec()-before)/1000.0
	var last := Time.get_ticks_usec()
	for frame in 90:
		await process_frame
		var now := Time.get_ticks_usec()
		report.frames.append({"frame":frame,"interval_ms":(now-last)/1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		last = now
	report["source_hashes"] = {}
	for path in ["main/main.gd","player/petting_hand.gd","player/petting_surface.gd","project.godot","assets/models/glb/godot_mvp/cat_reference.fbx","assets/models/glb/godot_mvp/player_arm.glb"]:
		if FileAccess.file_exists("res://"+path): report.source_hashes[path] = FileAccess.get_sha256("res://"+path)
	var output_path="res://tests/results/startup-profile-current.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): output_path=argument.trim_prefix("--report=")
		if argument.begins_with("--scope="): report.scope=argument.trim_prefix("--scope=")
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STARTUP_PROFILE ",JSON.stringify(report.timings_ms))
	game.free()
	quit()
