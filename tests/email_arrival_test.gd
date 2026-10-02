extends SceneTree
# Verify the notice through the same controls a player uses; the clock is
# positioned near a release instead of waiting 25 seconds for each letter.
class RecordingSound extends Node:
	var played: Array[String] = []
	func play(kind: String) -> void: played.append(kind)
	func play_at(kind: String, _position: Vector3) -> void: played.append(kind)
var game
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if value: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func press(key: Key):
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = down
		root.push_input(event,true)
		await process_frame
func click(control: Control):
	var point := control.get_global_rect().get_center()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		root.push_input(event,true)
		await process_frame
func answer_current():
	await click(game.hud.email_options[game.inbox.current.options.find(game.inbox.current.answer)])
	await click(game.hud.submit_button)
func run():
	if DisplayServer.get_name() == "headless": quit(2); return
	game = load("res://main/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.verifying_build = true
	game.set_process(false)
	game.next_cat_in = 1000
	game.sound.free()
	var recorder := RecordingSound.new()
	game.add_child(recorder)
	game.sound = recorder
	check(not game.hud.email_ready_label.visible,"No unread notice before the shift")
	await click(game.hud.action)
	check(game.hud.email_ready_label.visible,"First available letter is indicated in the room")
	await press(KEY_F)
	check(not game.hud.email_ready_label.visible,"Opening the first letter clears its unread notice")
	await answer_current()
	await press(KEY_F)
	game.shift_time = game.RULES.EMAIL_INTERVAL - .05
	game._process(0)
	check(not game.hud.email_ready_label.visible,"No notice before the next release")
	var sound_count := recorder.played.count("work")
	await press(KEY_ESCAPE)
	game.set_process(true)
	var frozen_time: float = game.shift_time
	await create_timer(.12).timeout
	game.set_process(false)
	check(game.shift_time == frozen_time and not game.hud.email_ready_label.visible,"Pause freezes the clock and the pending arrival")
	await press(KEY_ESCAPE)
	game._process(.1)
	check(game.hud.email_ready_label.visible and game.hud.email_ready_label.is_visible_in_tree(),"New mail is visible outside the laptop at release")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/email-ready-room-pass5.png")
	check(recorder.played.count("work") == sound_count+1,"Release plays one short arrival sound")
	for step in 60: game._process(1.0/60)
	check(recorder.played.count("work") == sound_count+1,"Following frames do not repeat the arrival sound")
	game.hud.show_status("Кот идёт к чашке!")
	game.hud.flash_spray()
	check(game.hud.email_ready_label.visible,"Cat status and spray feedback preserve unread mail")
	await press(KEY_F)
	check(game.inbox.index == 0 and game.hud.email_ready_label.visible,"Opening the laptop keeps the next letter unread until it is opened")
	check(game.hud.email_feedback.text.begins_with("Новое письмо пришло"),"Laptop explains how to open the ready letter")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/results/email-ready-laptop-pass5.png")
	game.room.desk.spill()
	game._sync_obstruction()
	await click(game.hud.next_button)
	check(game.inbox.index == 0 and game.hud.email_ready_label.visible and game.hud.next_button.disabled,"Coffee obstruction cannot discard or open unread mail")
	await press(KEY_E)
	game._process(game.RULES.CLEAN_DURATION)
	check(not game.room.desk.dirty and game.hud.email_ready_label.visible,"Cleanup preserves the ready letter")
	await press(KEY_F)
	await click(game.hud.next_button)
	check(game.inbox.index == 1 and not game.hud.email_ready_label.visible,"Clicking next opens the letter and clears its unread indication")
	game._process(.1)
	check(recorder.played.count("work") == sound_count+1,"Opening mail does not retrigger its notification")
	for index in range(1,5):
		await answer_current()
		if index < 4:
			game.shift_time = (index+1)*game.RULES.EMAIL_INTERVAL
			game._process(0)
			await click(game.hud.next_button)
	check(game.quota == 100,"Existing five-letter quota is unchanged")
	var completed_sound_count := recorder.played.count("work")
	game.shift_time = 125
	game._process(.1)
	check(not game.hud.email_ready_label.visible and recorder.played.count("work") == completed_sound_count,"No sixth-letter notice after completing quota")
	game._end_shift(true)
	check(not game.hud.email_ready_label.visible,"Result screen has no stale unread indicator")
	game.free()
	await process_frame
	print("EMAIL_ARRIVAL_TEST: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
