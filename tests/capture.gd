extends SceneTree

func _initialize() -> void: call_deferred("run")

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		root.push_input(event)

func snapshot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/" + name + ".png")

func run() -> void:
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await snapshot("start")
	click(game.hud.action.get_global_rect().get_center())
	if not game.started:
		push_error("Start button failed")
		quit(1)
		return
	game.set_process(false)
	game._spawn_cat()
	game.active_cat._process(100)
	game.hud.update_cat(game.active_cat, game.player)
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await snapshot("office")
	game._on_work_requested()
	var correct: int = game.inbox.current.options.find(game.inbox.current.answer)
	click(game.hud.email_options[correct].get_global_rect().get_center())
	if game.inbox.selected != correct:
		push_error("Email option click failed")
		quit(1)
		return
	await snapshot("iteration1-email")
	click(game.hud.submit_button.get_global_rect().get_center())
	if game.quota != game.RULES.QUOTA_PER_EMAIL:
		push_error("Email submit click failed")
		quit(1)
		return
	await snapshot("iteration1-sent")
	game._on_work_requested()
	game.player.camera.look_at(game.active_cat.global_position + Vector3.UP * .75)
	game.hud.update_cat(game.active_cat, game.player)
	await snapshot("cat")
	print("GUI_CLICKS: start, choose, submit passed")
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
