extends SceneTree
func _initialize(): call_deferred("run")
func run():
	root.size=Vector2i(900,900)
	root.content_scale_size=root.size
	var stage:=Node3D.new()
	root.add_child(stage)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("c3c9c3")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=.65
	stage.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-40,-30,0)
	light.light_energy=.8
	light.shadow_enabled=true
	stage.add_child(light)
	var floor:=MeshInstance3D.new()
	floor.mesh=PlaneMesh.new()
	floor.mesh.size=Vector2(10,10)
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("c3c9c3")
	floor.material_override=material
	stage.add_child(floor)
	var cat=load("res://cats/cat.tscn").instantiate()
	var model_name := "cat_reference"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--model-name="):
			model_name=argument.trim_prefix("--model-name=")
			cat.model_scene=load("res://assets/models/glb/godot_mvp/"+model_name+".fbx")
	stage.add_child(cat)
	cat.set_process(false)
	cat.position.y=.06
	var camera:=Camera3D.new()
	stage.add_child(camera)
	camera.current=true
	camera.fov=36
	var views={"front":Vector3(0,.65,1.8),"side":Vector3(2.8,.7,0),"three-quarter":Vector3(1.6,.8,1.7)}
	var review_pass:="pass4"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-pass="): review_pass=argument.trim_prefix("--review-pass=")
	var output := "res://tests/results/reference-shape-"+review_pass
	DirAccess.make_dir_recursive_absolute(output)
	var report := {"scope":"Rendered isolated Idle and Sit after two seconds of animation and tail settling; full gameplay transitions are checked separately.", "model":model_name, "root_height":.06, "resolution":[900,900], "images":[], "hashes":{}}
	for path in ["cats/cat.gd", "cats/desktop_poses.gd", "cats/tail_motion.gd", "assets/models/glb/godot_mvp/"+model_name+".fbx", "tests/reference_shape_review.gd"]:
		report.hashes[path] = FileAccess.get_sha256("res://"+path)
	for clip in ["Idle","Sit"]:
		cat.pose_player.play(clip)
		for frame in 120:
			cat.pose_player.advance(1.0/60)
			cat.tail_motion.apply(1.0/60)
		for name in views:
			camera.position=views[name]
			camera.look_at(Vector3(0,.28,0))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s-%s.png"%[output,clip,name])
			report.images.append({"image":"%s-%s.png"%[clip,name], "clip":clip, "clip_time":cat.animation.current_animation_position, "view":name})
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	stage.free()
	await process_frame
	print("REFERENCE_SHAPE_CAPTURE_OK")
	quit()
