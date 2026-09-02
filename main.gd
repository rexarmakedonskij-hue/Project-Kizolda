extends Node3D

const SHIFT_DURATION := 40.0 # Temporary test shift; the release setting will be 40 * 60 seconds.
const CAT_RESPONSE_TIME := 5.0
const MAX_WALL_DAMAGE := 50.0

var camera: Camera3D
var view_pivot: Node3D
var yaw := 0.0
var pitch := 0.0
var shift_time := 0.0
var quota := 0
var wall_damage := 0.0
var cat: MeshInstance3D
var cat_side := 1
var cat_is_active := false
var cat_time := 0.0
var next_cat_in := 4.0
var status_label: Label
var quota_label: Label
var damage_label: Label
var clock_label: Label
var hint_label: Label
var hud_layer: CanvasLayer
var work_pressed := false
var shoo_pressed := false

func _ready() -> void:
	_build_room()
	_build_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			work_pressed = true
		elif event.keycode == KEY_SPACE:
			shoo_pressed = true
	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clamp(pitch - event.relative.y * 0.0025, -0.45, 0.45)
		view_pivot.rotation.y = yaw
		camera.rotation.x = pitch

func _process(delta: float) -> void:
	shift_time += delta
	if shift_time >= SHIFT_DURATION:
		_finish_shift()
		return

	if work_pressed:
		work_pressed = false
		quota = min(quota + 5, 100)
		status_label.text = "Задачи обработаны. Не отвлекайся — но слушай котов!"

	if cat_is_active:
		cat_time += delta
		if shoo_pressed and _is_looking_at_cat():
			_chase_cat()
		elif cat_time >= CAT_RESPONSE_TIME:
			wall_damage = min(wall_damage + 10.0, MAX_WALL_DAMAGE)
			status_label.text = "Кот успел испортить обои!"
			_remove_cat()
			if wall_damage >= MAX_WALL_DAMAGE:
				_game_over()
	else:
		next_cat_in -= delta
		if next_cat_in <= 0.0:
			_spawn_cat()

	_update_hud()
	shoo_pressed = false

func _build_room() -> void:
	# Soft pastel room made entirely from primitive meshes, so the prototype has no asset dependency.
	_add_box(Vector3(0, -0.2, 0), Vector3(12, 0.3, 10), Color("e9d8c1"))
	_add_box(Vector3(0, 3.0, -5), Vector3(12, 6, 0.25), Color("f5c9c8"))
	_add_box(Vector3(-6, 3.0, 0), Vector3(0.25, 6, 10), Color("b8d9e6"))
	_add_box(Vector3(6, 3.0, 0), Vector3(0.25, 6, 10), Color("b8d9e6"))
	# desk and laptop
	_add_box(Vector3(0, 0.85, -1.7), Vector3(4.0, 0.18, 1.8), Color("8a5a44"))
	_add_box(Vector3(0, 1.65, -2.28), Vector3(2.1, 1.25, 0.12), Color("303645"))
	_add_box(Vector3(0, 1.65, -2.20), Vector3(1.86, 1.02, 0.04), Color("75c4e6"))
	_add_box(Vector3(0, 1.00, -1.65), Vector3(1.9, 0.08, 1.15), Color("555765"))
	# lamp and wallpaper accents
	_add_box(Vector3(-3.6, 2.3, -4.8), Vector3(1.5, 1.8, 0.06), Color("fff1a8"))
	_add_box(Vector3(3.6, 2.3, -4.8), Vector3(1.5, 1.8, 0.06), Color("fff1a8"))

	view_pivot = Node3D.new()
	add_child(view_pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.55, 0.35)
	camera.current = true
	camera.fov = 72.0
	view_pivot.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.2
	add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3.8, -1)
	fill.light_color = Color("ffe7b2")
	fill.omni_range = 13.0
	add_child(fill)

func _add_box(position_value: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	box.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	box.material_override = material
	box.position = position_value
	add_child(box)
	return box

func _spawn_cat() -> void:
	cat_is_active = true
	cat_time = 0.0
	cat_side = [-1, 1].pick_random()
	cat = _add_box(Vector3(4.8 * cat_side, 0.52, -3.8), Vector3(0.75, 0.85, 0.45), Color("f08b6e"))
	# Ears make the placeholder clearly read as a cartoon cat.
	_add_cat_ear(Vector3(4.55 * cat_side, 1.05, -3.8))
	_add_cat_ear(Vector3(5.05 * cat_side, 1.05, -3.8))
	status_label.text = "Слышно: ш-ш-ш... Кот дерёт обои %s!" % ("слева" if cat_side < 0 else "справа")

func _add_cat_ear(pos: Vector3) -> void:
	var ear := _add_box(pos, Vector3(0.22, 0.28, 0.25), Color("f08b6e"))
	ear.set_meta("cat_part", true)

func _remove_cat() -> void:
	for child in get_children():
		if child is MeshInstance3D and (child == cat or child.has_meta("cat_part")):
			child.queue_free()
	cat = null
	cat_is_active = false
	next_cat_in = randf_range(5.0, 9.0)

func _is_looking_at_cat() -> bool:
	if cat == null:
		return false
	var to_cat := (cat.global_position - camera.global_position).normalized()
	var forward := -camera.global_transform.basis.z.normalized()
	return forward.dot(to_cat) > 0.88

func _chase_cat() -> void:
	status_label.text = "Пшшш! Кот убежал. Возвращайся к работе."
	_remove_cat()

func _finish_shift() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	status_label.text = "Смена завершена! Выполнено: %d%%. Нажми Esc и перезапусти сцену." % quota
	set_process(false)

func _game_over() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	status_label.text = "Обои уничтожены. Арендодатель выселил тебя. Перезапусти сцену."
	set_process(false)

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.11, 0.16, 0.84)
	panel.position = Vector2(20, 20)
	panel.size = Vector2(360, 165)
	hud_layer.add_child(panel)

	quota_label = _label(Vector2(38, 35), 22)
	damage_label = _label(Vector2(38, 68), 22)
	clock_label = _label(Vector2(38, 101), 20)
	hint_label = _label(Vector2(38, 137), 16)
	hint_label.text = "[F] работать   [Пробел] прогнать кота"
	status_label = _label(Vector2(20, 650), 20)
	status_label.size = Vector2(1100, 40)
	status_label.text = "Смена началась. Выполняй квоту и береги обои."

func _label(pos: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	hud_layer.add_child(label)
	return label

func _update_hud() -> void:
	quota_label.text = "Квота: %d%% / 100%%" % quota
	damage_label.text = "Обои: %.0f%% / 50%%" % wall_damage
	clock_label.text = "Смена: %02d:%02d" % [int(shift_time) / 60, int(shift_time) % 60]
