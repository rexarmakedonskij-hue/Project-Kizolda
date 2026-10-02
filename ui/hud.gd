extends CanvasLayer
signal start_requested
signal restart_requested
signal pause_requested
signal work_toggled
signal email_chosen(option: int)
signal email_submitted
signal next_email_requested
signal clean_requested
const RULES = preload("res://systems/shift_rules.gd")
var work_panel: Panel
var email_title: Label
var email_sender: Label
var email_body: Label
var email_feedback: Label
var email_options: Array[Button] = []
var submit_button: Button
var next_button: Button
var quota_label: Label
var damage_label: Label
var clock_label: Label
var email_ready_label: Label
var status_label: Label
var quota_bar: ProgressBar
var damage_bar: ProgressBar
var cat_label: Label
var cat_panel: Panel
var reticle: Label
var modal: ColorRect
var modal_title: Label
var modal_subtitle: Label
var modal_body: Label
var action: Button
var mode := "start"
var spray: ColorRect
var obstruction: Label
var pet_feedback: Label
var work_blocked := false
const INK := Color("172d32")
const MINT := Color("8ad7b1")
const CORAL := Color("f2a080")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel(root, Rect2(24, 24, 256, 156))
	_label(root, Vector2(40, 34), 12, "PAWDUCTIVITY", MINT)
	quota_label = _label(root, Vector2(40, 54), 20)
	quota_bar = _bar(root, Vector2(40, 83), MINT)
	quota_bar.size = Vector2(224, 8)
	damage_label = _label(root, Vector2(40, 99), 15)
	damage_bar = _bar(root, Vector2(40, 126), CORAL)
	damage_bar.size = Vector2(224, 6)
	email_ready_label = _label(root, Vector2(40, 148), 12, "НОВОЕ ПИСЬМО • F / Tab", MINT)
	email_ready_label.size = Vector2(224, 20)
	email_ready_label.hide()
	_panel(root, Rect2(1112, 24, 144, 76))
	_label(root, Vector2(1128, 34), 11, "ДО КОНЦА СМЕНЫ", MINT)
	clock_label = _label(root, Vector2(1146, 53), 24)
	_panel(root, Rect2(24, 642, 1232, 62))
	status_label = _label(root, Vector2(40, 649), 17)
	status_label.size.x = 1180
	_label(root, Vector2(40, 679), 12, "МЫШЬ — осмотр    F / TAB — ноутбук    ПРОБЕЛ — погладить / прогнать    E — убрать кофе    ESC — пауза", MINT)
	cat_panel = _panel(root, Rect2(400, 24, 480, 42))
	cat_panel.hide()
	cat_label = _label(root, Vector2(416, 34), 15, "", CORAL)
	obstruction = _label(root, Vector2(360, 76), 15, "", CORAL)
	obstruction.size = Vector2(700, 36)
	obstruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obstruction.add_theme_color_override("font_outline_color", INK)
	obstruction.add_theme_constant_override("outline_size", 5)
	reticle = _label(root, Vector2(630, 342), 25, "+", Color.WHITE)
	reticle.add_theme_color_override("font_outline_color", INK)
	reticle.add_theme_constant_override("outline_size", 4)
	pet_feedback = _label(root, Vector2.ZERO, 36, "♥", CORAL)
	pet_feedback.hide()
	spray = ColorRect.new()
	spray.color = Color(0.7, 0.95, 1, 0)
	spray.size = Vector2(1280, 720)
	spray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spray)
	_build_inbox(root)
	modal = ColorRect.new()
	modal.size = Vector2(1280, 720)
	modal.color = Color(0.04, 0.1, 0.12, 0.68)
	root.add_child(modal)
	_panel(modal, Rect2(310, 158, 660, 402))
	_label(modal, Vector2(348, 184), 14, "ДОМАШНИЙ ОФИС / КОШАЧЬИ ЗАБОТЫ", MINT)
	modal_title = _label(modal, Vector2(346, 220), 40, "PAWDUCTIVITY")
	modal_subtitle = _label(modal, Vector2(348, 280), 21, "Работать из дома? Легко. Если бы не коты.")
	modal_body = _label(modal, Vector2(348, 334), 19)
	modal_body.size = Vector2(580, 120)
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.text = "За %d секунд обработай пять писем: F / Tab — ноутбук.\nПробел: погладить кота на клавиатуре, прогнать от чашки и обоев. Посмотри на кота перед действием. Кофе пролит? E — уборка. Esc — пауза." % int(RULES.DURATION)
	action = Button.new()
	action.position = Vector2(348, 484)
	action.size = Vector2(584, 48)
	action.text = "Начать смену"
	action.add_theme_font_size_override("font_size", 21)
	action.add_theme_color_override("font_color", INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = MINT.lightened(0.1) if state == "hover" else MINT
		style.set_corner_radius_all(9)
		action.add_theme_stylebox_override(state, style)
	modal.add_child(action)
	action.pressed.connect(_action)

func _action() -> void:
	if mode == "start": start_requested.emit()
	elif mode == "pause": pause_requested.emit()
	else: restart_requested.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			pause_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_F, KEY_TAB] and not modal.visible:
			work_toggled.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and mode == "result": restart_requested.emit()
		elif event.keycode == KEY_E and not modal.visible:
			clean_requested.emit()
			get_viewport().set_input_as_handled()

func update_values(quota: int, damage: float, elapsed: float) -> void:
	quota_label.text = "Письма  %d / 5" % (quota / RULES.QUOTA_PER_EMAIL)
	damage_label.text = "Обои  %d%% / %d%%" % [int(damage), int(RULES.DAMAGE_LIMIT)]
	quota_bar.value = quota
	damage_bar.value = damage / RULES.DAMAGE_LIMIT * 100
	var remaining := int(ceil(maxf(0, RULES.DURATION - elapsed)))
	clock_label.text = "%02d:%02d" % [remaining / 60, remaining % 60]

func update_cat(cat, player) -> void:
	pet_feedback.hide()
	cat_label.visible = is_instance_valid(cat)
	cat_panel.visible = cat_label.visible
	obstruction.visible = work_blocked and (not is_instance_valid(cat) or work_panel.visible)
	if is_instance_valid(cat):
		if cat.desktop != null:
			cat_label.text = cat.desktop.label()
			if cat.desktop.state == "petting" and player.pet_hand.touching and not player.camera.is_position_behind(cat.global_position):
				pet_feedback.position = player.camera.unproject_position(cat.global_position + Vector3.UP * .6) - Vector2(14, 24 + cat.desktop.elapsed * 12)
				pet_feedback.show()
		elif not cat.route.is_empty():
			cat_label.text = "КОТ ИДЁТ К ОБОЯМ"
		else:
			cat_label.text = "%s: %s %.1f c" % ["СЛЕВА" if cat.position.x < 0 else "СПРАВА", "ГОТОВИТСЯ" if cat.warning else "ДО УЩЕРБА", cat.scratch_timer.time_left]
		if not player.can_see(cat):
			var local_target: Vector3=player.camera.to_local(cat.global_position+Vector3.UP*(.3 if cat.desktop != null else .75))
			cat_label.text=("→  " if local_target.x>.05 else ("←  " if local_target.x<-.05 else "↶  "))+cat_label.text
		reticle.modulate = MINT if player.can_see(cat) else Color.WHITE
	else: reticle.modulate = Color.WHITE

func show_status(message: String) -> void: status_label.text = message
func set_email_ready(ready: bool) -> void:
	email_ready_label.visible = ready
func set_obstruction(message: String, blocked: bool) -> void:
	obstruction.text = message
	work_blocked = blocked
func hide_modal() -> void: modal.hide()

func show_pause(paused: bool) -> void:
	modal.visible = paused
	if not paused: return
	mode = "pause"
	modal_title.text = "ПАУЗА"
	modal_subtitle.text = "Можно выдохнуть."
	modal_body.text = "Время смены и таймер кота остановлены.\nНажми Esc или кнопку, чтобы продолжить."
	action.text = "Продолжить"

func show_result(won: bool, message: String, quota: int, damage: float) -> void:
	pet_feedback.hide()
	mode = "result"
	modal.show()
	cat_label.hide()
	cat_panel.hide()
	modal_title.text = "СМЕНА ЗАКРЫТА!" if won else "НЕ В ЭТУ СМЕНУ"
	modal_subtitle.text = message
	modal_body.text = "Квота: %d%%   •   Повреждения: %d%%\n\nНажми R или кнопку ниже для новой попытки." % [quota, int(damage)]
	action.text = "Ещё одну смену"

func flash_spray() -> void:
	spray.color.a = 0.2
	create_tween().tween_property(spray, "color:a", 0.0, 0.25)

func _panel(parent: Node, rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Node, pos: Vector2, font_size: int, text := "", color := Color.WHITE) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _bar(parent: Node, pos: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = Vector2(267, 8)
	bar.show_percentage = false
	for key in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color if key == "fill" else Color("345055")
		style.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(key, style)
	parent.add_child(bar)
	return bar

func _build_inbox(root: Control) -> void:
	work_panel = _panel(root, Rect2(362, 126, 872, 480))
	work_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	email_title = _label(work_panel, Vector2(24, 18), 25)
	email_sender = _label(work_panel, Vector2(24, 56), 16, "", MINT)
	email_body = _label(work_panel, Vector2(24, 94), 20)
	email_body.size = Vector2(820, 120)
	email_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in range(3):
		var button := _email_button(Vector2(24, 218 + i * 49), Vector2(820, 43), "")
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func(): email_chosen.emit(i))
		email_options.append(button)
	email_feedback = _label(work_panel, Vector2(24, 370), 16, "", CORAL)
	email_feedback.size = Vector2(820, 50)
	email_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	submit_button = _email_button(Vector2(24, 426), Vector2(244, 40), "Отправить")
	submit_button.pressed.connect(func(): email_submitted.emit())
	next_button = _email_button(Vector2(284, 426), Vector2(258, 40), "Следующее письмо")
	next_button.pressed.connect(func(): next_email_requested.emit())
	var leave := _email_button(Vector2(558, 426), Vector2(286, 40), "В комнату [F / Tab]")
	leave.pressed.connect(func(): work_toggled.emit())
	work_panel.hide()

func _email_button(pos: Vector2, dimensions: Vector2, text: String) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = dimensions
	button.text = text
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("355950") if state == "pressed" else Color("29444a")
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)
	work_panel.add_child(button)
	return button

func set_working(value: bool, inbox, quota: int, next_wait := 0.0) -> void:
	work_panel.visible = value
	reticle.visible = not value
	if value: refresh_email(inbox, quota, next_wait)
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null: focused.release_focus()

func refresh_email(inbox, quota: int, next_wait := 0.0) -> void:
	email_title.text = "ВХОДЯЩИЕ / " + str(inbox.index + 1) + " • " + str(inbox.current.subject)
	email_sender.text = inbox.current.sender
	email_body.text = inbox.current.body
	email_feedback.text = "Квота готова. Осталось беречь комнату до конца смены." if quota >= 100 else ("Следующее письмо придёт через %d с. Пока следи за котом." % int(ceil(next_wait)) if inbox.resolved and next_wait > 0 else ("Новое письмо пришло. Нажми «Следующее письмо»." if inbox.resolved else inbox.feedback))
	for i in range(email_options.size()):
		email_options[i].text = ("●  " if inbox.selected == i else "○  ") + str(inbox.current.options[i])
		email_options[i].set_pressed_no_signal(inbox.selected == i)
		email_options[i].disabled = inbox.resolved or work_blocked
	submit_button.disabled = inbox.resolved or inbox.selected < 0 or work_blocked
	next_button.text = "Через %d с" % int(ceil(next_wait)) if inbox.resolved and next_wait > 0 else "Следующее письмо"
	next_button.disabled = not inbox.resolved or quota >= 100 or work_blocked or next_wait > 0
