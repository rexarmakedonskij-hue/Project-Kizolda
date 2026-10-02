extends RefCounted
# Five connected sections, including the weighted tip bone. State-dependent
# curves keep the tail alive without stretching its mesh or changing the rig.
const UPRIGHT=[1.15,1.40,1.65,2.00,2.45]
const SEATED=[-.70,-.90,-.15,.28,.45]
const WRAP=[.85,1.3,1.8,2.3,2.8]
var cat
var skeleton: Skeleton3D
var bones: Array[int]=[]
var lengths: Array[float]=[]
var directions: Array[Vector3]=[]
var angles:=UPRIGHT.duplicate()
var headings: Array[float]=[0,0,0,0,0]
const ANGULAR_SPEED := 2.4

func _init(owner_cat):
	cat=owner_cat
	skeleton=cat.pose_player.skeleton
	for name in ["tail_1","tail_2","tail_3","tail_4","tail_4_end"]: bones.append(skeleton.find_bone(name))
	for segment in bones.size():
		var origin:=skeleton.get_bone_global_rest(bones[segment]).origin
		var vector: Vector3
		if segment<4:
			vector=skeleton.get_bone_global_rest(bones[segment+1]).origin-origin
		else:
			vector=origin-skeleton.get_bone_global_rest(bones[segment-1]).origin
		directions.append(vector.normalized())
		lengths.append((skeleton.global_basis*vector).length())

func apply(delta: float):
	# Non-looping clips clear current_animation at their final sample. Their
	# assigned pose remains visible until the next state starts a new clip.
	var clip: String=cat.animation.assigned_animation
	var sitting:=0.0
	if clip=="Sit": sitting=1.0
	elif cat.desktop!=null and clip in ["SitDown","Stand"]:
		sitting=smoothstep(0,1,clampf(cat.desktop.elapsed/cat.animation.get_animation(clip).length,0,1))
		if clip=="Stand": sitting=1-sitting
	var airborne:=clip in ["Jump","Descend","Land"]
	var crouching:=clip in ["Crouch","CrouchDown"]
	var weight:=1-exp(-delta*9)
	for segment in bones.size():
		var goal: float=UPRIGHT[segment]
		if airborne: goal=[.15,.45,.70,.90,1.35][segment]
		elif crouching: goal=[.55,.90,1.15,1.60,2.10][segment]
		goal=lerpf(goal,[.0,.10,.25,.5,.9][segment],cat.uprightness)
		goal=lerpf(goal,float(SEATED[segment]),sitting)
		goal+=.025*sin(cat.face_time*1.8-segment*.5)
		angles[segment]=move_toward(float(angles[segment]),lerpf(float(angles[segment]),goal,weight),ANGULAR_SPEED*delta)
		var yaw: float=WRAP[segment]*sitting+.045*sin(cat.face_time*1.3-segment*.6)
		headings[segment]=move_toward(headings[segment],lerpf(headings[segment],yaw,weight),ANGULAR_SPEED*delta)
	skeleton.force_update_all_bone_transforms()
	var origin:=skeleton.to_global(skeleton.get_bone_global_pose(bones[0]).origin)
	var back: Vector3=-cat.global_basis.z.normalized()
	for segment in bones.size():
		var horizontal:=Basis(Vector3.UP,headings[segment])*back
		var direction: Vector3=(horizontal*cos(float(angles[segment]))+Vector3.UP*sin(float(angles[segment]))).normalized()
		var rest: Transform3D=skeleton.global_transform*skeleton.get_bone_global_rest(bones[segment])
		var original: Vector3=(skeleton.global_basis*directions[segment]).normalized()
		var rotation:=Basis(Quaternion(original,direction))
		var placed:=Transform3D(rotation*rest.basis,origin)
		skeleton.set_bone_global_pose(bones[segment],skeleton.global_transform.affine_inverse()*placed)
		skeleton.force_update_all_bone_transforms()
		origin+=direction*lengths[segment]
