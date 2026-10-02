extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var model_path: String = args[0] if args.size() > 0 else "res://builds/b3-rig-review/B3-rig-review.glb"
	var output: String = args[1] if args.size() > 1 else "res://tests/results/b3-godot"
	root.size = Vector2i(960, 960)
	root.content_scale_size = Vector2i(960, 960)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("cbd0d0")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .15
	stage.add_child(env)
	for light_pose in [Vector3(-35,-30,0), Vector3(-20,130,0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_pose
		light.light_energy = .22 if light_pose.y < 0 else .08
		light.shadow_enabled = true
		stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("cbd0d0")
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var started := Time.get_ticks_msec()
	if document.append_from_file(model_path, state) != OK:
		quit(1)
		return
	var model := document.generate_scene(state)
	preload("res://assets/models/glb/godot_mvp/cat_import.gd").apply_vertex_colors(model)
	stage.add_child(model)
	var load_ms := Time.get_ticks_msec() - started
	var animation: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in ["Walk", "Scratch"]:
		animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var driver = preload("res://cats/pose_player.gd").new(animation, skeleton)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(2.2, 1.5, 3.1)
	camera.look_at(Vector3(0,.75,0))
	camera.fov = 31
	camera.make_current()
	driver.play("Sit")
	for i in 30:
		await process_frame
	if args.size() > 2 and args[2] == "profile":
		var results: Array = []
		for mode in ["hidden", "visible", "no_shadows", "no_groom", "only_groom"]:
			root.grab_focus()
			model.visible = mode != "hidden"
			for mesh in model.find_children("*", "MeshInstance3D", true, false):
				var groom := "groom" in mesh.name
				mesh.visible = (mode != "no_groom" or not groom) and (mode != "only_groom" or groom)
			for light in stage.find_children("*", "DirectionalLight3D", false, false):
				light.shadow_enabled = mode != "no_shadows"
			driver.play("Walk")
			for i in 30:
				await process_frame
			var timings: Array[float] = []
			var animation_us := 0
			var focused := 0
			var previous := Time.get_ticks_usec()
			var end := previous + 3000000
			while Time.get_ticks_usec() < end:
				await process_frame
				var now := Time.get_ticks_usec()
				var delta := (now - previous) / 1000000.0
				timings.append(delta * 1000.0)
				previous = now
				if root.has_focus(): focused += 1
				driver.advance(delta)
				animation_us += Time.get_ticks_usec() - now
			timings.sort()
			results.append({"mode": mode, "frames": timings.size(), "focused_frames": focused,
				"median_ms": timings[timings.size()/2], "p95_ms": timings[int(timings.size()*.95)],
				"animation_mean_ms": animation_us / 1000.0 / timings.size(),
				"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps})
		var diagnostic := FileAccess.open(output + "-profile.json", FileAccess.WRITE)
		diagnostic.store_string(JSON.stringify(results, "  "))
		print("B3_PROFILE ", JSON.stringify(results))
		quit()
		return
	var intervals: Array[float] = []
	var focused_frames := 0
	var sequence := [["Sit", 1.0], ["Walk", 1.6], ["Sit", .12], ["Scratch", 1.6], ["Walk", 1.6]]
	for index in sequence.size():
		root.grab_focus()
		var entry: Array = sequence[index]
		driver.play(entry[0], .3)
		var elapsed := 0.0
		var previous := Time.get_ticks_usec()
		while elapsed < float(entry[1]):
			await process_frame
			var now := Time.get_ticks_usec()
			var delta := (now - previous) / 1000000.0
			previous = now
			intervals.append(delta * 1000.0)
			if root.has_focus(): focused_frames += 1
			elapsed += delta
			driver.advance(delta)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "-%d.png" % index)
	intervals.sort()
	var report := {"load_ms": load_ms, "frames": intervals.size(), "median_frame_ms": intervals[intervals.size()/2], "p95_frame_ms": intervals[int(intervals.size()*.95)], "window": "960x960", "scope": "one cat in studio, loading and screenshot writes excluded"}
	report["focused_frames"] = focused_frames
	var file := FileAccess.open(output + "-performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("B3_GRAPHICAL_CHECK_OK ", JSON.stringify(report))
	stage.queue_free()
	await process_frame
	quit()
