extends SceneTree
# Check the deformed fur, including the old missing-rest rotation as a fault.
var failures := 0
var cat
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var surfaces := []
var report := {}

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1

func lowest_skin() -> float:
	skeleton.force_update_all_bone_transforms()
	var transforms: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
		if bone < 0: bone = mesh.skin.get_bind_bone(bind)
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
	var lowest := INF
	for arrays in surfaces:
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for slot in 4:
				var index: int = vertex * 4 + slot
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][index]
				if weight > 0:
					point += (transforms[arrays[Mesh.ARRAY_BONES][index]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * weight
			lowest = minf(lowest, point.y)
	return lowest

func run():
	cat = load("res://cats/cat.tscn").instantiate()
	# The controller's floor routes place the root 6 cm above the floor;
	# MODEL_GROUND_Y cancels this authored root height in the imported model.
	cat.position.y = .06
	root.add_child(cat)
	cat.set_process(false)
	skeleton = cat.pose_player.skeleton
	mesh = cat.model.find_child("mesh_cat", true, false)
	for surface in mesh.mesh.get_surface_count(): surfaces.append(mesh.mesh.surface_get_arrays(surface))
	var clip: Animation = cat.animation.get_animation("Idle")
	cat.pose_player.play("Idle", 0)
	var samples := []
	var lowest := INF
	var maximum_paw_drift := 0.0
	var initial := {}
	for sample in 25:
		cat.animation.seek(clip.length * sample / 24.0, true)
		var skin_y := lowest_skin()
		lowest = minf(lowest, skin_y)
		for limb in ["front", "back"]:
			for side in ["left", "right"]:
				var name := "leg_%s_%s_4" % [limb, side]
				var point := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin)
				if sample == 0: initial[name] = point
				maximum_paw_drift = maxf(maximum_paw_drift, point.distance_to(initial[name]))
		samples.append({"time":clip.length * sample / 24.0, "skin_floor_y":skin_y})
	check(lowest >= -.003, "Whole idle cycle keeps the actual fur above the floor within 3 mm")
	check(maximum_paw_drift < .01, "Idle breathing keeps all four paw positions within 1 cm")
	# Inject the original fault after measuring production; a green check must
	# distinguish it from a correctly composed imported rotation.
	skeleton.reset_bone_poses()
	skeleton.set_bone_pose_rotation(skeleton.find_bone("body_2"), Quaternion(Vector3.RIGHT, .012))
	var legacy_y := lowest_skin()
	check(legacy_y < -.02, "Negative control detects the original spine rotation driving fur through the floor")
	report = {"passed":failures == 0, "scope":"Full-cycle bone-skinned fur and four paw positions; negative control removes body_2 imported rest rotation.", "minimum_skin_y":lowest, "maximum_paw_drift":maximum_paw_drift, "legacy_missing_rest_skin_y":legacy_y, "samples":samples, "hashes":{}}
	for path in ["cats/cat.gd", "assets/models/glb/godot_mvp/cat_reference.fbx"]:
		report.hashes[path] = FileAccess.get_sha256("res://" + path)
	FileAccess.open("res://tests/results/idle-surface-pass6.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	cat.free()
	print("IDLE_SURFACE_CHECKS: ", 3 - failures, " passed, ", failures, " failed")
	quit(1 if failures else 0)
