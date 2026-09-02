extends Node3D

const SHIFT_DURATION := 40.0
const CAT_SCENE := preload("res://cats/cat.tscn")
@onready var room = $Room
@onready var player = $Player
@onready var hud = $HUD
var shift_time := 0.0
var quota := 0
var wall_damage := 0.0
var active_cat
var next_cat_in := 4.0
var finished := false

func _ready() -> void:
	player.work_requested.connect(_on_work_requested)
	player.shoo_requested.connect(_on_shoo_requested)
	hud.show_status("Смена началась. Выполняй квоту и береги обои.")

func _process(delta: float) -> void:
	if finished: return
	shift_time += delta
	if shift_time >= SHIFT_DURATION:
		_end_shift(quota >= 100)
		return
	if active_cat == null:
		next_cat_in -= delta
		if next_cat_in <= 0.0: _spawn_cat()
	hud.update_values(quota, wall_damage, shift_time)

func _on_work_requested() -> void:
	quota = min(quota + 5, 100)
	hud.show_status("Задачи обработаны. Не отвлекайся — но слушай котов!")

func _spawn_cat() -> void:
	active_cat = CAT_SCENE.instantiate()
	active_cat.position = room.get_cat_position([-1, 1].pick_random())
	add_child(active_cat)
	active_cat.scratched_wall.connect(_on_cat_scratched_wall)
	active_cat.was_chased.connect(_on_cat_chased)
	active_cat.start_scratching()
	hud.show_status("Слышно: ш-ш-ш... Кот дерёт обои!")

func _on_shoo_requested() -> void:
	if active_cat != null: active_cat.try_to_chase(player)

func _on_cat_chased(cat) -> void:
	if cat == active_cat:
		active_cat = null
		next_cat_in = randf_range(5.0, 9.0)
		hud.show_status("Пшшш! Кот убежал. Возвращайся к работе.")

func _on_cat_scratched_wall(cat, amount: float) -> void:
	if cat != active_cat: return
	wall_damage = room.damage_wall(amount)
	active_cat = null
	next_cat_in = randf_range(5.0, 9.0)
	if wall_damage >= 50.0:
		_end_shift(false, "Обои уничтожены. Арендодатель выселил тебя.")
	else: hud.show_status("Кот успел испортить обои!")

func _end_shift(won: bool, message := "") -> void:
	finished = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if message.is_empty(): message = "Смена завершена! Выполнено: %d%%." % quota if won else "Квота не выполнена."
	hud.show_status(message + " Перезапусти сцену для новой смены.")
