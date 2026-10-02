extends SceneTree
# Complete the shift through routed mouse and keyboard events, without calling
# the gameplay handlers. Read-only state provides aim and an oracle for answers.
var game
var events := {}
var pets := 0
var cleaned := false
var spilled := false
var actions := []
var profile := "standard"
var review_pass := "pass3"
var petted_ids := {}
var initial_source_hashes := {}
func _initialize(): call_deferred("run")
func source_hashes() -> Dictionary:
	var hashes := {}
	for path in ["main/main.gd", "ui/hud.gd", "cats/cat.gd", "cats/desktop_behavior.gd", "cats/desktop_poses.gd", "cats/scratch_poses.gd", "cats/pose_player.gd", "cats/grounded_gait.gd", "cats/tail_motion.gd", "cats/wall_support.gd", "cats/desktop_foot_contact.gd", "player/player.gd", "player/petting_hand.gd", "player/petting_surface.gd", "systems/shift_rules.gd", "systems/inbox.gd", "assets/models/glb/godot_mvp/cat_reference.fbx", "assets/models/glb/godot_mvp/player_arm.glb"]:
		if FileAccess.file_exists("res://" + path): hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes

func record_sources(report: Dictionary) -> bool:
	var final_hashes := source_hashes()
	report.source_hashes_at_start = initial_source_hashes
	report.source_hashes_at_end = final_hashes
	report.sources_unchanged = initial_source_hashes == final_hashes
	return report.sources_unchanged
func press(key: Key):
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = down
		root.push_input(event,true)
		await process_frame
func click(control: Control):
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	await process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		root.push_input(event,true)
		await process_frame
func aim(cat):
	var height := .3 if cat.desktop != null else .75
	var direction: Vector3 = (cat.global_position+Vector3.UP*height-game.player.camera.global_position).normalized()
	var yaw := clampf(atan2(-direction.x,-direction.z),-1.9,1.9)
	var pitch := clampf(asin(direction.y),-.65,.65)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2((game.player.view_pivot.rotation.y-yaw)/.0025,(game.player.pitch-pitch)/.0025)
	root.push_input(motion,true)
func run():
	if DisplayServer.get_name() == "headless": quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="): profile=argument.trim_prefix("--profile=")
		if argument.begins_with("--review-pass="): review_pass=argument.trim_prefix("--review-pass=")
	seed(418)
	initial_source_hashes = source_hashes()
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build = true # Hidden-window focus must not pause this harness.
	await click(game.hud.action)
	Engine.time_scale = 8
	if profile == "delayed":
		await run_delayed()
		return
	var deadline := Time.get_ticks_msec()+45000
	while not game.finished and Time.get_ticks_msec()<deadline:
		await process_frame
		var cat = game.active_cat
		if is_instance_valid(cat):
			var kind: String = cat.desktop.kind if cat.desktop != null else "wall"
			events[kind] = true
			var delayed:=profile=="relaxed"
			var keyboard_ready: bool=kind=="keyboard" and (cat.desktop.state=="seated" and cat.desktop.elapsed> (1.3 if delayed else 0))
			if profile=="early" and kind=="keyboard":
				keyboard_ready=cat.desktop.state=="settle" and cat.desktop.elapsed>.15
			var wall_ready: bool=kind=="wall" and not cat.warning and cat.scratch_age>(1.2 if delayed else 0)
			var cup_ready: bool=profile=="early" and kind=="cup" and cat.desktop.state=="touch" and cat.desktop.elapsed>.3
			var react: bool=keyboard_ready or wall_ready or cup_ready
			if react:
				if game.working: await press(KEY_F)
				aim(cat)
				await process_frame
				await press(KEY_SPACE)
				actions.append({"key":"space","kind":kind,"time":game.shift_time})
			if kind=="keyboard" and is_instance_valid(cat) and game.player.pet_hand.touching and not petted_ids.has(cat.get_instance_id()):
				petted_ids[cat.get_instance_id()]=true
				pets+=1
		if game.room.desk.dirty:
			spilled = true
			if not game.keyboard_blocked and not game.cleaning:
				if game.working: await press(KEY_F)
				await press(KEY_E)
				actions.append({"key":"E","time":game.shift_time})
		elif spilled: cleaned = true
		if not game._work_blocked() and game.quota<100:
			if not game.working: await press(KEY_F)
			if game.inbox.resolved:
				if not game.hud.next_button.disabled: await click(game.hud.next_button)
			elif game.hud.work_panel.visible:
				var answer: int = game.inbox.current.options.find(game.inbox.current.answer)
				await click(game.hud.email_options[answer])
				await click(game.hud.submit_button)
				actions.append({"email":game.inbox.index,"time":game.shift_time})
	Engine.time_scale = 1
	var cup_ok: bool=not spilled if profile=="early" else cleaned
	var passed: bool = game.finished and game.quota==100 and game.wall_damage<game.RULES.DAMAGE_LIMIT and pets>0 and cup_ok and events.size()==3
	var report := {"profile":profile,"passed":passed,"finished":game.finished,"quota":game.quota,"damage":game.wall_damage,"petted":pets,"spilled":spilled,"cleaned":cleaned,"events":events,"actions":actions,"elapsed":game.shift_time}
	passed = record_sources(report) and passed
	report.passed = passed
	var file := FileAccess.open("res://tests/results/real-input-shift-%s-%s.json"%[review_pass,profile],FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("REAL_INPUT_SHIFT ",JSON.stringify(report))
	game.free()
	await process_frame
	quit(0 if passed else 1)

func run_delayed():
	# Reading time accumulates only while the current letter is readable.
	# The oracle still supplies answer/aim; delays do not prove human usability.
	const READING_SECONDS := [8.0,10.0,12.0,9.0,11.0]
	var reading := {}
	var reactions := []
	var pending_reactions := {}
	var reacted := {}
	var mail_notices := []
	var wrong_attempts := 0
	var wrong_rejected := false
	var correct_answers := 0
	var correction_started := -1.0
	var pause_evidence := {}
	var last_time: float = game.shift_time
	var deadline := Time.get_ticks_msec()+45000
	while not game.finished and Time.get_ticks_msec()<deadline:
		await process_frame
		var elapsed: float = game.shift_time-last_time
		last_time = game.shift_time
		var index: int = game.inbox.index
		if not game.inbox.resolved and game.working and game.hud.work_panel.visible and not game._work_blocked():
			reading[index] = reading.get(index,0.0)+elapsed
			if pause_evidence.is_empty() and reading[index]>=2.0:
				await press(KEY_ESCAPE)
				var paused_at: float = game.shift_time
				var real_start := Time.get_ticks_msec()
				await create_timer(.18,true,false,true).timeout
				pause_evidence={"paused":paused,"start":paused_at,"end":game.shift_time,"real_ms":Time.get_ticks_msec()-real_start,"frozen":game.shift_time==paused_at}
				await press(KEY_ESCAPE)
		var cat = game.active_cat
		if is_instance_valid(cat):
			var kind: String = cat.desktop.kind if cat.desktop != null else "wall"
			events[kind]=true
			var identifier: int = cat.get_instance_id()
			var cue_visible: bool = game.hud.cat_panel.visible and game.hud.cat_label.visible
			var cue_text: String = game.hud.cat_label.text
			var cue_ready: bool = (kind=="keyboard" and cue_text.contains("КЛАВИАТУРА ЗАНЯТА")) or (kind=="cup" and cue_text.contains("ТРОГАЕТ ЧАШКУ")) or (kind=="wall" and cue_text.contains("ДО УЩЕРБА"))
			var eligible: bool = (kind=="keyboard" and cat.desktop.state in ["settle","seated"]) or (kind=="cup" and cat.desktop.state=="touch") or (kind=="wall" and cat.route.is_empty() and not cat.warning)
			if eligible and cue_visible and cue_ready and not pending_reactions.has(identifier) and not reacted.has(identifier):
				pending_reactions[identifier]={"kind":kind,"cue_time":game.shift_time,"cue":cue_text,"target_delay":2.0+.3*((pending_reactions.size()+reacted.size()+1)%3),"cat_in_aim_at_cue":game.player.can_see(cat)}
			if pending_reactions.has(identifier) and game.shift_time-pending_reactions[identifier].cue_time>=pending_reactions[identifier].target_delay:
				var reaction: Dictionary = pending_reactions[identifier]
				if game.working: await press(KEY_F)
				if is_instance_valid(cat) and cat==game.active_cat:
					aim(cat)
					await process_frame
					reaction["action_time"]=game.shift_time
					reaction["wait_seconds"]=game.shift_time-float(reaction.cue_time)
					await press(KEY_SPACE)
					reaction["accepted"]=game.active_cat!=cat or (is_instance_valid(cat) and cat.desktop!=null and cat.desktop.state in ["pet_wait","petting"])
					actions.append({"key":"space","kind":kind,"time":reaction.action_time})
				else:
					reaction["accepted"]=false
					reaction["missed"]="Cat completed the interaction before the delayed action"
				reactions.append(reaction)
				reacted[identifier]=true
				pending_reactions.erase(identifier)
			if kind=="keyboard" and is_instance_valid(cat) and game.player.pet_hand.touching and not petted_ids.has(identifier):
				petted_ids[identifier]=true
				pets+=1
		if game.room.desk.dirty:
			spilled=true
			if not game.keyboard_blocked and not game.cleaning:
				if game.working: await press(KEY_F)
				await press(KEY_E)
				actions.append({"key":"E","time":game.shift_time})
		elif spilled: cleaned=true
		if not game._work_blocked() and game.quota<100:
			# A persistent UI cue drives opening mail, rather than polling a
			# disabled next button at every frame to discover its release.
			var mail_ready: bool = game.hud.email_ready_label.visible
			if not game.working and (mail_ready or not game.inbox.resolved): await press(KEY_F)
			if game.working and game.inbox.resolved and mail_ready:
				mail_notices.append({"opening_email":game.inbox.index+1,"time":game.shift_time,"visible_text":game.hud.email_ready_label.text})
				await click(game.hud.next_button)
			elif game.working and not game.inbox.resolved and float(reading.get(index,0.0))>=READING_SECONDS[index]:
				var answer: int = game.inbox.current.options.find(game.inbox.current.answer)
				if wrong_attempts==0:
					var quota_before: int = game.quota
					await click(game.hud.email_options[(answer+1)%3])
					await click(game.hud.submit_button)
					wrong_attempts+=1
					wrong_rejected=not game.inbox.resolved and game.quota==quota_before and game.inbox.feedback.begins_with("Проверь")
					correction_started=float(reading.get(index,0.0))
					actions.append({"email":index,"wrong":true,"time":game.shift_time,"rejected":wrong_rejected})
				elif correction_started<0 or float(reading.get(index,0.0))-correction_started>=2.0:
					await click(game.hud.email_options[answer])
					await click(game.hud.submit_button)
					if game.inbox.resolved:
						correct_answers+=1
						correction_started=-1
						actions.append({"email":index,"time":game.shift_time,"read_seconds":reading.get(index,0.0)})
						await press(KEY_F)
		last_time=game.shift_time
	Engine.time_scale=1
	var letters := []
	var reading_complete := reading.size()==5
	for index in range(5):
		var seconds: float = reading.get(index,0.0)
		letters.append({"email":index,"read_seconds":seconds,"required_seconds":READING_SECONDS[index]})
		reading_complete=reading_complete and seconds>=READING_SECONDS[index]
	var cup_ok: bool = not spilled or cleaned
	var reaction_kinds := {}
	var reactions_verified := not reactions.is_empty()
	for reaction in reactions:
		reaction_kinds[reaction.kind]=true
		var wait_seconds: float = reaction.get("wait_seconds",0.0)
		reactions_verified=reactions_verified and reaction.get("accepted",false) and wait_seconds>=2.0 and wait_seconds<=3.001
	reactions_verified=reactions_verified and reaction_kinds.size()==3
	var passed: bool = game.finished and game.quota==100 and game.wall_damage<game.RULES.DAMAGE_LIMIT and pets>0 and cup_ok and events.size()==3 and reading_complete and reactions_verified and wrong_attempts==1 and wrong_rejected and correct_answers==5 and mail_notices.size()==4 and pause_evidence.get("frozen",false)
	var report := {"profile":profile,"passed":passed,"finished":game.finished,"quota":game.quota,"damage":game.wall_damage,"petted":pets,"spilled":spilled,"cleaned":cleaned,"events":events,"actions":actions,"elapsed":game.shift_time,"reading":letters,"reactions":reactions,"reactions_verified":reactions_verified,"mail_notices":mail_notices,"wrong_attempts":wrong_attempts,"wrong_rejected":wrong_rejected,"correct_answers":correct_answers,"pause":pause_evidence,"limitations":"Read-only answer and aiming oracles remain. UI notices, routed controls, reading/reaction delays, correction and pause are verified; subjective usability is not proven."}
	passed = record_sources(report) and passed
	report.passed = passed
	var file := FileAccess.open("res://tests/results/real-input-shift-%s-%s.json"%[review_pass,profile],FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("REAL_INPUT_SHIFT ",JSON.stringify(report))
	game.free()
	await process_frame
	quit(0 if passed else 1)
