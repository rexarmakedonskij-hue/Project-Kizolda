extends SceneTree

const PROFILES := ["early", "after_consequence", "slow_reactive", "ignore"]
const SEEDS := [418, 2026]
const READING_SECONDS := 10.0
const SLOW_READING_SECONDS := 30.0

func _initialize() -> void:
	call_deferred("run")

func intervene(game, cat) -> bool:
	if game.working:
		game._on_work_requested()
	game.player.camera.look_at(cat.global_position + Vector3.UP * (.3 if cat.desktop != null else .75))
	game._on_shoo_requested()
	return game.active_cat == null or (cat.desktop != null and cat.desktop.state == "petting")

func should_intervene(game, cat, profile: String) -> bool:
	if profile == "ignore":
		return false
	if cat.desktop != null:
		if profile == "early":
			return cat.desktop.state == "warning" and cat.desktop.elapsed >= 1.0
		return (cat.desktop.kind == "keyboard" and cat.desktop.state == "seated") or (cat.desktop.kind == "cup" and game.room.desk.dirty)
	if profile == "early":
		return cat.route.is_empty() and cat.warning and cat.scratch_timer.time_left <= game.RULES.WARNING_DURATION - 1.0
	return game.wall_damage > 0

func run_profile(profile: String, run_seed: int) -> Dictionary:
	seed(run_seed)
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.player.enabled = false
	Engine.time_scale = 20.0
	var next_work_at := 0.0
	var work_times: Array[float] = []
	var intervention_times: Array[float] = []
	var seen := {}
	var deadline := Time.get_ticks_msec() + 30000
	while not game.finished and Time.get_ticks_msec() < deadline:
		await process_frame
		var cat = game.active_cat
		if is_instance_valid(cat):
			var kind: String = cat.desktop.kind if cat.desktop != null else "wall"
			if not seen.has(kind):
				seen[kind] = game.shift_time
			if should_intervene(game, cat, profile) and intervene(game, cat):
				intervention_times.append(game.shift_time)
		if profile != "ignore" and game.room.desk.dirty and not is_instance_valid(game.active_cat) and not game.cleaning:
			game._start_cleaning()
		if game.inbox.resolved and game._email_wait() <= 0 and not game._work_blocked() and game.quota < 100:
			if not game.working:
				game._on_work_requested()
			game._next_email()
		if game.shift_time >= next_work_at and not game.inbox.resolved and not game._work_blocked() and game.quota < 100:
			if not game.working:
				game._on_work_requested()
			game._choose_email(game.inbox.current.options.find(game.inbox.current.answer))
			game._submit_email()
			game._next_email()
			work_times.append(game.shift_time)
			next_work_at = game.shift_time + (SLOW_READING_SECONDS if profile == "slow_reactive" else READING_SECONDS)
	Engine.time_scale = 1.0
	var result := {
		"seed": run_seed,
		"profile": profile,
		"finished": game.finished,
		"won": game.finished and game.quota == 100 and game.wall_damage < game.RULES.DAMAGE_LIMIT,
		"quota": game.quota,
		"damage": game.wall_damage,
		"events": seen,
		"work_times": work_times,
		"interventions": intervention_times,
		"elapsed": game.shift_time,
	}
	game.queue_free()
	await process_frame
	return result

func run() -> void:
	var results := []
	var valid := true
	for run_seed in SEEDS:
		for profile in PROFILES:
			var result: Dictionary = await run_profile(profile, run_seed)
			results.append(result)
			print("BALANCE_PROFILE ", JSON.stringify(result))
			valid = valid and result.finished and result.events.size() == 3
			if profile == "ignore":
				valid = valid and not result.won and result.quota < 100 and result.damage >= 50
			else:
				valid = valid and result.won and result.quota == 100 and result.work_times.size() == 5
				valid = valid and result.work_times[4] >= 95.0
	var file := FileAccess.open("res://tests/results/balance-probe-2026-09-26.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	file.close()
	print("BALANCE_PROBE_CHECK: ", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)
