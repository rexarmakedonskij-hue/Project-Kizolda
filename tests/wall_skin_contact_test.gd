extends SceneTree
# Actual office triangles and renderer skin. Every 60 Hz rise/work/lower frame
# is checked; approach/depart walking is sampled at 0.5 s plus transition frames.
var output := "res://tests/results/wall-skin-surfaces-step2"
var game
var failures := 0
var selected_side := 0
func _initialize(): call_deferred("run")
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output=arg.trim_prefix("--report=")
		if arg.begins_with("--side="): selected_side=int(arg.trim_prefix("--side="))
	DirAccess.make_dir_recursive_absolute(output)
	game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build=true
	game.start_shift()
	game.set_process(false)
	game.player.enabled=false
	var view=SubViewport.new()
	view.size=Vector2i(1280,720)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_3d=game.get_world_3d()
	root.add_child(view)
	var camera=Camera3D.new()
	view.add_child(camera)
	camera.current=true
	camera.fov=43
	var report={"scope":"Real room surface triangles; all rise/work/lower frames at 60 Hz, walking sampled every .5 s and early handoff frames", "cases":[],"source_hashes":{}}
	for path in ["cats/wall_support.gd","cats/cat.gd","cats/grounded_gait.gd","room/room.gd","room/ground_surface.gd","tests/wall_skin_geometry.gd","tests/wall_skin_contact_test.gd","assets/models/glb/godot_mvp/cat_reference.fbx","assets/models/glb/godot_mvp/office.glb"]:
		report.source_hashes[path]=FileAccess.get_sha256("res://"+path)
	for side in [-1,1]:
		if selected_side!=0 and side!=selected_side:continue
		game._spawn_cat("wall")
		var cat=game.active_cat
		cat.approach(PackedVector3Array([Vector3(0,.06,2),Vector3(side*4.7,.06,.5),game.room.get_cat_position(side)]))
		cat.set_process(false)
		cat.scratch_timer.stop()
		var support=cat.wall_support
		if support==null:
			push_error("Production cat is missing wall support")
			quit(2)
			return
		var measure=preload("res://tests/wall_skin_geometry.gd").new(cat,game.room)
		var data={"side":side,"completed":false,"shoo_requested":false,"samples":[],"surfaces":measure.surfaces_metadata(),"maximum_floor_penetration":0.0,"maximum_wall_penetration":0.0,"minimum_supports":4,"failed_support_frames":0,"failed_front_wall_frames":0}
		var warning_age:=0.0
		var departure_frame:=-10000
		var shots:={}
		var case_path=output+"/side-%d.json"%side
		for frame in 4000:
			cat._process(1.0/60.0)
			cat.scratch_timer.stop()
			if cat.is_queued_for_deletion():
				data.completed=true
				break
			game.player.camera.look_at(cat.global_position+Vector3.UP*.75)
			var state="depart" if cat.leaving else ("approach" if not cat.route.is_empty() else ("warning" if cat.warning else "scratch"))
			if state=="warning":
				warning_age+=1.0/60.0
				if warning_age>=cat.RULES.WARNING_DURATION: cat._scratch()
			if state=="scratch" and cat.scratch_age>=cat.cycle_length*3 and not data.shoo_requested:
				game._on_shoo_requested()
				data.shoo_requested=cat.leaving
				if cat.leaving: departure_frame=frame
			var critical=cat.uprightness>.00001 or (state=="depart" and frame-departure_frame<180)
			if not critical and frame%30!=0: continue
			var target=cat.global_position+Vector3.UP*(.4 if cat.uprightness>.5 else .30)
			camera.global_position=target+Vector3(-side*1.3,.30,.25)
			camera.look_at(target)
			await process_frame
			await RenderingServer.frame_post_draw
			var geometry=measure.sample()
			var sample={"frame":frame,"time":frame/60.0,"state":state,"uprightness":cat.uprightness,"support":support.metrics.duplicate(true),"geometry":geometry}
			data.samples.append(sample)
			if data.samples.size()%30==0:
				FileAccess.open(case_path,FileAccess.WRITE).store_string(JSON.stringify(data,"  "))
			data.maximum_floor_penetration=maxf(data.maximum_floor_penetration,geometry.maximum_floor_penetration)
			data.maximum_wall_penetration=maxf(data.maximum_wall_penetration,geometry.maximum_wall_penetration)
			if cat.uprightness>.15:
				data.minimum_supports=mini(data.minimum_supports,geometry.supports)
				if geometry.supports<2: data.failed_support_frames+=1
			if state=="scratch" and cat.pose_player.source.is_empty():
				if not geometry.paws.front_left.wall_supported and not geometry.paws.front_right.wall_supported: data.failed_front_wall_frames+=1
			var key=state+str(int(cat.uprightness*4))
			if not shots.has(key):
				view.get_texture().get_image().save_png(output+"/side-%d-%s.png"%[side,key])
				shots[key]=true
			if data.samples.size()%30==0: print("WALL_SKIN ",side," frame=",frame," measure_ms=",geometry.measurement_usec/1000.0," floor_mm=",data.maximum_floor_penetration*1000," wall_mm=",data.maximum_wall_penetration*1000)
		var ok:bool=data.completed and data.shoo_requested and data.maximum_floor_penetration<.003 and data.maximum_wall_penetration<.003 and data.failed_support_frames==0 and data.failed_front_wall_frames==0
		data.passed=ok
		if not ok: failures+=1
		report.cases.append(data)
		FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		if is_instance_valid(cat): cat.queue_free()
		await process_frame
		game.active_cat=null
		game.departing_cat=null
	print("WALL_SKIN_CONTACT failures=",failures)
	report.source_hashes_after={}
	report.sources_unchanged=true
	for path in report.source_hashes:
		report.source_hashes_after[path]=FileAccess.get_sha256("res://"+path)
		if report.source_hashes_after[path]!=report.source_hashes[path]:report.sources_unchanged=false
	if not report.sources_unchanged:failures+=1
	report.passed=failures==0
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	view.free()
	game.free()
	quit(1 if failures else 0)
