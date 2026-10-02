extends Node3D
signal scratched_wall(cat, amount: float)
signal was_chased(cat)
signal scratching_started
signal scratch_stroke(from: Vector3, to: Vector3, duration: float)
signal event_changed(cat, kind: String, state: String)
signal pet_contact(cat)
const RULES = preload("res://systems/shift_rules.gd")
const CAT_MODEL = preload("res://assets/models/glb/godot_mvp/cat_reference.fbx")
@export var model_scene: PackedScene = CAT_MODEL
const MODEL_SCALE := 1.65
const MODEL_YAW := -PI / 2.0
const MODEL_GROUND_Y := -0.06
const SCRATCH_ROLL := 1.05
const SCRATCH_FORWARD := 0.39
const SCRATCH_TOP := 0.62
const SCRATCH_BOTTOM := 0.48
const POSTURE_BLEND_DURATION := 0.45
static var reference_material: StandardMaterial3D
var warning := true
@onready var scratch_timer: Timer = $ScratchTimer
var model: Node3D
var active := true
var age := 0.0
var animation: AnimationPlayer
var pose_player
var scratch_age := 0.0
var cycle_length := 4.0 / 3.0
var route := PackedVector3Array()
var home := Vector3.ZERO
var leaving := false
var pose_transition := 0.0
var uprightness := 0.0
const WALK_SPEED := .65
const GAIT_SPEED := (.28*MODEL_SCALE/2.0) / (.65 * 1.2)
const ACCELERATION := 1.6
const TURN_SPEED := 2.4
var move_speed := 0.0
var rear_pivot := Vector3.ZERO
var desktop
var sit_amount := 0.0
var pet_hand
var pet_player
var face_time := 0.0
var face_mesh: MeshInstance3D
var face_shapes := {}
var gaze := 0.0
var grounded_gait
var tail_motion
var ground_surface
var wall_support

func ground_height_at(point: Vector3) -> float:
	return ground_surface.height_under_paw(point) if ground_surface!=null else 0.0

func _ready() -> void:
	model = model_scene.instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	model.rotation.y = MODEL_YAW
	model.position.y = MODEL_GROUND_Y
	add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		_apply_reference_coloring(mesh as MeshInstance3D)
		if mesh.mesh.get_blend_shape_count() > 0:
			face_mesh = mesh
			for index in mesh.mesh.get_blend_shape_count():
				face_shapes[String(mesh.mesh.get_blend_shape_name(index))] = index
	add_to_group("pawductivity_cats")
	animation = model.find_child("AnimationPlayer", true, false)
	if animation:
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var library := animation.get_animation_library("")
		var source: Animation = animation.get_animation(animation.get_animation_list()[0])
		if not library.has_animation("Walk"):
			library.add_animation("Walk", source.duplicate())
		if not library.has_animation("Scratch"):
			library.add_animation("Scratch", _make_scratch_animation())
		library.add_animation("Idle", _make_idle_animation())
		for name in ["Sit", "SitDown", "Stand", "Crouch", "CrouchDown", "Jump", "Land", "Descend", "Touch"]:
			library.add_animation(name, _make_desktop_animation(name))
		var clip := animation.get_animation("Scratch")
		clip.loop_mode = Animation.LOOP_LINEAR
		cycle_length = clip.length
		animation.get_animation("Walk").loop_mode = Animation.LOOP_LINEAR
		pose_player = preload("res://cats/pose_player.gd").new(animation, model.find_child("Skeleton3D", true, false))
		var skeleton: Skeleton3D = pose_player.skeleton
		skeleton.reset_bone_poses()
		for side in ["left", "right"]:
			var bone := skeleton.find_bone("leg_back_%s_4" % side)
			rear_pivot += model.to_local(skeleton.to_global(skeleton.get_bone_global_rest(bone).origin)) * .5
		grounded_gait=preload("res://cats/grounded_gait.gd").new(self)
		tail_motion=preload("res://cats/tail_motion.gd").new(self)
		wall_support=preload("res://cats/wall_support.gd").new(self)
		tail_motion.apply(0)
	scratch_timer.one_shot = false
	scratch_timer.timeout.connect(_scratch)

func _apply_reference_coloring(mesh_instance: MeshInstance3D) -> void:
	if reference_material == null:
		reference_material = StandardMaterial3D.new()
		reference_material.vertex_color_use_as_albedo = true
		reference_material.roughness = .82
	mesh_instance.material_override = reference_material

func _make_scratch_animation() -> Animation:
	return _make_baked_animation(preload("res://cats/scratch_poses.gd").DATA, 1.35)

func _make_idle_animation() -> Animation:
	var clip := Animation.new()
	clip.length = 3.6
	clip.loop_mode = Animation.LOOP_LINEAR
	_add_scratch_cycle(clip, "body_2", Vector3.RIGHT, 0.0, .012, 0.0)
	_add_scratch_cycle(clip, "head", Vector3.UP, 0.0, .045, .15)
	for segment in 4:
		_add_scratch_cycle(clip, "tail_%d" % (segment + 1), Vector3.UP, 0.0, .07, segment * .12)
	_complete_rest_tracks(clip)
	return clip

func _complete_rest_tracks(clip: Animation, sample_count := 13) -> void:
	# AnimationPlayer may restore cached values for tracks omitted by a clip.
	# Explicit rest keys prevent a lifted walking hind paw leaking into Scratch.
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
	for bone in skeleton.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:%s" % skeleton.get_bone_name(bone))
		var rest := skeleton.get_bone_rest(bone)
		for kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			if clip.find_track(path, kind) >= 0: continue
			var track := clip.add_track(kind)
			clip.track_set_path(track, path)
			clip.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
			var value = rest.origin if kind == Animation.TYPE_POSITION_3D else (rest.basis.get_rotation_quaternion() if kind == Animation.TYPE_ROTATION_3D else rest.basis.get_scale())
			for sample in sample_count: clip.track_insert_key(track, clip.length * sample / (sample_count - 1.0), value)

func _make_desktop_animation(kind: String) -> Animation:
	const POSES = preload("res://cats/desktop_poses.gd")
	var clip := _make_baked_animation(POSES.DATA[kind], POSES.DURATIONS[kind])
	clip.loop_mode = Animation.LOOP_LINEAR if kind in ["Sit", "Touch"] else Animation.LOOP_NONE
	return clip

func _make_baked_animation(samples: Array, length: float) -> Animation:
	var clip := Animation.new()
	clip.length = length
	clip.loop_mode = Animation.LOOP_LINEAR
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		var rest := skeleton.get_bone_rest(bone)
		var path := NodePath("Armature/Skeleton3D:%s" % bone_name)
		var position_track := clip.add_track(Animation.TYPE_POSITION_3D)
		var rotation_track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(position_track, path)
		clip.track_set_path(rotation_track, path)
		clip.track_set_interpolation_type(position_track, Animation.INTERPOLATION_CUBIC)
		clip.track_set_interpolation_type(rotation_track, Animation.INTERPOLATION_CUBIC)
		for sample in samples.size():
			var data: Array = samples[sample][bone_name]
			var p: Array = data[0]
			var q: Array = data[1]
			# FBX skeleton coordinates are centimetres; mesh/armature scale
			# restores metres. Apply baked deltas in the original bone frame.
			var pose := rest * Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2]) * .01)
			var time := clip.length * sample / (samples.size() - 1.0)
			clip.track_insert_key(position_track, time, pose.origin)
			clip.track_insert_key(rotation_track, time, pose.basis.get_rotation_quaternion())
	_complete_rest_tracks(clip, samples.size())
	return clip

func update_sitting(_delta: float, _sitting: bool) -> void:
	# The seated body and planted paws are baked together in the rig.
	model.rotation.z = 0.0
	model.position.y = MODEL_GROUND_Y

func _add_scratch_cycle(
	clip: Animation,
	bone_name: String,
	axis: Vector3,
	center: float,
	amplitude: float,
	phase_offset: float,
	harmonic := 0.0,
) -> void:
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var bone := skeleton.find_bone(bone_name)
	var authored := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, NodePath("Armature/Skeleton3D:%s" % bone_name))
	clip.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for sample in 13:
		var time := clip.length * sample / 12.0
		var phase := fmod(float(sample) / 12.0 + phase_offset, 1.0)
		var angle := center + amplitude * cos(TAU * phase) + harmonic * sin(TAU * phase * 2.0)
		clip.track_insert_key(track, time, authored * Quaternion(axis, angle))

func _update_posture(delta: float, target: float) -> void:
	uprightness = move_toward(uprightness, target, delta / POSTURE_BLEND_DURATION)
	var eased := smoothstep(0.0, 1.0, uprightness)
	model.rotation.z = lerpf(0.0, SCRATCH_ROLL, eased)
	model.position.z = lerpf(0.0, SCRATCH_FORWARD, eased)
	var baseline := Basis.from_euler(Vector3(0, MODEL_YAW, 0)) * (rear_pivot * MODEL_SCALE)
	var raised := model.basis * rear_pivot
	model.position.y = MODEL_GROUND_Y + baseline.y - raised.y

func _process(delta: float) -> void:
	if not active: return
	# Bounded integration keeps acceleration, turns and animation independent
	# of render rate, including interrupted posture changes.
	var remaining := delta
	while remaining > 0.000001 and active and not is_queued_for_deletion():
		var step := minf(remaining, 1.0 / 60.0)
		var was_moving := not route.is_empty()
		_tick(step)
		if wall_support!=null:wall_support.apply(step)
		remaining -= step
		if was_moving and route.is_empty(): break
	_update_face(delta)
	tail_motion.apply(delta)

func _update_face(delta: float) -> void:
	if not is_instance_valid(face_mesh): return
	var phase := fmod(face_time, 4.8)
	var blink := sin(PI * clampf(phase/.18, 0, 1)) if phase<.18 else 0.0
	if desktop != null and desktop.state == "petting" and pet_hand != null and pet_hand.touching:
		blink = maxf(blink, .45*sin(PI*clampf((desktop.elapsed-pet_hand.CONTACT_START)/(pet_hand.CONTACT_END-pet_hand.CONTACT_START),0,1)))
	var desired_gaze := 0.0
	if desktop != null and desktop.kind == "keyboard" and desktop.state in ["settle", "seated", "pet_wait", "petting"]:
		var viewer := get_viewport().get_camera_3d()
		if viewer != null:
			var sk: Skeleton3D = pose_player.skeleton
			var head_position := sk.to_global(sk.get_bone_global_pose(sk.find_bone("head")).origin)
			# FBX keeps Blender's facial axes (+X forward, +Y across the face)
			# under its import transform. Remove that transform's centimetre scale.
			var direction: Vector3 = face_mesh.global_basis.orthonormalized().inverse() * (viewer.global_position-head_position)
			desired_gaze = clampf(direction.y/maxf(absf(direction.x), .1), -1, 1)
		if desktop.state == "seated":
			# Brief glances at the keyboard interrupt the fixed stare between
			# blinks. Affection keeps attention on the player instead.
			var glance := fmod(desktop.elapsed, 5.0)
			desired_gaze += -.30 if glance>1.2 and glance<1.7 else (.25 if glance>3.2 and glance<3.7 else 0.0)
		desired_gaze = clampf(desired_gaze,-1,1)
	gaze = lerpf(gaze, desired_gaze, 1-exp(-delta*6))
	for name in face_shapes:
		var value := 0.0
		match name:
			"Blink": value=blink
			"HideIris": value=smoothstep(.70,.95,blink)
			"LookLeft": value=maxf(gaze,0)
			"LookRight": value=maxf(-gaze,0)
		face_mesh.set_blend_shape_value(face_shapes[name], value)

func _tick(delta: float) -> void:
	face_time += delta
	if desktop != null and desktop.tick(delta): return
	if not route.is_empty():
		_update_posture(delta, 0.0)
		if wall_support!=null and wall_support.engaged and leaving:
			move_speed=0.0
			pose_player.advance(delta)
			return
		var to_target := route[0] - position
		var desired_yaw := atan2(to_target.x, to_target.z)
		var previous_yaw := rotation.y
		rotation.y = rotate_toward(rotation.y, desired_yaw, TURN_SPEED * delta)
		var turn_rate := absf(angle_difference(previous_yaw,rotation.y))/delta
		var alignment := maxf(0.0, cos(angle_difference(rotation.y, desired_yaw)))
		var braking := minf(1.0, to_target.length() / .22)
		var target_speed := WALK_SPEED * alignment * braking
		# Lower onto all four paws before walking away from the wall.
		target_speed *= 1.0 - smoothstep(0.0, .75, uprightness)
		move_speed = move_toward(move_speed, target_speed, ACCELERATION * delta)
		var distance_left := move_speed * delta
		var gait_speed := maxf(move_speed,turn_rate*.32)
		var wanted_yaw := rotation.y
		rotation.y=previous_yaw
		var offset := to_target.normalized()*distance_left
		var gait_advance := delta*gait_speed/GAIT_SPEED/animation.current_animation_length
		var parent_basis: Basis=get_parent().global_basis if get_parent() is Node3D else Basis.IDENTITY
		var allowed: float=grounded_gait.limit_motion(angle_difference(previous_yaw,wanted_yaw),parent_basis*offset,gait_advance)
		rotation.y=previous_yaw+angle_difference(previous_yaw,wanted_yaw)*allowed
		distance_left*=allowed
		pose_player.advance(delta, gait_speed / GAIT_SPEED)
		while not route.is_empty() and distance_left > 0:
			var destination := route[0]
			var direction := destination - position
			var distance := direction.length()
			if distance <= maxf(distance_left, .002):
				position = destination
				distance_left -= distance
				route.remove_at(0)
			else:
				position += direction.normalized() * distance_left
				distance_left = 0
		grounded_gait.apply(delta,move_speed*allowed/maxf(gait_speed,.001))
		if route.is_empty():
			move_speed = 0.0
			if desktop != null: desktop.arrived()
			elif leaving: queue_free()
			else:
				pose_player.play("Idle", POSTURE_BLEND_DURATION)
				pose_transition = POSTURE_BLEND_DURATION
				start_scratching()
			grounded_gait.reset()
		return
	rotation.y = rotate_toward(rotation.y, PI, TURN_SPEED * delta)
	if warning:
		_update_posture(delta, 1.0)
		pose_player.advance(delta)
		if pose_transition > 0:
			pose_transition -= delta
		age += delta
		return
	_update_posture(delta, 1.0)
	var previous := scratch_age / cycle_length
	scratch_age += delta
	if animation: pose_player.advance(delta)
	var current := scratch_age / cycle_length
	for stroke in [Vector2(-1, .4), Vector2(1, .9)]:
		if floorf(current - stroke.y) > floorf(previous - stroke.y):
			var x: float = stroke.x * .055
			scratch_stroke.emit(
				to_global(Vector3(x, SCRATCH_TOP-position.y, .515)),
				to_global(Vector3(x, SCRATCH_BOTTOM-position.y, .515)),
				cycle_length * .2,
			)

func turn_in_place(target_yaw: float, delta: float) -> bool:
	var difference := angle_difference(rotation.y, target_yaw)
	if absf(difference) < .02: return true
	var turn := clampf(difference, -TURN_SPEED*delta, TURN_SPEED*delta)
	var gait_speed := absf(turn)/maxf(delta,.001)*.32
	var phase_advance := delta*gait_speed/GAIT_SPEED/animation.current_animation_length
	var allowed: float = grounded_gait.limit_motion(turn, Vector3.ZERO, phase_advance)
	rotation.y += turn*allowed
	pose_player.advance(delta,gait_speed/GAIT_SPEED)
	grounded_gait.apply(delta,0.0)
	return absf(angle_difference(rotation.y,target_yaw)) < .02

func _scratch() -> void:
	if not active: return
	if warning:
		warning = false
		pose_player.play("Scratch", .25)
		scratch_age = 0.0
		scratching_started.emit()
		scratch_timer.start(RULES.SCRATCH_INTERVAL)
	else:
		scratched_wall.emit(self, RULES.SCRATCH_DAMAGE)

func start_scratching() -> void:
	warning = true
	scratch_timer.start(RULES.WARNING_DURATION)

func approach(points: PackedVector3Array) -> void:
	if points.is_empty(): return
	grounded_gait.reset()
	home = points[0]
	position = home
	route = points.slice(1)
	warning = true
	scratch_timer.stop()
	uprightness = 0.0
	move_speed = 0.0
	if not route.is_empty():
		var direction := route[0] - position
		rotation.y = atan2(direction.x, direction.z)
	_update_posture(0.0, 0.0)
	pose_player.play("Walk", .25)
	pose_player.advance(0)

func try_to_chase(player) -> bool:
	if not active or leaving or not player.can_see(self): return false
	if desktop != null and desktop.kind == "keyboard" and desktop.state in ["align", "settle", "seated", "pet_wait", "petting"]: return false
	scratch_timer.stop()
	leaving = true
	if desktop != null:
		desktop.chase()
		was_chased.emit(self)
		return true
	route = PackedVector3Array([Vector3(position.x, .06, .5), home])
	pose_player.play("Walk", .3)
	was_chased.emit(self)
	return true

func try_to_pet(player) -> bool:
	if not active or leaving or not player.can_see(self): return false
	if desktop == null or desktop.kind != "keyboard" or desktop.state not in ["align", "settle", "seated"]: return false
	pet_hand = player.pet_hand
	pet_player = player
	desktop.pet()
	return true

func stop() -> void:
	active = false
	if pet_hand != null: pet_hand.reset()
	scratch_timer.stop()

func approach_desktop(kind: String) -> void:
	desktop = preload("res://cats/desktop_behavior.gd").new(self, kind)
	approach(PackedVector3Array([Vector3(2.6, .06, 1.5), Vector3(2.6, .06, -.65), desktop.floor_point]))
