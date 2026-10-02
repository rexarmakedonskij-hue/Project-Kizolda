extends SceneTree
var game
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if value: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._process(game.RULES.FIRST_CAT_DELAY-.1)
	check(not is_instance_valid(game.active_cat),"First visit still waits the full initial delay")
	game._process(.1)
	var cat = game.active_cat
	cat.set_process(false)
	check(is_instance_valid(cat) and cat.desktop.kind=="keyboard","First visit still starts with keyboard")
	var held_delay: float = game.next_cat_in
	game._process(2)
	check(game.next_cat_in==held_delay,"Cooldown cannot elapse while a cat is active")
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	game._on_shoo_requested()
	var cooldown: float = game.next_cat_in
	check(cooldown>=game.RULES.RESPAWN_MIN and cooldown<=game.RULES.RESPAWN_MAX,"Chase retains the original randomized cooldown")
	game._process(1)
	check(absf(game.next_cat_in-(cooldown-1))<.001 and game.departing_cat==cat,"Cooldown advances while the departing cat walks home")
	game.toggle_pause()
	game.set_process(true)
	var paused_cooldown: float = game.next_cat_in
	await create_timer(.12).timeout
	game.set_process(false)
	check(game.next_cat_in==paused_cooldown,"Pause freezes the departure cooldown")
	game.toggle_pause()
	game._process(cooldown+1)
	check(game.next_cat_in==0 and not is_instance_valid(game.active_cat) and game.departing_cat==cat,"Expired cooldown waits for the current cat to finish leaving")
	game._spawn_cat("cup")
	check(not is_instance_valid(game.active_cat) and game.event_index==1,"Direct spawning also prevents overlapping visits")
	for step in 6000:
		if cat.is_queued_for_deletion(): break
		cat._process(1.0/60)
	check(cat.is_queued_for_deletion(),"Departing cat completes its real route home")
	await process_frame
	game._process(0)
	check(is_instance_valid(game.active_cat) and game.active_cat.desktop.kind=="cup" and game.event_index==2,"Next visit starts after departure without another full cooldown")
	game.active_cat.set_process(false)
	game._end_shift(true)
	game._process(100)
	check(game.event_index==2,"Finished shift does not schedule further visits")
	game.free()
	await process_frame
	await create_timer(.4).timeout
	print("CAT_VISIT_PACING_TEST: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
