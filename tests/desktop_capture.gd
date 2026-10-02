extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func reach(cat, state: String) -> bool:
	for i in 3600:
		if cat.desktop.state==state: return true
		cat._process(1.0/60)
	return false
func shot(label: String) -> void:
	game.hud.update_cat(game.active_cat,game.player)
	await create_timer(.35).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/desk-"+label+".png")
func run() -> void:
	game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game.player.enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.player.camera.look_at(Vector3(0,1,-1.5))
	game._spawn_cat("keyboard")
	var cat=game.active_cat
	cat.set_process(false)
	if not reach(cat,"jump_up"): quit(1); return
	cat._process(.42)
	await shot("jump")
	if not reach(cat,"seated"): quit(1); return
	cat._process(.5)
	await shot("keyboard")
	game.player.camera.position=Vector3(2.6,2.3,-.1)
	game.player.camera.look_at(cat.position+Vector3.UP*.25)
	await shot("keyboard-side")
	game.player.camera.position=Vector3(0,1.55,.35)
	game.player.camera.look_at(cat.position+Vector3.UP*.3)
	game._on_shoo_requested()
	cat._process(.6)
	await shot("petting")
	cat.free()
	game.active_cat=null
	game.keyboard_blocked=false
	game._sync_obstruction()
	game.player.camera.position=Vector3(0,1.55,.35)
	game.player.camera.look_at(Vector3(-.5,1,-1.5))
	game._spawn_cat("cup")
	cat=game.active_cat
	cat.set_process(false)
	if not reach(cat,"touch"): quit(1); return
	cat._process(.7)
	await shot("cup-warning")
	if not reach(cat,"spill"): quit(1); return
	game.room.desk._process(.65)
	await shot("spill")
	game._start_cleaning()
	game._process(1.2)
	await shot("cleaning")
	game._process(1.3)
	await shot("clean")
	game.free()
	await process_frame
	print("DESKTOP_CAPTURE_OK")
	quit()
