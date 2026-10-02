extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(960, 960)
	root.content_scale_size = Vector2i(960, 960)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("cbd0d0")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .15
	stage.add_child(env)
	for light_pose in [Vector3(-35,-30,0), Vector3(-20,130,0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_pose
		light.light_energy = .22 if light_pose.y < 0 else .08
		light.shadow_enabled = true
		stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("cbd0d0")
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var model = load("res://assets/models/glb/godot_mvp/cat.glb").instantiate()
	stage.add_child(model)
	for mesh_name in ["Head", "Body"]:
		var mesh: MeshInstance3D = model.find_child(mesh_name, true, false)
		var skin: StandardMaterial3D = mesh.get_active_material(0)
		print(mesh_name, " vertex tint: ", skin.vertex_color_use_as_albedo, " material: ", skin.albedo_color)
	var animation: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play("Sit")
	animation.seek(.2,true)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.fov = 31
	camera.make_current()
	var poses := [Vector3(0,1.3,3.4), Vector3(2.2,1.5,3.1), Vector3(2.3,1.2,2.6)]
	for i in range(3):
		if i == 2:
			animation.play("Walk")
			animation.seek(.2, true)
		camera.position = poses[i]
		camera.look_at(Vector3(0,.75,0))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/results/cat-reference-%d.png" % i)
	stage.queue_free()
	await process_frame
	await create_timer(.3).timeout
	print("CAT_MODEL_CAPTURE_OK")
	quit()
