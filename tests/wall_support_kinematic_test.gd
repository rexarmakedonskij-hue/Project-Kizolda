extends SceneTree
# Intermediate CPU evidence, not a rendered model/skin acceptance check.
# Uses the real office and interaction, fixed 60 Hz, exact terminal-paw pads.
var game
var lean := .035
var output := "res://tests/results/wall-support-kinematic-lean35.json"
var production_hook := false
var interrupt_at := "scratch-complete"
var full_route := false
func _initialize(): call_deferred("run")
func vec(point: Vector3) -> Array: return [point.x,point.y,point.z]

func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lean="): lean=float(arg.trim_prefix("--lean="))
		if arg.begins_with("--report="): output=arg.trim_prefix("--report=")
		if arg=="--production-hook": production_hook=true
		if arg.begins_with("--interrupt="): interrupt_at=arg.trim_prefix("--interrupt=")
		if arg=="--full-route": full_route=true
	game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build=true
	game.start_shift()
	game.set_process(false)
	game.player.enabled=false
	game.player.pet_hand.set_process(false)
	game.room.desk.set_process(false)
	var report := {"scope":"CPU-only actual terminal-paw skin bind points and world room surfaces; full rendering and blended skin require separate evidence", "lean":lean,"production_hook":production_hook,"interrupt_at":interrupt_at,"cases":[],"source_hashes":{},"passed":true}
	report.full_route=full_route
	for path in ["cats/cat.gd","cats/wall_support.gd","cats/grounded_gait.gd","cats/paw_geometry.gd","room/room.gd","room/ground_surface.gd","tests/wall_support_kinematic_test.gd"]:
		report.source_hashes[path]=FileAccess.get_sha256("res://"+path)
	for side in [-1,1]:
		game._spawn_cat("wall")
		var cat=game.active_cat
		var endpoint: Vector3=game.room.get_cat_position(side)
		cat.approach(PackedVector3Array([endpoint+Vector3(0,0,.8),endpoint]))
		if full_route: cat.approach(PackedVector3Array([Vector3(0,.06,2),Vector3(side*4.7,.06,.5),endpoint]))
		cat.set_process(false)
		cat.scratch_timer.stop()
		var support=cat.wall_support if production_hook else preload("res://cats/wall_support.gd").new(cat)
		support.extra_forward=lean
		if not production_hook:cat.wall_support=null
		var sk: Skeleton3D=cat.pose_player.skeleton
		var data := {"side":side,"completed":false,"shoo_requested":false,"handoff":false,
			"maximum_joint_gap":0.0,"maximum_length_error":0.0,"maximum_front_target_error":0.0,
			"maximum_foot_step":0.0,"maximum_floor_penetration":0.0,"maximum_wall_penetration":0.0,
			"minimum_front_carpus_height":INF,"minimum_front_elbow_height":INF,
			"minimum_supports":4,"failed_support_frames":0,"failed_work_contact_frames":0,
			"states":{},"samples":[],"paw_counts":{}}
		for name in support.paw_pads: data.paw_counts[name]=support.paw_pads[name].size()
		var previous := {}
		var warning_age := 0.0
		for frame in (4000 if full_route else 2400):
			cat._process(1.0/60.0)
			if not production_hook: support.apply(1.0/60.0)
			cat.scratch_timer.stop()
			if cat.is_queued_for_deletion():
				data.completed=true
				break
			sk.force_update_all_bone_transforms()
			game.player.camera.look_at(cat.global_position+Vector3.UP*.75)
			var state: String="depart" if cat.leaving else ("approach" if not cat.route.is_empty() else ("warning" if cat.warning else "scratch"))
			data.states[state]=int(data.states.get(state,0))+1
			if state=="warning":
				warning_age+=1.0/60.0
				if warning_age>=cat.RULES.WARNING_DURATION: cat._scratch()
			var should_interrupt:bool=(state=="scratch" and cat.scratch_age>=cat.cycle_length*3)
			if interrupt_at=="warning-early": should_interrupt=state=="warning" and warning_age>=.1
			elif interrupt_at=="warning-late": should_interrupt=state=="warning" and warning_age>=.6
			elif interrupt_at=="scratch-early": should_interrupt=state=="scratch" and cat.scratch_age>=.1
			if should_interrupt and not data.shoo_requested:
				game._on_shoo_requested()
				data.shoo_requested=cat.leaving
			var paws := {}
			var supports := 0
			for foot in support.feet:
				var poses: Array[Transform3D]=support._poses(foot)
				var gaps: Dictionary=support._paw_gaps(foot,poses[3])
				var supported: bool=(gaps.wall>=-.002 and gaps.wall<=.005) or (gaps.floor>=-.002 and gaps.floor<=.005)
				var chain := []
				for pose in poses: chain.append(vec(pose.origin))
				paws[foot.name]={"position":vec(poses[3].origin),"chain":chain,"lengths":foot.lengths.duplicate(),"floor_gap":gaps.floor,"wall_gap":gaps.wall,"supported":supported}
				if String(foot.name).begins_with("front_"):
					var carpus: float=poses[2].origin.y-cat.ground_height_at(poses[2].origin)
					var elbow: float=poses[1].origin.y-cat.ground_height_at(poses[1].origin)
					if carpus<data.minimum_front_carpus_height:
						data.minimum_front_carpus_height=carpus
						data["minimum_carpus_sample"]={"frame":frame,"state":state,"foot":foot.name,"chain":chain,"lengths":foot.lengths.duplicate()}
					if elbow<data.minimum_front_elbow_height:
						data.minimum_front_elbow_height=elbow
						data["minimum_elbow_sample"]={"frame":frame,"state":state,"foot":foot.name,"chain":chain,"lengths":foot.lengths.duplicate()}
				if supported: supports+=1
				data.maximum_floor_penetration=maxf(data.maximum_floor_penetration,-gaps.floor)
				if is_finite(gaps.wall): data.maximum_wall_penetration=maxf(data.maximum_wall_penetration,-gaps.wall)
				if previous.has(foot.name):
					var distance: float=poses[3].origin.distance_to(previous[foot.name])
					if distance>data.maximum_foot_step:
						data.maximum_foot_step=distance
						data["maximum_step_sample"]={"frame":frame,"state":state,"foot":foot.name,"from":vec(previous[foot.name]),"to":vec(poses[3].origin),"chain":chain,"lengths":foot.lengths.duplicate()}
				previous[foot.name]=poses[3].origin
				for joint in 3:
					var length: float=poses[joint].origin.distance_to(poses[joint+1].origin)
					data.maximum_length_error=maxf(data.maximum_length_error,absf(length-foot.lengths[joint]))
					var rest: Transform3D=sk.get_bone_global_rest(foot.bones[joint])
					var rest_next: Vector3=sk.get_bone_global_rest(foot.bones[joint+1]).origin
					var local_tail: Vector3=rest.affine_inverse()*rest_next
					var tail: Vector3=sk.to_global(sk.get_bone_global_pose(foot.bones[joint])*local_tail)
					data.maximum_joint_gap=maxf(data.maximum_joint_gap,tail.distance_to(poses[joint+1].origin))
			data.maximum_front_target_error=maxf(data.maximum_front_target_error,float(support.metrics.get("maximum_front_target_error",0.0)))
			if cat.uprightness>.15:
				data.minimum_supports=mini(data.minimum_supports,supports)
				if supports<2: data.failed_support_frames+=1
			if state=="scratch" and cat.pose_player.source.is_empty():
				var left: Dictionary=paws.front_left
				var right: Dictionary=paws.front_right
				if not (left.wall_gap>=-.002 and left.wall_gap<=.005) and not (right.wall_gap>=-.002 and right.wall_gap<=.005):
					data.failed_work_contact_frames+=1
			if state=="depart" and cat.uprightness<.00001 and not support.engaged: data.handoff=true
			if cat.uprightness>.00001 or frame%15==0:
				data.samples.append({"frame":frame,"state":state,"uprightness":cat.uprightness,"root":vec(cat.global_position),"supports":supports,"paws":paws,"wall_support":support.metrics.duplicate(true)})
		data["passed"]=data.completed and data.shoo_requested and data.handoff and data.maximum_length_error<.001 and data.maximum_joint_gap<.001 and data.maximum_foot_step<=.045 and data.maximum_floor_penetration<=.003 and data.maximum_wall_penetration<=.003 and data.minimum_front_carpus_height>=.02 and data.failed_support_frames==0 and data.failed_work_contact_frames==0
		report.passed=report.passed and data.passed
		report.cases.append(data)
		print("WALL_KINEMATIC_CASE ",JSON.stringify({"side":side,"lean":lean,"passed":data.passed,"states":data.states,"completed":data.completed,"supports":data.minimum_supports,"failed_support_frames":data.failed_support_frames,"failed_work_contact_frames":data.failed_work_contact_frames,"maximum_front_target_error":data.maximum_front_target_error,"maximum_foot_step":data.maximum_foot_step,"maximum_length_error":data.maximum_length_error,"maximum_joint_gap":data.maximum_joint_gap}))
		if is_instance_valid(cat): cat.queue_free()
		await process_frame
		game.active_cat=null
		game.departing_cat=null
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	report.source_hashes_after={}
	for path in report.source_hashes:
		report.source_hashes_after[path]=FileAccess.get_sha256("res://"+path)
	report.sources_unchanged=report.source_hashes_after==report.source_hashes
	report.passed=report.passed and report.sources_unchanged
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	game.free()
	print("WALL_KINEMATIC ",report.passed," lean=",lean," report=",output)
	quit(0 if report.passed else 1)
