extends RefCounted
# Support for the wall controller. The torso may rise only
# as far as four fixed-length chains can retain their authored contact targets.
var cat
var skeleton: Skeleton3D
var max_lift := .04
var lift := 0.0
var feet := []
var flat_relative := {}
var rear_anchors := {}
var metrics := {}
var engaged := false
var support_pose := 0.0
var support_yaw := 0.0
var rear_steps := {}
var fore_brace := {}
var fore_end_relative := {}
var lower_started := false
var paw_pads := {}
var front_wall_supports := 0
var front_floor_supports := 0
var extra_forward := .035
var front_outputs := {}
const BRACE_DURATION := .28
const STEP_DURATION := .24
const STEP_HEIGHT := .035
const STEP_SPEED := 2.0

func _init(owner_cat):
	cat = owner_cat
	skeleton = cat.pose_player.skeleton
	paw_pads=preload("res://cats/paw_geometry.gd").get_pads(cat.model,skeleton)
	for foot in cat.grounded_gait.feet:
		feet.append({"name":foot.name,"bones":foot.bones.duplicate(),
			"lengths":foot.lengths.duplicate(),"ground_offset":foot.ground_offset})
		var rest: Transform3D = skeleton.global_transform * skeleton.get_bone_global_rest(foot.bones[3])
		flat_relative[foot.name] = cat.global_basis.inverse() * rest.basis
		if String(foot.name).begins_with("front_"):
			var endpoint:int = skeleton.find_bone("leg_%s_4_end"%foot.name)
			var end:Transform3D = skeleton.global_transform*skeleton.get_bone_global_rest(endpoint)
			fore_end_relative[foot.name] = rest.basis.inverse()*(end.origin-rest.origin)

func apply(delta: float):
	if cat.desktop != null or not cat.active or cat.is_queued_for_deletion(): return
	# PosePlayer has just sampled or blended the authored bones. Reach tests
	# and support capture must see that pose, not last frame's solved chain.
	skeleton.force_update_all_bone_transforms()
	var upright: float = cat.uprightness
	if not engaged and upright > .00001:
		engaged = true
		support_pose = 0.0
		support_yaw = cat.rotation.y
		for foot in feet:
			if String(foot.name).begins_with("front_"):
				front_outputs[foot.name]=_poses(foot)[3].origin
			if not String(foot.name).begins_with("back_"): continue
			var pose := _poses(foot)[3]
			var anchor := pose.origin
			for source in cat.grounded_gait.feet:
				if source.name == foot.name and source.ready and Vector3(source.anchor).length() > .01:
					anchor = source.anchor
			anchor.y = cat.global_position.y+foot.ground_offset+cat.ground_height_at(anchor)
			rear_steps[foot.name] = {"anchor":anchor,"output":pose.origin,"swing":false,"age":0.0,"start":pose.origin,"steps":0}
	if engaged and fore_brace.is_empty():
		for foot in feet:
			if foot.name != "front_left":continue
			var pose:=_poses(foot)[3]
			fore_brace={"start":pose.origin,"output":pose.origin,"age":0.0,"releasing":false,"release_start":pose.origin,"release_age":0.0}
	if engaged and cat.leaving and not lower_started:
		lower_started=true
		fore_brace.age=BRACE_DURATION
		fore_brace.releasing=false
	if engaged:
		# Keep the bracing body facing the wall until its feet have lowered.
		# The ordinary gait performs the turn after the support handoff.
		if cat.leaving: cat.rotation.y = support_yaw
		upright = _limit_posture(upright)
		cat.uprightness = upright
		cat._update_posture(0.0, upright)
		cat.model.position.z+=extra_forward*smoothstep(0.0,.30,upright)
		support_pose = upright
		fore_brace.age += delta
	var eased := smoothstep(0.0, 1.0, upright)
	var support_amount := smoothstep(0.0, .15, upright)
	metrics = {"uprightness":upright,"lift":0.0,"maximum_length_error":0.0,
		"maximum_front_target_error":0.0,"maximum_rear_ground_error":0.0,
		"contacts":{},"targets":{},"front_skin_gaps":{}}
	if upright < .00001 and (not engaged or (lift < .00001 and not _rear_swinging() and _brace_finished())):
		if engaged: _handoff()
		return
	skeleton.force_update_all_bone_transforms()
	var targets := {}
	var orientations := {}
	_start_rear_step()
	var goal := max_lift * eased
	var allowed := max_lift
	# Keep the trunk at the same support height while the hanging warning
	# arms blend into their first reach. That blend includes a fully extended
	# frame; raising beforehand would require an abrupt torso drop to retain
	# the authored wall targets. The working posture rises gradually afterward.
	if cat.warning or (not cat.leaving and not cat.pose_player.source.is_empty()):
		goal = minf(goal, .0015*eased)
	for foot in feet:
		var poses := _poses(foot)
		var target: Vector3 = poses[3].origin
		var orientation: Basis = poses[3].basis
		if String(foot.name).begins_with("front_") and not cat.warning and not cat.leaving:
			var path := _stroke_path(foot.name)
			var toe_offset: Vector3=orientation*fore_end_relative[foot.name]
			target.y=path.x-toe_offset.y
			target=_wall_target(foot,target,orientation,.002+path.y)
		if foot.name=="front_left" and _use_brace(upright):
			var braced:Dictionary = _brace_target(foot,delta)
			target=braced.target
			orientation=braced.orientation
		elif String(foot.name).begins_with("front_") and front_outputs.has(foot.name):
			if cat.leaving: target=_wall_target(foot,target,orientation,.002,false)
			target=Vector3(front_outputs[foot.name]).move_toward(target,STEP_SPEED*delta)
		if String(foot.name).begins_with("back_"):
			var ground: float = cat.global_position.y + float(foot.ground_offset)+cat.ground_height_at(target)
			target = _rear_target(foot, delta)
			var flat: Basis = cat.global_basis * flat_relative[foot.name]
			orientation = flat
		else:
			# The authored lowering pose can put the rotated palm below the
			# floor. Keep the actual pad above the surface throughout landing.
			target=cat.grounded_gait._floor_target(foot,target,orientation)

		var reach: float = (foot.lengths[0] + foot.lengths[1] + foot.lengths[2]) * .998
		if not cat.leaving or String(foot.name).begins_with("back_"):
			allowed = minf(allowed, _lift_limit(poses[0].origin, target, reach, allowed))
		targets[foot.name] = target
		orientations[foot.name] = orientation
	# Reach has priority over smoothing: contact cannot be preserved by stretching
	# an arm. Idle hanging arms allow less lift than the raised Scratch paws.
	lift = minf(move_toward(lift, minf(goal, allowed), .08 * delta), allowed)
	cat.model.global_position += Vector3.UP * lift
	skeleton.force_update_all_bone_transforms()
	var maximum_length_error := 0.0
	var maximum_front_error := 0.0
	var maximum_ground_error := 0.0
	front_wall_supports=0
	front_floor_supports=0
	for foot in feet:
		var poses := _poses(foot)
		var points: Array[Vector3] = []
		for pose in poses: points.append(pose.origin)
		var target: Vector3 = targets[foot.name]
		var output: Vector3
		if String(foot.name).begins_with("back_"):
			output = _solve_hind(foot, points, poses, target, orientations[foot.name], support_amount)
			rear_steps[foot.name].output = output
		else:
			if cat.leaving and not (foot.name=="front_left" and _use_brace(upright)): target += Vector3.UP*lift
			if target.y<cat.global_position.y+float(foot.ground_offset)+.10:
				var seeded: Dictionary=cat.grounded_gait.seed_front_chain(foot,points,poses,target)
				points=seeded.points
				poses=seeded.poses
			output = cat.grounded_gait._solve(foot, points, poses, target, orientations[foot.name])
			front_outputs[foot.name]=output
		if foot.name=="front_left" and _use_brace(upright):fore_brace.output=output
		var placed := _poses(foot)
		if String(foot.name).begins_with("front_"):
			var gaps := _paw_gaps(foot,placed[3])
			metrics.front_skin_gaps[foot.name]=gaps
			if gaps.wall>=-.002 and gaps.wall<=.005: front_wall_supports+=1
			if gaps.floor>=-.002 and gaps.floor<=.005: front_floor_supports+=1
			if foot.name=="front_left":
				fore_brace["wall_supported"]=gaps.wall>=-.002 and gaps.wall<=.005
				fore_brace["floor_supported"]=gaps.floor>=-.002 and gaps.floor<=.005
		for segment in 3:
			maximum_length_error = maxf(maximum_length_error,
				absf(placed[segment].origin.distance_to(placed[segment+1].origin)-float(foot.lengths[segment])))
		if String(foot.name).begins_with("front_"):
			maximum_front_error = maxf(maximum_front_error, output.distance_to(target))
		elif upright >= .999 and not rear_steps[foot.name].swing:
			var ground: float = cat.global_position.y + float(foot.ground_offset)+cat.ground_height_at(output)
			maximum_ground_error = maxf(maximum_ground_error, absf(output.y-ground))
		metrics.contacts[foot.name] = [output.x,output.y,output.z]
		metrics.targets[foot.name] = [target.x,target.y,target.z]
	metrics.lift = lift
	metrics.lift_limit = allowed
	metrics.rear_steps = {}
	for name in rear_steps:
		var state:Dictionary = rear_steps[name]
		metrics.rear_steps[name] = {"swing":state.swing,"age":state.age,"steps":state.steps,"anchor":[state.anchor.x,state.anchor.y,state.anchor.z]}
	metrics.support_contacts = {}
	var supports := 0
	for foot in feet:
		var supported:=false
		if String(foot.name).begins_with("back_"):
			supported=not rear_steps[foot.name].swing and Vector3(metrics.contacts[foot.name][0],metrics.contacts[foot.name][1],metrics.contacts[foot.name][2]).distance_to(rear_steps[foot.name].anchor)<.001
		else:
			var gaps:Dictionary=metrics.front_skin_gaps[foot.name]
			supported=(gaps.wall>=-.002 and gaps.wall<=.005) or (gaps.floor>=-.002 and gaps.floor<=.005)
		metrics.support_contacts[foot.name]=supported
		if supported:supports+=1
	metrics.supports=supports
	metrics.fore_brace=fore_brace.duplicate(true)
	metrics.maximum_length_error = maximum_length_error
	metrics.maximum_front_target_error = maximum_front_error
	metrics.maximum_rear_ground_error = maximum_ground_error

func _poses(foot: Dictionary) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in foot.bones:
		result.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone))
	return result

func _lift_limit(hip: Vector3, target: Vector3, reach: float, wanted: float) -> float:
	if (hip + Vector3.UP * wanted).distance_to(target) <= reach: return wanted
	var horizontal:=Vector2(hip.x-target.x,hip.z-target.z).length_squared()
	if horizontal>=reach*reach:return 0.0
	# Blending Walk into Idle can raise a hip beyond its plant even with
	# unchanged body pitch. Allow a small body compression in that case;
	# clipping the offset at zero would pull the planted paw off the floor.
	var highest_hip:=target.y+sqrt(reach*reach-horizontal)
	return minf(wanted,highest_hip-hip.y)

func _solve_hind(foot: Dictionary, points: Array[Vector3], poses: Array[Transform3D], target: Vector3, orientation: Basis, amount: float) -> Vector3:
	# A cat supports its body above the heel (hock), with the metatarsus rising
	# from the planted toes. Seed this three-link chain in that anatomical plane;
	# unconstrained FABRIK retains the rolled low heel from the source posture.
	var root := points[0]
	var a: float = foot.lengths[0]
	var b: float = foot.lengths[1]
	var c: float = foot.lengths[2]
	var to_root := root-target
	var distance := to_root.length()
	var axis := to_root.normalized()
	var backward: Vector3 = -cat.global_basis.z.normalized()
	backward.y = 0.0
	backward = backward.normalized()
	var desired := (Vector3.UP*.78 + backward*.625).normalized()
	var proximal_reach := (a+b)*.997
	var cosine := clampf((distance*distance+c*c-proximal_reach*proximal_reach)/(2.0*distance*c), -1.0, 1.0)
	var tangent := desired-axis*desired.dot(axis)
	if tangent.length() < .00001: tangent = Vector3.UP-axis*axis.y
	tangent = tangent.normalized()
	var desired_angle := acos(clampf(desired.dot(axis), -1.0, 1.0))
	var angle := minf(desired_angle, acos(cosine))
	var heel_direction := axis*cos(angle)+tangent*sin(angle)
	var hock := target+heel_direction*c
	var proximal := hock-root
	var d := proximal.length()
	var proximal_axis := proximal.normalized()
	var knee_pole: Vector3 = cat.global_basis.z.normalized()
	knee_pole -= proximal_axis*knee_pole.dot(proximal_axis)
	knee_pole = knee_pole.normalized()
	var along := (a*a-b*b+d*d)/(2.0*d)
	var height := sqrt(maxf(a*a-along*along, 0.0))
	var knee := root+proximal_axis*along+knee_pole*height
	# Fade the pole across the actual rise/lower, then let the common fixed-
	# length solve restore exact segment lengths and the contact target.
	var seeded: Array[Vector3] = [root, points[1].lerp(knee, amount), points[2].lerp(hock, amount), points[3]]
	var original := points.duplicate()
	var adjusted: Array[Transform3D] = []
	for joint in 3:
		var old_direction: Vector3 = original[joint+1]-original[joint]
		var seed_direction: Vector3 = seeded[joint+1]-seeded[joint]
		adjusted.append(Transform3D(Basis(Quaternion(old_direction.normalized(), seed_direction.normalized()))*poses[joint].basis, seeded[joint]))
	adjusted.append(poses[3])
	return cat.grounded_gait._solve(foot, seeded, adjusted, target, orientation)

func _rear_swinging() -> bool:
	for state in rear_steps.values():
		if state.swing: return true
	return false

func _rear_goal(foot: Dictionary) -> Vector3:
	var hip := _poses(foot)[0].origin
	var forward:Vector3 = cat.global_basis.z.normalized()
	forward.y=0.0
	# Supporting toes lie below the hip with a modest toe-forward allowance.
	# The rolled authored endpoint is far ahead of the hip and is unsuitable
	# as a plant: following it produces the original half-metre floor drag.
	var goal := hip+forward*.035
	goal.y=cat.global_position.y+foot.ground_offset+cat.ground_height_at(goal)
	return goal

func _start_rear_step():
	if not engaged or _rear_swinging(): return
	if front_wall_supports+front_floor_supports==0:return
	if not cat.leaving and fore_brace.age<BRACE_DURATION: return
	if cat.warning and not fore_brace.get("wall_supported",false):return
	if cat.leaving and support_pose<.15:
		if front_floor_supports==0:return
	var selected := ""
	var largest := .055
	for foot in feet:
		if not rear_steps.has(foot.name): continue
		var state:Dictionary = rear_steps[foot.name]
		var error:float = Vector3(state.anchor).distance_to(_rear_goal(foot))
		if error>largest:
			largest=error
			selected=foot.name
	if selected.is_empty(): return
	var state:Dictionary = rear_steps[selected]
	state.swing=true
	state.age=0.0
	state.start=state.output

func _rear_target(foot: Dictionary, delta:float) -> Vector3:
	var state:Dictionary = rear_steps[foot.name]
	if not state.swing: return state.anchor
	state.age += delta
	var phase:float = minf(state.age/STEP_DURATION,1.0)
	var goal := _rear_goal(foot)
	var target:Vector3 = Vector3(state.start).lerp(goal,smoothstep(0.0,1.0,phase))
	target.y += STEP_HEIGHT*sin(PI*phase)
	target = Vector3(state.output).move_toward(target,STEP_SPEED*delta)
	if phase>=1.0 and target.distance_to(goal)<.001:
		state.swing=false
		state.steps+=1
		state.anchor=target
	return target

func _posture_transform(value:float) -> Transform3D:
	var eased := smoothstep(0.0,1.0,value)
	var basis := Basis.from_euler(Vector3(0,cat.MODEL_YAW,cat.SCRATCH_ROLL*eased)).scaled(Vector3.ONE*cat.MODEL_SCALE)
	var baseline:Vector3 = Basis.from_euler(Vector3(0,cat.MODEL_YAW,0))*(cat.rear_pivot*cat.MODEL_SCALE)
	var raised:Vector3 = basis*cat.rear_pivot
	return cat.global_transform*Transform3D(basis,Vector3(0,cat.MODEL_GROUND_Y+baseline.y-raised.y,cat.SCRATCH_FORWARD*eased+extra_forward*smoothstep(0.0,.30,value)))

func _posture_fits(value:float) -> bool:
	var future := _posture_transform(value)
	var current_inverse:Transform3D = cat.model.global_transform.affine_inverse()
	for foot in feet:
		if foot.name=="front_left" and cat.leaving and _rear_swinging() and not fore_brace.is_empty():
			# While a rear paw is stepping, the bracing forepaw is the second
			# support. Do not lower the shoulder out of reach of that contact.
			var shoulder:Vector3=future*(current_inverse*_poses(foot)[0].origin)
			var front_reach:float=(foot.lengths[0]+foot.lengths[1]+foot.lengths[2])*.99
			if (shoulder+Vector3.UP*lift).distance_to(fore_brace.output)>front_reach:return false
		if not rear_steps.has(foot.name): continue
		var state:Dictionary = rear_steps[foot.name]
		if state.swing: continue
		var hip:Vector3 = future*(current_inverse*_poses(foot)[0].origin)
		var reach:float = (foot.lengths[0]+foot.lengths[1]+foot.lengths[2])*.975
		if (hip+Vector3.UP*lift).distance_to(state.anchor)>reach:return false
	return true

func _limit_posture(wanted:float) -> float:
	if _posture_fits(wanted):return wanted
	var lo:=0.0
	var hi:=1.0
	for iteration in 12:
		var mid:float = (lo+hi)*.5
		if _posture_fits(lerpf(support_pose,wanted,mid)):lo=mid
		else:hi=mid
	return lerpf(support_pose,wanted,lo)

func _handoff():
	for foot in cat.grounded_gait.feet:
		var rear=rear_steps.has(foot.name)
		var output:Vector3=rear_steps[foot.name].output if rear else front_outputs[foot.name]
		foot.anchor=rear_steps[foot.name].anchor if rear else output
		foot.output=output
		foot.ready=true
		foot.planted=true if rear else (output.y+cat.grounded_gait._pad_minimum(foot,cat.global_basis*flat_relative[foot.name])-cat.ground_height_at(output)<.005)
		foot.basis=cat.global_basis*flat_relative[foot.name]
		foot.phase=fmod(cat.animation.current_animation_position/cat.animation.current_animation_length+float(foot.offset),1.0)
		var poses:=_poses(foot)
		var points:Array[Vector3]=[]
		for pose in poses:points.append(pose.origin)
		if not rear:
			var seeded: Dictionary=cat.grounded_gait.seed_front_chain(foot,points,poses,output)
			points=seeded.points
			poses=seeded.poses
		cat.grounded_gait._solve(foot,points,poses,output,foot.basis)
	engaged=false
	fore_brace.clear()
	lower_started=false
	rear_steps.clear()
	rear_anchors.clear()
	front_outputs.clear()
	lift=0.0

func _use_brace(upright:float) -> bool:
	if fore_brace.is_empty():return false
	if not cat.leaving:return cat.warning
	return upright>.15 or _rear_swinging() or not _brace_finished()

func _brace_finished() -> bool:
	if fore_brace.is_empty():return true
	if not fore_brace.get("releasing",false) or fore_brace.get("release_age",0.0)<.20 or not fore_brace.get("floor_supported",false):return false
	for foot in feet:
		if foot.name!="front_left":continue
		var flat:Basis=cat.global_basis*flat_relative[foot.name]
		var goal:Vector3=_poses(foot)[3].origin
		goal.y=maxf(goal.y,cat.grounded_gait._plant_height(foot,goal,flat))
		return Vector3(fore_brace.output).distance_to(goal)<.004
	return false

func _brace_target(foot:Dictionary,delta:float)->Dictionary:
	var poses:=_poses(foot)
	var hip:Vector3=poses[0].origin
	var flat:Basis=cat.global_basis*flat_relative[foot.name]
	var tilt:float=-PI*.25*smoothstep(.18,.70,support_pose)
	var orientation:=Basis(cat.global_basis.x.normalized(),tilt)*flat
	var toe_offset:Vector3=orientation*fore_end_relative[foot.name]
	var toe:Vector3=cat.to_global(Vector3(cat.to_local(hip).x,0,.505))
	toe.y=hip.y+toe_offset.y
	var target:=toe-toe_offset
	target=_wall_target(foot,target,orientation,.002)
	var reach:float=(foot.lengths[0]+foot.lengths[1]+foot.lengths[2])*.997
	if hip.distance_to(target)>reach:
		target=hip+(target-hip).normalized()*reach
	if not cat.leaving:
		target=Vector3(fore_brace.start).lerp(target,smoothstep(0.0,1.0,minf(fore_brace.age/BRACE_DURATION,1.0)))
	else:
		if support_pose<=.15 and not _rear_swinging() and not fore_brace.releasing:
			fore_brace.releasing=true
			fore_brace.release_start=fore_brace.output
		if fore_brace.releasing:
			fore_brace.release_age += delta
			var t:=smoothstep(0.0,1.0,minf(fore_brace.release_age/.20,1.0))
			var goal:Vector3=poses[3].origin
			goal.y=maxf(goal.y,cat.grounded_gait._plant_height(foot,goal,flat))
			target=Vector3(fore_brace.release_start).lerp(goal,t)
			orientation=cat.grounded_gait._blend_basis(orientation,flat,t)
			target=_wall_target(foot,target,orientation,.002,false)
	target=Vector3(fore_brace.output).move_toward(target,STEP_SPEED*delta)
	return {"target":target,"orientation":orientation}

func _stroke_path(name: String) -> Vector2:
	var phase=fmod(cat.scratch_age/cat.cycle_length+(.5 if name=="front_left" else 0.0),1.0)
	if phase<.14:return Vector2(.62,0)
	if phase<.42:return Vector2(.62-.14*smoothstep(0,1,(phase-.14)/.28),0)
	if phase<.58:return Vector2(.48,.012*smoothstep(0,1,(phase-.42)/.16))
	var u=(phase-.58)/.42
	return Vector2(.48+.14*smoothstep(0,1,u),.04*pow(sin(PI*u),2))

func _wall_target(foot: Dictionary, target: Vector3, orientation: Basis, desired_gap: float, pull := true) -> Vector3:
	var gap := INF
	var candidates: Array=cat.ground_surface.wall_candidates(target) if cat.ground_surface!=null else []
	for local_point in paw_pads[foot.name]:
		var point: Vector3=target+orientation*local_point
		var surface: float=cat.ground_surface.wall_front_at(point,candidates) if cat.ground_surface!=null else cat.to_global(Vector3(0,0,.505)).z
		if is_finite(surface): gap=minf(gap,point.z-surface)
	if is_finite(gap): target.z+=(desired_gap-gap) if pull else maxf(0,desired_gap-gap)
	return target

func _paw_gaps(foot: Dictionary, pose: Transform3D) -> Dictionary:
	var wall := INF
	var floor := INF
	var height: float=cat.ground_height_at(pose.origin)
	var candidates: Array=cat.ground_surface.wall_candidates(pose.origin) if cat.ground_surface!=null else []
	for local_point in paw_pads[foot.name]:
		var point: Vector3=pose*local_point
		floor=minf(floor,point.y-height)
		var surface: float=cat.ground_surface.wall_front_at(point,candidates) if cat.ground_surface!=null else cat.to_global(Vector3(0,0,.505)).z
		if is_finite(surface):wall=minf(wall,point.z-surface)
	return {"wall":wall,"floor":floor}
