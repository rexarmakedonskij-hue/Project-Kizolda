extends SceneTree
var failures := 0
var report_name := "hand-scalp-current"
var tuning := {"crown_y":.135,"palm_y":.035,"front":0.0,"pitch":0.0,"pitch_stroke":0.0,"thumb_adduction":0.0}
var trial_contact := false
var model_name := "player_arm"
var full_contact := false
var surface_fit := false
func _initialize(): call_deferred("run")
func check(condition: bool, text: String):
	if condition: print("PASS ",text)
	else:
		failures+=1
		push_error(text)
func run():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_name=argument.trim_prefix("--report=")
		if argument.begins_with("--model="): model_name=argument.trim_prefix("--model=")
		if argument=="--full-contact": full_contact=true
		if argument=="--surface-fit":
			surface_fit=true
			trial_contact=true
		for key in tuning:
			if argument.begins_with("--"+key+"="):
				tuning[key]=float(argument.get_slice("=",1))
				trial_contact=true
	var game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if trial_contact:
		var source=FileAccess.get_file_as_string("res://player/petting_hand.gd")
		source=source.replace("Vector3(0, .135, .065)","Vector3(0, %.6f, .065)"%tuning.crown_y)
		source=source.replace("Vector3(0, .035, .063)","Vector3(0, %.6f, .063)"%tuning.palm_y)
		source=source.replace("var at_contact := contact + PALM_CONTACT_OFFSET","contact += Vector3(0,0,%.6f)\n\tvar at_contact := contact + PALM_CONTACT_OFFSET"%tuning.front)
		source=source.replace("var orphan_age := 0.0","var orphan_age := 0.0\nvar stroke_pose := 0.0")
		source=source.replace("var at_contact := contact + PALM_CONTACT_OFFSET","stroke_pose=stroke\n\tvar at_contact := contact + PALM_CONTACT_OFFSET")
		source=source.replace("var turn := Basis(Vector3.UP, PI)","var turn := Basis(Vector3.RIGHT,%.6f+%.6f*stroke_pose)*Basis(Vector3.UP, PI)"%[tuning.pitch,tuning.pitch_stroke])
		source=source.replace("skeleton.set_bone_pose_rotation(thumb,authored*Quaternion(Vector3.RIGHT,.045+pressure*.025))","var adduction=Quaternion((palm.basis.inverse()*Vector3.UP).normalized(),%.6f) if joint==0 else Quaternion.IDENTITY\n\t\tskeleton.set_bone_pose_rotation(thumb,adduction*authored*Quaternion(Vector3.RIGHT,.045+pressure*.025))"%tuning.thumb_adduction)
		if surface_fit:
			source=source.replace("var orphan_age := 0.0","var orphan_age := 0.0\nvar fur_surface")
			source=source.replace("active = true","fur_surface=load(\"res://player/petting_surface.gd\").new()\n\tfur_surface.bind(cat,self)\n\tactive = true")
			source=source.replace("var gaze: float", "var prior_wrist:=wrist\n\ttouching=not cancelled and seconds>=CONTACT_START and seconds<CONTACT_END\n\tpose(shoulder,at_contact)\n\tfur_surface.update_fur()\n\tvar correction: float=fur_surface.palm_correction(.002+lift)\n\tcontact.y+=correction\n\tat_contact.y+=correction\n\twrist=prior_wrist\n\tvar gaze: float")
		var script=GDScript.new()
		script.source_code=source
		check(script.reload()==OK,"isolated contact trial compiles")
		game.player.pet_hand.free()
		game.player.pet_hand=script.new()
		game.player.add_child(game.player.pet_hand)
	if model_name!="player_arm":
		var hand=game.player.pet_hand
		hand.model.free()
		hand.model=load("res://assets/models/glb/godot_mvp/"+model_name+".glb").instantiate()
		hand.add_child(hand.model)
		hand.skeleton=hand.model.find_child("Skeleton3D",true,false)
		for animation in hand.model.find_children("*","AnimationPlayer",true,false): animation.stop()
		hand.rest.clear()
		for index in hand.skeleton.get_bone_count(): hand.rest[hand.skeleton.get_bone_name(index)]=hand.skeleton.get_bone_global_rest(index)
	game.start_shift()
	game.set_process(false)
	game.player.enabled=false
	game._spawn_cat("keyboard")
	var cat=game.active_cat
	cat.set_process(false)
	for index in 3600:
		if cat.desktop.state=="seated": break
		cat._process(1.0/60)
	cat._process(.4)
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	game._on_shoo_requested()
	var samples := []
	var steps := [1.05,.6]
	if full_contact:
		steps=[game.player.pet_hand.CONTACT_START]
		for index in 21: steps.append(.05)
	for delta in steps:
		cat._process(delta)
		await process_frame
		await RenderingServer.frame_post_draw
		var hand=game.player.pet_hand
		var measure=load("res://tests/hand_scalp_measure.gd")
		var actual=measure.measure(cat,hand)
		if hand.get("fur_surface")!=null: actual["projection_usec"]={"fur":hand.fur_surface.last_update_usec,"palm":hand.fur_surface.last_correction_usec}
		if hand.get("fur_surface")!=null and absf(hand.age-1.05)<.001: actual["cpu_skin_match"]=hand.fur_surface.debug_skin_match()
		var cycle=fmod(maxf(0,hand.age-hand.CONTACT_START)/(hand.CONTACT_END-hand.CONTACT_START)*2,1.0)
		var expected_gap=.002+sin(PI*(cycle-.7)/.3)*.024 if cycle>=.7 else .002
		actual["expected_palm_gap_m"]=expected_gap
		var raised={}
		var lowered={}
		if not full_contact or absf(hand.age-1.05)<.001 or absf(hand.age-1.65)<.001:
			raised=measure.measure(cat,hand,Vector3.UP*.06)
			lowered=measure.measure(cat,hand,Vector3.DOWN*.06)
		samples.append({"age":hand.age,"actual":actual,"raised_control":raised,"lowered_control":lowered})
		check(actual.max_depth_m<.003,"actual hand does not sink into skull at %.2f s (%.3f mm)"%[hand.age,actual.max_depth_m*1000])
		check(actual.closest_palm_gap_m!=null and absf(actual.closest_palm_gap_m-expected_gap)<.004,"central palm follows fur/contact lift at %.2f s"%hand.age)
		if not raised.is_empty():
			check(raised.max_depth_m<.0001,"raised geometric control is outside skull")
			check(lowered.max_depth_m>.015 and lowered.vertices_deeper_than_3mm>100,"lowered geometric control detects solid skull penetration")
	var report={"passed":failures==0,"failures":failures,"samples":samples,"model":model_name,"trial_contact":trial_contact,"tuning":tuning,"sources":{"hand":FileAccess.get_sha256("res://assets/models/glb/godot_mvp/"+model_name+".glb"),"cat":FileAccess.get_sha256("res://assets/models/glb/godot_mvp/cat_reference.fbx"),"controller":FileAccess.get_sha256("res://player/petting_hand.gd")}}
	var file=FileAccess.open("res://tests/results/"+report_name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("HAND_SCALP_TEST ",JSON.stringify({"passed":failures==0,"failures":failures}))
	game.free()
	quit(0 if failures==0 else 1)
