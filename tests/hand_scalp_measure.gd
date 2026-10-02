extends RefCounted
# Geometric diagnostic using actual rendered skin, without a proxy skull shape.
static func measure(cat, hand, sample_shift := Vector3.ZERO) -> Dictionary:
	var crown: Vector3=hand.contact
	var cell := .01
	var triangles := {}
	var included := 0
	for mesh in cat.model.find_children("*","MeshInstance3D",true,false):
		if mesh.name!="mesh_cat": continue
		var baked=mesh.bake_mesh_from_current_skeleton_pose()
		if baked==null: continue
		for surface in baked.get_surface_count():
			var arrays=baked.surface_get_arrays(surface)
			var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for index in indices.size()/3:
				var a: Vector3=mesh.to_global(points[indices[index*3]])
				var b: Vector3=mesh.to_global(points[indices[index*3+1]])
				var c: Vector3=mesh.to_global(points[indices[index*3+2]])
				var low=Vector3(minf(a.x,minf(b.x,c.x)),minf(a.y,minf(b.y,c.y)),minf(a.z,minf(b.z,c.z)))
				var high=Vector3(maxf(a.x,maxf(b.x,c.x)),maxf(a.y,maxf(b.y,c.y)),maxf(a.z,maxf(b.z,c.z)))
				if high.x<crown.x-.10 or low.x>crown.x+.10 or high.z<crown.z-.15 or low.z>crown.z+.10: continue
				var normal: Vector3=mesh.global_basis*(normals[indices[index*3]]+normals[indices[index*3+1]]+normals[indices[index*3+2]])
				included+=1
				for x in range(floori(low.x/cell),floori(high.x/cell)+1):
					for z in range(floori(low.z/cell),floori(high.z/cell)+1):
						var key=Vector2i(x,z)
						if not triangles.has(key): triangles[key]=[]
						triangles[key].append([a,b,c,signf(normal.y)])
	var maximum_depth := 0.0
	var deepest := Vector3.ZERO
	var tested := 0
	var penetrated := 0
	var depths := []
	var palm_gaps := []
	for mesh in hand.model.find_children("*","MeshInstance3D",true,false):
		if mesh.name!="HandSkin": continue
		var baked=mesh.bake_mesh_from_current_skeleton_pose()
		for surface in baked.get_surface_count():
			var points: PackedVector3Array=baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var rest_points: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex_index in points.size():
				var vertex=points[vertex_index]
				var point: Vector3=mesh.to_global(vertex)+sample_shift
				if absf(point.x-crown.x)>.10 or point.z<crown.z-.15 or point.z>crown.z+.10: continue
				var key=Vector2i(floori(point.x/cell),floori(point.z/cell))
				if not triangles.has(key): continue
				var hits := []
				for triangle in triangles[key]:
					var a: Vector3=triangle[0]
					var b: Vector3=triangle[1]
					var c: Vector3=triangle[2]
					var ab=Vector2(b.x-a.x,b.z-a.z)
					var ac=Vector2(c.x-a.x,c.z-a.z)
					var ap=Vector2(point.x-a.x,point.z-a.z)
					var det=ab.cross(ac)
					if absf(det)<.000000001: continue
					var u=ap.cross(ac)/det
					var v=ab.cross(ap)/det
					if u<-.00001 or v<-.00001 or u+v>1.00001: continue
					var height=a.y+u*(b.y-a.y)+v*(c.y-a.y)
					hits.append([height,triangle[3]])
				if hits.is_empty(): continue
				hits.sort_custom(func(a,b):return a[0]<b[0])
				var winding := 0.0
				var closest_exit := INF
				var previous_height := -INF
				var closest_below := -INF
				for hit in hits:
					# Shared triangle edges can give the same surface hit twice.
					if absf(hit[0]-previous_height)<.00001: continue
					if hit[0]>point.y:
						winding+=hit[1]
						if hit[1]>0: closest_exit=minf(closest_exit,hit[0])
					elif hit[1]>0: closest_below=maxf(closest_below,hit[0])
					previous_height=hit[0]
				tested+=1
				var depth=closest_exit-point.y if winding>0 and closest_exit!=INF else 0.0
				var source_point: Vector3=rest_points[vertex_index]
				if source_point.y<-.009 and source_point.z>.67 and source_point.z<.73 and absf(source_point.x)<.04:
					if depth>0: palm_gaps.append(-depth)
					elif closest_below!=-INF: palm_gaps.append(point.y-closest_below)
				depths.append(depth)
				if depth>.003: penetrated+=1
				if depth>maximum_depth:
					maximum_depth=depth
					deepest=point
	depths.sort()
	palm_gaps.sort()
	return {"scope":"Vertical rays through actual GPU-deformed cat mesh in contact footprint; signed outward surface normals distinguish solid volume from air below projecting ears. Palm gap samples use authored central underside vertices, excluding wrist and fingers. Raw geometric diagnostic, not a proxy collision shape.","sample_shift":str(sample_shift),"cat_triangles":included,"sampled_hand_vertices":tested,"max_depth_m":maximum_depth,"vertices_deeper_than_3mm":penetrated,"deepest_hand_point":str(deepest),"contact":str(crown),"depth_p99_m":depths[floori(depths.size()*.99)] if not depths.is_empty() else null,"palm_gap_samples":palm_gaps.size(),"closest_palm_gap_m":palm_gaps[0] if not palm_gaps.is_empty() else null,"median_palm_gap_m":palm_gaps[palm_gaps.size()/2] if not palm_gaps.is_empty() else null}
