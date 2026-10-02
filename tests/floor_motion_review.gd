extends SceneTree
# Exercise the real route controller through acceleration, two turns and arrival.
func _initialize(): call_deferred("run")
func run():
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	var stage:=Node3D.new()
	root.add_child(stage)
	var world:=WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color("bec7c3")
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color.WHITE
	world.environment.ambient_light_energy=.55
	stage.add_child(world)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-45,-30,0)
	light.light_energy=.8
	light.shadow_enabled=true
	stage.add_child(light)
	var floor:=MeshInstance3D.new()
	floor.mesh=PlaneMesh.new()
	floor.mesh.size=Vector2(20,20)
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("b0bbb5")
	floor.material_override=material
	stage.add_child(floor)
	for axis in 2:
		for line in range(-5,6):
			var marker:=MeshInstance3D.new()
			marker.mesh=BoxMesh.new()
			marker.mesh.size=Vector3(.008,.002,10) if axis==0 else Vector3(10,.002,.008)
			marker.position=Vector3(line,.002,0) if axis==0 else Vector3(0,.002,line)
			var ink:=StandardMaterial3D.new()
			ink.albedo_color=Color("8d9c94")
			marker.material_override=ink
			stage.add_child(marker)
	var cat=load("res://cats/cat.tscn").instantiate()
	stage.add_child(cat)
	cat.set_process(false)
	cat.approach(PackedVector3Array([Vector3(0,.06,0),Vector3(0,.06,1.6),Vector3(1.5,.06,1.6),Vector3(1.5,.06,.2)]))
	var camera:=Camera3D.new()
	stage.add_child(camera)
	camera.current=true
	camera.fov=45
	var review_pass:="pass4"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-pass="): review_pass=argument.trim_prefix("--review-pass=")
	var output:="res://tests/results/floor-motion-"+review_pass
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/.gdignore",FileAccess.WRITE).close()
	var samples:=[]
	var previous_root: Vector3=cat.position
	for frame in 260:
		cat._process(1.0/20)
		camera.position=cat.position+Vector3(1.6,.9,1.8)
		camera.look_at(cat.position+Vector3.UP*.30)
		var sk: Skeleton3D=cat.pose_player.skeleton
		sk.force_update_all_bone_transforms()
		var feet:={}
		for limb in ["front","back"]:
			for side in ["left","right"]:
				var p:=sk.to_global(sk.get_bone_global_pose(sk.find_bone("leg_%s_%s_4"%[limb,side])).origin)
				feet[limb+"_"+side]=[p.x,p.y,p.z]
		var contacts:={}
		for foot in cat.grounded_gait.feet: contacts[foot.name]=foot.ready and foot.planted
		samples.append({"time":(frame+1)/20.0,"root":[cat.position.x,cat.position.y,cat.position.z],"yaw":cat.rotation.y,"intended_speed":cat.move_speed,"actual_speed":cat.position.distance_to(previous_root)*20,"clip":cat.animation.current_animation,"phase":cat.animation.current_animation_position,"feet":feet,"contacts":contacts})
		previous_root=cat.position
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(output+"/%04d.jpg"%frame,.9)
		if frame%40==0: print("FLOOR_REVIEW ",frame," ",cat.position," ",cat.move_speed)
	FileAccess.open(output+"/motion.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"  "))
	stage.free()
	print("FLOOR_MOTION_CAPTURE_OK")
	quit()
