extends Node3D

var wallpaper_damage := 0.0
func _ready() -> void:
	for data in [[Vector3(0,-0.2,0),Vector3(12,0.3,10),Color("e9d8c1")],[Vector3(0,3,-5),Vector3(12,6,0.25),Color("f5c9c8")],[Vector3(-6,3,0),Vector3(0.25,6,10),Color("b8d9e6")],[Vector3(6,3,0),Vector3(0.25,6,10),Color("b8d9e6")],[Vector3(0,0.85,-1.7),Vector3(4,0.18,1.8),Color("8a5a44")],[Vector3(0,1.65,-2.28),Vector3(2.1,1.25,0.12),Color("303645")],[Vector3(0,1.65,-2.2),Vector3(1.86,1.02,0.04),Color("75c4e6")]]:
		_add_box(data[0], data[1], data[2])
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-50,-25,0); add_child(light)
func get_cat_position(side: int) -> Vector3: return Vector3(4.8 * side, 0.52, -3.8)
func damage_wall(amount: float) -> float:
	wallpaper_damage = min(wallpaper_damage + amount, 50.0); return wallpaper_damage
func _add_box(pos: Vector3, size_value: Vector3, color: Color) -> void:
	var box := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = size_value; box.mesh = mesh
	var material := StandardMaterial3D.new(); material.albedo_color = color; box.material_override = material; box.position = pos; add_child(box)
