extends SceneTree
var game
func vec(p: Vector3)->Array:return [p.x,p.y,p.z]
func _initialize():call_deferred("run")
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

func run():
	game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build=true
	game.start_shift()
	game.set_process(false)
	game._spawn_cat("keyboard")
	var cat=game.active_cat
	cat.set_process(false)
	var sk:Skeleton3D=cat.pose_player.skeleton
	var rows:={}
	for clip in ["rest","Idle","Crouch"]:
		if clip=="rest":sk.reset_bone_poses()
		else:cat.pose_player.play(clip,0);cat.pose_player.advance(.1)
		var b:=sk.find_bone("body_2")
		rows[clip]={"skin":skin_bounds(cat),"body2_rest":str(sk.get_bone_rest(b)),"body2_pose":str(sk.get_bone_pose(b))}
	FileAccess.open("res://tests/results/desktop-idle-diagnostic.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	print(JSON.stringify(rows))
	quit()
