extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var args := OS.get_cmdline_user_args()
	var model_path: String = args[0] if args.size() > 0 else "res://builds/b3-rig-review/B3-rig-review.glb"
	var error := document.append_from_file(model_path, state)
	if error != OK:
		push_error("B3 GLB import failed: %s" % error)
		quit(1)
		return
	var model := document.generate_scene(state)
	preload("res://assets/models/glb/godot_mvp/cat_import.gd").apply_vertex_colors(model)
	root.add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var animations := model.find_children("*", "AnimationPlayer", true, false)
	if not (skeletons.size() == 1 and animations.size() == 1):
		fail("skeletons.size() == 1 and animations.size() == 1")
		return
	var skeleton: Skeleton3D = skeletons[0]
	var animation: AnimationPlayer = animations[0]
	if not (skeleton.get_bone_count() == 16):
		fail("skeleton.get_bone_count() == 16")
		return
	if not (animation.has_animation("Scratch") and animation.has_animation("Sit")):
		fail("Missing Scratch or Sit clip")
		return
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip := animation.get_animation("Scratch")
	if not (abs(clip.length - 40.0 / 30.0) < .001):
		fail("abs(clip.length - 40.0 / 30.0) < .001")
		return
	animation.play("Scratch")
	animation.seek(0, true)
	var first: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		first.append(skeleton.get_bone_pose(i))
	animation.seek(clip.length, true)
	for i in skeleton.get_bone_count():
		if not (first[i].is_equal_approx(skeleton.get_bone_pose(i))):
			fail("first[i].is_equal_approx(skeleton.get_bone_pose(i))")
			return
	var paw := skeleton.find_bone("paw_L")
	animation.seek(.35 * clip.length, true)
	var high := skeleton.get_bone_pose(paw).origin
	animation.seek(.60 * clip.length, true)
	var low := skeleton.get_bone_pose(paw).origin
	if not (high.distance_to(low) > .3):
		fail("high.distance_to(low) > .3")
		return
	if not animation.has_animation("Walk"):
		fail("Missing Walk clip")
		return
	var walk := animation.get_animation("Walk")
	if abs(walk.length - .8) > .001:
		fail("Walk duration differs from stride timing")
		return
	animation.play("Walk")
	animation.seek(0, true)
	var walk_first: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		walk_first.append(skeleton.get_bone_pose(i))
	animation.seek(walk.length, true)
	for i in skeleton.get_bone_count():
		if not walk_first[i].is_equal_approx(skeleton.get_bone_pose(i)):
			fail("Walk loop seam differs")
			return
	var start := sample_paw(animation, skeleton, "paw_L", 0)
	var planted := sample_paw(animation, skeleton, "paw_L", .2)
	var lifted := sample_paw(animation, skeleton, "paw_L", .6)
	if abs(start.y - planted.y) > .002 or abs((start.z - planted.z) - .8 * .2) > .005:
		fail("Planted foot slips relative to route speed")
		return
	if lifted.y - planted.y < .08:
		fail("Swing foot does not clear the floor")
		return
	# Exercise the runtime pose capture, including an interrupted transition.
	var driver = preload("res://cats/pose_player.gd").new(animation, skeleton)
	animation.seek(.2, true)
	var before := skeleton.get_bone_pose(paw)
	driver.play("Sit", .3)
	driver.advance(.001)
	if before.origin.distance_to(skeleton.get_bone_pose(paw).origin) > .01:
		fail("Walk to Sit snaps on its first sample")
		return
	driver.advance(.1)
	before = skeleton.get_bone_pose(paw)
	driver.play("Scratch", .3)
	driver.advance(.001)
	if before.origin.distance_to(skeleton.get_bone_pose(paw).origin) > .01:
		fail("Interrupted transition snaps")
		return
	for step in 20:
		driver.advance(1.0 / 60.0)
	var blended_end: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		blended_end.append(skeleton.get_bone_pose(i))
	animation.seek(animation.current_animation_position, true)
	for i in skeleton.get_bone_count():
		if not blended_end[i].is_equal_approx(skeleton.get_bone_pose(i)):
			fail("Completed blend does not reach the target animation")
			return
	print("B3_WALK_OK: seam, planted stride, foot lift, blend interruption and target pose")
	skeleton.force_update_all_bone_transforms()
	var head := skeleton.find_bone("head")
	var head_basis := skeleton.get_bone_global_pose(head).basis
	var rest_basis := skeleton.get_bone_global_rest(head).basis
	if not head_basis.is_equal_approx(rest_basis):
		fail("Scratch head tilts away from its neutral orientation: " + str(head_basis.get_euler()))
		return
	var colored := 0
	var tint_enabled := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > 0:
				colored += 1
				var material: StandardMaterial3D = instance.mesh.surface_get_material(surface)
				if material.vertex_color_use_as_albedo:
					tint_enabled += 1
	if not (colored > 0):
		fail("colored > 0")
		return
	if tint_enabled != colored:
		fail("Vertex colors are not enabled on every painted surface")
		return
	print("B3_IMPORT_OK bones=", skeleton.get_bone_count(), " clips=", animation.get_animation_list(), " colored_surfaces=", colored, " tint_enabled=", tint_enabled)
	model.queue_free()
	await process_frame
	quit()

func fail(message: String) -> void:
	push_error("B3_IMPORT_FAILED: " + message)
	quit(1)

func sample_paw(animation: AnimationPlayer, skeleton: Skeleton3D, name: String, time: float) -> Vector3:
	animation.seek(time, true)
	skeleton.force_update_all_bone_transforms()
	return skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
