extends SceneTree
# Compare flight clips in the actual desktop state machine, preserving root physics.
const STEP := 1.0/60.0
var game
var failures := 0
var output := "res://tests/results/desktop-flight-trial-v5"
var trial_name := "desktop_poses_trial_v5"
var foot_contact_trial := false

func _initialize(): call_deferred("run")
func vec(p: Vector3) -> Array: return [p.x,p.y,p.z]
func check(ok: bool,label: String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures+=1

func reach(cat,state: String) -> bool:
	for i in 6000:
		if cat.desktop.state==state: return true
		if cat.is_queued_for_deletion(): return false
		cat._process(1.0/60)
	return false

func skin_bounds(cat) -> Dictionary:
	var sk: Skeleton3D=cat.pose_player.skeleton
	sk.force_update_all_bone_transforms()
	var mesh: MeshInstance3D=cat.model.find_child("mesh_cat",true,false)
	var transforms: Array[Transform3D]=[]
	for bind in mesh.skin.get_bind_count():
		var bone:=sk.find_bone(mesh.skin.get_bind_name(bind))
		if bone<0: bone=mesh.skin.get_bind_bone(bind)
		transforms.append(sk.global_transform*sk.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
	var floor_low:=INF
	var desk_low:=INF
	var floor_vertex:={}
	var desk_vertex:={}
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array=mesh.mesh.surface_get_arrays(surface)
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var p:=Vector3.ZERO
			for slot in 4:
				var weight: float=arrays[Mesh.ARRAY_WEIGHTS][vertex*4+slot]
				if weight>0: p+=(transforms[arrays[Mesh.ARRAY_BONES][vertex*4+slot]]*arrays[Mesh.ARRAY_VERTEX][vertex])*weight
			var info:={"surface":surface,"vertex":vertex,"world":vec(p),"rest":vec(arrays[Mesh.ARRAY_VERTEX][vertex]),"weights":{}}
			for slot in 4:
				var weight: float=arrays[Mesh.ARRAY_WEIGHTS][vertex*4+slot]
				if weight>0: info.weights[String(mesh.skin.get_bind_name(arrays[Mesh.ARRAY_BONES][vertex*4+slot]))]=weight
			if p.y<floor_low:
				floor_low=p.y
				floor_vertex=info
			# Actual rounded-oak desktop bounds from build_mvp.py, before bevel.
			if absf(p.x)<1.825 and p.z> -2.475 and p.z< -.925 and p.y<desk_low:
				desk_low=p.y
				desk_vertex=info
	return {"floor_low":floor_low,"desk_low":desk_low if is_finite(desk_low) else null,"desk_surface_y":.94,"floor_vertex":floor_vertex,"desk_vertex":desk_vertex}

func gpu_skin_bounds(cat) -> Dictionary:
	# Read the renderer's deformed mesh, independently of the CPU bind calculation.
	var mesh: MeshInstance3D=cat.model.find_child("mesh_cat",true,false)
	var baked: ArrayMesh=mesh.bake_mesh_from_current_skeleton_pose()
	var floor_low:=INF
	var desk_low:=INF
	var floor_vertex:={}
	var desk_vertex:={}
	var vertex_count:=0
	for surface in baked.get_surface_count():
		var points: PackedVector3Array=baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in points.size():
			var p: Vector3=mesh.to_global(points[vertex])
			vertex_count+=1
			var info:={"surface":surface,"vertex":vertex,"world":vec(p)}
			if p.y<floor_low:
				floor_low=p.y
				floor_vertex=info
			if absf(p.x)<1.825 and p.z> -2.475 and p.z< -.925 and p.y<desk_low:
				desk_low=p.y
				desk_vertex=info
	return {"floor_low":floor_low,"desk_low":desk_low if is_finite(desk_low) else null,"desk_surface_y":.94,"floor_vertex":floor_vertex,"desk_vertex":desk_vertex,"vertices":vertex_count,"method":"renderer-deformed mesh"}

func sample(cat,frame: int) -> Dictionary:
	var sk: Skeleton3D=cat.pose_player.skeleton
	sk.force_update_all_bone_transforms()
	var bones:={}
	for bone in sk.get_bone_count(): bones[sk.get_bone_name(bone)]=vec(sk.to_global(sk.get_bone_global_pose(bone).origin))
	var gap:=0.0
	for limb in ["front","back"]:
		for side in ["left","right"]:
			for joint in range(1,4):
				var bone:=sk.find_bone("leg_%s_%s_%d"%[limb,side,joint])
				var next:=sk.find_bone("leg_%s_%s_%d"%[limb,side,joint+1])
				var end_rest:=sk.get_bone_global_rest(bone).affine_inverse()*sk.get_bone_global_rest(next).origin
				var end_pose:=sk.to_global(sk.get_bone_global_pose(bone)*end_rest)
				gap=maxf(gap,end_pose.distance_to(sk.to_global(sk.get_bone_global_pose(next).origin)))
	return {"frame":frame,"state":cat.desktop.state,"elapsed":cat.desktop.elapsed,"root":vec(cat.position),"yaw":cat.rotation.y,"bones":bones,"bone_gap":gap,"skin":skin_bounds(cat)}

func run():
	if DisplayServer.get_name()=="headless":
		push_error("Flight skin verification requires the graphics renderer; use a hidden window.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output="res://tests/results/"+arg.trim_prefix("--output=")
		if arg.begins_with("--trial-name="): trial_name=arg.trim_prefix("--trial-name=")
		if arg == "--foot-contact-trial": foot_contact_trial = true
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/.gdignore",FileAccess.WRITE).close()
	var report:={"step":STEP,"clips":trial_name,"cases":{},"hashes":{}}
	report["extra_trial_foot_contact"] = foot_contact_trial
	for path in ["tests/desktop_flight_trial.gd","cats/desktop_foot_contact.gd","cats/cat.gd","cats/desktop_poses.gd","cats/"+trial_name+".gd","assets/models/glb/godot_mvp/cat_reference.fbx","cats/desktop_behavior.gd","assets/models/blender/build_desktop_poses.py"]:
		report.hashes[path]=FileAccess.get_sha256("res://"+path)
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	for label in ["baseline","trial"]:
		seed(60027)
		game=load("res://main/main.tscn").instantiate()
		root.add_child(game)
		await process_frame
		game.verifying_build=true
		game.start_shift()
		game.set_process(false)
		game.player.enabled=false
		game._spawn_cat("keyboard")
		var cat=game.active_cat
		print("CONTACT_INITIALIZATION_USEC ", cat.desktop.foot_contact.initialization_usec)
		var contact_helper
		if label == "trial" and foot_contact_trial:
			contact_helper = load("res://cats/desktop_foot_contact.gd").new(cat)
		cat.set_process(false)
		cat.scratch_timer.stop()
		if label=="trial":
			var poses=load("res://cats/"+trial_name+".gd")
			var library: AnimationLibrary=cat.animation.get_animation_library("")
			for kind in ["Crouch","CrouchDown","Jump","Land","Descend"]:
				var clip: Animation=cat._make_baked_animation(poses.DATA[kind],poses.DURATIONS[kind])
				clip.loop_mode=Animation.LOOP_NONE
				library.remove_animation(kind)
				library.add_animation(kind,clip)
		var view:=SubViewport.new()
		view.size=Vector2i(1280,720)
		view.world_3d=game.get_world_3d()
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var camera:=Camera3D.new()
		view.add_child(camera)
		camera.current=true
		camera.fov=40
		var dir: String=output+"/"+label
		DirAccess.make_dir_recursive_absolute(dir)
		var samples:=[]
		var frame:=0
		for flight in ["up","down"]:
			check(reach(cat,"crouch" if flight=="up" else "crouch_down"),label+" reaches "+flight+" anticipation")
			while cat.desktop.state in (["crouch","jump_up","land_up"] if flight=="up" else ["crouch_down","jump_down","land_down"]):
				if contact_helper != null and cat.desktop.state in ["crouch", "crouch_down", "land_up", "land_down"]:
					contact_helper.apply()
				camera.global_position=cat.global_position+Vector3(0,.85,1.8)
				camera.look_at(cat.global_position+Vector3.UP*.3)
				var data: Dictionary=sample(cat,frame)
				data["flight"]=flight
				samples.append(data)
				await process_frame
				await RenderingServer.frame_post_draw
				data["cpu_skin"]=data.skin
				data["skin"]=gpu_skin_bounds(cat)
				view.get_texture().get_image().save_jpg(dir+"/%04d.jpg"%frame,.92)
				frame+=1
				cat._process(STEP)
				if frame>360:
					check(false,"Flight capture exceeded bounded duration")
					break
		var max_gap:=0.0
		var min_floor:=INF
		var min_desk:=INF
		var max_cpu_gpu_error:=0.0
		for data in samples:
			max_gap=maxf(max_gap,data.bone_gap)
			max_cpu_gpu_error=maxf(max_cpu_gpu_error,absf(data.skin.floor_low-data.cpu_skin.floor_low))
			if data.state in ["crouch","crouch_down","jump_up","jump_down","land_up","land_down"]:
				min_floor=minf(min_floor,data.skin.floor_low)
				if data.skin.desk_low!=null: min_desk=minf(min_desk,float(data.skin.desk_low))
		check(max_gap<.001,label+" flight keeps every limb joint connected")
		check(max_cpu_gpu_error<.0002,label+" CPU contact bounds agree with renderer geometry")
		if label=="trial":
			check(min_floor> -.003,"Trial anticipation, flight and landing skin stay above the floor")
			check(min_desk>.937,"Trial anticipation, flight and landing skin stay above the desktop")
		FileAccess.open(dir+"/motion.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"  "))
		report.cases[label]={"frames":frame,"max_bone_gap":max_gap,"lowest_skin_floor":min_floor,"lowest_skin_desk":min_desk,"max_cpu_gpu_contact_error":max_cpu_gpu_error}
		FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		view.free()
		game.free()
	check(float(report.cases.trial.lowest_skin_desk)>=float(report.cases.baseline.lowest_skin_desk)-.001,"Trial does not lower skin clearance through the desktop")
	report["passed"]=failures==0
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("FLIGHT_TRIAL_REVIEW ",JSON.stringify(report.cases)," failures=",failures)
	quit(0 if failures==0 else 1)
