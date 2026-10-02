extends RefCounted
# Measurement only. Call sample() after frame_post_draw. Surfaces come from
# the actual instantiated office, including bevels, stripes, skirting and rug.
const CELL := .25
const CONTACT_GAP := .005
const PENETRATION_LIMIT := .003
const SURFACE_AXES := [1,2]
var cat
var room
var skin_sources := []
var floor_surfaces := []
var wall_surfaces := []
var floor_bins := {}
var wall_bins := {}

func _init(owner_cat, actual_room):
	cat = owner_cat
	room = actual_room
	var sk: Skeleton3D = cat.pose_player.skeleton
	for mesh in cat.model.find_children("*", "MeshInstance3D", true, false):
		var skin: Skin = mesh.get_skin()
		if skin == null: continue
		var bind_names := []
		for bind in skin.get_bind_count():
			var name := String(skin.get_bind_name(bind))
			var bone := sk.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)
			bind_names.append(String(sk.get_bone_name(bone)) if bone >= 0 else "")
		var labels := []
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var names := []
			var influences := int(bones.size()/maxi(vertices.size(),1))
			for vertex in vertices.size():
				var ownership := {}
				for slot in influences:
					var index := vertex*influences+slot
					var name: String = bind_names[bones[index]]
					if name.begins_with("leg_") and name.ends_with("_4"):
						name = name.trim_prefix("leg_").trim_suffix("_4")
						ownership[name] = float(ownership.get(name,0.0))+weights[index]
				var chosen := ""
				for name in ownership:
					if ownership[name] > .5: chosen = name
				names.append(chosen)
			labels.append(names)
		skin_sources.append({"mesh":mesh,"labels":labels})
	for mesh in room.find_children("*", "MeshInstance3D", true, false):
		var name: String = String(mesh.name).to_lower().replace("_", " ")
		if name.begins_with("oak floorboard") or name.begins_with("rounded woven rug") or name.begins_with("rug weave"):
			_add_surface(mesh, 1, floor_surfaces, floor_bins)
		if name.begins_with("back wallpaper") or name.begins_with("wallpaper stripe") or name.begins_with("back skirting"):
			_add_surface(mesh, 2, wall_surfaces, wall_bins)

func _project(point: Vector3, axis: int) -> Vector2:
	return Vector2(point.x, point.z if axis == 1 else point.y)

func _bin(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/CELL),floori(point.y/CELL))

func _add_surface(mesh: MeshInstance3D, axis: int, surfaces: Array, bins: Dictionary):
	var triangles := []
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	var top := -INF
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for index in range(0,count,3):
			var points := []
			var projected := []
			for corner in 3:
				var point: Vector3 = mesh.to_global(vertices[indices[index+corner] if not indices.is_empty() else index+corner])
				points.append(point)
				var q := _project(point,axis)
				projected.append(q)
				minimum = minimum.min(q)
				maximum = maximum.max(q)
				top = maxf(top,point[axis])
			var a: Vector2 = projected[0]
			var b: Vector2 = projected[1]
			var c: Vector2 = projected[2]
			var denominator := (b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
			if absf(denominator)<1e-10: continue
			triangles.append({"a":a,"b":b,"c":c,"inverse":1.0/denominator,
				"values":Vector3(points[0][axis],points[1][axis],points[2][axis]),
				"min":a.min(b).min(c),"max":a.max(b).max(c)})
	if triangles.is_empty(): return
	var surface_index := surfaces.size()
	surfaces.append({"name":String(mesh.name),"axis":axis,"triangles":triangles,"min":minimum,"max":maximum,"top":top})
	for triangle_index in triangles.size():
		var triangle: Dictionary=triangles[triangle_index]
		var low := _bin(triangle.min)
		var high := _bin(triangle.max)
		for x in range(low.x,high.x+1):
			for y in range(low.y,high.y+1):
				var key := Vector2i(x,y)
				if not bins.has(key): bins[key]=[]
				bins[key].append(Vector2i(surface_index,triangle_index))

func _surface_at(point: Vector3, axis: int, surfaces: Array, bins: Dictionary) -> Dictionary:
	var projected := _project(point,axis)
	var value := -INF
	var label := ""
	for entry in bins.get(_bin(projected),[]):
		var surface: Dictionary = surfaces[entry.x]
		for triangle in [surface.triangles[entry.y]]:
			if projected.x<triangle.min.x-.000001 or projected.x>triangle.max.x+.000001 or projected.y<triangle.min.y-.000001 or projected.y>triangle.max.y+.000001: continue
			var a: Vector2 = triangle.a
			var b: Vector2 = triangle.b
			var c: Vector2 = triangle.c
			var u: float = ((b.y-c.y)*(projected.x-c.x)+(c.x-b.x)*(projected.y-c.y))*triangle.inverse
			var v: float = ((c.y-a.y)*(projected.x-c.x)+(a.x-c.x)*(projected.y-c.y))*triangle.inverse
			if u<-.00001 or v<-.00001 or u+v>1.00001: continue
			var values: Vector3 = triangle.values
			var candidate := values.x*u+values.y*v+values.z*(1.0-u-v)
			if candidate>value:
				value=candidate
				label=surface.name
	return {"value":value,"name":label,"valid":not label.is_empty()}

func _paw_record() -> Dictionary:
	return {"vertices":0,"minimum_floor_gap":INF,"minimum_wall_gap":INF,
		"nearest_floor_distance":INF,"nearest_wall_distance":INF,
		"wall_vertices_within_5mm":0,"floor_vertices_within_5mm":0,
		"floor_surface":"","wall_surface":"","floor_vertex":{},"wall_vertex":{}}

func sample() -> Dictionary:
	var begin := Time.get_ticks_usec()
	var result := {"paws":{},"skin_vertices":0,"minimum_floor_gap":INF,"minimum_wall_gap":INF,
		"maximum_floor_penetration":0.0,"maximum_wall_penetration":0.0,
		"floor_penetrating_vertices":0,"wall_penetrating_vertices":0,"worst_floor_vertex":{},"worst_wall_vertex":{},
		"floor_surface_count":floor_surfaces.size(),"wall_surface_count":wall_surfaces.size(),
		"scope":"Actual renderer skeleton bake; mesh triangles define surfaces at each vertex footprint. Paw mask is >50% terminal paw bone weight; no separate claw geometry exists in this model."}
	for name in ["front_left","front_right","back_left","back_right"]: result.paws[name]=_paw_record()
	for source in skin_sources:
		var mesh: MeshInstance3D = source.mesh
		var world_transform:=mesh.global_transform
		var baked := mesh.bake_mesh_from_current_skeleton_pose()
		for surface in baked.get_surface_count():
			var arrays: Array = baked.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in vertices.size():
				var point:Vector3 = world_transform*vertices[index]
				if not point.is_finite():
					result["nonfinite_vertices"]=int(result.get("nonfinite_vertices",0))+1
					continue
				result.skin_vertices+=1
				var name: String = source.labels[surface][index]
				if not name.is_empty(): result.paws[name].vertices+=1
				# Only skin near the floor/back wall can penetrate these surfaces.
				for axis in SURFACE_AXES:
					if axis==1 and point.y>.18: continue
					if axis==2 and point.z>-4.70: continue
					var contact := _surface_at(point,axis,floor_surfaces if axis==1 else wall_surfaces,floor_bins if axis==1 else wall_bins)
					if not contact.valid: continue
					var kind := "floor" if axis==1 else "wall"
					var gap: float = point[axis]-contact.value
					var new_minimum:bool=gap<result["minimum_"+kind+"_gap"]
					var new_paw_minimum:bool=not name.is_empty() and gap<result.paws[name]["minimum_"+kind+"_gap"]
					# Detailed provenance is retained for minima, not allocated
					# for the tens of thousands of unreported vertices per frame.
					if new_minimum or new_paw_minimum:
						var record := {"mesh":String(mesh.name),"surface":surface,"vertex":index,"world":[point.x,point.y,point.z],"room_surface":contact.name,"room_surface_coordinate":contact.value}
						if new_minimum:
							result["minimum_"+kind+"_gap"]=gap
							result["worst_"+kind+"_vertex"]=record
						if new_paw_minimum:
							result.paws[name]["minimum_"+kind+"_gap"]=gap
							result.paws[name][kind+"_surface"]=contact.name
							result.paws[name][kind+"_vertex"]=record
					if gap<0:
						result["maximum_"+kind+"_penetration"]=maxf(result["maximum_"+kind+"_penetration"],-gap)
						if gap<-.001: result[kind+"_penetrating_vertices"]+=1
					if name.is_empty(): continue
					var paw: Dictionary = result.paws[name]
					paw["nearest_"+kind+"_distance"]=minf(paw["nearest_"+kind+"_distance"],absf(gap))
					if absf(gap)<=CONTACT_GAP: paw[kind+"_vertices_within_5mm"]+=1
	var supports := 0
	for name in result.paws:
		var paw: Dictionary = result.paws[name]
		paw["floor_supported"] = paw.minimum_floor_gap>=-PENETRATION_LIMIT and paw.nearest_floor_distance<=CONTACT_GAP
		paw["wall_supported"] = paw.minimum_wall_gap>=-PENETRATION_LIMIT and paw.nearest_wall_distance<=CONTACT_GAP
		paw["supported"] = paw.floor_supported or paw.wall_supported
		if paw.supported: supports+=1
	result["supports"]=supports
	result["measurement_usec"]=Time.get_ticks_usec()-begin
	return result

func surfaces_metadata() -> Dictionary:
	var result := {"floor":[],"wall":[]}
	for spec in [["floor",floor_surfaces],["wall",wall_surfaces]]:
		for surface in spec[1]:
			result[spec[0]].append({"name":surface.name,"maximum_surface_coordinate":surface.top,
				"projected_min":[surface.min.x,surface.min.y],"projected_max":[surface.max.x,surface.max.y],"triangles":surface.triangles.size()})
	return result
