extends SceneTree
var failures := 0
var checks := 0
var game

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	else: print("PASS: ", label)

func fresh() -> void:
	paused = false
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = InputEventKey.new()
	event.keycode = code
	root.push_input(event)

func right_answer() -> int:
	return game.inbox.current.options.find(game.inbox.current.answer)

func run() -> void:
	await fresh()
	check(game.quota == 0 and not game.started, "Start menu waits")
	game._on_work_requested()
	check(not game.working, "Cannot work before start")
	game.start_shift()
	key(KEY_F)
	check(game.working and game.hud.work_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "F opens laptop and frees cursor")
	check(game.quota == 0, "Opening laptop gives no quota")
	game._submit_email()
	check(game.quota == 0 and not game.inbox.resolved, "Unselected answer rejected")
	var correct := right_answer()
	game._choose_email((correct + 1) % 3)
	game._submit_email()
	check(game.quota == 0 and game.inbox.feedback.begins_with("Проверь"), "Wrong answer explains correction")
	game._choose_email(correct)
	var subject: String = game.inbox.current.subject
	key(KEY_TAB)
	check(not game.working and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "Tab returns to room")
	game._submit_email()
	check(game.quota == 0, "Cannot submit from room")
	key(KEY_F)
	check(game.inbox.current.subject == subject and game.inbox.selected == correct, "Interruption preserves email and selection")
	key(KEY_ESCAPE)
	check(paused and game.working, "Pause remembers laptop mode")
	game._submit_email()
	check(game.quota == 0, "Paused submit ignored")
	key(KEY_ESCAPE)
	check(not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Resume restores laptop cursor")
	game._submit_email()
	check(game.quota == game.RULES.QUOTA_PER_EMAIL and game.inbox.resolved, "Correct answer earns quota")
	game._submit_email()
	check(game.quota == game.RULES.QUOTA_PER_EMAIL, "Repeated submit cannot duplicate reward")
	game._next_email()
	check(game.inbox.current.subject == subject and game.hud.next_button.disabled, "Next email waits for its arrival")
	game.shift_time = game.RULES.EMAIL_INTERVAL
	game.hud.refresh_email(game.inbox, game.quota, game._email_wait())
	game._next_email()
	check(game.inbox.current.subject != subject and game.inbox.selected == -1, "Next email changes task and resets selection")
	game._process(game.RULES.FIRST_CAT_DELAY)
	game.active_cat._process(100)
	check(is_instance_valid(game.active_cat) and game.active_cat.warning, "First cat begins warning")
	var cat = game.active_cat
	check(not game.player.can_see(cat), "Cat outside aim cone")
	game.player.camera.look_at(cat.global_position + Vector3.UP * .75)
	game._on_shoo_requested()
	check(is_instance_valid(game.active_cat), "Cannot spray while working")
	key(KEY_F)
	game._on_shoo_requested()
	check(game.active_cat == null and game.wall_damage == 0, "Early shoo prevents all damage")
	check(game.next_cat_in >= game.RULES.RESPAWN_MIN and game.next_cat_in <= game.RULES.RESPAWN_MAX, "Respawn interval from rules")
	check(cat.leaving, "Chased cat begins leaving")
	cat._process(100)
	await process_frame
	check(not is_instance_valid(cat), "Chased cat removed")
	game._spawn_cat()
	game.active_cat._process(100)
	cat = game.active_cat
	cat.scratch_timer.start(.02)
	await create_timer(.06).timeout
	check(not cat.warning and game.wall_damage == 0, "Warning ends before first damage")
	cat.scratch_timer.start(.02)
	# Timer emits at most once per rendered frame. Give two real timeouts a
	# bounded opportunity instead of assuming the machine fits them in 75 ms.
	var scratch_deadline := Time.get_ticks_msec()+1000
	while game.wall_damage < 20 and Time.get_ticks_msec() < scratch_deadline:
		await process_frame
	check(game.wall_damage >= 20 and is_instance_valid(game.active_cat), "Actual timer repeats scratches")
	cat.scratch_timer.start(5)
	game.toggle_pause()
	var before: float = game.shift_time
	var cat_before: float = cat.scratch_timer.time_left
	await create_timer(.05, true).timeout
	check(game.shift_time == before and cat.scratch_timer.time_left == cat_before, "Pause freezes both clocks")
	game.toggle_pause()
	for i in range(5): game._on_cat_scratched_wall(cat, 10)
	check(game.finished and game.wall_damage == game.RULES.DAMAGE_LIMIT, "Wallpaper loss clamps damage")
	check(cat.scratch_timer.is_stopped(), "Finished shift stops cat")
	await fresh()
	game.start_shift()
	key(KEY_F)
	game._process(game.SHIFT_DURATION)
	check(game.finished and not game.hud.work_panel.visible, "Shift can end with laptop open")
	game._choose_email(right_answer())
	game._submit_email()
	check(game.quota == 0, "No answers after finish")
	await fresh()
	game.start_shift()
	game._on_work_requested()
	for i in range(5):
		game._choose_email(right_answer())
		game._submit_email()
		if i < 4:
			game.shift_time = (i + 1) * game.RULES.EMAIL_INTERVAL
			game._next_email()
	check(game.quota == 100 and game.hud.next_button.disabled and game.hud.next_button.text == "Следующее письмо", "Five completed emails meet quota without a false arrival countdown")
	game._process(game.SHIFT_DURATION)
	check(game.finished and game.hud.modal_title.text == "СМЕНА ЗАКРЫТА!", "Successful shift")
	await fresh()
	check(game.quota == 0 and game.inbox.selected == -1 and not game.working, "Fresh shift resets inbox and modes")
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("ITERATION_1_CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
