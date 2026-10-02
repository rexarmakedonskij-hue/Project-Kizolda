extends SceneTree
var game
func _initialize(): call_deferred("run")
func run():
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.verifying_build = true
	game.set_process(false)
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._spawn_cat("keyboard")
	var cat = game.active_cat
	cat.set_process(false)
	for step in 3600:
		if cat.desktop.state=="warning": break
		cat._process(1.0/60)
	# Sample the entire anticipation, rather than skipping its turn toward the desk.
	cat.desktop.elapsed=cat.desktop.duration-.8
	game.player.camera.global_position=Vector3(3.8,2.8,2.4)
	game.player.camera.look_at(Vector3(1.2,1.0,-1.1))
	DirAccess.make_dir_recursive_absolute("res://tests/results/desktop-motion-frames")
	var shots := {}
	var petted := false
	for frame in 280:
		if not is_instance_valid(cat) or cat.is_queued_for_deletion(): break
		cat._process(1.0/20)
		game._process(0)
		var state: String = cat.desktop.state
		if state=="seated" and not petted and cat.desktop.elapsed>.35:
			# Review camera stays outside the game viewpoint; trigger the same
			# accepted interaction after the gameplay checks verify its input.
			cat.pet_hand=game.player.pet_hand
			cat.pet_player=game.player
			cat.desktop.pet()
			petted=true
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.save_jpg("res://tests/results/desktop-motion-frames/%04d.jpg" % frame,.9)
		if not shots.has(state):
			shots[state]=true
			picture.save_png("res://tests/results/motion-"+state+".png")
		if state.begins_with("jump_") and frame%3==0:
			picture.save_png("res://tests/results/motion-"+state+"-%03d.png" % frame)
	game.free()
	print("DESKTOP_MOTION_REVIEW ",shots)
	quit()
