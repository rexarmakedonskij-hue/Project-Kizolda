extends SceneTree
# Isolated composition experiment. The production hand script and mesh are never written.
# Each view gets a fresh seated cat and the actual petting controller. Camera changes
# for comparison screenshots happen between manual ticks, with no forced hand samples.
const POLES := {
	"current": Vector3(1, 1.2, 1.5),
	"side": Vector3(2, 1.0, -.8),
	"back": Vector3(2, .8, -1.5)
}
const SOURCE_POLE := "var pole := Vector3(1, 1.2, 1.5)"
const SOURCES := [
	"player/petting_hand.gd", "player/petting_surface.gd", "player/player.gd",
	"player/player.tscn", "main/main.gd", "main/main.tscn", "cats/cat.gd",
	"cats/cat.tscn", "cats/desktop_behavior.gd", "cats/pose_player.gd",
	"cats/desktop_poses.gd", "cats/desktop_foot_contact.gd",
	"cats/grounded_gait.gd", "cats/tail_motion.gd", "cats/wall_support.gd",
	"assets/models/glb/godot_mvp/player_arm.glb",
	"assets/models/glb/godot_mvp/cat_reference.fbx", "tests/hand_pole_trial.gd"
]
var game
var folder := "res://tests/results/hand-pole-trial"
var selected_pole := "all"
var measure_geometry := false
var model_name := "player_arm"
var reports: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			folder = "res://tests/results/" + argument.trim_prefix("--folder=")
		elif argument.begins_with("--pole="):
			selected_pole = argument.trim_prefix("--pole=")
		elif argument == "--geometry":
			measure_geometry = true
		elif argument.begins_with("--model="):
			model_name=argument.trim_prefix("--model=")
	if selected_pole != "all" and not POLES.has(selected_pole):
		push_error("Unknown pole; use current, side, back, or all")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(folder)
	var source_before: Dictionary = source_hashes()
	var original: String = FileAccess.get_file_as_string("res://player/petting_hand.gd")
	if model_name!="player_arm":
		original=original.replace("res://assets/models/glb/godot_mvp/player_arm.glb","res://assets/models/glb/godot_mvp/"+model_name+".glb")
	if original.count(SOURCE_POLE) != 1:
		push_error("Production elbow pole line changed; isolated replacement refused")
		quit(2)
		return
	for pole_name in POLES:
		if selected_pole != "all" and pole_name != selected_pole:
			continue
		var pole: Vector3 = POLES[pole_name]
		var replacement := "var pole := Vector3(%s, %s, %s)" % [pole.x, pole.y, pole.z]
		var trial_source: String = original.replace(SOURCE_POLE, replacement)
		var trial_script := GDScript.new()
		trial_script.source_code = trial_source
		var compile_error: int = trial_script.reload()
		if compile_error != OK:
			failures.append({"pole": pole_name, "compile_error": compile_error})
			continue
		for view_name in ["ordinary", "aimed"]:
			await run_case(str(pole_name), pole, view_name, trial_script, digest(trial_source))
	var source_after: Dictionary = source_hashes()
	var unchanged: bool = source_before == source_after
	var valid: bool = failures.is_empty() and unchanged
	var file := FileAccess.open(folder + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"harness_valid": valid,
		"scope": "Comparison evidence, not artistic acceptance. The in-memory script changes the elbow pole and the explicitly selected model. Physical arm lengths, contact timings and actual pet controller are unchanged. Ordinary camera acceptance/cancellation is observed, never forced.",
		"selected_pole": selected_pole, "model":model_name, "geometry_enabled": measure_geometry,
		"source_sha256_before": source_before, "source_sha256_after": source_after,
		"sources_unchanged": unchanged, "failures": failures, "cases": reports
	}, "  "))
	print("HAND_POLE_TRIAL_FINISHED cases=", reports.size(), " valid=", valid)
	quit(0 if valid else 1)

func run_case(pole_name: String, pole: Vector3, view_name: String, trial_script: GDScript, trial_sha: String) -> void:
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build = true
	game.start_shift()
	game.set_process(false)
	game.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.player.pet_hand.free()
	var hand = trial_script.new()
	game.player.pet_hand = hand
	game.player.add_child(hand)
	hand.set_process(false)
	game._spawn_cat("keyboard")
	var cat = game.active_cat
	cat.set_process(false)
	for tick in 3600:
		if cat.desktop.state == "seated":
			break
		cat._process(1.0 / 60.0)
	if cat.desktop.state != "seated":
		failures.append({"pole": pole_name, "view": view_name, "error": "Cat never reached seated state"})
		game.free()
		return
	cat._process(.4)
	var camera: Camera3D = game.player.camera
	var ordinary_transform: Transform3D = camera.global_transform
	if view_name == "aimed":
		camera.look_at(cat.global_position + Vector3.UP * .3)
	var case_folder: String = folder + "/" + pole_name + "-" + view_name
	DirAccess.make_dir_recursive_absolute(case_folder)
	var can_see_before: bool = game.player.can_see(cat)
	game._on_shoo_requested()
	var report := {
		"pole_name": pole_name, "pole": vector(pole), "view": view_name,
		"in_memory_script_sha256": trial_sha,
		"ordinary_camera_transform": str(ordinary_transform),
		"camera_transform_at_request": str(camera.global_transform),
		"can_see_before_request": can_see_before, "request_accepted": hand.active,
		"physical_upper_length_m": hand.upper_length,
		"physical_forearm_length_m": hand.forearm_length,
		"length_s": hand.LENGTH, "contact_start_s": hand.CONTACT_START,
		"contact_end_s": hand.CONTACT_END, "samples": []
	}
	if not hand.active:
		game._process(0)
		await screenshot(case_folder + "/request-rejected.png")
		report["rejection_status"] = "Actual controller rejected ordinary/aimed gaze; no override was applied."
		reports.append(report)
		game.free()
		await process_frame
		return
	var stages := [
		{"name": "first-contact", "time": hand.CONTACT_START + .00001},
		{"name": "cycle-lift", "time": hand.CONTACT_START + (hand.CONTACT_END-hand.CONTACT_START)*.5*.85},
		{"name": "mid-stroke-1.4", "time": 1.4},
		{"name": "end-contact", "time": hand.CONTACT_END + .00001}
	]
	for stage in stages:
		var target_age: float = stage.time
		while cat.desktop.state == "petting" and cat.desktop.elapsed < target_age - .0000001:
			cat._process(minf(1.0 / 60.0, target_age - cat.desktop.elapsed))
		game._process(0)
		hand.skeleton.force_update_all_bone_transforms()
		cat.pose_player.skeleton.force_update_all_bone_transforms()
		await process_frame
		await RenderingServer.frame_post_draw
		var sample: Dictionary = composition(cat, hand, camera)
		sample["stage"] = stage.name
		sample["requested_age_s"] = target_age
		sample["hand_age_s"] = hand.age
		sample["desktop_age_s"] = cat.desktop.elapsed
		sample["desktop_state"] = cat.desktop.state
		sample["hand_active"] = hand.active
		sample["touching"] = hand.touching
		sample["cancelled"] = hand.cancelled
		if measure_geometry and hand.active:
			sample["actual_gpu_scalp"] = load("res://tests/hand_scalp_measure.gd").measure(cat, hand)
		var stem: String = case_folder + "/" + str(stage.name)
		root.get_texture().get_image().save_png(stem + ".png")
		var visible_before: bool = hand.visible
		hand.visible = false
		await screenshot(stem + "-without-hand.png")
		hand.visible = visible_before
		var previous: Transform3D = camera.global_transform
		camera.global_position = Vector3(.70, 1.95, -.60)
		camera.look_at(cat.global_position + Vector3.UP * .38)
		await screenshot(stem + "-quarter.png")
		camera.global_transform = previous
		report.samples.append(sample)
		if sample.maximum_joint_length_error_m > .0001:
			failures.append({"pole": pole_name, "view": view_name, "stage": stage.name, "joint_error_m": sample.maximum_joint_length_error_m})
		print("HAND_POLE_STAGE ", pole_name, " ", view_name, " ", stage.name, " age=", hand.age, " cancelled=", hand.cancelled)
	# Finish using the same original-view controller, so cancellation/completion
	# is recorded rather than being bypassed by comparison-camera screenshots.
	for tick in 240:
		if not hand.active:
			break
		cat._process(1.0 / 60.0)
	report["finished"] = hand.finished
	report["cancelled_at_end"] = hand.cancelled
	report["desktop_state_at_end"] = cat.desktop.state
	reports.append(report)
	game.free()
	await process_frame

func screenshot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func composition(cat, hand, camera: Camera3D) -> Dictionary:
	var sk: Skeleton3D = hand.skeleton
	var shoulder: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("upper_arm")).origin)
	var elbow: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("forearm")).origin)
	var wrist: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("palm")).origin)
	var upper_error: float = absf(shoulder.distance_to(elbow) - hand.upper_length)
	var forearm_error: float = absf(elbow.distance_to(wrist) - hand.forearm_length)
	var arm_meshes: Dictionary = {}
	var hand_triangles: Array = []
	var minimum_camera_distance := INF
	for mesh in hand.model.find_children("*", "MeshInstance3D", true, false):
		var baked: ArrayMesh = mesh.bake_mesh_from_current_skeleton_pose()
		var world_points: Array = []
		for surface in baked.get_surface_count():
			var arrays: Array = baked.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var surface_world: Array = []
			for vertex in points:
				var world_point: Vector3 = mesh.to_global(vertex)
				world_points.append(world_point)
				surface_world.append(world_point)
				minimum_camera_distance = minf(minimum_camera_distance, camera.global_position.distance_to(world_point))
			for triangle in indices.size() / 3:
				hand_triangles.append([surface_world[indices[triangle*3]], surface_world[indices[triangle*3+1]], surface_world[indices[triangle*3+2]]])
		arm_meshes[str(mesh.name)] = projected_bounds(world_points, camera)
	var cat_sk: Skeleton3D = cat.pose_player.skeleton
	var head_center: Vector3 = cat_sk.to_global(cat_sk.get_bone_global_pose(cat_sk.find_bone("head")).origin)
	var head_points: Array = []
	for mesh in cat.model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			continue
		var baked: ArrayMesh = mesh.bake_mesh_from_current_skeleton_pose()
		for surface in baked.get_surface_count():
			var source: Array = mesh.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
			var binds: PackedInt32Array = source[Mesh.ARRAY_BONES]
			for index in points.size():
				var head_weight := 0.0
				for slot in 4:
					var bind: int = binds[index*4+slot]
					var bone_name: String = str(mesh.skin.get_bind_name(bind))
					if bone_name.is_empty():
						bone_name = cat_sk.get_bone_name(mesh.skin.get_bind_bone(bind))
					if bone_name == "head":
						head_weight += weights[index*4+slot]
				if head_weight >= .95:
					head_points.append(mesh.to_global(points[index]))
	var left_tip := Vector3(0, -INF, 0)
	var right_tip := Vector3(0, -INF, 0)
	var crown := Vector3(0, -INF, 0)
	for point in head_points:
		var lateral: float = point.x - head_center.x
		if lateral < -.035 and point.y > left_tip.y:
			left_tip = point
		elif lateral > .035 and point.y > right_tip.y:
			right_tip = point
		elif absf(lateral) <= .035 and point.y > crown.y:
			crown = point
	var landmarks := {"shoulder": projected_point(shoulder, camera), "elbow": projected_point(elbow, camera), "wrist": projected_point(wrist, camera), "contact": projected_point(hand.contact, camera), "head_bone": projected_point(head_center, camera)}
	for entry in [["ear_screen_left_tip", left_tip], ["ear_screen_right_tip", right_tip], ["central_crown", crown]]:
		var point: Vector3 = entry[1]
		if not point.is_finite():
			continue
		var marker: Dictionary = projected_point(point, camera)
		marker["hand_occludes_actual_point"] = hand.visible and segment_hits_hand(camera.global_position, point, hand_triangles)
		landmarks[entry[0]] = marker
	return {
		"camera_world": vector(camera.global_position), "camera_fov_degrees": camera.fov,
		"camera_rotation_radians": vector(camera.global_rotation), "landmarks": landmarks,
		"actual_gpu_arm_mesh_projected_bounds": arm_meshes,
		"actual_gpu_head_weighted_projected_bounds": projected_bounds(head_points, camera),
		"minimum_arm_vertex_camera_distance_m": minimum_camera_distance,
		"upper_joint_error_m": upper_error, "forearm_joint_error_m": forearm_error,
		"maximum_joint_length_error_m": maxf(upper_error, forearm_error),
		"cat_yaw_radians": cat.global_rotation.y,
		"ear_locator_scope": "Highest actual GPU-deformed head-owned vertex on each world-X side of this front-facing seated fixture. Central crown uses |X-head X|<=35 mm. Point occlusion intersects actual posed hand triangles; projected bounds alone do not establish occlusion or artistic acceptance."
	}

func projected_bounds(points: Array, camera: Camera3D) -> Dictionary:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var behind := 0
	var outside := 0
	for point in points:
		if camera.is_position_behind(point):
			behind += 1
			continue
		var screen: Vector2 = camera.unproject_position(point)
		low = low.min(screen)
		high = high.max(screen)
		if not Rect2(Vector2.ZERO, Vector2(root.size)).has_point(screen):
			outside += 1
	return {"minimum_px": [low.x, low.y] if low.is_finite() else null, "maximum_px": [high.x, high.y] if high.is_finite() else null, "vertices": points.size(), "behind_camera": behind, "outside_viewport": outside}

func projected_point(point: Vector3, camera: Camera3D) -> Dictionary:
	var screen: Vector2 = camera.unproject_position(point)
	return {"world_m": vector(point), "screen_px": [screen.x, screen.y], "behind_camera": camera.is_position_behind(point), "inside_viewport": Rect2(Vector2.ZERO, Vector2(root.size)).has_point(screen), "camera_distance_m": camera.global_position.distance_to(point)}

func segment_hits_hand(start: Vector3, end: Vector3, triangles: Array) -> bool:
	var direction: Vector3 = end - start
	for triangle in triangles:
		var ab: Vector3 = triangle[1] - triangle[0]
		var ac: Vector3 = triangle[2] - triangle[0]
		var p: Vector3 = direction.cross(ac)
		var determinant: float = ab.dot(p)
		if absf(determinant) < .0000000001:
			continue
		var offset: Vector3 = start - triangle[0]
		var u: float = offset.dot(p) / determinant
		if u < 0 or u > 1:
			continue
		var q: Vector3 = offset.cross(ab)
		var v: float = direction.dot(q) / determinant
		if v < 0 or u + v > 1:
			continue
		var fraction: float = ac.dot(q) / determinant
		if fraction > .00001 and fraction < .99999:
			return true
	return false

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func digest(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func source_hashes() -> Dictionary:
	var result := {}
	for path in SOURCES:
		result[path] = FileAccess.get_sha256("res://" + path)
	if model_name!="player_arm":
		var candidate: String="assets/models/glb/godot_mvp/"+model_name+".glb"
		result[candidate]=FileAccess.get_sha256("res://"+candidate)
	return result
