extends SceneTree
func _initialize():call_deferred("run")
func run():
	var inspect_vertices=[19333,19334,19336,19339]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--vertices="):
			inspect_vertices=[]
			for value in argument.trim_prefix("--vertices=").split(","):inspect_vertices.append(int(value))
	var model=load("res://assets/models/glb/godot_mvp/cat_reference.fbx").instantiate()
	root.add_child(model)
	await process_frame
	var sk:Skeleton3D=model.find_child("Skeleton3D",true,false)
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.name!="mesh_cat":continue
		var skin:Skin=mesh.get_skin()
		for surface in mesh.mesh.get_surface_count():
			var a:Array=mesh.mesh.surface_get_arrays(surface)
			var points:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			var bones:PackedInt32Array=a[Mesh.ARRAY_BONES]
			var weights:PackedFloat32Array=a[Mesh.ARRAY_WEIGHTS]
			var n:int=int(bones.size()/points.size())
			for vertex in inspect_vertices:
				if vertex>=points.size():continue
				var report={"surface":surface,"vertex":vertex,"rest_position":str(points[vertex]),"weights":[]}
				for slot in n:
					var offset:int=vertex*n+slot
					if weights[offset]<.000001:continue
					var bind:int=bones[offset]
					var name:String=String(skin.get_bind_name(bind))
					var bone:int=sk.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)
					report.weights.append({"bone":sk.get_bone_name(bone),"weight":weights[offset]})
				print("PAW_BIND ",JSON.stringify(report))
	model.queue_free()
	quit()
