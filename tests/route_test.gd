extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
func run() -> void:
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat()
	var cat = game.active_cat
	cat.set_process(false)
	check(cat.animation.has_animation("Walk"), "Imported run clip mapped to Walk")
	check(cat.scratch_timer.is_stopped() and not cat.route.is_empty(), "Approach delays warning timer")
	var before: Vector3 = cat.position
	cat._process(.1)
	check(cat.position.distance_to(before) > 0 and cat.position.distance_to(before) < .08, "Movement accelerates from rest without teleport")
	game.toggle_pause()
	before = cat.position
	cat.set_process(true)
	await create_timer(.06, true).timeout
	check(cat.position == before, "Pause freezes approach")
	game.toggle_pause()
	cat.set_process(false)
	cat._process(100)
	check(cat.route.is_empty() and cat.warning and cat.scratch_timer.time_left > 0, "Arrival begins warning at wall")
	check(cat.position.distance_to(game.room.get_cat_position(-1 if cat.position.x<0 else 1)) < .01, "Route reaches the actual room wall approach position")
	game.player.camera.look_at(cat.global_position + Vector3.UP * .75)
	check(cat.try_to_chase(game.player), "Shoo starts return route")
	check(cat.leaving and not cat.route.is_empty() and game.active_cat == null, "Leaving cat no longer threatens work")
	check(not cat.try_to_chase(game.player), "Repeated shoo cannot restart departure")
	cat._process(.1)
	game._end_shift(false)
	before = cat.position
	cat._process(1)
	check(cat.position == before, "Result freezes departing cat too")
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("ROUTE_CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
