extends SceneTree

var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await process_frame

func press(key: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Control playtest needs a graphics display for mouse capture")
		quit(2)
		return
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	check(game.hud.modal.visible and not game.started, "Start screen is visible")
	await click(game.hud.action)
	check(game.started and not game.hud.modal.visible, "Mouse click starts the shift")
	await press(KEY_F)
	check(game.working and game.hud.work_panel.visible, "F opens the laptop")
	var answer: int = game.inbox.current.options.find(game.inbox.current.answer)
	await click(game.hud.email_options[answer])
	check(game.inbox.selected == answer, "Mouse click selects an email response")
	await click(game.hud.submit_button)
	check(game.quota == 20 and game.inbox.resolved, "Mouse click sends a correct response")
	check(game.hud.next_button.disabled and game.hud.next_button.text.begins_with("Через"), "Next email shows its arrival countdown")
	game.shift_time = game.RULES.EMAIL_INTERVAL
	game._process(0.0)
	await click(game.hud.next_button)
	check(not game.inbox.resolved and game.inbox.selected == -1, "Mouse click loads the next email")
	await press(KEY_ESCAPE)
	check(paused and game.hud.modal.visible, "Esc pauses the shift")
	await click(game.hud.action)
	check(not paused and not game.hud.modal.visible, "Pause button resumes the shift")
	await press(KEY_F)
	check(not game.working, "F returns to the room")
	game._spawn_cat("wall")
	var cat = game.active_cat
	cat.set_process(false)
	cat.position = game.room.get_cat_position(1)
	cat.route.clear()
	game.player.camera.look_at(cat.global_position + Vector3.UP * .75)
	await press(KEY_SPACE)
	check(game.active_cat == null and is_instance_valid(game.departing_cat), "Space shooes a visible cat")
	game.departing_cat.free()
	game.departing_cat = null
	game._spawn_cat("keyboard")
	cat = game.active_cat
	cat.set_process(false)
	for step in 3600:
		if cat.desktop.state == "seated": break
		cat._process(1.0 / 60)
	game.player.camera.look_at(cat.global_position + Vector3.UP * .3)
	await press(KEY_SPACE)
	check(cat.desktop.state == "petting" and game.keyboard_blocked, "Space pets the seated cat while the keyboard stays occupied")
	cat._process(.4)
	var pet_elapsed: float = cat.desktop.elapsed
	await press(KEY_SPACE)
	check(cat.desktop.elapsed == pet_elapsed, "Repeated Space does not restart petting")
	for step in 600:
		if not is_instance_valid(cat): break
		cat._process(1.0 / 60)
		game._process(0.0)
	check(game.active_cat == null and not game.keyboard_blocked, "Petted cat leaves and frees the keyboard")
	game.room.desk.spill()
	game._sync_obstruction()
	await press(KEY_E)
	check(game.cleaning, "E starts coffee cleanup")
	game._process(game.RULES.CLEAN_DURATION)
	check(not game.cleaning and not game.room.desk.dirty, "Cleanup completes and restores work")
	game.queue_free()
	await process_frame
	print("CONTROL_PLAYTEST: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
