extends RefCounted
# Inspect the renderer's deformed triangles against the same imported rest skin.
static func measure(hand, rest_meshes: Dictionary) -> Dictionary:
	var maximum := 1.0
	var above := 0
	var total := 0
	var nonfinite := 0
	var worst := {}
	var tip_sum := Vector3.ZERO
	var tip_count := 0
	for mesh in hand.model.find_children("*","MeshInstance3D",true,false):
		var baked=mesh.bake_mesh_from_current_skeleton_pose()
		for surface in baked.get_surface_count():
			var after=baked.surface_get_arrays(surface)
			var before=rest_meshes[mesh.name].surface_get_arrays(surface)
			var old: PackedVector3Array=before[Mesh.ARRAY_VERTEX]
			var points: PackedVector3Array=after[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=after[Mesh.ARRAY_INDEX]
			for index in points.size():
				if not points[index].is_finite(): nonfinite+=1
				if mesh.name=="HandSkin" and old[index].z>.85:
					tip_sum+=points[index]
					tip_count+=1
			for triangle in indices.size()/3:
				for edge in 3:
					var a=indices[triangle*3+edge]
					var b=indices[triangle*3+(edge+1)%3]
					var length=old[a].distance_to(old[b])
					if length<.00001: continue
					var ratio=points[a].distance_to(points[b])/length
					if ratio>maximum:
						maximum=ratio
						worst={"mesh":mesh.name,"rest_a":str(old[a]),"rest_b":str(old[b]),"posed_a":str(points[a]),"posed_b":str(points[b]),"rest_edge_m":length,"posed_edge_m":points[a].distance_to(points[b])}
					if ratio>2: above+=1
					total+=1
	return {"max_edge_stretch":maximum,"worst_edge":worst,"edges_over_twice_rest":above,"triangle_edges":total,"nonfinite_vertices":nonfinite,"tip_vertices":tip_count,"tip_centroid":tip_sum/maxi(1,tip_count)}
