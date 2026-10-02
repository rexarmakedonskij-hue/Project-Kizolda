extends SceneTree
var game
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func fresh() -> void:
	paused = false
	if is_instance_valid(game): game.free()
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_shift()
	game.set_process(false)
	game.next_cat_in = 1000
func spawn(kind: String):
	game._spawn_cat(kind)
	var cat = game.active_cat
	cat.set_process(false)
	return cat
func reach(cat, state: String) -> bool:
	for i in 3600:
		if not is_instance_valid(cat) or cat.is_queued_for_deletion(): return false
		if cat.desktop.state == state: return true
		cat._process(1.0/60)
	return false
func chase(cat) -> bool:
	game.player.camera.look_at(cat.global_position+Vector3.UP*(.3 if cat.desktop != null else .75))
	return cat.try_to_chase(game.player)
func paw(cat, name: String) -> Vector3:
	var sk: Skeleton3D = cat.pose_player.skeleton
	sk.force_update_all_bone_transforms()
	return sk.to_global(sk.get_bone_global_pose(sk.find_bone(name)).origin)
func lowest_skin(cat) -> float:
	var sk: Skeleton3D=cat.pose_player.skeleton
	sk.force_update_all_bone_transforms()
	var mesh: MeshInstance3D=cat.model.find_child("mesh_cat",true,false)
	var transforms: Array[Transform3D]=[]
	for bind in mesh.skin.get_bind_count():
		var bone:=sk.find_bone(mesh.skin.get_bind_name(bind))
		if bone<0: bone=mesh.skin.get_bind_bone(bind)
		transforms.append(sk.global_transform*sk.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
	var lowest:=INF
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array=mesh.mesh.surface_get_arrays(surface)
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var p:=Vector3.ZERO
			for slot in 4:
				var weight: float=arrays[Mesh.ARRAY_WEIGHTS][vertex*4+slot]
				if weight>0:
					p+=(transforms[arrays[Mesh.ARRAY_BONES][vertex*4+slot]]*arrays[Mesh.ARRAY_VERTEX][vertex])*weight
			lowest=minf(lowest,p.y)
	return lowest
func run() -> void:
	await fresh()
	var cat = spawn("keyboard")
	check(reach(cat,"warning"),"Keyboard: walk reaches jump warning")
	check(not game.keyboard_blocked,"Warning does not block work")
	check(reach(cat,"jump_up"),"Keyboard: crouch leads to jump")
	var launch_direction: Vector3=cat.desktop.jump_to-cat.desktop.jump_from
	launch_direction.y=0
	check(cat.global_basis.z.dot(launch_direction.normalized())>.99,"Cat faces the landing point at takeoff")
	var before: Vector3 = cat.position
	var continuous := true
	for i in 6:
		var previous: Vector3 = cat.position
		cat._process(1.0/60)
		# Launch velocity is about 5.2 units/s; include horizontal motion at 60 Hz.
		continuous = continuous and cat.position.distance_to(previous)<.095
	check(cat.position.y>before.y and continuous,"Jump rises without frame-to-frame teleports")
	check(reach(cat,"seated"),"Keyboard: landing and approach lead to sitting")
	check(game.keyboard_blocked and not game.working,"Sitting interrupts work and blocks keyboard")
	cat._process(.4)
	var supported := true
	for limb in ["front", "back"]:
		for side in ["left", "right"]:
			var foot := paw(cat,"leg_%s_%s_4" % [limb,side])
			supported = supported and absf(foot.y-1.035)<.018
	check(supported,"Seated cat keeps all four paws on the keyboard surface")
	var lowest:=lowest_skin(cat)
	print("SEATED_SKIN_LOWEST ",lowest)
	check(lowest>1.015,"Seated torso and haunches stay above the keyboard")
	var sk: Skeleton3D=cat.pose_player.skeleton
	var head:=sk.find_bone("head")
	var rest_head: Basis=(sk.global_basis*sk.get_bone_global_rest(head).basis).orthonormalized()
	var seated_head: Basis=(sk.global_basis*sk.get_bone_global_pose(head).basis).orthonormalized()
	check(rest_head.y.dot(seated_head.y)>.99,"Sitting keeps the head level instead of tilting with the torso")
	for transition in ["SitDown","Stand"]:
		cat.pose_player.play(transition)
		var clip: Animation=cat.animation.get_animation(transition)
		var joint_gap:=0.0
		var jump:=0.0
		var previous: Dictionary={}
		for sample in 49:
			cat.animation.seek(clip.length*sample/48.0,true)
			sk.force_update_all_bone_transforms()
			for limb in ["front","back"]:
				for side in ["left","right"]:
					for segment in range(2,5):
						var child:=sk.find_bone("leg_%s_%s_%d"%[limb,side,segment])
						var parent:=sk.get_bone_parent(child)
						var point:=sk.to_global(sk.get_bone_global_pose(child).origin)
						var expected:=sk.to_global(sk.get_bone_global_pose(parent)*sk.get_bone_rest(child).origin)
						joint_gap=maxf(joint_gap,point.distance_to(expected))
						if previous.has(child): jump=maxf(jump,point.distance_to(previous[child]))
						previous[child]=point
		print("LEG_TRANSITION ",transition," max_gap=",joint_gap," max_step=",jump)
		check(joint_gap<.004,"%s keeps every knee, hock and ankle connected"%transition)
		check(jump<.06,"%s moves the leg joints without a frame discontinuity"%transition)
	cat.pose_player.play("Sit")
	cat.pose_player.advance(.4)
	game._on_work_requested()
	var selected: int = game.inbox.selected
	game._choose_email(0)
	game._submit_email()
	check(game.inbox.selected==selected and game.quota==0 and game.hud.submit_button.disabled,"Blocked keyboard rejects mouse actions and reward")
	game._on_work_requested()
	check(not chase(cat),"Seated cat requires petting instead of shooing")
	game.player.camera.look_at(cat.global_position+Vector3.UP*.3)
	game._on_shoo_requested()
	check(cat.desktop.state=="petting" and game.active_cat==cat and game.keyboard_blocked and game.hud.spray.color.a==0,"Space pets the seated cat without spray or early keyboard release")
	cat._process(.3)
	var pet_age: float = cat.desktop.elapsed
	game._on_shoo_requested()
	check(cat.desktop.elapsed==pet_age,"Repeated pet input does not restart the reaction")
	game.toggle_pause()
	cat.set_process(true)
	await create_timer(.06,true).timeout
	check(cat.desktop.elapsed==pet_age,"Pause freezes petting")
	cat.set_process(false)
	game.toggle_pause()
	check(reach(cat,"jump_down"),"Seated cat stands and reaches descent")
	launch_direction=cat.desktop.jump_to-cat.desktop.jump_from
	launch_direction.y=0
	check(cat.global_basis.z.dot(launch_direction.normalized())>.99,"Cat faces away from the table before descending")
	check(game.active_cat==null,"Petting finishes with a calm departure")
	game._process(0.0)
	check(not game.keyboard_blocked and not game.hud.work_blocked,"Keyboard unlocks after the last paw clears the laptop")
	check(reach(cat,"depart"),"Descent lands on floor before walking home")
	check(absf(cat.position.y-.06)<.001,"Descent ends at floor height")
	await fresh()
	cat=spawn("keyboard")
	check(reach(cat,"seated"),"Unprompted keyboard visit reaches sitting")
	cat._process(game.RULES.KEYBOARD_LINGER+.05)
	check(game.active_cat==null and game.keyboard_blocked,"Automatic departure keeps keys blocked while cat is still on them")
	check(reach(cat,"jump_down"),"Automatic departure reaches desk edge")
	game._process(0.0)
	check(not game._work_blocked(),"Automatic departure frees keyboard after cat clears it")
	await fresh()
	cat=spawn("cup")
	check(reach(cat,"touch"),"Cup: cat reaches warning taps")
	var touches_cup := false
	for i in 13:
		cat.pose_player.play("Touch")
		cat.pose_player.advance(i*.1)
		# Complete facing before measuring the animated paw against the cup.
		cat.rotation.y=-PI/2
		var foot := paw(cat,"leg_front_left_4_end")
		var cup: Vector3 = game.room.desk.CUP_POSITION
		var distance := Vector2(foot.x-cup.x,foot.z-cup.z).length()
		touches_cup = touches_cup or (distance < .14 and distance > .075 and foot.y > cup.y+.04 and foot.y<cup.y+.225)
	check(touches_cup,"Tapping paw reaches the cup side above the table")
	check(not game.room.desk.dirty,"Cup remains upright during warning")
	check(chase(cat),"Cup warning can be interrupted")
	check(cat.animation.current_animation=="Idle","Standing cat leaves the cup without first snapping into a seated pose")
	for i in 300: cat._process(1.0/60)
	check(not game.room.desk.dirty,"Early interruption prevents spill")
	await fresh()
	cat=spawn("cup")
	check(reach(cat,"spill"),"Uninterrupted tapping tips the cup")
	check(game.room.desk.dirty and game.hud.work_blocked,"Spill blocks work")
	game.room.desk._process(.7)
	check(game.room.desk.cup.rotation.z>1.5 and game.room.desk.puddle.visible,"Cup tips away from the pushing paw and coffee shows consequence")
	game._start_cleaning()
	game._process(1.0)
	check(game.cleaning and game.clean_elapsed==1,"Cleanup takes time")
	game.toggle_pause()
	var progress: float=game.clean_elapsed
	game.set_process(true)
	await create_timer(.08,true).timeout
	check(game.clean_elapsed==progress,"Pause freezes cleanup")
	game.set_process(false)
	game.toggle_pause()
	game._on_work_requested()
	check(not game.cleaning and game.room.desk.dirty,"Changing attention interrupts cleanup")
	game._start_cleaning()
	game._process(game.RULES.CLEAN_DURATION)
	check(not game.room.desk.dirty and not game.hud.work_blocked,"Complete cleanup restores desk and work")
	game._start_cleaning()
	check(not game.cleaning,"Clean desk cannot start another cleanup")
	await fresh()
	cat=spawn("keyboard")
	check(reach(cat,"jump_up"),"Interrupt test reaches jump")
	cat._process(.2)
	before=cat.position
	check(chase(cat),"Cat can be shooed in midair")
	check(cat.position==before and cat.desktop.state=="jump_up","Midair interruption does not teleport")
	check(reach(cat,"jump_down"),"Interrupted jump safely lands and returns")
	game._end_shift(false)
	before=cat.position
	cat._process(1)
	check(cat.position==before,"Result freezes descent")
	game.free()
	await create_timer(.1).timeout
	print("DESKTOP_CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
