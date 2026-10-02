extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat()
	var cat=game.active_cat
	cat._process(100)
	cat._process(4.0)
	cat.set_process(false)
	cat.scratch_timer.stop()
	cat._scratch()
	cat.scratch_timer.stop()
	cat._process(cat.cycle_length)
	game.hud.hide()
	game.player.enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var camera=game.player.camera
	camera.global_position=cat.global_position+Vector3(1.05,1.1,-.04)
	camera.look_at(cat.global_position+Vector3.UP*.62)
	DirAccess.make_dir_recursive_absolute("res://builds/scratch-review-frames")
	for frame in 81:
		# Capture the same fixed-step gait/contact/body updates as gameplay.
		if frame>0:cat._process(1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/scratch-review-frames/frame%03d.png" % frame)
	game.free()
	await process_frame
	print("SCRATCH_MOVIE_FRAMES_OK")
	quit()
