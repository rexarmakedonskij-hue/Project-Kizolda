extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat("keyboard")
	var cat = game.active_cat
	cat.set_process(false)
	for i in 3600:
		if cat.desktop.state == "seated": break
		cat._process(1.0/60)
	cat._process(.4)
	var sk = cat.pose_player.skeleton
	sk.force_update_all_bone_transforms()
	for name in ["head", "neck", "body_2"]:
		var bone = sk.find_bone(name)
		if bone >= 0: print(name, " ", sk.to_global(sk.get_bone_global_pose(bone).origin), " basis ", sk.global_basis * sk.get_bone_global_pose(bone).basis)
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	game._on_shoo_requested()
	cat._process(.8)
	var hand = game.player.pet_hand
	var hs: Skeleton3D = hand.skeleton
	for mesh in hand.model.find_children("*", "MeshInstance3D", true, false):
		if mesh.name not in ["Palm", "Wrist", "Cuff", "Forearm sleeve"]: continue
		var arrays = mesh.mesh.surface_get_arrays(0)
		var center := Vector3.ZERO
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var point := Vector3.ZERO
			for slot in 4:
				var weight: float = arrays[Mesh.ARRAY_WEIGHTS][vertex*4+slot]
				if weight == 0: continue
				var bind: int = arrays[Mesh.ARRAY_BONES][vertex*4+slot]
				var bone = hs.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0: bone = mesh.skin.get_bind_bone(bind)
				point += hs.to_global(hs.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind)*arrays[Mesh.ARRAY_VERTEX][vertex])*weight
			center += point
		center /= arrays[Mesh.ARRAY_VERTEX].size()
		print("ARM_MESH ",mesh.name," world center ",center, " node ",mesh.global_position)
	print("WRIST ",hand.wrist)
	game.free()
	quit()
