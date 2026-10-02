extends Node3D
# World-space arm: the shoulder stays at the seated player, the hand follows the cat.
const LENGTH := 2.7
const CONTACT_START := .80
const CONTACT_END := 1.90
const PALM_CONTACT_OFFSET := Vector3(0, .070, .063)
const FIT_FUR_GAP := .0035
const FUR_SURFACE := preload("res://player/petting_surface.gd")
const SURFACE_MODEL := preload("res://assets/models/glb/godot_mvp/cat_reference.fbx")
const SHOULDER := Vector3(.30, 1.24, .02)
const HOME := Vector3(.48, 1.10, .44)
var upper_length := .30
var forearm_length := .34
var model: Node3D
var skeleton: Skeleton3D
var player
var cat
var active := false
var finished := false
var touching := false
var cancelled := false
var retract_age := 0.0
var retract_from := Vector3.ZERO
var wrist := Vector3.ZERO
var contact := Vector3.ZERO
var age := 0.0
var rest := {}
var elbow_world := Vector3.ZERO
var shoulder_world := Vector3.ZERO
var orphan_age := 0.0
var stroke_pose := 0.0
var fur_surface
var finger_pressure := 0.0
var retract_pressure := 0.0
var orphan_pressure := 0.0
var surface_prepare_usec := 0
var surface_geometry_source := ""

func _ready() -> void:
	model = preload("res://assets/models/glb/godot_mvp/player_arm.glb").instantiate()
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	for animation in model.find_children("*", "AnimationPlayer", true, false):
		animation.stop()
	for i in skeleton.get_bone_count(): rest[skeleton.get_bone_name(i)] = skeleton.get_bone_global_rest(i)
	upper_length = (rest["forearm"].origin-rest["upper_arm"].origin).length()
	forearm_length = (rest["palm"].origin-rest["forearm"].origin).length()
	visible = false
	# Prepare the shared contact geometry during scene loading, not on first touch.
	var surface_model=SURFACE_MODEL.instantiate()
	add_child(surface_model)
	var prepared_surface=FUR_SURFACE.new()
	prepared_surface.bind_model(surface_model,surface_model.find_child("Skeleton3D",true,false),self)
	surface_prepare_usec=prepared_surface.last_bind_usec
	surface_geometry_source=prepared_surface.geometry_source
	surface_model.free()

func begin(target, owner_player) -> void:
	cat = target
	player = owner_player
	fur_surface=FUR_SURFACE.new()
	fur_surface.bind(cat,self)
	active = true
	finished = false
	cancelled = false
	touching = false
	age = 0
	orphan_age = 0
	finger_pressure=0.0
	visible = true
	sample(0)

func reset() -> void:
	active = false
	finished = true
	touching = false
	visible = false
	cat = null
	fur_surface=null

func landmark(name: String) -> Vector3:
	var sk: Skeleton3D = cat.pose_player.skeleton
	sk.force_update_all_bone_transforms()
	return sk.to_global(sk.get_bone_global_pose(sk.find_bone(name)).origin)

func _process(delta: float) -> void:
	if not active or is_instance_valid(cat): return
	if orphan_age == 0:
		retract_from = wrist
		orphan_pressure=finger_pressure
	orphan_age += delta
	var home: Vector3 = player.global_position + HOME
	var t := smoothstep(0, .65, orphan_age)
	wrist = retract_from.lerp(home, t)+Vector3.UP*sin(PI*t)*.20
	pose(player.global_position+SHOULDER, wrist)
	if orphan_age >= .65: reset()

func sample(seconds: float) -> void:
	if not active: return
	age = seconds
	var shoulder: Vector3 = player.global_position + SHOULDER
	var home: Vector3 = player.global_position + HOME
	if not is_instance_valid(cat):
		reset()
		return
	var head := landmark("head")
	# The bone origin lies inside the skull. Offset onto its upper fur surface.
	var sk: Skeleton3D = cat.pose_player.skeleton
	var head_basis := (sk.global_basis * sk.get_bone_global_pose(sk.find_bone("head")).basis).orthonormalized()
	var crown: Vector3 = head + head_basis * Vector3(0, .090, .065)*(cat.MODEL_SCALE/2.0)
	var stroke := 0.0
	var lift := 0.0
	if seconds >= CONTACT_START and seconds < CONTACT_END:
		var phase := (seconds-CONTACT_START)/(CONTACT_END-CONTACT_START)*2
		var cycle := fmod(phase, 1.0)
		if cycle < .7: stroke = smoothstep(0, .7, cycle)
		else:
			stroke = 1-smoothstep(.7, 1, cycle)
			lift = sin(PI*(cycle-.7)/.3)*.024
	contact = crown + Vector3(0, -.018, -.085)*stroke + Vector3.UP*lift
	contact += Vector3(0,0,.100)
	stroke_pose=stroke
	var at_contact := contact + PALM_CONTACT_OFFSET
	# Fit the underside of the curved palm to the animated fur surface.
	var prior_wrist:=wrist
	touching=not cancelled and seconds>=CONTACT_START and seconds<CONTACT_END
	pose(shoulder,at_contact)
	fur_surface.update_fur()
	# Sparse palm samples can sit about 1 mm above the complete rendered pad.
	# Reserve that margin while keeping the actual palm close to the fur.
	var correction: float=fur_surface.palm_correction(FIT_FUR_GAP+lift)
	contact.y+=correction
	at_contact.y+=correction
	wrist=prior_wrist
	var gaze: float = (-player.camera.global_basis.z).dot((head-player.camera.global_position).normalized())
	if gaze < .40 and not cancelled:
		cancelled = true
		retract_age = seconds
		retract_from = wrist
		retract_pressure=finger_pressure
	if cancelled:
		var t := clampf((seconds-retract_age)/.65, 0, 1)
		var eased:=smoothstep(0,1,t)
		wrist = retract_from.lerp(home, eased) + Vector3.UP*sin(PI*eased)*.26
		finished = t >= 1
	elif seconds < CONTACT_START:
		var t := smoothstep(0, CONTACT_START, seconds)
		wrist = home.lerp(at_contact, t) + Vector3.UP*sin(PI*t)*.25
	elif seconds < CONTACT_END:
		wrist = at_contact
	else:
		var t := smoothstep(CONTACT_END, LENGTH, seconds)
		wrist = at_contact.lerp(home, t) + Vector3.UP*sin(PI*t)*.27
		finished = seconds >= LENGTH
	touching = not cancelled and seconds >= CONTACT_START and seconds < CONTACT_END
	pose(shoulder, wrist)
	if finished: reset()

func pose(shoulder: Vector3, target_wrist: Vector3) -> void:
	# The reach solver places bones far from the imported mesh origin. Preserve
	# visibility in close side/top views where the static import bounds miss it.
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.extra_cull_margin<2.0: mesh.extra_cull_margin=2.0
	skeleton.reset_bone_poses()
	var a := skeleton.to_local(shoulder)
	var b := skeleton.to_local(target_wrist)
	var delta := b-a
	var distance := clampf(delta.length(), absf(upper_length-forearm_length)+.005, upper_length+forearm_length-.002)
	var forward := delta.normalized()
	# Solve both joints against the same reachable endpoint; never stretch the forearm.
	b = a + forward*distance
	wrist = skeleton.to_global(b)
	# The forearm starts outside the viewer's right edge; no cut sleeve floats
	# beside the cat after removing the visible upper arm.
	# Raise the bent elbow so the sleeve passes above the cheek instead of
	# crossing the eye. The shoulder and both segment lengths stay physical.
	var pole := Vector3(1, 1.2, 1.5)
	var perpendicular := (pole-forward*pole.dot(forward)).normalized()
	var along := (upper_length*upper_length-forearm_length*forearm_length+distance*distance)/(2*distance)
	var bend := sqrt(maxf(0, upper_length*upper_length-along*along))
	var elbow := a+forward*along+perpendicular*bend
	elbow_world = skeleton.to_global(elbow)
	shoulder_world = shoulder
	place_bone("upper_arm", a, elbow-a)
	skeleton.force_update_all_bone_transforms()
	place_bone("forearm", elbow, b-elbow)
	skeleton.force_update_all_bone_transforms()
	if skeleton.find_bone("elbow_helper") >= 0:
		# A centre joint carries the sleeve through a bend without collapsing it.
		var middle := ((elbow-a).normalized()+(b-elbow).normalized()).normalized()
		place_bone("elbow_helper", elbow, middle)
		skeleton.force_update_all_bone_transforms()
	var palm_rest: Transform3D = rest["palm"]
	# Explicit yaw keeps the palm facing down even for the antiparallel direction.
	var turn := Basis(Vector3.RIGHT,-.10-.30*stroke_pose)*Basis(Vector3.UP, PI)
	var palm := Transform3D(turn*palm_rest.basis, b)
	skeleton.set_bone_global_pose(skeleton.find_bone("palm"), palm)
	# Relaxed fingers yield slightly at contact instead of forming a rigid plate.
	var pressure := sin(PI*clampf((age-CONTACT_START)/(CONTACT_END-CONTACT_START),0,1)) if touching else 0.0
	# Withdraw immediately, while the fingers release their last pressure over
	# a short interval instead of snapping from the stroke to a rigid rest pose.
	if orphan_age>0: pressure=orphan_pressure*(1-smoothstep(0,.18,orphan_age))
	elif cancelled: pressure=retract_pressure*(1-smoothstep(0,.18,age-retract_age))
	finger_pressure=pressure
	for digit in 4:
		for joint in 3:
			var curl := (.035+.05*pressure)*(1-joint*.25)*(1+digit*.08)
			var finger := skeleton.find_bone("finger_%d_%d"%[digit,joint])
			var authored := skeleton.get_bone_rest(finger).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(finger,authored*Quaternion(Vector3.RIGHT,curl))
	for joint in 3:
		var thumb := skeleton.find_bone("thumb_%d"%joint)
		var authored := skeleton.get_bone_rest(thumb).basis.get_rotation_quaternion()
		var adduction=Quaternion((palm.basis.inverse()*Vector3.UP).normalized(),-.35) if joint==0 else Quaternion.IDENTITY
		var curl=(.35 if joint==0 else .045)+pressure*.025
		skeleton.set_bone_pose_rotation(thumb,adduction*authored*Quaternion(Vector3.RIGHT,curl))
	skeleton.force_update_all_bone_transforms()

func place_bone(name: String, origin: Vector3, direction: Vector3) -> void:
	var original: Transform3D = rest[name]
	var turn := Basis(Quaternion(Vector3.BACK, direction.normalized()))
	skeleton.set_bone_global_pose(skeleton.find_bone(name), Transform3D(turn*original.basis, origin))
