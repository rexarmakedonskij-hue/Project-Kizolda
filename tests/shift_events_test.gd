extends SceneTree
var game
var seen := {}
var damage_seen := false
var spilled := false
var cleaned := false
var sitting := false
var petted := false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	seed(418)
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.player.enabled = false
	Engine.time_scale = 20
	var deadline := Time.get_ticks_msec()+25000
	while not game.finished and Time.get_ticks_msec()<deadline:
		await process_frame
		var cat = game.active_cat
		if is_instance_valid(cat):
			var kind: String = cat.desktop.kind if cat.desktop != null else "wall"
			if not seen.has(kind):
				seen[kind] = game.shift_time
				print("EVENT ", kind, " at ", game.shift_time)
			if kind == "keyboard" and game.keyboard_blocked: sitting = true
			if kind == "keyboard" and cat.desktop.state == "seated":
				if game.working: game._on_work_requested()
				game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
				game._on_shoo_requested()
				petted = cat.desktop.state == "petting"
			if kind == "wall" and game.wall_damage>0:
				damage_seen = true
				if game.working: game._on_work_requested()
				game.player.camera.look_at(cat.global_position+Vector3.UP*.75)
				game._on_shoo_requested()
		if game.room.desk.dirty:
			spilled = true
			if not is_instance_valid(game.active_cat): game._start_cleaning()
		elif spilled: cleaned = true
		if not game._work_blocked() and game.quota<100:
			if not game.working: game._on_work_requested()
			game._choose_email(game.inbox.current.options.find(game.inbox.current.answer))
			game._submit_email()
			game._next_email()
	Engine.time_scale = 1
	var ok: bool = game.finished and game.quota==100 and game.wall_damage<game.RULES.DAMAGE_LIMIT and seen.size()==3 and sitting and petted and spilled and cleaned and damage_seen
	print("SHIFT_EVENTS: ", seen, " seated=", sitting, " spill=", spilled, " cleanup=", cleaned, " damage=", damage_seen, " quota=", game.quota, " elapsed=",game.shift_time)
	game.free()
	await create_timer(.1).timeout
	print("SHIFT_EVENTS_CHECK: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
