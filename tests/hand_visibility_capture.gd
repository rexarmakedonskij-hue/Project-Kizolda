extends SceneTree
var game
var folder := "res://tests/results/hand-visibility-review"
var model_name := "player_arm"
var cancel_at := -1.0
var rest_meshes := {}
var previous_vertices := {}
var samples := []
var previous_wrist := Vector3.INF
var previous_tip := Vector3.INF
func _initialize(): call_deferred("run")
func run():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="): folder="res://tests/results/"+argument.trim_prefix("--folder=")
		if argument.begins_with("--model="): model_name=argument.trim_prefix("--model=")
		if argument.begins_with("--cancel-at="): cancel_at=float(argument.trim_prefix("--cancel-at="))
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build=true
	game.start_shift()
	game.set_process(false)
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._spawn_cat("keyboard")
	var cat = game.active_cat
	cat.set_process(false)
	for i in 3600:
		if cat.desktop.state == "seated": break
		cat._process(1.0/60)
	cat._process(.4)
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	var hand=game.player.pet_hand
	if model_name!="player_arm":
		hand.model.free()
		hand.model=load("res://assets/models/glb/godot_mvp/"+model_name+".glb").instantiate()
		hand.add_child(hand.model)
		hand.skeleton=hand.model.find_child("Skeleton3D",true,false)
		for animation in hand.model.find_children("*","AnimationPlayer",true,false): animation.stop()
		hand.rest.clear()
		for index in hand.skeleton.get_bone_count(): hand.rest[hand.skeleton.get_bone_name(index)]=hand.skeleton.get_bone_global_rest(index)
	hand.skeleton.reset_bone_poses()
	hand.skeleton.force_update_all_bone_transforms()
	await process_frame
	await RenderingServer.frame_post_draw
	for mesh in hand.model.find_children("*","MeshInstance3D",true,false): rest_meshes[mesh.name]=mesh.bake_mesh_from_current_skeleton_pose()
	game._on_shoo_requested()
	DirAccess.make_dir_recursive_absolute(folder+"/frames")
	for frame in 57:
		if cancel_at>=0 and absf(frame/20.0-cancel_at)<.001: game.player.camera.rotation.y+=PI
		if frame > 0 and is_instance_valid(cat): cat._process(1.0/20)
		game._process(0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(folder+"/frames/%04d.jpg" % frame, .9)
		if hand.active:
			var skin=load("res://tests/hand_skin_measure.gd").measure(hand,rest_meshes)
			var movement := 0.0
			var mesh_steps := {}
			for mesh in hand.model.find_children("*","MeshInstance3D",true,false):
				var baked=mesh.bake_mesh_from_current_skeleton_pose()
				for surface in baked.get_surface_count():
					var points: PackedVector3Array=baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var key=str(mesh.name)+str(surface)
					if previous_vertices.has(key):
						for index in points.size():
							var step=points[index].distance_to(previous_vertices[key][index])
							movement=maxf(movement,step)
							mesh_steps[mesh.name]=maxf(mesh_steps.get(mesh.name,0.0),step)
					previous_vertices[key]=points
			var scalp={}
			if frame%2==0: scalp=load("res://tests/hand_scalp_measure.gd").measure(cat,hand)
			var wrist_step=hand.wrist.distance_to(previous_wrist) if previous_wrist.is_finite() else 0.0
			var tip: Vector3=skin.tip_centroid
			var tip_step=tip.distance_to(previous_tip) if previous_tip.is_finite() else 0.0
			samples.append({"frame":frame,"age":hand.age,"touching":hand.touching,"cancelled":hand.cancelled,"skin":skin,"maximum_vertex_step_m":movement,"mesh_max_steps_m":mesh_steps,"wrist_step_m":wrist_step,"fingertip_centroid_step_m":tip_step,"finger_pressure":hand.finger_pressure,"scalp":scalp})
			previous_wrist=hand.wrist
			previous_tip=tip
		if frame in [6, 14, 26, 36, 46, 74]:
			root.get_texture().get_image().save_png(folder+"/stage-%d.png" % frame)
		if frame >= 11 and frame <= 53:
			root.get_texture().get_image().save_png(folder+"/visible-%d.png" % frame)
			var prior_visibility: bool = hand.visible
			hand.visible = false
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/uncovered-%d.png" % frame)
			hand.visible = prior_visibility
		if frame in [16,28] and is_instance_valid(cat) and hand.active:
			var view: Transform3D = game.player.camera.global_transform
			var report = {"age":hand.age,"wrist":str(hand.wrist),"contact":str(hand.contact),"elbow":str(hand.elbow_world),"shoulder":str(hand.shoulder_world),"elbow_viewport":str(game.player.camera.unproject_position(hand.elbow_world)),"touching":hand.touching}
			report["scalp_surface"]=load("res://tests/hand_scalp_measure.gd").measure(cat,hand)
			var report_file = FileAccess.open(folder+"/contact-%d.json"%frame,FileAccess.WRITE)
			report_file.store_string(JSON.stringify(report,"  "))
			game.player.camera.global_position = Vector3(1.6,1.9,-.5)
			game.player.camera.look_at(cat.global_position+Vector3.UP*.35)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/side-%d.png"%frame)
			game.player.camera.global_position = Vector3(0,2.7,-.65)
			game.player.camera.look_at(cat.global_position+Vector3.UP*.35)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/overhead-%d.png"%frame)
			game.player.camera.global_transform = view
		if frame % 20 == 0: print("CAPTURE_FRAME ", frame)
	var passed=true
	for sample in samples:
		passed=passed and sample.skin.max_edge_stretch<=2.0 and sample.skin.nonfinite_vertices==0 and sample.maximum_vertex_step_m<.18
		if not sample.scalp.is_empty(): passed=passed and sample.scalp.max_depth_m<.003
	var sources={}
	for path in ["player/petting_hand.gd","player/petting_surface.gd","cats/cat.gd","assets/models/glb/godot_mvp/"+model_name+".glb","assets/models/glb/godot_mvp/cat_reference.fbx"]: sources[path]=FileAccess.get_sha256("res://"+path)
	var report_file=FileAccess.open(folder+"/geometry-sequence.json",FileAccess.WRITE)
	report_file.store_string(JSON.stringify({"passed":passed,"model":model_name,"cancel_at":cancel_at,"sources":sources,"samples":samples},"  "))
	game.free()
	print("HAND_CAPTURE_OK")
	quit(0 if passed else 1)
