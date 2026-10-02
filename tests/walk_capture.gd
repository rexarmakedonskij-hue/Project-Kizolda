extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat()
	var cat = game.active_cat
	cat.set_process(false)
	cat.position = Vector3(2.5, .06, -.4)
	cat.rotation.y = 0
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.player.camera.global_position = cat.position + Vector3(1.5, 1.2, 1.7)
	game.player.camera.look_at(cat.position + Vector3(0, .5, .2))
	for i in range(3):
		cat.animation.seek(i * .2, true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/results/walk-%d.png" % i)
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("WALK_CAPTURE_OK")
	quit()
