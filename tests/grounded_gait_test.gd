extends SceneTree
var failures:=0
func check(ok: bool,label: String):
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error(label)
func _initialize(): call_deferred("run")
func run():
	var cat=load("res://cats/cat.tscn").instantiate()
	root.add_child(cat)
	cat.set_process(false)
	cat.approach(PackedVector3Array([Vector3(0,.06,0),Vector3(0,.06,1.6),Vector3(1.5,.06,1.6),Vector3(1.5,.06,.2)]))
	var previous:={}
	var max_drift:=0.0
	var max_gap:=0.0
	var max_step:=0.0
	var contact_samples:=0
	var turning_samples:=0
	var minimum_support:=4
	var lifted:=false
	var diagnostic_steps:=0
	var diagnostic_support:=0
	var hip_drop:=INF
	for frame in 1200:
		var yaw: float=cat.rotation.y
		cat._process(1.0/60)
		if cat.route.is_empty(): break
		var sk: Skeleton3D=cat.pose_player.skeleton
		sk.force_update_all_bone_transforms()
		var support:=0
		for foot in cat.grounded_gait.feet:
			var point:=sk.to_global(sk.get_bone_global_pose(foot.bones[3]).origin)
			var contact: bool=foot.ready and foot.planted
			if frame>30:
				var rest_hip:=sk.to_global(sk.get_bone_global_rest(foot.bones[0]).origin)
				var visible_hip:=sk.to_global(sk.get_bone_global_pose(foot.bones[0]).origin)
				hip_drop=minf(hip_drop,rest_hip.y-visible_hip.y)
			if contact: support+=1
			if previous.has(foot.name):
				var before: Dictionary=previous[foot.name]
				var step: float=point.distance_to(before.point)
				max_step=maxf(max_step,step)
				if step>.045 and diagnostic_steps<8:
					print("STEP_EVENT frame=",frame," foot=",foot.name," distance=",step," phase=",foot.phase," before=",before.point," after=",point," contact=",contact," ready=",foot.ready)
					diagnostic_steps+=1
				if contact and before.contact and point.distance_to(foot.anchor)<.001 and Vector3(before.anchor).distance_to(foot.anchor)<.001:
					max_drift=maxf(max_drift,step)
					contact_samples+=1
					if absf(angle_difference(yaw,cat.rotation.y))>.01: turning_samples+=1
			previous[foot.name]={"point":point,"contact":contact,"anchor":foot.anchor}
			lifted=lifted or point.y>cat.global_position.y+float(foot.ground_offset)+.025
			for joint in 3:
				var parent: Transform3D=sk.get_bone_global_rest(foot.bones[joint])
				var child: Vector3=sk.get_bone_global_rest(foot.bones[joint+1]).origin
				var tail:=parent.affine_inverse()*child
				var end:=sk.to_global(sk.get_bone_global_pose(foot.bones[joint])*tail)
				var next:=sk.to_global(sk.get_bone_global_pose(foot.bones[joint+1]).origin)
				max_gap=maxf(max_gap,end.distance_to(next))
		if frame>20: minimum_support=mini(minimum_support,support)
		if frame>20 and support<2 and diagnostic_support<5:
			print("SUPPORT_EVENT frame=",frame," count=",support," yaw=",cat.rotation.y," phases=",cat.grounded_gait.feet.map(func(f): return [f.name,f.phase]))
			diagnostic_support+=1
	print("GAIT_MEASURES drift=",max_drift," gap=",max_gap," step=",max_step," support=",minimum_support," samples=",contact_samples," turns=",turning_samples)
	check(contact_samples>300 and turning_samples>20 and max_drift<.0005,"Planted feet stay within half a millimetre through straight motion and turns")
	check(max_gap<.001,"All three joints stay connected without stretching")
	check(max_step<.045 and lifted,"Feet lift and advance without a teleport")
	check(minimum_support>=2,"At least two feet support the walk and turns")
	check(cat.route.is_empty(),"The constrained walk completes both corners and arrives within 20 seconds")
	check(hip_drop>.028,"All four limb roots follow the lowered walking body")
	cat.free()
	print("GROUNDED_GAIT_CHECKS: ",6-failures," passed, ",failures," failed")
	quit(1 if failures else 0)
