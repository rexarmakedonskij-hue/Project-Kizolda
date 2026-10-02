@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	apply_vertex_colors(scene)
	return scene

static func apply_vertex_colors(scene: Node) -> void:
	# B3 also paints the groom, ears and irises into COLOR_0.
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] == null or arrays[Mesh.ARRAY_COLOR].is_empty():
				continue
			var material := instance.mesh.surface_get_material(surface)
			if material is StandardMaterial3D:
				material.vertex_color_use_as_albedo = true
