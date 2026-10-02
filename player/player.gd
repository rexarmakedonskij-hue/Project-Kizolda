extends Node3D
signal shoo_requested
@onready var view_pivot: Node3D = $ViewPivot
@onready var camera: Camera3D = $ViewPivot/Camera3D
var pitch := 0.0
var enabled := false
var pet_hand

func _ready() -> void:
	pet_hand = preload("res://player/petting_hand.gd").new()
	add_child(pet_hand)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: shoo_requested.emit()
	if event is InputEventMouseMotion:
		view_pivot.rotation.y = clampf(view_pivot.rotation.y - event.relative.x * 0.0025, -1.9, 1.9)
		pitch = clampf(pitch - event.relative.y * 0.0025, -0.65, 0.65)
		camera.rotation.x = pitch

func can_see(target: Node3D) -> bool:
	var height := .3 if target.get("desktop") != null else .75
	var direction := (target.global_position + Vector3.UP * height - camera.global_position).normalized()
	return (-camera.global_transform.basis.z).dot(direction) > 0.88
