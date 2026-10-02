extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(condition: bool, label: String):
	checks+=1
	if condition: print("PASS: ",label)
	else:
		failures+=1
		push_error(label)
func run():
	var game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	var hand=game.player.pet_hand
	var model=hand.SURFACE_MODEL.instantiate()
	game.add_child(model)
	var skeleton: Skeleton3D=model.find_child("Skeleton3D",true,false)
	var mesh: MeshInstance3D=model.find_child("mesh_cat",true,false)
	var surface=hand.FUR_SURFACE.new()
	surface.bind_model(model,skeleton,hand)
	var baked=surface.load_baked(mesh,skeleton)
	check(not baked.is_empty(),"Baked data matches the imported cat geometry and rig")
	check(var_to_bytes(baked)==var_to_bytes(surface.geometry),"Baked contact geometry is byte-identical to the freshly built surface")
	var head=skeleton.find_bone("head")
	var previous=skeleton.get_bone_rest(head)
	var changed=previous
	changed.origin.y+=.001
	skeleton.set_bone_rest(head,changed)
	check(surface.load_baked(mesh,skeleton).is_empty(),"A changed skeletal rest rejects stale contact data")
	skeleton.set_bone_rest(head,previous)
	var previous_bind=mesh.skin.get_bind_pose(0)
	var changed_bind=previous_bind
	changed_bind.origin.x+=.001
	mesh.skin.set_bind_pose(0,changed_bind)
	check(surface.load_baked(mesh,skeleton).is_empty(),"A changed skin bind rejects stale contact data")
	mesh.skin.set_bind_pose(0,previous_bind)
	check(not surface.load_baked(mesh,skeleton).is_empty(),"Restoring the original rig restores cache validity")
	var previous_mesh=mesh.mesh
	var edited_mesh=ArrayMesh.new()
	for index in previous_mesh.get_surface_count():
		var arrays=previous_mesh.surface_get_arrays(index)
		if index==0:
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			vertices[0].x+=.001
			arrays[Mesh.ARRAY_VERTEX]=vertices
		edited_mesh.add_surface_from_arrays(previous_mesh.surface_get_primitive_type(index),arrays)
	mesh.mesh=edited_mesh
	check(surface.load_baked(mesh,skeleton).is_empty(),"A changed imported mesh rejects stale contact data")
	mesh.mesh=previous_mesh
	surface.bind_model(model,skeleton,hand)
	var count=surface.palm_vertices.size()
	surface.bind_model(model,skeleton,hand)
	check(surface.palm_vertices.size()==count,"Rebinding a contact surface does not duplicate palm samples")
	print("PETTING_SURFACE_CACHE ",checks," checks; failures=",failures)
	model.free()
	game.free()
	quit(1 if failures else 0)
