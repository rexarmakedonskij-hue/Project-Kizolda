extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var cat=load("res://cats/cat.tscn").instantiate()
 root.add_child(cat)
 cat.set_process(false)
 var sk: Skeleton3D=cat.pose_player.skeleton
 for i in cat.tail_motion.bones.size():
  var bone: int=cat.tail_motion.bones[i]
  var rest:=sk.get_bone_global_rest(bone)
  print("TAIL_AXIS ",sk.get_bone_name(bone)," cached=",cat.tail_motion.directions[i]," y=",rest.basis.y.normalized()," dot=",rest.basis.y.normalized().dot(cat.tail_motion.directions[i]))
 cat.free()
 quit()
