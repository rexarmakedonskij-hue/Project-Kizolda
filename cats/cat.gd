extends Node3D
const CAT_SCENE := preload("res://assets/models/glb/cat.glb")
signal scratched_wall(cat, amount: float)
signal was_chased(cat)
@onready var scratch_timer: Timer = $ScratchTimer
func _ready() -> void:
	var model := CAT_SCENE.instantiate()
	model.scale = Vector3(0.55, 0.55, 0.55)
	add_child(model)
	scratch_timer.timeout.connect(func(): scratched_wall.emit(self, 10.0))
func start_scratching() -> void: scratch_timer.start()
func try_to_chase(player) -> void:
	if player.can_see(self): was_chased.emit(self); queue_free()
