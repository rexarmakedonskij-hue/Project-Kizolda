extends RefCounted
# Immutable skin points expressed in each terminal paw bone's bind frame.
# Shared by grounded movement and other contact solvers; no posed nodes cached.
static var mesh_cache := {}
const FOOT_NAMES := ["front_left","front_right","back_left","back_right"]

static func get_pads(model: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var pads := {}
	for name in FOOT_NAMES: pads[name] = PackedVector3Array()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var skin: Skin = mesh.get_skin()
		if skin == null or mesh.mesh == null: continue
		var key := str(mesh.mesh.get_instance_id())+":"+str(skin.get_instance_id())
		if not mesh_cache.has(key):
			var bind_feet := {}
			for bind in skin.get_bind_count():
				var bind_name := String(skin.get_bind_name(bind))
				var bone := skeleton.find_bone(bind_name) if not bind_name.is_empty() else skin.get_bind_bone(bind)
				if bone < 0: continue
				var name := String(skeleton.get_bone_name(bone))
				if name.begins_with("leg_") and name.ends_with("_4"):
					var foot_name := name.trim_prefix("leg_").trim_suffix("_4")
					if foot_name in FOOT_NAMES: bind_feet[bind]=foot_name
			if bind_feet.is_empty():
				mesh_cache[key]={}
				continue
			var mesh_pads := {}
			for name in FOOT_NAMES: mesh_pads[name]=PackedVector3Array()
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				if vertices.is_empty() or bones.is_empty(): continue
				var influences := int(bones.size()/vertices.size())
				for vertex in vertices.size():
					for slot in influences:
						var offset := vertex*influences+slot
						if weights[offset] < .98: continue
						var bind := bones[offset]
						if bind_feet.has(bind):
							var name: String = bind_feet[bind]
							var points: PackedVector3Array = mesh_pads[name]
							points.append(skin.get_bind_pose(bind)*vertices[vertex])
							mesh_pads[name]=points
			mesh_cache[key]=mesh_pads
		for name in mesh_cache[key]:
			var points: PackedVector3Array = pads[name]
			points.append_array(mesh_cache[key][name])
			pads[name]=points
	return pads
