extends Node3D
signal work_requested
signal shoo_requested
@onready var view_pivot: Node3D = $ViewPivot
@onready var camera: Camera3D = $ViewPivot/Camera3D
var pitch := 0.0
func _ready() -> void: Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed: Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event.keycode == KEY_F: work_requested.emit()
		elif event.keycode == KEY_SPACE: shoo_requested.emit()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		view_pivot.rotate_y(-event.relative.x * 0.0025)
		pitch = clamp(pitch - event.relative.y * 0.0025, -0.45, 0.45)
		camera.rotation.x = pitch
func can_see(target: Node3D) -> bool:
	return (-camera.global_transform.basis.z).dot((target.global_position - camera.global_position).normalized()) > 0.88
