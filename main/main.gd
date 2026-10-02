extends Node3D

const RULES = preload("res://systems/shift_rules.gd")
const SHIFT_DURATION := RULES.DURATION
const CAT_SCENE := preload("res://cats/cat.tscn")
@export var cat_model_scene: PackedScene
@onready var room = $Room
@onready var player = $Player
@onready var hud = $HUD
var shift_time := 0.0
var quota := 0
var wall_damage := 0.0
var active_cat: Node3D
var departing_cat: Node3D
var next_cat_in := RULES.FIRST_CAT_DELAY
var finished := false
var started := false
var sound: Node
var inbox = preload("res://systems/inbox.gd").new()
var working := false
var event_index := 0
const EVENT_ORDER := ["keyboard", "cup", "wall"]
var keyboard_blocked := false
var cleaning := false
var clean_elapsed := 0.0
var email_announced_index := 0
var verifying_build := "--verify-build" in OS.get_cmdline_user_args()

func _ready() -> void:
	sound = preload("res://systems/sound.gd").new()
	add_child(sound)
	player.shoo_requested.connect(_on_shoo_requested)
	hud.start_requested.connect(start_shift)
	hud.restart_requested.connect(restart)
	hud.pause_requested.connect(toggle_pause)
	hud.work_toggled.connect(_on_work_requested)
	hud.email_chosen.connect(_choose_email)
	hud.email_submitted.connect(_submit_email)
	hud.next_email_requested.connect(_next_email)
	hud.clean_requested.connect(_start_cleaning)
	hud.show_status("Твой офис. Твои коты. Твоя выдержка.")
	hud.update_values(0, 0, 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if verifying_build:
		add_child(preload("res://systems/build_verification.gd").new())

func start_shift() -> void:
	started = true
	player.enabled = true
	hud.hide_modal()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_status("Смена началась. Выполни квоту и береги обои.")
	hud.set_email_ready(true)

func _process(delta: float) -> void:
	if finished or not started: return
	shift_time = minf(shift_time + delta, SHIFT_DURATION)
	if shift_time >= SHIFT_DURATION:
		_end_shift(quota >= 100)
		return
	_update_email_arrival()
	if cleaning:
		clean_elapsed = minf(clean_elapsed + delta, RULES.CLEAN_DURATION)
		room.desk.clean_progress(clean_elapsed/RULES.CLEAN_DURATION)
		hud.set_obstruction("Убираем кофе… %.1f с" % (RULES.CLEAN_DURATION-clean_elapsed), true)
		if clean_elapsed >= RULES.CLEAN_DURATION:
			cleaning = false
			room.desk.clean()
			_sync_obstruction()
			hud.show_status("Стол чист. Можно продолжать работу.")
	if keyboard_blocked and is_instance_valid(departing_cat) and departing_cat.desktop != null:
		# Shooing starts the departure, but the keys remain occupied until
		# the cat's last paw has moved past the laptop edge.
		if departing_cat.desktop.state in ["to_edge", "crouch_down", "jump_down", "land_down", "depart"] and departing_cat.position.x > 1.15:
			keyboard_blocked = false
			_sync_obstruction()
			hud.show_status("Клавиатура свободна. Можно работать.")
	if not is_instance_valid(active_cat):
		# Let the next visit's cooldown run while this cat walks home, while
		# still keeping the room limited to one cat at a time.
		next_cat_in = maxf(0.0, next_cat_in - delta)
		if not is_instance_valid(departing_cat) and next_cat_in <= 0.0:
			_spawn_cat(EVENT_ORDER[event_index % EVENT_ORDER.size()])
			event_index += 1
	hud.update_values(quota, wall_damage, shift_time)
	hud.update_cat(active_cat, player)
	var cup_tap:=0.0
	if is_instance_valid(active_cat) and active_cat.desktop != null and active_cat.desktop.kind=="cup" and active_cat.desktop.state=="touch":
		cup_tap=pow(.5-.5*cos(TAU*active_cat.desktop.elapsed/1.2),4)
	room.desk.tap(cup_tap)
	if working and inbox.resolved and quota < 100:
		hud.refresh_email(inbox, quota, _email_wait())

func _on_work_requested() -> void:
	if not started or finished or get_tree().paused: return
	if cleaning: _cancel_cleaning()
	working = not working
	_sync_work_mode()

func _sync_work_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if working else Input.MOUSE_MODE_CAPTURED
	hud.set_working(working, inbox, quota, _email_wait())
	if working and not inbox.resolved:
		hud.set_email_ready(false)

func _update_email_arrival() -> void:
	if quota >= 100 or not inbox.resolved or _email_wait() > 0.0: return
	var ready_index: int = inbox.index + 1
	if ready_index <= email_announced_index: return
	email_announced_index = ready_index
	hud.set_email_ready(true)
	sound.play("work")

func _email_wait() -> float:
	if quota >= 100: return 0.0
	return maxf(0.0, (inbox.index + 1) * RULES.EMAIL_INTERVAL - shift_time)

func _choose_email(option: int) -> void:
	if not working or finished or get_tree().paused or _work_blocked(): return
	inbox.choose(option)
	hud.refresh_email(inbox, quota)

func _submit_email() -> void:
	if not working or finished or get_tree().paused or _work_blocked(): return
	if inbox.submit():
		quota = mini(quota + RULES.QUOTA_PER_EMAIL, 100)
		sound.play("work")
		hud.show_status("Квота готова! Береги обои до конца смены." if quota == 100 else "Письмо обработано. Следующее придёт позже; следи за котом.")
	hud.refresh_email(inbox, quota, _email_wait())
	hud.update_values(quota, wall_damage, shift_time)

func _next_email() -> void:
	if not working or finished or get_tree().paused or _work_blocked() or not inbox.resolved or quota >= 100 or _email_wait() > 0: return
	inbox.next_email()
	hud.set_email_ready(false)
	hud.refresh_email(inbox, quota, _email_wait())

func _spawn_cat(kind := "wall") -> void:
	if finished or is_instance_valid(active_cat) or is_instance_valid(departing_cat): return
	active_cat = CAT_SCENE.instantiate()
	active_cat.ground_surface=room.ground_surface
	if cat_model_scene != null: active_cat.model_scene = cat_model_scene
	var side: int = [-1, 1].pick_random()
	active_cat.position = room.get_cat_position(side)
	active_cat.rotation.y = PI
	add_child(active_cat)
	active_cat.scratched_wall.connect(_on_cat_scratched_wall)
	active_cat.was_chased.connect(_on_cat_chased)
	active_cat.scratching_started.connect(_on_scratching_started)
	active_cat.scratch_stroke.connect(_on_scratch_stroke)
	active_cat.event_changed.connect(_on_cat_event)
	active_cat.pet_contact.connect(_on_pet_contact)
	if kind != "wall":
		active_cat.approach_desktop(kind)
		sound.play_at("cat",active_cat.global_position)
		hud.show_status("Кот идёт к клавиатуре. Можно прогнать заранее!" if kind == "keyboard" else "Кот заинтересовался чашкой. Следи за лапой!")
		return
	active_cat.approach(PackedVector3Array([Vector3(0, .06, 2.0), Vector3(side * 4.7, .06, .5), room.get_cat_position(side)]))
	sound.play_at("cat", active_cat.global_position)
	hud.show_status("Кот идёт к обоям слева. Можно вмешаться заранее!" if side < 0 else "Кот идёт к обоям справа. Можно вмешаться заранее!")

func _on_scratching_started() -> void:
	if not finished:
		hud.show_status("Кот начал царапать! Выйди из ноутбука и прогони его.")

func _on_scratch_stroke(from: Vector3, to: Vector3, duration: float) -> void:
	if finished: return
	room.draw_scratch(from, to, duration)
	sound.play_at("scratch", from)

func _on_shoo_requested() -> void:
	if not started or finished or get_tree().paused or working: return
	if cleaning: _cancel_cleaning()
	if is_instance_valid(active_cat) and active_cat.desktop != null and active_cat.desktop.kind == "keyboard" and active_cat.desktop.state in ["align", "settle", "seated", "pet_wait", "petting"]:
		if active_cat.try_to_pet(player):
			hud.show_status("Кот садится — затем погладим." if active_cat.desktop.state in ["align","pet_wait"] else "Гладим кота. Он доволен и сейчас освободит клавиатуру.")
		elif active_cat.desktop.state not in ["petting", "pet_wait"]:
			hud.show_status("Посмотри на кота и нажми пробел, чтобы погладить.")
		return
	sound.play("spray")
	hud.flash_spray()
	if not is_instance_valid(active_cat) or not active_cat.try_to_chase(player):
		hud.show_status("Посмотри прямо на кота и нажми пробел.")

func _on_pet_contact(cat) -> void:
	if finished: return
	sound.play_at("purr", cat.global_position)

func _on_cat_chased(cat) -> void:
	if cat != active_cat: return
	departing_cat = cat
	active_cat = null
	_sync_obstruction()
	room.stop_scratches()
	next_cat_in = randf_range(RULES.RESPAWN_MIN, RULES.RESPAWN_MAX)
	hud.show_status("Кот освобождает клавиатуру…" if keyboard_blocked else ("Кот уходит. E — убери пролитый кофе." if room.desk.dirty else "Кот уходит. Можно продолжить работу."))

func _on_cat_scratched_wall(cat, amount: float) -> void:
	if cat != active_cat or finished: return
	wall_damage = room.damage_wall(amount, -1 if cat.position.x < 0 else 1)
	hud.update_values(quota, wall_damage, shift_time)
	if wall_damage >= RULES.DAMAGE_LIMIT: _end_shift(false, "Обои испорчены. Арендодатель недоволен.")
	else: hud.show_status("Ещё +10% повреждений! Прогони кота, он не остановится сам.")

func _end_shift(won: bool, message := "") -> void:
	finished = true
	player.enabled = false
	working = false
	hud.set_email_ready(false)
	hud.set_working(false, inbox, quota)
	get_tree().call_group("pawductivity_cats", "stop")
	cleaning = false
	room.desk.set_process(false)
	room.stop_scratches()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.update_values(quota, wall_damage, shift_time)
	if message.is_empty(): message = "Работа сделана, квартира цела." if won else "Рабочая квота не выполнена."
	hud.show_result(won, message, quota, wall_damage)
	sound.play("win" if won else "scratch")

func toggle_pause() -> void:
	if not started or finished: return
	get_tree().paused = not get_tree().paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused or working else Input.MOUSE_MODE_CAPTURED
	hud.show_pause(get_tree().paused)

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and not finished and not get_tree().paused and not verifying_build:
		toggle_pause()

func _work_blocked() -> bool:
	return keyboard_blocked or room.desk.dirty or cleaning

func _sync_obstruction() -> void:
	var message := ""
	if keyboard_blocked: message = "Кот освобождает клавиатуру…" if is_instance_valid(departing_cat) else "Кот занял клавиатуру. F — в комнату, пробел — погладить."
	elif room.desk.dirty: message = "Кофе на столе. Нажми E, чтобы убрать (2,5 с)."
	room.set_keyboard_blocked(keyboard_blocked)
	hud.set_obstruction(message, _work_blocked())
	hud.refresh_email(inbox, quota, _email_wait())

func _on_cat_event(cat, kind: String, state: String) -> void:
	if finished: return
	if kind == "keyboard" and state in ["align","settle","seated","pet_wait"] and cat == active_cat and not keyboard_blocked:
		keyboard_blocked = true
		working = false
		_sync_work_mode()
		_sync_obstruction()
		hud.show_status("Клавиатура занята! Посмотри на кота и нажми пробел, чтобы погладить.")
		sound.play_at("keyboard",cat.global_position)
	elif state == "warning":
		sound.play_at("cat",cat.global_position)
	elif kind == "cup" and state == "touch":
		sound.play_at("cup",room.desk.CUP_POSITION)
		hud.show_status("Кот трогает чашку. Прогони, пока кофе не пролился!")
	elif kind == "cup" and state == "spill" and cat == active_cat:
		room.desk.spill()
		working = false
		_sync_work_mode()
		_sync_obstruction()
		sound.play_at("spill",room.desk.CUP_POSITION)
		hud.show_status("Кофе пролился. E — убрать; пробел — прогнать кота.")

func _start_cleaning() -> void:
	if not started or finished or get_tree().paused or cleaning or not room.desk.dirty: return
	if keyboard_blocked:
		hud.show_status("Сначала погладь кота на клавиатуре.")
		return
	working = false
	_sync_work_mode()
	cleaning = true
	clean_elapsed = 0
	hud.show_status("Убираем кофе… F или пробел — прервать уборку.")

func _cancel_cleaning() -> void:
	cleaning = false
	clean_elapsed = 0
	room.desk.clean_progress(0)
	_sync_obstruction()
