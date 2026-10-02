extends Node
# Opt-in packaged-build smoke test: Pawductivity.exe -- --verify-build
# Exercises the shipped resources and writes evidence to user://.
var game
var seen := {}
var seated := false
var petted := false
var hand_contact := false
var spilled := false
var cleaned := false
var scratched := false
var wall_support_active := false
var shots := {}
var stopping := false
var started_ms := 0

func _ready() -> void:
	game = get_parent()
	call_deferred("start")

func start() -> void:
	started_ms = Time.get_ticks_msec()
	game.start_shift()
	game.player.enabled = false
	Engine.time_scale = 10

func capture(label: String) -> void:
	if shots.has(label) or DisplayServer.get_name() == "headless": return
	shots[label] = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://verify-%s.png" % label)

func _process(_delta: float) -> void:
	if started_ms == 0 or stopping: return
	if game.finished or Time.get_ticks_msec()-started_ms>45000:
		finish()
		return
	var cat = game.active_cat
	if is_instance_valid(cat):
		var kind: String = cat.desktop.kind if cat.desktop != null else "wall"
		if kind=="wall" and cat.wall_support!=null and cat.wall_support.engaged:wall_support_active=true
		if not seen.has(kind): seen[kind] = game.shift_time
		game.player.camera.look_at(cat.global_position+Vector3.UP*(.3 if kind!="wall" else .75))
		if kind == "keyboard" and game.keyboard_blocked:
			seated = true
			capture("keyboard")
			if cat.desktop.state == "seated" and cat.desktop.elapsed > .5:
				if game.working: game._on_work_requested()
				game._on_shoo_requested()
				petted = cat.desktop.state == "petting"
			if cat.desktop.state == "petting" and game.player.pet_hand.touching:
				hand_contact = game.player.pet_hand.visible
				capture("petting")
		if kind == "cup" and cat.desktop.state == "touch" and cat.desktop.elapsed>.5:
			capture("cup")
		if kind == "wall" and game.wall_damage>0:
			scratched = true
			capture("wall")
			if game.working: game._on_work_requested()
			game._on_shoo_requested()
	if game.room.desk.dirty:
		spilled = true
		if game.room.desk.spill_age>=.65: capture("spill")
		if not is_instance_valid(game.active_cat): game._start_cleaning()
	elif spilled: cleaned = true
	if not game._work_blocked() and game.quota<100:
		if not game.working: game._on_work_requested()
		game._choose_email(game.inbox.current.options.find(game.inbox.current.answer))
		game._submit_email()
		game._next_email()
		if game.quota==100 and game.working: game._on_work_requested()

func finish() -> void:
	stopping = true
	Engine.time_scale = 1
	var cache_ready: bool = game.player.pet_hand.surface_geometry_source=="baked"
	var ok: bool = game.finished and game.quota==100 and seen.size()==3 and seated and petted and hand_contact and not game.player.pet_hand.active and spilled and cleaned and scratched and wall_support_active and game.wall_damage<game.RULES.DAMAGE_LIMIT and cache_ready
	var report := {"passed":ok,"events":seen,"seated":seated,"petted":petted,"hand_contact":hand_contact,"hand_hidden_at_end":not game.player.pet_hand.visible,"spilled":spilled,"cleaned":cleaned,"scratched":scratched,"quota":game.quota,"damage":game.wall_damage,"shift_seconds":game.shift_time,"renderer":DisplayServer.get_name(),"screenshots":shots.keys()}
	report["petting_surface"]={"source":game.player.pet_hand.surface_geometry_source,"prepare_ms":game.player.pet_hand.surface_prepare_usec/1000.0,"baked_cache_loaded":cache_ready}
	report["wall_support_active"]=wall_support_active
	var file := FileAccess.open("user://build-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	await get_tree().create_timer(.5).timeout
	get_tree().quit(0 if ok else 1)
