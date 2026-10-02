extends SceneTree
# Run after importing a changed cat mesh/rig, then ship the validated data with it.
func _initialize(): call_deferred("run")
func run():
	var game=load("res://main/main.tscn").instantiate()
	root.add_child(game)
	var hand=game.player.pet_hand
	var model=hand.SURFACE_MODEL.instantiate()
	game.add_child(model)
	var surface=hand.FUR_SURFACE.new()
	surface.bind_model(model,model.find_child("Skeleton3D",true,false),hand)
	var mesh=model.find_child("mesh_cat",true,false)
	var payload={"version":surface.BAKED_VERSION,"fingerprint":surface.geometry_fingerprint(mesh,surface.cat_skeleton),"geometry":surface.geometry}
	var file=FileAccess.open(surface.BAKED_PATH,FileAccess.WRITE)
	if file==null:
		push_error("Cannot save baked petting contact surface")
		quit(1)
		return
	file.store_var(payload,false)
	file.close()
	print("PETTING_SURFACE_BAKED ",payload.fingerprint," points=",surface.geometry.points.size()," triangles=",surface.geometry.triangles.size()," nodes=",surface.geometry.nodes.size())
	model.free()
	game.free()
	quit()
