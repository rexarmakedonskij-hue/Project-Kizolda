extends SceneTree
var failures:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error(label)
func run():
	var game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.verifying_build=true
	game.set_process(false)
	game.player.enabled=false
	game._spawn_cat("keyboard")
	var cat=game.active_cat
	cat.set_process(false)
	for i in 3600:
		if cat.desktop.state=="seated": break
		cat._process(1.0/60)
	check(cat.face_shapes.has_all(["Blink","HideIris","LookLeft","LookRight"]),"Imported face has eyelid closure and both gaze shapes")
	var camera: Camera3D=game.player.camera
	var centre: Vector3=camera.global_position
	var directions:=[]
	var max_step:=0.0
	var capture:="--capture" in OS.get_cmdline_user_args()
	var output:="res://tests/results/face-motion-pass3"
	if capture: DirAccess.make_dir_recursive_absolute(output)
	for offset in [-.35,.35,0.0]:
		camera.global_position=centre+Vector3(offset,0,0)
		for i in 60:
			var previous: float=cat.gaze
			cat._process(1.0/60)
			max_step=maxf(max_step,absf(cat.gaze-previous))
		directions.append(cat.gaze)
		print("GAZE_SAMPLE offset=",offset," value=",cat.gaze," viewer=",root.get_camera_3d()," state=",cat.desktop.state)
		if capture:
			# Keep a common frontal review viewpoint so only the eye motion
			# changes between images; avoid sampling an incidental blink.
			cat.face_time=1.0
			cat._update_face(0)
			camera.global_position=centre
			camera.look_at(cat.global_position+Vector3.UP*.3)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/gaze-%s.png"%str(offset))
	check(directions[0]*directions[1]<0 and absf(directions[0])>.2 and absf(directions[1])>.2,"Gaze follows the viewer on both sides")
	check(max_step*.0025*cat.MODEL_SCALE<.001 and absf(directions[2])<.02,"Gaze changes less than 1 mm per frame and returns to centre")
	cat._process(.5)
	check(cat.gaze>.15,"Waiting cat briefly glances across the keyboard")
	cat.face_time=4.8+.09-1.0/60
	cat._process(1.0/60)
	check(cat.face_mesh.get_blend_shape_value(cat.face_shapes["Blink"])>.99 and cat.face_mesh.get_blend_shape_value(cat.face_shapes["HideIris"])>.99,"Full blink closes lids and hides the coloured iris")
	if capture:
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/blink.png")
	game._on_shoo_requested()
	cat._process((game.player.pet_hand.CONTACT_START+game.player.pet_hand.CONTACT_END)*.5)
	check(cat.desktop.state=="petting" and cat.face_mesh.get_blend_shape_value(cat.face_shapes["Blink"])>.4 and cat.face_mesh.get_blend_shape_value(cat.face_shapes["HideIris"])<.001,"Affection half-closes the eyes without hiding the iris")
	if capture:
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/affection.png")
	game.toggle_pause()
	cat.set_process(true)
	var age: float=cat.face_time
	await create_timer(.05,true).timeout
	check(is_equal_approx(cat.face_time,age),"Pause freezes facial motion")
	game.toggle_pause()
	cat.set_process(false)
	game.free()
	print("FACE_MOTION_CHECKS: ",7-failures," passed, ",failures," failed")
	quit(1 if failures else 0)
