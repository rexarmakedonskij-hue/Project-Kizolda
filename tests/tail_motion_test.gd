extends SceneTree
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error(label)
func points(cat) -> Array[Vector3]:
	var sk: Skeleton3D=cat.pose_player.skeleton
	var output: Array[Vector3]=[]
	for bone in cat.tail_motion.bones: output.append(sk.to_global(sk.get_bone_global_pose(bone).origin))
	var last: int=cat.tail_motion.bones.back()
	var rest:=sk.get_bone_global_rest(last)
	var end: Vector3=rest.affine_inverse()*(rest.origin+cat.tail_motion.directions.back()*cat.tail_motion.lengths.back()/sk.global_basis.get_scale().x)
	output.append(sk.to_global(sk.get_bone_global_pose(last)*end))
	return output
func run():
	var cat=load("res://cats/cat.tscn").instantiate()
	root.add_child(cat)
	cat.set_process(false)
	cat.desktop={"elapsed":0.0}
	var sk: Skeleton3D=cat.pose_player.skeleton
	var max_gap:=0.0
	var max_length_error:=0.0
	var max_step:=0.0
	var lowest:=INF
	var untouched:=true
	var previous: Array[Vector3]=[]
	for clip in ["Idle","Walk","Crouch","Jump","Land","SitDown","Sit","Stand","Walk","CrouchDown","Descend","Land","Idle"]:
		cat.pose_player.play(clip,.12)
		var duration: float=cat.animation.current_animation_length
		for frame in int(ceil(minf(duration,1.2)*60)):
			cat.desktop.elapsed=(frame+1)/60.0
			cat.face_time+=1.0/60
			cat.pose_player.advance(1.0/60)
			var before:={}
			for bone in sk.get_bone_count():
				if not sk.get_bone_name(bone).begins_with("tail_"): before[bone]=sk.get_bone_global_pose(bone)
			cat.tail_motion.apply(1.0/60)
			for bone in before: untouched=untouched and sk.get_bone_global_pose(bone).is_equal_approx(before[bone])
			var p:=points(cat)
			for segment in 5:
				max_length_error=maxf(max_length_error,absf(p[segment].distance_to(p[segment+1])-cat.tail_motion.lengths[segment]))
				if not previous.is_empty():
					var movement:=p[segment+1].distance_to(previous[segment+1])
					if movement>.09: print("TAIL_STEP ",clip," frame=",frame," segment=",segment," movement=",movement," root=",p[0]," previous_root=",previous[0])
					max_step=maxf(max_step,movement)
				if clip in ["Idle","Walk","Crouch","Sit","Stand","CrouchDown"]: lowest=minf(lowest,p[segment+1].y-cat.global_position.y)
				if segment==4: continue
				var parent:=sk.get_bone_global_rest(cat.tail_motion.bones[segment])
				var local_end:=parent.affine_inverse()*sk.get_bone_global_rest(cat.tail_motion.bones[segment+1]).origin
				var end:=sk.to_global(sk.get_bone_global_pose(cat.tail_motion.bones[segment])*local_end)
				max_gap=maxf(max_gap,end.distance_to(p[segment+1]))
			previous=p
	cat.pose_player.play("Idle")
	for frame in 120:
		cat.pose_player.advance(1.0/60)
		cat.tail_motion.apply(1.0/60)
	var standing:=points(cat)
	print("TAIL_MEASURES gap=",max_gap," length_error=",max_length_error," step=",max_step," min_y=",lowest)
	check(max_gap<.001 and max_length_error<.001,"Five tail sections stay connected and keep their lengths through all action transitions")
	check(max_step<.09,"Tail tip changes continuously through sitting, standing and jumping poses")
	check(lowest>-.045,"Tail centre line retains ground clearance in supported poses")
	check(untouched,"Tail motion preserves head, torso and all four limb poses")
	check(standing.back().y-standing[0].y>.30 and (standing.back()-standing[4]).dot(cat.global_basis.z)>0,"Standing tail rises with its tip curled toward the body")
	cat.desktop=null
	cat.free()
	print("TAIL_MOTION_CHECKS: %d passed, %d failed"%[checks-failures,failures])
	quit(1 if failures else 0)
