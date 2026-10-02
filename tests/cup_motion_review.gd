extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.verifying_build=true
	game.set_process(false)
	game.player.enabled=false
	game.room.desk.set_process(false)
	game._spawn_cat("cup")
	var cat=game.active_cat
	cat.set_process(false)
	for i in 3600:
		if cat.desktop.state=="touch": break
		cat._process(1.0/60)
	game.player.camera.global_position=Vector3(-2.1,1.75,-.25)
	game.player.camera.look_at(Vector3(-1.0,1.15,-1.1))
	DirAccess.make_dir_recursive_absolute("res://tests/results/cup-motion-frames")
	FileAccess.open("res://tests/results/cup-motion-frames/.gdignore",FileAccess.WRITE).close()
	for frame in 160:
		if is_instance_valid(cat) and not cat.is_queued_for_deletion(): cat._process(.05)
		game._process(0)
		game.room.desk._process(.05)
		await process_frame
		await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image()
		picture.save_jpg("res://tests/results/cup-motion-frames/%04d.jpg"%frame,.9)
		if frame in [11,36,66,90]: picture.save_png("res://tests/results/cup-pass2-%03d.png"%frame)
	game.free()
	print("CUP_MOTION_REVIEW_OK")
	quit()
