extends RefCounted
# Prevent the mixed Walk/Crouch pose from putting the actual paw underside
# below its support plane. Use the existing fixed-length limb solver.
var cat
var skeleton: Skeleton3D
var pads := {}
var metrics := {}
var initialization_usec := 0

func _init(owner_cat):
	var started := Time.get_ticks_usec()
	cat = owner_cat
	skeleton = cat.pose_player.skeleton
	pads=preload("res://cats/paw_geometry.gd").get_pads(cat.model,skeleton)
	initialization_usec = Time.get_ticks_usec() - started

func apply():
	metrics = {"maximum_correction":0.0, "maximum_target_error":0.0}
	var support_y: float = cat.global_position.y + cat.MODEL_GROUND_Y
	skeleton.force_update_all_bone_transforms()
	for foot in cat.grounded_gait.feet:
		var poses: Array[Transform3D] = []
		var points: Array[Vector3] = []
		for bone in foot.bones:
			var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			poses.append(pose)
			points.append(pose.origin)
		var minimum := INF
		for point in pads[foot.name]: minimum = minf(minimum, (poses[3] * point).y)
		if not is_finite(minimum): continue
		var ground := support_y
		if cat.desktop!=null and cat.desktop.state in ["crouch","land_down"]:
			ground+=cat.ground_height_at(points[3])
		var correction := maxf(0.0, ground + .001 - minimum)
		if correction < .00001: continue
		var target := points[3] + Vector3.UP * correction
		var placed: Vector3 = cat.grounded_gait._solve(foot, points, poses, target, poses[3].basis)
		metrics.maximum_correction = maxf(metrics.maximum_correction, correction)
		metrics.maximum_target_error = maxf(metrics.maximum_target_error, placed.distance_to(target))
