extends Node3D
signal scratched_wall(cat, amount: float)
signal was_chased(cat)
@onready var scratch_timer: Timer = $ScratchTimer
func _ready() -> void:
	_add_part(Vector3.ZERO, Vector3(0.75,0.85,0.45))
	_add_part(Vector3(-0.25,0.52,0), Vector3(0.22,0.28,0.25))
	_add_part(Vector3(0.25,0.52,0), Vector3(0.22,0.28,0.25))
	scratch_timer.timeout.connect(func(): scratched_wall.emit(self, 10.0))
func start_scratching() -> void: scratch_timer.start()
func try_to_chase(player) -> void:
	if player.can_see(self): was_chased.emit(self); queue_free()
func _add_part(pos: Vector3, size_value: Vector3) -> void:
	var part := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = size_value; part.mesh = mesh
	var material := StandardMaterial3D.new(); material.albedo_color = Color("f08b6e"); part.material_override = material; part.position = pos; add_child(part)
