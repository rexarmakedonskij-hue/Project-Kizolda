extends Node3D
const RULES = preload("res://systems/shift_rules.gd")

var wallpaper_damage := 0.0
var marks: Node3D
var scratch_tweens: Array[Tween] = []
var desk
var laptop_screen: MeshInstance3D
var laptop_keys: Array[MeshInstance3D] = []
var screen_surface: StandardMaterial3D
var key_surface: StandardMaterial3D
var screen_normal := Color.WHITE
var keys_normal := Color.WHITE
var laptop_tween: Tween
var ground_surface

func _ready() -> void:
	var office = preload("res://assets/models/glb/godot_mvp/office.glb").instantiate()
	add_child(office)
	_align_floor_and_rug(office)
	_align_skirting(office)
	for node in office.find_children("*", "MeshInstance3D", true, false):
		var label: String = node.name.to_lower().replace("_", " ")
		if label.begins_with("coffee") or label.begins_with("cup handle"): node.hide()
		if label.begins_with("spray"): node.position.z -= .48
		if label.begins_with("plant"): node.position.x -= .55
		if label.begins_with("laptop luminous screen"):
			laptop_screen = node
		if label.begins_with("keyboard key"):
			laptop_keys.append(node)
	if laptop_screen and not laptop_keys.is_empty():
		screen_surface = laptop_screen.get_active_material(0).duplicate()
		key_surface = laptop_keys[0].get_active_material(0).duplicate()
		screen_normal = screen_surface.albedo_color
		keys_normal = key_surface.albedo_color
		laptop_screen.material_override = screen_surface
		for key in laptop_keys: key.material_override = key_surface
	desk = preload("res://room/desk_props.gd").new()
	add_child(desk)
	marks = Node3D.new()
	add_child(marks)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("c4d9d5")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dce4ed")
	settings.ambient_light_energy = 0.3
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_color = Color("fff5ea")
	sun.light_energy = 0.3
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2, 3, -1)
	fill.light_color = Color("d6edff")
	fill.light_energy = 0.15
	fill.omni_range = 9
	add_child(fill)
	ground_surface=preload("res://room/ground_surface.gd").new(self)

func _align_floor_and_rug(office: Node3D) -> void:
	var rug := []
	var low := INF
	var high := -INF
	for mesh in office.find_children("*","MeshInstance3D",true,false):
		var label=String(mesh.name).to_lower().replace("_"," ")
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		if label.begins_with("oak floorboard"):
			mesh.global_position.y+=global_position.y-bounds.end.y
		elif label.begins_with("rounded woven rug") or label.begins_with("rug weave"):
			rug.append(mesh)
			low=minf(low,bounds.position.y)
			high=maxf(high,bounds.end.y)
	# The imported prototype's woven rug was over five centimetres thick.
	# Keep its weave and pattern as a 3 mm textile above the actual floor.
	if not rug.is_empty() and high>low:
		var factor=.003/(high-low)
		for mesh in rug:
			var original_y: float=mesh.global_position.y
			mesh.scale.y*=factor
			mesh.global_position.y=global_position.y+(original_y-low)*factor

func _align_skirting(office: Node3D) -> void:
	var wallpaper_front := -INF
	var side_fronts := {}
	var trims := []
	for mesh in office.find_children("*","MeshInstance3D",true,false):
		var label=String(mesh.name).to_lower().replace("_"," ")
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		if label.begins_with("back wallpaper"): wallpaper_front=bounds.end.z
		elif label.begins_with("sage side wall"):
			side_fronts[signf(bounds.get_center().x-global_position.x)]=bounds.end.x if bounds.get_center().x<global_position.x else bounds.position.x
		elif label.begins_with("back skirting") or label.begins_with("side skirting"): trims.append(mesh)
	for mesh in trims:
		var label=String(mesh.name).to_lower().replace("_"," ")
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		mesh.scale.y*=.12/bounds.size.y
		if label.begins_with("back skirting"): mesh.scale.z*=.03/bounds.size.z
		else: mesh.scale.x*=.03/bounds.size.x
		bounds=mesh.global_transform*mesh.get_aabb()
		mesh.global_position.y+=global_position.y-bounds.position.y
		if label.begins_with("back skirting"):
			mesh.global_position.z+=wallpaper_front-bounds.position.z
		else:
			var side=signf(bounds.get_center().x-global_position.x)
			mesh.global_position.x+=side_fronts[side]-(bounds.end.x if side>0 else bounds.position.x)

func set_keyboard_blocked(blocked: bool) -> void:
	if not screen_surface or not key_surface: return
	if laptop_tween and laptop_tween.is_valid(): laptop_tween.kill()
	laptop_tween = create_tween().set_parallel(true)
	laptop_tween.tween_property(screen_surface, "albedo_color", Color("9c6366") if blocked else screen_normal, .3)
	laptop_tween.tween_property(key_surface, "albedo_color", Color("db9a91") if blocked else keys_normal, .3)

func get_cat_position(side: int) -> Vector3:
	return Vector3(4.7 * side, 0.06, -4.38)

func damage_wall(amount: float, side := 1) -> float:
	wallpaper_damage = minf(wallpaper_damage + amount, RULES.DAMAGE_LIMIT)
	return wallpaper_damage

func draw_scratch(from: Vector3, to: Vector3, duration: float) -> void:
	scratch_tweens = scratch_tweens.filter(func(t): return t.is_valid())
	# Bound visible geometry even if a shift is lengthened later.
	while marks.get_child_count() > 69:
		var oldest := marks.get_child(0)
		marks.remove_child(oldest)
		oldest.queue_free()
	for i in range(3):
		var mark := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.018, from.distance_to(to), 0.003)
		mark.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("755046")
		mark.material_override = material
		var offset := Vector3((i - 1) * .045, 0, 0)
		var start=from+offset
		var finish=to+offset
		start.z=ground_surface.wall_front_at(start)+.0015
		finish.z=ground_surface.wall_front_at(finish)+.0015
		mark.position = start
		mark.scale.y = .001
		marks.add_child(mark)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(mark, "scale:y", 1.0, duration)
		tween.tween_property(mark, "position", (start + finish) / 2, duration)
		scratch_tweens.append(tween)

func stop_scratches() -> void:
	for tween in scratch_tweens:
		if tween.is_valid(): tween.kill()
	scratch_tweens.clear()
