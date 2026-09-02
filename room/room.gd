extends Node3D

const DESK_SCENE := preload("res://assets/models/glb/desk.glb")
const CHAIR_SCENE := preload("res://assets/models/glb/chair.glb")
const LAPTOP_SCENE := preload("res://assets/models/glb/laptop.glb")
const WALL_SCENE := preload("res://assets/models/glb/wall_intact.glb")

var wallpaper_damage := 0.0
func _ready() -> void:
	_add_box(Vector3(0, -0.2, 0), Vector3(12, 0.3, 10), Color("e9d8c1"))
	_add_model(WALL_SCENE, Vector3(0, 0, -4.84))
	_add_model(WALL_SCENE, Vector3(-5.88, 0, 0), Vector3(2, 1, 1), Vector3(0, PI / 2, 0))
	_add_model(WALL_SCENE, Vector3(5.88, 0, 0), Vector3(2, 1, 1), Vector3(0, PI / 2, 0))
	_add_model(DESK_SCENE, Vector3(0, 0.65, -1.7), Vector3(0.7, 0.7, 0.7))
	_add_model(CHAIR_SCENE, Vector3(0, 0.08, 0.25), Vector3(0.72, 0.72, 0.72))
	_add_model(LAPTOP_SCENE, Vector3(0, 1.25, -2.18), Vector3(0.72, 0.72, 0.72))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.2
	add_child(light)
func get_cat_position(side: int) -> Vector3: return Vector3(4.8 * side, 0.52, -3.8)
func damage_wall(amount: float) -> float:
	wallpaper_damage = min(wallpaper_damage + amount, 50.0); return wallpaper_damage
func _add_box(pos: Vector3, size_value: Vector3, color: Color) -> void:
	var box := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = size_value; box.mesh = mesh
	var material := StandardMaterial3D.new(); material.albedo_color = color; box.material_override = material; box.position = pos; add_child(box)

func _add_model(scene: PackedScene, pos: Vector3, scale_value := Vector3.ONE, rotation_value := Vector3.ZERO) -> void:
	var model := scene.instantiate()
	model.position = pos
	model.scale = scale_value
	model.rotation = rotation_value
	add_child(model)
