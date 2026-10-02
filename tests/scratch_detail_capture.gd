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
	cat._process(cat.POSTURE_BLEND_DURATION)
	cat.set_process(false)
	cat.scratch_timer.stop()
	cat._scratch()
	cat.scratch_timer.stop()
	game.hud.hide()
	game.player.enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var camera=game.player.camera
	for angle in ["side","rear"]:
		camera.global_position=cat.global_position+(Vector3(1.05,1.1,-.04) if angle=="side" else Vector3(.15,1.05,1.12))
		camera.look_at(cat.global_position+Vector3.UP*.78)
		for phase in 4:
			cat.animation.seek(cat.cycle_length*phase/4.0,true)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/results/scratch-detail-%s-%d.png" %[angle,phase])
	game.free()
	await process_frame
	print("SCRATCH_DETAIL_CAPTURE_OK")
	quit()
