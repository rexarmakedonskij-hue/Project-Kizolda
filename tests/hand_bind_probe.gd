extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var hand = load("res://player/petting_hand.gd").new()
	root.add_child(hand)
	hand.set_process(false)
	for index in hand.skeleton.get_bone_count():
		print("BIND ", hand.skeleton.get_bone_name(index), " rest=", hand.rest[hand.skeleton.get_bone_name(index)], " pose=",hand.skeleton.get_bone_pose(index))
	hand.age=.8
	hand.touching=true
	hand.pose(Vector3(.30,1.24,-1.28),Vector3(0,1.575,-1.270))
	for index in hand.skeleton.get_bone_count():
		var name = hand.skeleton.get_bone_name(index)
		var current = hand.skeleton.get_bone_global_pose(index)
		var relative = hand.skeleton.get_bone_global_pose(hand.skeleton.find_bone("palm")).affine_inverse()*current
		var original = hand.rest["palm"].affine_inverse()*hand.rest[name]
		print("CURRENT ",name," relative_origin=",relative.origin," original_origin=",original.origin," delta=",relative.origin.distance_to(original.origin))
	quit()
