extends SceneTree
var game
func _initialize(): call_deferred("run")
func run():
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._spawn_cat("keyboard")
	var cat = game.active_cat
	cat.set_process(false)
	for i in 3600:
		if cat.desktop.state == "seated": break
		cat._process(1.0/60)
	cat._process(.4)
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	game._on_shoo_requested()
	DirAccess.make_dir_recursive_absolute("res://tests/results/hand-review-frames")
	for frame in 100:
		if frame > 0 and is_instance_valid(cat): cat._process(1.0/20)
		game._process(0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg("res://tests/results/hand-review-frames/%04d.jpg" % frame, .9)
		if frame in [6, 14, 26, 36, 46, 74]:
			root.get_texture().get_image().save_png("res://tests/results/hand-stage-%d.png" % frame)
		if frame % 20 == 0: print("CAPTURE_FRAME ", frame)
	# Side view exposes the contact and bent elbow for visual inspection.
	if is_instance_valid(cat): cat.free()
	game.active_cat = null
	game.departing_cat = null
	game._spawn_cat("keyboard")
	cat = game.active_cat
	cat.set_process(false)
	for i in 3600:
		if cat.desktop.state == "seated": break
		cat._process(1.0/60)
	game.player.camera.global_position = Vector3(1.6,1.9,-.5)
	game.player.camera.look_at(cat.global_position+Vector3.UP*.35)
	game._on_shoo_requested()
	cat._process(.8)
	var hand = game.player.pet_hand
	print("SIDE_HAND ", hand.age, " wrist=",hand.wrist," contact=",hand.contact," palm=",hand.skeleton.to_global(hand.skeleton.get_bone_global_pose(hand.skeleton.find_bone("palm")).origin))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/hand-side.png")
	game.player.camera.global_position = Vector3(0,2.7,-.65)
	game.player.camera.look_at(cat.global_position+Vector3.UP*.35)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/hand-overhead.png")
	game.free()
	print("HAND_CAPTURE_OK")
	quit()
