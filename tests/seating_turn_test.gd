extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if value: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build=true
	game.start_shift()
	game.set_process(false)
	game.player.enabled=false
	game._spawn_cat("keyboard")
	var cat=game.active_cat
	cat.set_process(false)
	for frame in 3600:
		if cat.desktop.state=="align": break
		cat._process(1.0/60)
	check(cat.desktop.state=="align" and game.keyboard_blocked,"The keyboard is occupied while the cat finds its seat")
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	game._on_shoo_requested()
	check(cat.desktop.state=="align" and cat.desktop.pet_pending and not cat.leaving and not game.player.pet_hand.active,"Early Space queues affection without shooing or starting the hand during the turn")
	var turn_seconds := 0.0
	var max_plant_drift := 0.0
	var previous := {}
	while cat.desktop.state=="align" and turn_seconds<5:
		cat._process(1.0/60)
		turn_seconds+=1.0/60
		for foot in cat.grounded_gait.feet:
			if foot.ready and foot.planted:
				if previous.has(foot.name): max_plant_drift=maxf(max_plant_drift,foot.output.distance_to(previous[foot.name]))
				previous[foot.name]=foot.output
			else: previous.erase(foot.name)
	check(turn_seconds<2 and max_plant_drift<.001,"The planted turn finishes within two seconds without sliding support paws")
	check(cat.desktop.state=="pet_wait" and cat.animation.assigned_animation=="SitDown","Queued affection preserves the complete sit-down")
	var sitting_yaw: float=cat.rotation.y
	var seating_time := 0.0
	var hand_waited := true
	while cat.desktop.state=="pet_wait" and seating_time<2:
		hand_waited=hand_waited and not game.player.pet_hand.active
		cat._process(1.0/60)
		seating_time+=1.0/60
	check(hand_waited and seating_time>=.64 and absf(angle_difference(cat.rotation.y,sitting_yaw))<.021,"The hand waits for sitting and the seated body does not pivot on its paws")
	check(cat.desktop.state=="petting" and game.player.pet_hand.active and game.keyboard_blocked,"Affection starts once seated and keeps the keyboard occupied")
	game.free()
	await process_frame
	print("SEATING_TURN_CHECKS: ",checks-failures," passed, ",failures," failed")
	quit(0 if failures==0 else 1)
