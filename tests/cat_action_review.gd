extends SceneTree
# A review camera shares the real office world without moving the player camera.
# Controllers run in bounded fixed steps; the same accepted interactions are used.
const FPS := 20.0
var game
var review_views := []
var output := "res://tests/results/cat-action-pass6-baseline"
var kinds := ["keyboard","cup","wall"]
var wall_side := 0
var model_name := "cat_reference"

func _initialize(): call_deferred("run")

func vec(p: Vector3) -> Array: return [p.x,p.y,p.z]

func create_review_view() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.world_3d = game.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.fov = 40
	return {"viewport":viewport,"camera":camera}

func sample(cat, time: float, state: String) -> Dictionary:
	var sk: Skeleton3D = cat.pose_player.skeleton
	sk.force_update_all_bone_transforms()
	var bones := {}
	for bone in sk.get_bone_count():
		bones[sk.get_bone_name(bone)] = vec(sk.to_global(sk.get_bone_global_pose(bone).origin))
	var feet := {}
	for limb in ["front","back"]:
		for side in ["left","right"]:
			feet[limb+"_"+side] = bones["leg_%s_%s_4" % [limb,side]]
	var contacts := {}
	for foot in cat.grounded_gait.feet: contacts[foot.name] = foot.ready and foot.planted
	var hand = game.player.pet_hand
	var clip_time: float = cat.animation.current_animation_position if not cat.animation.current_animation.is_empty() else cat.animation.get_animation(cat.animation.assigned_animation).length
	return {"time":time,"state":state,"elapsed":cat.desktop.elapsed if cat.desktop else cat.age,
		"root":vec(cat.global_position),"yaw":cat.rotation.y,"uprightness":cat.uprightness,
		"clip":cat.animation.assigned_animation,"clip_position":clip_time,"blending":not cat.pose_player.source.is_empty(),
		"feet":feet,"contacts":contacts,"bones":bones,"hand_visible":hand.visible,
		"hand_touching":hand.touching,"hand_age":hand.age,"wrist":vec(hand.wrist),
		"contact":vec(hand.contact),"elbow":vec(hand.elbow_world),"cancelled":hand.cancelled}

func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-pass="): output="res://tests/results/cat-action-"+arg.trim_prefix("--review-pass=")
		if arg.begins_with("--kinds="): kinds=Array(arg.trim_prefix("--kinds=").split(","))
		if arg.begins_with("--wall-side="): wall_side=int(arg.trim_prefix("--wall-side="))
		if arg.begins_with("--model-name="): model_name=arg.trim_prefix("--model-name=")
	seed(60027)
	game = load("res://main/main.tscn").instantiate()
	game.cat_model_scene=load("res://assets/models/glb/godot_mvp/"+model_name+".fbx")
	root.add_child(game)
	await process_frame
	game.verifying_build = true
	game.start_shift()
	game.set_process(false)
	game.player.enabled = false
	game.player.pet_hand.set_process(false)
	game.room.desk.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	review_views = [create_review_view(),create_review_view()]
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/.gdignore",FileAccess.WRITE).close()
	var report := {"fps":FPS,"model_name":model_name,"fixed_controller_step":1.0/60.0,"world":"actual office",
		"player_camera_position":vec(game.player.camera.global_position),"events":{},"source_hashes":{}}
	for path in ["tests/cat_action_review.gd","cats/cat.gd","cats/desktop_behavior.gd","cats/grounded_gait.gd","cats/tail_motion.gd","player/petting_hand.gd","assets/models/glb/godot_mvp/cat_reference.fbx","assets/models/glb/godot_mvp/player_arm.glb"]:
		report.source_hashes[path] = FileAccess.get_sha256("res://"+path)
	var model_path := "assets/models/glb/godot_mvp/"+model_name+".fbx"
	report.source_hashes[model_path]=FileAccess.get_sha256("res://"+model_path)
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	for kind in kinds:
		var dir: String = output+"/"+kind
		for sub in ["three-quarter","side","player"]: DirAccess.make_dir_recursive_absolute(dir+"/"+sub)
		game._spawn_cat(kind)
		var cat = game.active_cat
		if not is_instance_valid(cat) or (kind!="wall" and cat.desktop==null):
			push_error("The actual controller failed to initialize; aborting invalid action capture")
			quit(1)
			return
		if kind=="wall" and wall_side in [-1,1]:
			cat.approach(PackedVector3Array([Vector3(0,.06,2),Vector3(wall_side*4.7,.06,.5),game.room.get_cat_position(wall_side)]))
		cat.set_process(false)
		cat.scratch_timer.stop()
		var samples := []
		var states := {}
		var pet_requested := false
		var wall_shoo_requested := false
		var wall_warning_age := 0.0
		var scratch_duration := 0.0
		var completed := false
		for frame in 1700:
			if not is_instance_valid(cat):
				completed = true
				break
			# Keep the physical player camera in place, aiming normally at the cat.
			game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
			cat._process(1.0/FPS)
			cat.scratch_timer.stop()
			game._process(0)
			game.room.desk._process(1.0/FPS)
			if cat.is_queued_for_deletion():
				completed = true
				break
			var state: String = cat.desktop.state if cat.desktop else ("depart" if cat.leaving else ("approach" if not cat.route.is_empty() else ("wall_warning" if cat.warning else "scratch")))
			if kind=="keyboard" and state=="seated" and cat.desktop.elapsed>.5 and not pet_requested:
				game._on_shoo_requested()
				pet_requested = cat.desktop.state=="petting"
				state = cat.desktop.state
			if kind=="wall" and state=="wall_warning":
				wall_warning_age += 1.0/FPS
				if wall_warning_age>=cat.RULES.WARNING_DURATION:
					cat._scratch()
					state="scratch"
			if kind=="wall" and state=="scratch":
				scratch_duration += 1.0/FPS
				if scratch_duration>=cat.cycle_length*3 and not wall_shoo_requested:
					if frame%100==0 or scratch_duration<cat.cycle_length*3+.1:
						print("WALL_SHOO_CHECK ",JSON.stringify({"started":game.started,"finished":game.finished,"working":game.working,"paused":paused,"active":cat.active,"leaving":cat.leaving,"can_see":game.player.can_see(cat),"active_cat":game.active_cat==cat,"camera":vec(game.player.camera.global_position),"forward":vec(-game.player.camera.global_basis.z)}))
					game._on_shoo_requested()
					wall_shoo_requested=cat.leaving
			var target: Vector3 = cat.global_position+Vector3.UP*(.55 if kind=="wall" and cat.uprightness>.5 else .30)
			var inward := -signf(cat.position.x) if kind=="wall" else 1.0
			for index in 2:
				var camera: Camera3D = review_views[index].camera
				camera.global_position=target+Vector3(inward*(1.25 if index==0 else 1.6),.55,1.25 if index==0 else .18)
				camera.look_at(target)
			var sample_data: Dictionary = sample(cat,(frame+1)/FPS,state)
			sample_data["game_finished"] = game.finished
			sample_data["cat_active"] = cat.active
			sample_data["can_see"] = game.player.can_see(cat)
			sample_data["desk_dirty"] = game.room.desk.dirty
			sample_data["cup_rotation"] = vec(game.room.desk.cup.rotation)
			sample_data["frame"] = frame
			samples.append(sample_data)
			await process_frame
			await RenderingServer.frame_post_draw
			for index in 2:
				var image: Image = review_views[index].viewport.get_texture().get_image()
				var view_name := "three-quarter" if index==0 else "side"
				image.save_jpg(dir+"/"+view_name+"/%04d.jpg"%frame,.88)
				if not states.has(state): image.save_png(dir+"/"+state+"-"+view_name+".png")
			if kind=="keyboard" and state in ["settle","seated","pet_wait","petting","stand"]:
				root.get_texture().get_image().save_jpg(dir+"/player/%04d.jpg"%frame,.88)
			if not states.has(state): states[state]=frame
			if frame%120==0: print("ACTION_REVIEW ",kind," ",frame," ",state)
		report.events[kind] = {"frames":samples.size(),"completed":completed,"states":states,"pet_requested":pet_requested,"shoo_requested":wall_shoo_requested}
		FileAccess.open(dir+"/motion.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"  "))
		FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		if is_instance_valid(cat): cat.queue_free()
		await process_frame
		game.active_cat=null
		game.departing_cat=null
		game.player.pet_hand.reset()
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	for view in review_views: view.viewport.queue_free()
	game.queue_free()
	var passed := true
	for kind in kinds:
		passed = passed and report.events[kind].completed
		if kind=="keyboard": passed=passed and report.events[kind].pet_requested
		if kind=="wall": passed=passed and report.events[kind].shoo_requested
	print("CAT_ACTION_REVIEW_OK ",JSON.stringify(report.events))
	quit(0 if passed else 1)
