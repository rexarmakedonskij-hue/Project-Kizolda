extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func make_cat():
	var cat = load("res://cats/cat.tscn").instantiate()
	root.add_child(cat)
	cat.set_process(false)
	return cat

func run() -> void:
	var cat = make_cat()
	var bones: Skeleton3D = cat.pose_player.skeleton
	var mesh: MeshInstance3D = cat.model.find_child("mesh_cat", true, false)
	var triangles := 0
	for surface in mesh.mesh.get_surface_count():
		triangles += mesh.mesh.surface_get_array_index_len(surface) / 3
	check(triangles > 794 and triangles < 100000, "Detailed cat stays under 100k triangles")
	cat.pose_player.play("Walk")
	var clip: Animation = cat.animation.get_animation("Walk")
	for limb in ["front", "back"]:
		for side in ["left", "right"]:
			var names_ok := true
			for segment in range(1, 5):
				names_ok = names_ok and bones.find_bone("leg_%s_%s_%d" % [limb, side, segment]) >= 0
			check(names_ok, "%s %s has four articulated leg/paw bones" % [limb, side])
			var foot := bones.find_bone("leg_%s_%s_4" % [limb, side])
			var low := INF
			var high := -INF
			var max_jump := 0.0
			var previous := Vector3.ZERO
			var first := Vector3.ZERO
			for sample in 121:
				cat.animation.seek(clip.length * sample / 120.0, true)
				bones.force_update_all_bone_transforms()
				var p := bones.to_global(bones.get_bone_global_pose(foot).origin)
				low = minf(low, p.y)
				high = maxf(high, p.y)
				if sample == 0: first = p
				else: max_jump = maxf(max_jump, p.distance_to(previous))
				previous = p
			check(high - low > .02, "%s %s lifts and plants the paw" % [limb, side])
			check(max_jump < .025 and previous.distance_to(first) < .005, "%s %s has a continuous gait and loop seam" % [limb, side])
	cat.pose_player.play("Scratch", .3)
	cat.pose_player.advance(.12)
	var visible: Array[Transform3D] = []
	for i in bones.get_bone_count(): visible.append(bones.get_bone_pose(i))
	cat.pose_player.play("Walk", .3)
	var no_snap := true
	for i in bones.get_bone_count():
		no_snap = no_snap and visible[i].is_equal_approx(bones.get_bone_pose(i))
	check(no_snap, "Interrupted blend starts from the exact visible pose")
	cat._update_posture(cat.POSTURE_BLEND_DURATION, 1.0)
	cat.position.y = .06
	cat.pose_player.play("Scratch")
	cat.pose_player.advance(.01)
	bones.force_update_all_bone_transforms()
	for side in ["left", "right"]:
		var foot := bones.find_bone("leg_back_%s_4" % side)
		var p := bones.to_global(bones.get_bone_global_pose(foot).origin)
		check(absf(p.y) < .05, "%s rear paw stays at floor during scratching" % side)
	var a = make_cat()
	var b = make_cat()
	var path := PackedVector3Array([Vector3.ZERO, Vector3(0,0,1), Vector3(1,0,1)])
	a.approach(path)
	b.approach(path)
	for i in 60: a._process(1.0/60)
	for i in 30: b._process(1.0/30)
	check(a.position.distance_to(b.position) < .002, "30 and 60 fps give the same movement")
	var bounded := true
	for i in 240:
		var angle: float = a.rotation.y
		a._process(1.0/60)
		bounded = bounded and absf(angle_difference(angle,a.rotation.y)) <= a.TURN_SPEED/60+.001
	check(bounded, "Corner and final orientation have no instant turn")
	cat.free()
	a.free()
	b.free()
	print("REFINED_CAT_CHECKS: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
