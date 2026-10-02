extends SceneTree
var failures := 0
var hand
var rest_meshes := {}
var model_name := "player_arm"
var report_name := "hand-skin-current"
var legacy_rotation_fixture := false
var report := {"samples":[],"passed":false}
func _initialize(): call_deferred("run")
func check(condition: bool, text: String):
	if condition: print("PASS ",text)
	else:
		failures += 1
		push_error(text)
func run():
	if DisplayServer.get_name()=="headless":
		push_error("Hand skin verification requires the graphics renderer; launch a hidden window.")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--model="): model_name=argument.trim_prefix("--model=")
		if argument.begins_with("--report="): report_name=argument.trim_prefix("--report=")
		if argument=="--legacy-finger-rotation": legacy_rotation_fixture=true
	hand=load("res://player/petting_hand.gd").new()
	root.add_child(hand)
	hand.set_process(false)
	hand.visible=true
	if model_name!="player_arm":
		hand.model.free()
		hand.model=load("res://assets/models/glb/godot_mvp/"+model_name+".glb").instantiate()
		hand.add_child(hand.model)
		hand.skeleton=hand.model.find_child("Skeleton3D",true,false)
		for animation in hand.model.find_children("*","AnimationPlayer",true,false): animation.stop()
		hand.rest.clear()
		for index in hand.skeleton.get_bone_count(): hand.rest[hand.skeleton.get_bone_name(index)]=hand.skeleton.get_bone_global_rest(index)
	check(hand.skeleton.get_bone_count()==19,"19 anatomical and reach bones retained")
	check(abs(hand.upper_length-.30)<.0001 and abs(hand.forearm_length-.34)<.0001,"physical arm lengths retained")
	await process_frame
	await RenderingServer.frame_post_draw
	hand.skeleton.reset_bone_poses()
	hand.skeleton.force_update_all_bone_transforms()
	for mesh in hand.model.find_children("*","MeshInstance3D",true,false): rest_meshes[mesh.name]=mesh.bake_mesh_from_current_skeleton_pose()
	var neutral_tip := Vector3.ZERO
	var pressure_tip := Vector3.ZERO
	var samples := []
	for seconds in [0.0,.80,.95,1.35,1.75,1.90,2.25]:
		samples.append({"seconds":seconds,"wrist":Vector3(0,1.575,-1.270),"label":"contact curl"})
	samples.append({"seconds":.25,"wrist":Vector3(.10,1.61,-1.10),"label":"approach"})
	samples.append({"seconds":1.70,"wrist":Vector3(0,1.55,-1.345),"label":"second stroke"})
	samples.append({"seconds":1.15,"wrist":Vector3(0,1.55,-1.345),"stroke":1.0,"label":"palm pitched at stroke end"})
	samples.append({"seconds":2.5,"wrist":Vector3(.48,1.10,-.86),"label":"return"})
	for sample in samples:
		var seconds: float=sample.seconds
		hand.age=seconds
		hand.touching=seconds>=hand.CONTACT_START and seconds<hand.CONTACT_END
		hand.stroke_pose=sample.get("stroke",0.0)
		hand.pose(Vector3(.30,1.24,-1.28),sample.wrist)
		if legacy_rotation_fixture:
			# Negative control: the former animation discarded imported bone frames.
			for index in hand.skeleton.get_bone_count():
				var name=hand.skeleton.get_bone_name(index)
				if name.begins_with("finger_") or name.begins_with("thumb_"):
					hand.skeleton.set_bone_pose_rotation(index,Quaternion(Vector3.RIGHT,.06))
			hand.skeleton.force_update_all_bone_transforms()
		await process_frame
		await RenderingServer.frame_post_draw
		var measurements=measure()
		measurements["seconds"]=seconds
		measurements["label"]=sample.label
		measurements["target_wrist"]=sample.wrist
		report.samples.append(measurements)
		check(measurements.max_edge_stretch<=2.0,"no skin spikes at %.2f s (max edge %.3fx)"%[seconds,measurements.max_edge_stretch])
		check(measurements.nonfinite_vertices==0,"finite deformed surface at %.2f s"%seconds)
		if seconds==0.0: neutral_tip=measurements.tip_centroid
		if seconds==1.35: pressure_tip=measurements.tip_centroid
	var yielding=neutral_tip.distance_to(pressure_tip)
	check(yielding>.0015 and yielding<.03,"fingertip yields physically under pressure (%.3f mm)"%(yielding*1000))
	report["fingertip_yield_m"]=yielding
	report["model"]=model_name
	report["legacy_rotation_fixture"]=legacy_rotation_fixture
	report["sources"]={"model_sha256":FileAccess.get_sha256("res://assets/models/glb/godot_mvp/"+model_name+".glb"),"controller_sha256":FileAccess.get_sha256("res://player/petting_hand.gd")}
	report["passed"]=failures==0
	report["failures"]=failures
	var file=FileAccess.open("res://tests/results/"+report_name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("HAND_SKIN_TEST ",JSON.stringify({"model":model_name,"passed":failures==0,"fingertip_yield_m":yielding}))
	hand.free()
	quit(0 if failures==0 else 1)
func measure() -> Dictionary:
	return load("res://tests/hand_skin_measure.gd").measure(hand,rest_meshes)
