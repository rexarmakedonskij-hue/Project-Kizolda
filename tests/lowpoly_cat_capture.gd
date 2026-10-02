extends SceneTree

const MODEL_PATH := "res://cats/cat.tscn"
const OUTPUT_PREFIX := "res://tests/results/refined-cat-walk"

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(960, 960)
	root.content_scale_size = Vector2i(960, 960)

	var stage := Node3D.new()
	root.add_child(stage)
	_add_environment(stage)

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("Could not load %s" % MODEL_PATH)
		quit(1)
		return
	var cat := packed.instantiate()
	stage.add_child(cat)
	cat.set_process(false)
	await process_frame
	var model: Node3D = cat.model

	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if meshes.is_empty() or skeletons.is_empty() or players.is_empty():
		push_error("Imported model is missing mesh, skeleton, or AnimationPlayer")
		quit(1)
		return

	var bounds: AABB
	var first_mesh := true
	var triangles := 0
	for child in meshes:
		var mesh_instance := child as MeshInstance3D
		var transformed := mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = transformed if first_mesh else bounds.merge(transformed)
		first_mesh = false
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3

	var animation_player := players[0] as AnimationPlayer
	var run_animation := "Walk"

	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_player.get_animation(run_animation).loop_mode = Animation.LOOP_LINEAR
	animation_player.play(run_animation)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var subject_size: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	plane.size = Vector2(subject_size * 8.0, subject_size * 8.0)
	floor_mesh.mesh = plane
	floor_mesh.position.y = bounds.position.y
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("cbd0d0")
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)

	var center := bounds.get_center()
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = center + Vector3(subject_size * 1.15, subject_size * 0.55, subject_size * 1.55)
	camera.look_at(center + Vector3.UP * subject_size * 0.05)
	camera.fov = 32
	camera.make_current()

	var animation := animation_player.get_animation(run_animation)
	for index in 3:
		var position := animation.length * float(index) / 3.0
		animation_player.seek(position, true)
		cat.tail_motion.apply(.2)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s-%d.png" % [OUTPUT_PREFIX, index])

	print("LOWPOLY_CAT_CAPTURE_OK meshes=%d bones=%d triangles=%d animation=%s length=%.3f" % [
		meshes.size(),
		(skeletons[0] as Skeleton3D).get_bone_count(),
		triangles,
		run_animation,
		animation.length,
	])
	if "--movie-frames" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://builds/cat-review-frames")
		cat.pose_player.play("Walk")
		for frame in 120:
			cat.pose_player.advance(1.0 / 30.0, cat.WALK_SPEED / cat.GAIT_SPEED)
			cat.tail_motion.apply(1.0/30)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://builds/cat-review-frames/frame%04d.png" % frame)
	quit()


func _add_environment(stage: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("cbd0d0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.25
	stage.add_child(environment)
	for light_pose in [Vector3(-35, -30, 0), Vector3(-20, 130, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = light_pose
		light.light_energy = 0.7 if light_pose.y < 0 else 0.25
		light.shadow_enabled = false
		stage.add_child(light)
