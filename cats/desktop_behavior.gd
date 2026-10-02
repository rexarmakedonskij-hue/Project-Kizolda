extends RefCounted
# Desk event state machine. Route movement stays in cat.gd; jumps and timed
# interactions are integrated here, and pause/shift-end stop both together.
var cat
var kind: String
var state := "approach"
var elapsed := 0.0
var duration := 0.0
var target := Vector3.ZERO
var edge := Vector3(1.35, 1.0, -1.1)
var floor_point := Vector3(2.65, .06, -1.1)
var jump_from := Vector3.ZERO
var jump_to := Vector3.ZERO
var effect_sent := false
var chase_pending := false
var pet_sound_sent := false
var pet_pending := false
var foot_contact

func _init(owner_cat, event_kind: String) -> void:
	cat = owner_cat
	kind = event_kind
	foot_contact = preload("res://cats/desktop_foot_contact.gd").new(cat)
	target = Vector3(0, 1.08, -1.52) if kind == "keyboard" else Vector3(-.87, 1.0, -1.1)

func enter(next: String, seconds := 0.0, clip := "Idle") -> void:
	state = next
	elapsed = 0.0
	duration = seconds
	if next == "petting" and cat.pet_hand != null: duration = cat.pet_hand.LENGTH
	cat.pose_player.play(clip, .06 if next.begins_with("jump_") else .12)
	cat.event_changed.emit(cat, kind, state)
	if next == "petting" and cat.pet_hand != null: cat.pet_hand.begin(cat, cat.pet_player)

func arrived() -> void:
	match state:
		"approach": enter("warning", cat.RULES.DESK_WARNING)
		"to_target":
			enter("align", 0, "Walk")
		"to_edge": enter("crouch_down", .28, "CrouchDown")
		"depart": cat.queue_free()

func tick(delta: float) -> bool:
	if not cat.route.is_empty(): return false
	elapsed += delta
	var yaw := 0.0 if kind == "keyboard" else -PI / 2.0
	if state == "align":
		if cat.turn_in_place(yaw,delta):
			cat.grounded_gait.reset()
			if kind == "keyboard": enter("pet_wait" if pet_pending else "settle", .65, "SitDown")
			else: enter("touch", cat.RULES.CUP_TOUCH_DURATION, "Touch")
		return true
	cat.pose_player.advance(delta)
	if state in ["settle", "seated", "pet_wait", "petting", "touch", "spill"]:
		cat.rotation.y = rotate_toward(cat.rotation.y, yaw, cat.TURN_SPEED * delta)
	if state in ["warning", "crouch", "crouch_down"]:
		var aim: Vector3 = (floor_point if state=="crouch_down" else edge)-cat.position
		cat.rotation.y = rotate_toward(cat.rotation.y, atan2(aim.x,aim.z), cat.TURN_SPEED*delta)
	if state in ["settle", "seated", "pet_wait", "petting"]:
		cat.update_sitting(delta, true)
	else: cat.update_sitting(delta, false)
	if state in ["crouch", "crouch_down", "land_up", "land_down"]:
		foot_contact.apply()
	if state == "petting":
		var touch_start: float = cat.pet_hand.CONTACT_START if cat.pet_hand != null else .80
		var touch_length: float = cat.pet_hand.CONTACT_END - touch_start if cat.pet_hand != null else 1.1
		var warmth := sin(PI * clampf((elapsed-touch_start) / touch_length, 0, 1))
		var skeleton: Skeleton3D = cat.pose_player.skeleton
		var head := skeleton.find_bone("head")
		skeleton.set_bone_pose_rotation(head, skeleton.get_bone_pose_rotation(head) * Quaternion(Vector3.RIGHT, warmth * .16))
		if cat.pet_hand != null:
			cat.pet_hand.sample(elapsed)
			if cat.pet_hand.touching and not pet_sound_sent:
				pet_sound_sent = true
				cat.pet_contact.emit(cat)
			if cat.pet_hand.finished:
				finish()
				return true
	if state.begins_with("jump_"):
		var t := clampf(elapsed / duration, 0, 1)
		# Clear the desktop edge before descending; on ascent, reach desk
		# height before the leading paws cross it.
		cat.position = jump_from.lerp(jump_to, smoothstep(0, 1, t))
		if state == "jump_up":
			cat.position = jump_from.lerp(jump_to, t)
			var gravity := 10.0
			var velocity := (jump_to.y-jump_from.y)/duration + gravity*duration*.5
			cat.position.y = jump_from.y + velocity*elapsed - gravity*elapsed*elapsed*.5
		else:
			cat.position = jump_from.lerp(jump_to, t)
			cat.position.y = lerpf(jump_from.y, jump_to.y, t*t*t) + sin(PI*t)*.08
		if t >= 1:
			cat.position = jump_to
			enter("land_up" if state == "jump_up" else "land_down", .24, "Land")
		return true
	if duration <= 0 or elapsed < duration: return true
	match state:
		"warning": enter("crouch", .35, "Crouch")
		"crouch": jump("jump_up", edge, .8)
		"land_up":
			if chase_pending: leave_table()
			else: walk("to_target", [target])
		"settle": enter("seated", cat.RULES.KEYBOARD_LINGER, "Sit")
		"pet_wait": enter("petting", 2.2, "Sit")
		"seated", "petting": finish()
		"touch":
			if not effect_sent:
				effect_sent = true
				enter("spill", .7, "Touch")
		"spill": finish()
		"stand": walk("to_edge", [edge])
		"crouch_down": jump("jump_down", floor_point, .7)
		"land_down": walk("depart", [Vector3(2.6, .06, .6), cat.home])
	return true

func walk(next: String, points: Array) -> void:
	enter(next, 0, "Walk")
	cat.route = PackedVector3Array(points)
	cat.move_speed = 0.0
	while not cat.route.is_empty() and cat.position.distance_to(cat.route[0]) < .008:
		cat.route.remove_at(0)
	if cat.route.is_empty(): arrived()

func jump(next: String, destination: Vector3, seconds: float) -> void:
	jump_from = cat.position
	jump_to = destination
	enter(next, seconds, "Jump" if next == "jump_up" else "Descend")

func leave_table() -> void:
	var sitting := state in ["settle", "seated", "pet_wait", "petting"]
	cat.route.clear()
	enter("stand", .55 if sitting else .2, "Stand" if sitting else "Idle")

func finish() -> void:
	if not cat.leaving:
		cat.leaving = true
		cat.was_chased.emit(cat)
	leave_table()

func chase() -> void:
	chase_pending = true
	if state in ["jump_up", "land_up"]:
		return # Finish the current jump before turning back: no midair teleport.
	if cat.position.y > .5:
		leave_table()
	else:
		cat.route.clear()
		walk("depart", [Vector3(2.6, .06, .6), cat.home])

func pet() -> void:
	if state == "align":
		# Accept the request while the cat finds its seat, then pet only after
		# the planted turn and complete sit-down. Repeated presses do not reset it.
		pet_pending = true
	elif state == "settle":
		# Keep the ongoing sit-down pose; waiting for affection must not snap it.
		state = "pet_wait"
		cat.event_changed.emit(cat, kind, state)
	else: enter("petting", 2.2, "Sit")

func label() -> String:
	var object := "КЛАВИАТУРЕ" if kind == "keyboard" else "ЧАШКЕ"
	match state:
		"align": return "КОТ УСТРАИВАЕТСЯ НА КЛАВИАТУРЕ" if kind=="keyboard" else "КОТ ПОВОРАЧИВАЕТСЯ К ЧАШКЕ"
		"approach", "to_target": return "КОТ ИДЁТ К " + object
		"warning", "crouch": return "ГОТОВИТСЯ ПРЫГНУТЬ — ПРОГОНИ КОТА"
		"jump_up", "land_up": return "КОТ ПРЫГАЕТ НА СТОЛ"
		"settle", "seated": return "КЛАВИАТУРА ЗАНЯТА — ПРОБЕЛ: ПОГЛАДИТЬ"
		"pet_wait": return "КОТ УСАЖИВАЕТСЯ…"
		"petting": return "ГЛАДИМ КОТА…"
		"touch": return "КОТ ТРОГАЕТ ЧАШКУ — УСПЕЙ ПРОГНАТЬ!"
		"spill": return "КОФЕ ПРОЛИТ — E: УБРАТЬ"
	return "КОТ УХОДИТ"
