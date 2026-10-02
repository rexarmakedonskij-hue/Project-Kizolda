extends RefCounted

var animation: AnimationPlayer
var skeleton: Skeleton3D
var source: Array[Transform3D] = []
var elapsed := 0.0
var duration := 0.0

func _init(player: AnimationPlayer, bones: Skeleton3D) -> void:
	animation = player
	skeleton = bones

func play(clip: String, blend := 0.0) -> void:
	# Capture the visible mixed pose, including an interrupted transition.
	source.clear()
	duration = blend
	elapsed = 0.0
	if duration > 0.0:
		for i in skeleton.get_bone_count():
			source.append(skeleton.get_bone_pose(i))
	animation.play(clip, 0.0)
	advance(0.0)

func advance(delta: float, playback_rate := 1.0) -> void:
	# GLTF import can omit tracks that stay at rest. Clear the previous clip's
	# pose before sampling so an omitted track cannot retain (e.g.) Walk's tilt.
	skeleton.reset_bone_poses()
	animation.advance(delta * playback_rate)
	if source.is_empty():
		return
	elapsed = minf(elapsed + delta, duration)
	var weight := elapsed / duration
	weight = weight * weight * (3.0 - 2.0 * weight)
	for i in skeleton.get_bone_count():
		var pose := source[i].interpolate_with(skeleton.get_bone_pose(i), weight)
		skeleton.set_bone_pose_position(i, pose.origin)
		skeleton.set_bone_pose_rotation(i, pose.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, pose.basis.get_scale())
	if elapsed >= duration:
		source.clear()
