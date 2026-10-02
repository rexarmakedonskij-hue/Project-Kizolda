extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	else: print("PASS: ", label)

func paw(skeleton: Skeleton3D, name: String) -> Vector3:
	skeleton.force_update_all_bone_transforms()
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin)

func run() -> void:
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat()
	game.active_cat._process(100)
	var cat = game.active_cat
	var start_roll: float = cat.model.rotation.z
	cat._process(cat.POSTURE_BLEND_DURATION * .5)
	var middle_roll: float = cat.model.rotation.z
	cat._process(4.0)
	check(
		start_roll < middle_roll and middle_roll < cat.model.rotation.z
		and is_equal_approx(cat.model.rotation.z, cat.SCRATCH_ROLL),
		"Cat rises into the scratch posture gradually",
	)
	cat.set_process(false)
	var skeleton: Skeleton3D = cat.model.find_child("Skeleton3D", true, false)
	check(skeleton != null and skeleton.get_bone_count() == 34, "Low-poly FBX contains the cat rig")
	check(cat.animation != null and cat.animation.has_animation("Scratch"), "Scratch adapter is installed")
	var active_mesh: MeshInstance3D = cat.model.find_child("mesh_cat", true, false)
	var source_model := (load("res://assets/third_party/daily_lowpoly_cat/cat_rigged.fbx") as PackedScene).instantiate()
	var source_mesh: MeshInstance3D = source_model.find_child("mesh_cat", true, false)
	check(active_mesh.mesh != source_mesh.mesh and active_mesh.skin != null, "Refined geometry retains skinning independently of source")
	check(active_mesh.material_override is StandardMaterial3D and active_mesh.material_override.vertex_color_use_as_albedo, "Reference colors are imported with the refined mesh")
	source_model.free()
	if not skeleton or not cat.animation:
		quit(1)
		return
	var scratch_clip: Animation = cat.animation.get_animation("Scratch")
	var smooth_tracks := true
	for track in scratch_clip.get_track_count():
		smooth_tracks = smooth_tracks and scratch_clip.track_get_interpolation_type(track) == Animation.INTERPOLATION_CUBIC
		smooth_tracks = smooth_tracks and scratch_clip.track_get_key_count(track) == 25
	check(smooth_tracks, "Scratch tracks use dense cubic motion curves")
	cat._scratch()
	cat.scratch_timer.stop()
	var length: float = cat.cycle_length
	# Sample the production controller after its transition, including the
	# contact solver. Seeking only the imported clip bypasses that controller.
	cat._process(length*2)
	var high := paw(skeleton,"leg_front_right_4_end")
	var low := high
	var other := high
	var first:=high
	var reaching_forward := true
	var hind_planted := true
	var working_contact := true
	var hind_start := {}
	for sample in 121:
		if sample>0:cat._process(length/120.0)
		if sample==60:
			low=paw(skeleton,"leg_front_right_4_end")
			other=paw(skeleton,"leg_front_left_4_end")
		var contacts:=0
		for foot in cat.wall_support.feet:
			if not String(foot.name).begins_with("front_"):continue
			var gap:Dictionary=cat.wall_support._paw_gaps(foot,cat.wall_support._poses(foot)[3])
			if gap.wall>=-.003 and gap.wall<=.005:contacts+=1
		working_contact=working_contact and contacts>=1
		for side in ["left", "right"]:
			var toe := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("leg_front_%s_4_end" % side)).origin)
			var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("leg_front_%s_1" % side)).origin)
			reaching_forward = reaching_forward and toe.z < shoulder.z - .17 and toe.z > -4.93 and toe.z < -4.84
			var hind := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("leg_back_%s_4_end" % side)).origin)
			if sample == 0: hind_start[side] = hind
			hind_planted = hind_planted and hind.distance_to(hind_start[side]) < .008 and hind.y >= 0.0 and hind.y < .05
	check(high.y-low.y>.07,"Paw travels downward through the scratch")
	check(working_contact,"A working paw stays against the actual wallpaper throughout the cycle")
	check(other.y-low.y>.07,"Paws move out of phase")
	check(reaching_forward, "Both front paws stay forward at the wallpaper throughout the cycle")
	check(hind_planted, "Rear paws stay level and planted while the shoulders move")
	var last := paw(skeleton,"leg_front_right_4_end")
	check(first.distance_to(last) < .005, "Scratch loop seam is continuous")
	game.room.stop_scratches()
	for mark in game.room.marks.get_children():mark.free()
	cat.scratch_age=0.0
	cat.pose_player.play("Scratch",0.0)
	cat._process(length * .401)
	check(game.room.marks.get_child_count() == 3 and game.wall_damage == 0, "Stroke reveals marks without extra damage")
	var mark: Node3D = game.room.marks.get_child(0)
	var middle_mark: Node3D = game.room.marks.get_child(1)
	var active_paw := paw(skeleton,"leg_front_right_4_end")
	check(absf(middle_mark.position.x - active_paw.x) < .02, "Claw marks are centered at the active paw")
	var initial := mark.scale.y
	for tween in game.room.scratch_tweens:
		tween.pause()
		tween.custom_step(.08)
	check(mark.scale.y > initial and mark.scale.y < 1, "Claw marks grow over time")
	for tween in game.room.scratch_tweens: tween.play()
	game.toggle_pause()
	var frozen := mark.scale.y
	var pose: float = cat.animation.current_animation_position
	cat.set_process(true)
	await create_timer(.06, true).timeout
	check(mark.scale.y == frozen and cat.animation.current_animation_position == pose, "Pause freezes animation and marks")
	game.toggle_pause()
	cat.set_process(false)
	game.player.camera.look_at(cat.global_position + Vector3.UP * .75)
	check(cat.try_to_chase(game.player), "Player interrupts scratching")
	check(game.room.scratch_tweens.is_empty(), "Shoo cancels unfinished mark effects")
	# A second visit cannot overlap the interrupted cat walking home. Advance
	# that actual route, then let queue_free finish before preparing a new cat.
	for depart_step in 6000:
		if cat.is_queued_for_deletion(): break
		cat._process(1.0 / 60)
	if not cat.is_queued_for_deletion():
		push_error("Interrupted cat did not complete departure within 100 game seconds")
		quit(1)
		return
	await process_frame
	if is_instance_valid(cat):
		push_error("Departing cat was not removed before the next scratch visit")
		quit(1)
		return
	game._spawn_cat()
	game.active_cat._process(100)
	cat = game.active_cat
	cat._scratch()
	game._end_shift(false)
	pose = cat.animation.current_animation_position
	await create_timer(.06).timeout
	check(cat.animation.current_animation_position == pose, "Result stops skeletal animation")
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("SCRATCH_CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
