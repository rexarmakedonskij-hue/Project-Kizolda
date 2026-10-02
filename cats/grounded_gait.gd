extends RefCounted
# World-space foot plants over the authored gait. Three joint chains retain
# their lengths; root motion waits for the next normal step when reach is exhausted.
var cat
var skeleton: Skeleton3D
var feet := []
var stride_amount:=1.0
var pads := {}
var metrics := {}

func _init(owner_cat):
	cat=owner_cat
	skeleton=cat.pose_player.skeleton
	pads=preload("res://cats/paw_geometry.gd").get_pads(cat.model,skeleton)
	for spec in [["front","left",0.0],["back","right",.25],["front","right",.5],["back","left",.75]]:
		var indices: Array[int]=[]
		var points: Array[Vector3]=[]
		for segment in range(1,5):
			var bone:=skeleton.find_bone("leg_%s_%s_%s"%[spec[0],spec[1],segment])
			indices.append(bone)
			points.append(skeleton.to_global(skeleton.get_bone_global_rest(bone).origin))
		var lengths: Array[float]=[]
		for segment in 3: lengths.append(points[segment].distance_to(points[segment+1]))
		var flat: Basis = skeleton.global_basis*skeleton.get_bone_global_rest(indices[3]).basis
		feet.append({"name":spec[0]+"_"+spec[1],"bones":indices,"lengths":lengths,"offset":spec[2],
			"ground_offset":points[3].y-cat.global_position.y,"ready":false,"planted":false,
			"phase":0.0,"anchor":Vector3.ZERO,"correction":Vector3.ZERO,"basis":Basis.IDENTITY,
			"flat_relative":cat.global_basis.inverse()*flat,"output":Vector3.ZERO})

func reset():
	stride_amount=1.0
	for foot in feet:
		foot.ready=false
		foot.planted=false

func limit_motion(yaw_delta: float,displacement: Vector3,phase_advance: float) -> float:
	if not cat.pose_player.source.is_empty(): return 1.0
	var supports:=[]
	var phase: float=cat.animation.current_animation_position/cat.animation.current_animation_length
	for foot in feet:
		var next_phase:=fmod(phase+phase_advance+float(foot.offset),1.0)
		if foot.ready and foot.planted and next_phase<.65 and next_phase>=float(foot.phase):
			var hip:=skeleton.to_global(skeleton.get_bone_global_pose(foot.bones[0]).origin)
			supports.append({"hip":hip,"anchor":foot.anchor,"reach":(foot.lengths[0]+foot.lengths[1]+foot.lengths[2])*.985})
	if _motion_fits(supports,yaw_delta,displacement,1.0): return 1.0
	var low:=0.0
	var high:=1.0
	for iteration in 10:
		var middle:=(low+high)*.5
		if _motion_fits(supports,yaw_delta,displacement,middle): low=middle
		else: high=middle
	return low

func _motion_fits(supports: Array,yaw_delta: float,displacement: Vector3,weight: float) -> bool:
	var pivot: Vector3=cat.global_position
	var turn:=Basis(Vector3.UP,yaw_delta*weight)
	for support in supports:
		var hip: Vector3=pivot+turn*(support.hip-pivot)+displacement*weight
		var anchor: Vector3=support.anchor
		if hip.distance_to(anchor)>float(support.reach): return false
	return true

func apply(delta: float,stride := 1.0):
	if cat.uprightness>.02:
		reset()
		return
	stride_amount=lerpf(stride_amount,stride,1-exp(-delta*10))
	metrics={"minimum_pad_clearance":INF,"maximum_floor_correction":0.0,"maximum_target_error":0.0}
	skeleton.force_update_all_bone_transforms()
	var phase: float=cat.animation.current_animation_position/cat.animation.current_animation_length
	for foot in feet:
		var poses: Array[Transform3D]=[]
		var points: Array[Vector3]=[]
		for bone in foot.bones:
			var pose: Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(bone)
			poses.append(pose)
			points.append(pose.origin)
		var raw:=points[3]
		var nominal:=skeleton.to_global(skeleton.get_bone_global_rest(foot.bones[3]).origin)
		var forward: Vector3=cat.global_basis.z.normalized()
		raw-=forward*(raw-nominal).dot(forward)*(1-stride_amount)
		var t:=fmod(phase+float(foot.offset),1.0)
		var stance:=t<.65
		var target:=raw
		var orientation:=poses[3].basis
		var flat: Basis=cat.global_basis*foot.flat_relative
		if not foot.ready:
			foot.anchor=_floor_target(foot,raw,flat)
			foot.anchor.y=_plant_height(foot,raw,flat)
			foot.basis=flat
			foot.correction=Vector3.ZERO
			foot.ready=true
			foot.planted=stance
			foot.phase=t
			foot.output=points[3]
		var touchdown: bool=stance and (not foot.planted or t<float(foot.phase))
		if touchdown:
			# Plant where the advancing paw actually arrived, rather than
			# snapping to an authored target still moving with a turning torso.
			foot.anchor=Vector3(foot.output.x,_plant_height(foot,foot.output,flat),foot.output.z)
			foot.basis=flat
		if not stance and foot.planted:
			foot.correction=foot.anchor-raw
			foot.correction.y=0
		foot.planted=stance
		if stance:
			target=foot.anchor
			orientation=foot.basis
		else:
			var u: float=(t-.65)/.35
			target+=Vector3(foot.correction)*(1-smoothstep(0,.65,u))
			orientation=_blend_basis(foot.basis,orientation,smoothstep(0,.65,u))
			# Toe-off keeps the authored rotation, then the pad returns flat
			# before touchdown. The following plant holds this world orientation.
			orientation=_blend_basis(orientation,flat,smoothstep(.50,1.0,u))
			target=_floor_target(foot,target,orientation)
			target=Vector3(foot.output).move_toward(target,2.0*delta)
			# The speed cap and a changing paw angle must not lower skin through
			# the visible floor. This correction affects height only, never X/Z.
			target=_floor_target(foot,target,orientation)
		foot.phase=t
		if String(foot.name).begins_with("front_"):
			var seeded:=seed_front_chain(foot,points,poses,target)
			points=seeded.points
			poses=seeded.poses
		foot.output=_solve(foot,points,poses,target,orientation)
		metrics.maximum_target_error=maxf(metrics.maximum_target_error,Vector3(foot.output).distance_to(target))
		var minimum := _pad_minimum(foot,orientation)
		metrics.minimum_pad_clearance=minf(metrics.minimum_pad_clearance,Vector3(foot.output).y+minimum-_support_height(foot.output))

func _support_height(position: Vector3) -> float:
	# Desktop routes already encode their supporting level in the root height.
	# Floor decoration only belongs to the ground route beneath the desk.
	var terrain: float=cat.ground_height_at(position) if cat.global_position.y<.5 else 0.0
	return cat.global_position.y+cat.MODEL_GROUND_Y+terrain

func _pad_minimum(foot: Dictionary, orientation: Basis) -> float:
	var minimum:=INF
	for point in pads[foot.name]: minimum=minf(minimum,(orientation*point).y)
	return minimum if is_finite(minimum) else cat.MODEL_GROUND_Y-float(foot.ground_offset)

func _plant_height(foot: Dictionary, position: Vector3, orientation: Basis) -> float:
	return _support_height(position)+.001-_pad_minimum(foot,orientation)

func _floor_target(foot: Dictionary, target: Vector3, orientation: Basis) -> Vector3:
	var correction:=maxf(0.0,_plant_height(foot,target,orientation)-target.y)
	metrics.maximum_floor_correction=maxf(float(metrics.get("maximum_floor_correction",0.0)),correction)
	return target+Vector3.UP*correction

func _blend_basis(from: Basis,to: Basis,weight: float) -> Basis:
	# Imported bone bases carry FBX unit scale; interpolate rotations separately.
	return Basis(from.get_rotation_quaternion().slerp(to.get_rotation_quaternion(),weight)).scaled(from.get_scale().lerp(to.get_scale(),weight))

func seed_front_chain(foot: Dictionary, points: Array[Vector3], poses: Array[Transform3D], target: Vector3) -> Dictionary:
	# An unconstrained three-link solve can fold the carpus below planted
	# fingers. Choose the anatomical elbow/carpus branch before the common
	# fixed-length solve; the planted target and its orientation stay unchanged.
	var root:=points[0]
	var a: float=foot.lengths[0]
	var b: float=foot.lengths[1]
	var c: float=foot.lengths[2]
	var reach:=a+b+c
	if root.distance_to(target)>reach*.999:
		target=root+(target-root).normalized()*reach*.999
	var to_root:=root-target
	var distance:=to_root.length()
	if distance<.000001: return {"points":points,"poses":poses}
	var axis:=to_root/distance
	var backward: Vector3=-cat.global_basis.z.normalized()
	backward.y=0.0
	backward=backward.normalized()
	var desired: Vector3=(Vector3.UP*.85+backward*.526).normalized()
	var proximal_reach: float=(a+b)*.997
	var cosine:=clampf((distance*distance+c*c-proximal_reach*proximal_reach)/(2.0*distance*c),-1.0,1.0)
	var tangent:=desired-axis*desired.dot(axis)
	if tangent.length()<.000001: tangent=backward-axis*backward.dot(axis)
	if tangent.length()<.000001: tangent=cat.global_basis.x-axis*cat.global_basis.x.dot(axis)
	tangent=tangent.normalized()
	var angle:=minf(acos(clampf(desired.dot(axis),-1.0,1.0)),acos(cosine))
	var carpus:=target+(axis*cos(angle)+tangent*sin(angle))*c
	var proximal:=carpus-root
	var d:=proximal.length()
	if d<.000001: return {"points":points,"poses":poses}
	var proximal_axis:=proximal/d
	var elbow_pole:=backward-proximal_axis*backward.dot(proximal_axis)
	if elbow_pole.length()<.000001: elbow_pole=cat.global_basis.x-proximal_axis*cat.global_basis.x.dot(proximal_axis)
	elbow_pole=elbow_pole.normalized()
	var along: float=(a*a-b*b+d*d)/(2.0*d)
	var height:=sqrt(maxf(a*a-along*along,0.0))
	var elbow:=root+proximal_axis*along+elbow_pole*height
	var seeded: Array[Vector3]=[root,elbow,carpus,target]
	var adjusted: Array[Transform3D]=[]
	for joint in 3:
		var before: Vector3=points[joint+1]-points[joint]
		var after: Vector3=seeded[joint+1]-seeded[joint]
		var rotation:=Basis(Quaternion(before.normalized(),after.normalized()))
		adjusted.append(Transform3D(rotation*poses[joint].basis,seeded[joint]))
	adjusted.append(Transform3D(poses[3].basis,target))
	return {"points":seeded,"poses":adjusted}

func _solve(foot: Dictionary,points: Array[Vector3],poses: Array[Transform3D],target: Vector3,orientation: Basis) -> Vector3:
	var root:=points[0]
	var lengths: Array[float]=foot.lengths
	var reach:=lengths[0]+lengths[1]+lengths[2]
	if root.distance_to(target)>reach*.999:
		target=root+(target-root).normalized()*reach*.999
	var previous:=points.duplicate()
	for iteration in 40:
		points[3]=target
		for joint in range(2,-1,-1):
			points[joint]=points[joint+1]+(points[joint]-points[joint+1]).normalized()*lengths[joint]
		points[0]=root
		for joint in 3:
			points[joint+1]=points[joint]+(points[joint+1]-points[joint]).normalized()*lengths[joint]
		if points[3].distance_to(target)<.00002: break
	for joint in 3:
		var original: Vector3=previous[joint+1]-previous[joint]
		var desired:=points[joint+1]-points[joint]
		var rotation:=Basis(Quaternion(original.normalized(),desired.normalized()))
		var placed:=Transform3D(rotation*poses[joint].basis,points[joint])
		skeleton.set_bone_global_pose(foot.bones[joint],skeleton.global_transform.affine_inverse()*placed)
		skeleton.force_update_all_bone_transforms()
	var planted:=Transform3D(orientation,points[3])
	skeleton.set_bone_global_pose(foot.bones[3],skeleton.global_transform.affine_inverse()*planted)
	skeleton.force_update_all_bone_transforms()
	return points[3]
