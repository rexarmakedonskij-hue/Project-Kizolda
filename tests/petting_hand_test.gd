extends SceneTree
var game
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
func fresh(state := "seated"):
	paused = false
	if is_instance_valid(game): game.free()
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game._spawn_cat("keyboard")
	var cat = game.active_cat
	cat.set_process(false)
	for i in 3600:
		if cat.desktop.state == state: break
		cat._process(1.0/60)
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	return cat
func run():
	var cat = await fresh()
	var hand = game.player.pet_hand
	check(game.player.camera.global_position.z < -.85 and game.player.camera.global_position.z > -1.02, "Seated viewpoint is close to the laptop at the front edge of the desk")
	check(absf(hand.upper_length+hand.forearm_length-.64)<.002, "Arm rig is physically shortened to 64 cm before the hand")
	var forearm_only := true
	for mesh in hand.model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			for i in arrays[Mesh.ARRAY_WEIGHTS].size():
				if arrays[Mesh.ARRAY_WEIGHTS][i] <= .0001: continue
				var bind: int = arrays[Mesh.ARRAY_BONES][i]
				var bone: int = hand.skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0: bone = mesh.skin.get_bind_bone(bind)
				forearm_only = forearm_only and hand.skeleton.get_bone_name(bone) not in ["upper_arm", "elbow_helper"]
	check(forearm_only, "Visible model contains only forearm and hand")
	var contacts := [0]
	cat.pet_contact.connect(func(_cat): contacts[0] += 1)
	game._on_shoo_requested()
	check(hand.active and hand.visible and not hand.touching, "Reach starts before contact")
	var smooth := true
	var reachable := true
	var clear := true
	var contact_follow := true
	var joints_connected := true
	var previous: Vector3 = hand.wrist
	var max_length_error := 0.0
	var min_clearance := 100.0
	var maximum_fit_residual := 0.0
	var fit_usec := []
	var tick_usec := []
	for frame in 162:
		var started:=Time.get_ticks_usec()
		cat._process(1.0/60)
		tick_usec.append(Time.get_ticks_usec()-started)
		if hand.active:
			smooth = smooth and hand.wrist.distance_to(previous) < .09
			reachable = reachable and hand.wrist.distance_to(hand.shoulder_world) < .64
			for point in [hand.elbow_world, hand.wrist]:
				if point.z < -.925:
					clear = clear and point.y > 1.075
					min_clearance = minf(min_clearance, point.y)
			if hand.touching:
				var cycle=fmod((hand.age-hand.CONTACT_START)/(hand.CONTACT_END-hand.CONTACT_START)*2,1.0)
				var lift=sin(PI*(cycle-.7)/.3)*.024 if cycle>=.7 else 0.0
				fit_usec.append(hand.fur_surface.last_correction_usec)
				var residual=absf(hand.fur_surface.palm_correction(hand.FIT_FUR_GAP+lift))
				maximum_fit_residual=maxf(maximum_fit_residual,residual)
				contact_follow = contact_follow and residual<.004
			var sk: Skeleton3D = hand.skeleton
			var wrist_pose := sk.to_global(sk.get_bone_global_pose(sk.find_bone("palm")).origin)
			var elbow_pose := sk.to_global(sk.get_bone_global_pose(sk.find_bone("forearm")).origin)
			joints_connected = joints_connected and wrist_pose.distance_to(hand.wrist)<.002 and elbow_pose.distance_to(hand.elbow_world)<.002
			joints_connected = joints_connected and absf(wrist_pose.distance_to(elbow_pose)-hand.forearm_length)<.002
			max_length_error = maxf(max_length_error, absf(wrist_pose.distance_to(elbow_pose)-hand.forearm_length))
		previous = hand.wrist
		if frame == 17: check(contacts[0] == 0, "Purr waits for touch")
		if frame == 45:
			var elapsed: float = cat.desktop.elapsed
			game._on_shoo_requested()
			check(cat.desktop.elapsed == elapsed, "Repeat preserves current stroke")
			game.toggle_pause()
			cat.set_process(true)
			await create_timer(.06, true).timeout
			check(cat.desktop.elapsed == elapsed and hand.age == elapsed, "Pause freezes cat and hand")
			cat.set_process(false)
			game.toggle_pause()
		if frame == 120: check(game.active_cat == cat, "Cat waits for withdrawal")
	cat._process(1.0/60)
	check(smooth and reachable, "Continuous motion stays within arm length")
	print("ARM_MEASURES lengths=",hand.upper_length,"/",hand.forearm_length," error=",max_length_error," min_y=",min_clearance)
	fit_usec.sort()
	tick_usec.sort()
	print("HAND_RUNTIME fit_residual_m=",maximum_fit_residual," fit_p95_usec=",fit_usec[floori(fit_usec.size()*.95)]," tick_p95_usec=",tick_usec[floori(tick_usec.size()*.95)]," fit_samples=",fit_usec.size())
	check(joints_connected, "Rendered skeleton follows wrist and elbow without gaps")
	check(clear, "Elbow and wrist clear desktop")
	check(contact_follow and contacts[0] == 1, "Fitted palm follows animated fur and triggers purr once")
	check(not hand.visible and game.active_cat == null, "Withdrawal precedes departure")
	cat = await fresh("settle")
	hand = game.player.pet_hand
	game._on_shoo_requested()
	check(cat.desktop.state == "pet_wait" and not hand.active, "Early input waits for settling")
	check(game.keyboard_blocked,"Queued affection keeps the occupied keyboard blocked")
	for frame in 60: cat._process(1.0/60)
	check(hand.active, "Queued petting starts after settling")
	game._end_shift(false)
	check(not hand.visible and not hand.active, "Result removes hand")
	cat = await fresh()
	hand = game.player.pet_hand
	game._on_shoo_requested()
	cat._process(1.2)
	var before: Vector3 = hand.wrist
	game.player.camera.rotation.y += PI
	cat._process(1.0/60)
	check(hand.cancelled and hand.wrist.distance_to(before) < .01, "Turn away withdraws without teleport")
	for frame in 45: cat._process(1.0/60)
	check(not hand.active and game.active_cat == null, "Turn-away return finishes before departure")
	cat = await fresh()
	hand = game.player.pet_hand
	game._on_shoo_requested()
	cat._process(1.2)
	cat.free()
	game.active_cat = null
	hand._process(1.0/60)
	check(hand.active, "Removed target starts gentle return")
	for frame in 45: hand._process(1.0/60)
	check(not hand.visible and not hand.active, "Removed target leaves no orphan hand")
	hand.pose(game.player.global_position+hand.SHOULDER, Vector3(4, 2, -4))
	var sk: Skeleton3D = hand.skeleton
	var palm := sk.to_global(sk.get_bone_global_pose(sk.find_bone("palm")).origin)
	var elbow := sk.to_global(sk.get_bone_global_pose(sk.find_bone("forearm")).origin)
	check(absf(palm.distance_to(elbow)-hand.forearm_length)<.002 and palm.distance_to(hand.shoulder_world)<.64,
		"Out-of-range target cannot stretch the rendered arm")
	game.free()
	await process_frame
	print("PETTING_HAND_CHECKS: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
