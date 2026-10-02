extends RefCounted
# The visible room geometry defines support height. Thin woven decoration
# remains part of the floor, including its raised weave under each paw.
var surfaces: Array[AABB] = []
var walls: Array[AABB] = []
var baseline := 0.0
func _init(room: Node3D):
	baseline=room.global_position.y
	for mesh in room.find_children("*","MeshInstance3D",true,false):
		var name=String(mesh.name).to_lower().replace("_"," ")
		if name.begins_with("oak floorboard") or name.begins_with("rounded woven rug") or name.begins_with("rug weave"):
			surfaces.append(mesh.global_transform*mesh.get_aabb())
		elif name.begins_with("back wallpaper") or name.begins_with("wallpaper stripe") or name.begins_with("back skirting"):
			walls.append(mesh.global_transform*mesh.get_aabb())
func wall_candidates(point: Vector3) -> Array[AABB]:
	var candidates: Array[AABB]=[]
	for bounds in walls:
		if point.x+.10>=bounds.position.x and point.x-.10<=bounds.end.x and point.y+.15>=bounds.position.y and point.y-.15<=bounds.end.y:
			candidates.append(bounds)
	return candidates
func wall_front_at(point: Vector3, candidates: Array = []) -> float:
	var front := -INF
	for bounds in (walls if candidates.is_empty() else candidates):
		if point.x>=bounds.position.x and point.x<=bounds.end.x and point.y>=bounds.position.y and point.y<=bounds.end.y:
			front=maxf(front,bounds.end.z)
	return front
func height_at(point: Vector3) -> float:
	var height=baseline
	for bounds in surfaces:
		if point.x>=bounds.position.x and point.x<=bounds.end.x and point.z>=bounds.position.z and point.z<=bounds.end.z:
			height=maxf(height,bounds.end.y)
	return height-baseline
func height_under_paw(point: Vector3) -> float:
	var height=height_at(point)
	for offset in [Vector3(.025,0,0),Vector3(-.025,0,0),Vector3(0,0,.025),Vector3(0,0,-.025)]:
		height=maxf(height,height_at(point+offset))
	return height
