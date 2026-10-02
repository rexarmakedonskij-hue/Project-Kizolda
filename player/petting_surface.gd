extends RefCounted
# Cache bind data once, then follow the actual animated fur and palm skin on CPU.
const BAKED_PATH := "res://assets/models/glb/godot_mvp/cat_petting_surface.bin"
const BAKED_VERSION := 1
var cat_skeleton: Skeleton3D
var cat_mesh: MeshInstance3D
var hand_skeleton: Skeleton3D
var cat_vertices := []
var cat_triangles := []
var palm_vertices := []
static var geometry_cache := {}
var head_bone := -1
var head_inverse := Transform3D.IDENTITY
var geometry := {}
var last_bind_usec := 0
var last_bind_memory_bytes := 0
var last_update_usec := 0
var last_correction_usec := 0
var geometry_source := ""
func geometry_fingerprint(mesh: MeshInstance3D, skeleton: Skeleton3D) -> String:
	# Imported geometry and rig data are available both in the editor and in exports.
	# Source FBX files need not be present in an exported game.
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for surface in mesh.mesh.get_surface_count():
		var arrays=mesh.mesh.surface_get_arrays(surface)
		for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_INDEX,Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS]:
			digest.update(var_to_bytes(arrays[slot]))
	for index in mesh.skin.get_bind_count():
		digest.update(var_to_bytes([mesh.skin.get_bind_name(index),mesh.skin.get_bind_bone(index),mesh.skin.get_bind_pose(index)]))
	for index in skeleton.get_bone_count():
		digest.update(var_to_bytes([skeleton.get_bone_name(index),skeleton.get_bone_parent(index),skeleton.get_bone_global_rest(index)]))
	return digest.finish().hex_encode()
func load_baked(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	if not FileAccess.file_exists(BAKED_PATH): return {}
	var file=FileAccess.open(BAKED_PATH,FileAccess.READ)
	if file==null: return {}
	var payload=file.get_var(false)
	if not payload is Dictionary: return {}
	if payload.get("version",0)!=BAKED_VERSION or payload.get("fingerprint","")!=geometry_fingerprint(mesh,skeleton): return {}
	var data=payload.get("geometry",{})
	if not data is Dictionary: return {}
	for field in ["points","triangles","records","bounds","centers","nodes","root"]:
		if not data.has(field): return {}
	if data.nodes.is_empty() or data.root<0 or data.root>=data.nodes.size(): return {}
	return data
func bind(cat, hand):
	bind_model(cat.model,cat.pose_player.skeleton,hand)
func bind_model(model: Node3D, skeleton: Skeleton3D, hand):
	var started=Time.get_ticks_usec()
	var before_memory=Performance.get_monitor(Performance.MEMORY_STATIC)
	cat_vertices=[]
	cat_triangles=[]
	palm_vertices=[]
	geometry={}
	geometry_source=""
	cat_skeleton=skeleton
	hand_skeleton=hand.skeleton
	var mesh: MeshInstance3D=model.find_child("mesh_cat",true,false)
	cat_mesh=mesh
	var head=cat_skeleton.find_bone("head")
	head_bone=head
	var key=str(mesh.mesh.get_instance_id())+":"+str(mesh.skin.get_instance_id())
	if not geometry_cache.has(key) and not "--rebuild-petting-surface" in OS.get_cmdline_user_args():
		var baked=load_baked(mesh,cat_skeleton)
		if not baked.is_empty():
			geometry_cache[key]=baked
			geometry_source="baked"
	if geometry_cache.has(key):
		if geometry_source.is_empty(): geometry_source="memory"
		geometry=geometry_cache[key]
		cat_vertices=geometry.records
		cat_triangles=geometry.triangles
	else:
		geometry_source="built"
		for surface in mesh.mesh.get_surface_count():
			var arrays=mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var accepted := {}
			for index in vertices.size():
				var record=vertex_record(mesh,cat_skeleton,arrays,index)
				record["surface"]=surface
				record["index"]=index
				var head_weight := 0.0
				for influence in record.influences:
					if influence.bone==head: head_weight+=influence.weight
				# Include blended skull boundaries so the projection has no holes.
				if head_weight>.01:
					accepted[index]=cat_vertices.size()
					cat_vertices.append(record)
			for index in indices.size()/3:
				var a=indices[index*3]
				var b=indices[index*3+1]
				var c=indices[index*3+2]
				if accepted.has(a) and accepted.has(b) and accepted.has(c): cat_triangles.append([accepted[a],accepted[b],accepted[c]])
	for arm_mesh in hand.model.find_children("*","MeshInstance3D",true,false):
		if arm_mesh.name!="HandSkin": continue
		for surface in arm_mesh.mesh.get_surface_count():
			var arrays=arm_mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var selected := 0
			for index in vertices.size():
				var point=vertices[index]
				if point.y<-.009 and point.z>.67 and point.z<.73 and absf(point.x)<.04:
					if selected%12==0: palm_vertices.append(vertex_record(arm_mesh,hand_skeleton,arrays,index))
					selected+=1
	if not geometry_cache.has(key):
		var transforms := []
		for index in cat_skeleton.get_bone_count(): transforms.append(cat_skeleton.global_transform*cat_skeleton.get_bone_global_rest(index))
		var inverse_head: Transform3D=transforms[head_bone].affine_inverse()
		var points := PackedVector3Array()
		for record in cat_vertices: points.append(inverse_head*skin_vertex(record,transforms))
		var bounds := []
		var centers := PackedVector3Array()
		var ids := []
		for index in cat_triangles.size():
			var triangle=cat_triangles[index]
			var box=AABB(points[triangle[0]],Vector3.ZERO)
			box=box.expand(points[triangle[1]]).expand(points[triangle[2]])
			bounds.append(box)
			centers.append(box.get_center())
			ids.append(index)
		geometry={"points":points,"triangles":cat_triangles,"records":cat_vertices,"bounds":bounds,"centers":centers,"nodes":[]}
		geometry["root"]=build_node(ids)
		geometry_cache[key]=geometry
	else: geometry=geometry_cache[key]
	last_bind_usec=Time.get_ticks_usec()-started
	last_bind_memory_bytes=int(Performance.get_monitor(Performance.MEMORY_STATIC)-before_memory)
func vertex_record(mesh: MeshInstance3D, skeleton: Skeleton3D, arrays: Array, index: int) -> Dictionary:
	var influences := []
	for slot in 4:
		var weight: float=arrays[Mesh.ARRAY_WEIGHTS][index*4+slot]
		if weight<=0: continue
		var bind_index: int=arrays[Mesh.ARRAY_BONES][index*4+slot]
		var bone=skeleton.find_bone(mesh.skin.get_bind_name(bind_index))
		if bone<0: bone=mesh.skin.get_bind_bone(bind_index)
		influences.append({"bone":bone,"weight":weight,"point":mesh.skin.get_bind_pose(bind_index)*arrays[Mesh.ARRAY_VERTEX][index]})
	return {"influences":influences}
func skin_vertex(record: Dictionary, transforms: Array) -> Vector3:
	var point := Vector3.ZERO
	for influence in record.influences: point+=(transforms[influence.bone]*influence.point)*influence.weight
	return point
func bone_transforms(skeleton: Skeleton3D) -> Array:
	var transforms := []
	skeleton.force_update_all_bone_transforms()
	for index in skeleton.get_bone_count(): transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(index))
	return transforms
func update_fur():
	var started=Time.get_ticks_usec()
	cat_skeleton.force_update_all_bone_transforms()
	head_inverse=(cat_skeleton.global_transform*cat_skeleton.get_bone_global_pose(head_bone)).affine_inverse()
	last_update_usec=Time.get_ticks_usec()-started
func fur_height(point: Vector3) -> float:
	var origin=head_inverse*(point+Vector3.UP)
	var direction=head_inverse.basis*Vector3.DOWN
	var closest := INF
	var stack=[geometry.root]
	while not stack.is_empty():
		var node: Dictionary=geometry.nodes[stack.pop_back()]
		var near=ray_box(origin,direction,node.box)
		if near==INF or near>closest: continue
		if node.has("ids"):
			for index in node.ids:
				var triangle=geometry.triangles[index]
				var a: Vector3=geometry.points[triangle[0]]
				var b: Vector3=geometry.points[triangle[1]]
				var c: Vector3=geometry.points[triangle[2]]
				var ab=b-a
				var ac=c-a
				var cross=direction.cross(ac)
				var determinant=ab.dot(cross)
				if absf(determinant)<1e-18: continue
				var relative=origin-a
				var u=relative.dot(cross)/determinant
				if u<0 or u>1: continue
				var other=relative.cross(ab)
				var v=direction.dot(other)/determinant
				if v<0 or u+v>1: continue
				var distance=ac.dot(other)/determinant
				if distance>=0: closest=minf(closest,distance)
		else:
			stack.append(node.left)
			stack.append(node.right)
	return point.y+1-closest if closest!=INF else -INF
func ray_box(origin: Vector3, direction: Vector3, box: AABB) -> float:
	var near := 0.0
	var far := INF
	for axis in 3:
		if absf(direction[axis])<1e-18:
			if origin[axis]<box.position[axis] or origin[axis]>box.end[axis]: return INF
			continue
		var a=(box.position[axis]-origin[axis])/direction[axis]
		var b=(box.end[axis]-origin[axis])/direction[axis]
		near=maxf(near,minf(a,b))
		far=minf(far,maxf(a,b))
		if near>far: return INF
	return near
func build_node(ids: Array) -> int:
	var box: AABB=geometry.bounds[ids[0]]
	for index in ids: box=box.merge(geometry.bounds[index])
	var number: int=geometry.nodes.size()
	geometry.nodes.append({"box":box})
	if ids.size()<=12:
		geometry.nodes[number]["ids"]=ids
	else:
		var axis=box.size.max_axis_index()
		ids.sort_custom(func(a,b):return geometry.centers[a][axis]<geometry.centers[b][axis])
		var middle=ids.size()/2
		var left=build_node(ids.slice(0,middle))
		var right=build_node(ids.slice(middle))
		geometry.nodes[number]["left"]=left
		geometry.nodes[number]["right"]=right
	return number
func palm_correction(gap: float) -> float:
	var started=Time.get_ticks_usec()
	var transforms=bone_transforms(hand_skeleton)
	var closest := INF
	for record in palm_vertices:
		var point=skin_vertex(record,transforms)
		var height=fur_height(point)
		if height!=-INF: closest=minf(closest,point.y-height)
	last_correction_usec=Time.get_ticks_usec()-started
	return clampf(gap-closest,-.05,.05) if closest!=INF else 0.0
func debug_skin_match() -> Dictionary:
	var transforms=bone_transforms(cat_skeleton)
	var baked := {}
	var errors := []
	var maximum := 0.0
	var rigid_maximum := 0.0
	var rigid_crown_maximum := 0.0
	for index in range(0,cat_vertices.size(),23):
		var record: Dictionary=cat_vertices[index]
		var mesh: MeshInstance3D=cat_mesh
		if not baked.has(mesh): baked[mesh]=mesh.bake_mesh_from_current_skeleton_pose()
		var arrays=baked[mesh].surface_get_arrays(record.surface)
		var gpu: Vector3=mesh.to_global(arrays[Mesh.ARRAY_VERTEX][record.index])
		var cpu=skin_vertex(record,transforms)
		var error=cpu.distance_to(gpu)
		maximum=maxf(maximum,error)
		var cached: Vector3=geometry.points[index]
		var rigid_error=(transforms[head_bone]*cached).distance_to(gpu)
		rigid_maximum=maxf(rigid_maximum,rigid_error)
		if absf(cached.x)<.055 and cached.y>.025 and cached.z>-.025 and cached.z<.12: rigid_crown_maximum=maxf(rigid_crown_maximum,rigid_error)
		var material=mesh.mesh.surface_get_material(record.surface)
		errors.append({"error_m":error,"surface":record.surface,"material":material.resource_name if material else "none","gpu":str(gpu),"cpu":str(cpu)})
	errors.sort_custom(func(a,b):return a.error_m>b.error_m)
	return {"scope":"Full CPU skin match is diagnostic only. Runtime BVH uses a rigid head-local approximation of the imported rest mesh; full GPU contact poses separately verify its contact footprint.","max_error_m":maximum,"rigid_head_max_error_m":rigid_maximum,"rigid_crown_max_error_m":rigid_crown_maximum,"vertices":cat_vertices.size(),"triangles":cat_triangles.size(),"cache_serialized_bytes":var_to_bytes(geometry).size(),"bind_usec":last_bind_usec,"bind_memory_delta_bytes":last_bind_memory_bytes,"worst":errors.slice(0,8)}
