extends SceneTree
var world: Node3D
var camera: Camera3D
var hand
var rest_meshes := {}
var folder := "res://tests/results/hand-anatomy-current"
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1280,720)
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(.18,.20,.22)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(.8,.86,1)
	settings.ambient_light_energy = .65
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.light_energy = 1.1
	world.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .34
	world.add_child(camera)
	camera.current = true
	hand = load("res://player/petting_hand.gd").new()
	world.add_child(hand)
	hand.visible = true
	hand.set_process(false)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--model="):
			var scene = load("res://assets/models/glb/godot_mvp/"+argument.trim_prefix("--model=")+".glb")
			hand.model.free()
			hand.model = scene.instantiate()
			hand.add_child(hand.model)
			hand.skeleton = hand.model.find_child("Skeleton3D",true,false)
			for animation in hand.model.find_children("*","AnimationPlayer",true,false): animation.stop()
			hand.rest.clear()
			for index in hand.skeleton.get_bone_count(): hand.rest[hand.skeleton.get_bone_name(index)] = hand.skeleton.get_bone_global_rest(index)
		if argument.begins_with("--folder="): folder = "res://tests/results/"+argument.trim_prefix("--folder=")
	DirAccess.make_dir_recursive_absolute(folder)
	hand.skeleton.reset_bone_poses()
	for mesh in hand.model.find_children("*","MeshInstance3D",true,false):
		print("SKIN_METHODS ", mesh.name, " bake=",mesh.has_method("bake_mesh_from_current_skeleton_pose"))
		print("BONES ", hand.skeleton.get_bone_count())
	await shot("rest-top",Vector3(0,.8,.74),Vector3(0,0,.74),Vector3.FORWARD)
	for mesh in hand.model.find_children("*","MeshInstance3D",true,false): rest_meshes[mesh.name] = mesh.bake_mesh_from_current_skeleton_pose()
	await shot("rest-palm",Vector3(0,-.8,.74),Vector3(0,0,.74),Vector3.FORWARD)
	await shot("rest-side",Vector3(.8,.18,.74),Vector3(0,0,.74),Vector3.UP)
	hand.age=.8
	hand.touching=true
	hand.pose(Vector3(.30,1.24,-1.28),Vector3(0,1.575,-1.270))
	await shot("touch-top",Vector3(0,2.4,-1.345),Vector3(0,1.575,-1.345),Vector3.BACK)
	await shot("touch-palm",Vector3(0,.8,-1.345),Vector3(0,1.575,-1.345),Vector3.BACK)
	await shot("touch-side",Vector3(.8,1.72,-1.345),Vector3(0,1.575,-1.345),Vector3.UP)
	await shot("touch-quarter",Vector3(.55,2.10,-1.10),Vector3(0,1.575,-1.345),Vector3.UP)
	measure_skin()
	world.free()
	print("HAND_ANATOMY_CAPTURE_OK")
	quit()
func shot(label: String, eye: Vector3, target: Vector3, up: Vector3):
	camera.position = eye
	camera.look_at(target,up)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")

func measure_skin():
	var result := {}
	for mesh in hand.model.find_children("*","MeshInstance3D",true,false):
		var baked = mesh.bake_mesh_from_current_skeleton_pose()
		var rest_baked = rest_meshes[mesh.name]
		var outliers := []
		var max_stretch := 1.0
		var stretched := 0
		var total := 0
		for surface in baked.get_surface_count():
			var after: Array = baked.surface_get_arrays(surface)
			var before: Array = rest_baked.surface_get_arrays(surface)
			var source: Array = mesh.mesh.surface_get_arrays(surface)
			var old: PackedVector3Array = before[Mesh.ARRAY_VERTEX]
			var points: PackedVector3Array = after[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = after[Mesh.ARRAY_INDEX]
			for triangle in indices.size()/3:
				for edge in 3:
					var a: int = indices[triangle*3+edge]
					var b: int = indices[triangle*3+(edge+1)%3]
					var old_length: float = old[a].distance_to(old[b])
					if old_length < .00001: continue
					var ratio: float = points[a].distance_to(points[b])/old_length
					total += 1
					if ratio > 2: stretched += 1
					if ratio > max_stretch:
						max_stretch = ratio
						var vertices := []
						for vertex in [a,b]:
							var influences := {}
							for slot in 4:
								var weight: float = source[Mesh.ARRAY_WEIGHTS][vertex*4+slot]
								if weight <= .0001: continue
								var bind: int = source[Mesh.ARRAY_BONES][vertex*4+slot]
								var bone: int = hand.skeleton.find_bone(mesh.skin.get_bind_name(bind))
								if bone < 0: bone = mesh.skin.get_bind_bone(bind)
								influences[hand.skeleton.get_bone_name(bone)] = weight
							vertices.append({"rest":str(old[vertex]),"deformed":str(points[vertex]),"weights":influences})
						outliers.append({"stretch":ratio,"vertices":vertices})
		result[mesh.name] = {"max_edge_stretch":max_stretch,"edges_over_twice_rest":stretched,"total_triangle_edges":total,"largest_outliers":outliers.slice(maxi(0,outliers.size()-5))}
	var file = FileAccess.open(folder+"/skin-measures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("SKIN_MEASURES ",JSON.stringify(result).left(180))
