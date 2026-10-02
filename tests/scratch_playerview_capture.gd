extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat("wall")
	var cat = game.active_cat
	cat._process(100)
	cat.position.x = 4.7
	cat._process(cat.POSTURE_BLEND_DURATION)
	cat.set_process(false)
	cat.scratch_timer.stop()
	cat._scratch()
	cat.scratch_timer.stop()
	cat.animation.seek(cat.cycle_length * .32, true)
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var suffix := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/scratch-player-view-%s.png" % suffix)
	game.queue_free()
	await process_frame
	print("SCRATCH_PLAYER_VIEW_CAPTURE_OK ", suffix)
	quit()
