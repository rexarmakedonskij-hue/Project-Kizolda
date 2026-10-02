extends Node3D

var cup: Node3D
var puddle: MeshInstance3D
var spill_age := -1.0
var dirty := false
var tap_target := 0.0
const CUP_POSITION := Vector3(-1.24, .952, -1.1)

func material(color: String, roughness := .7) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = roughness
	return result

func mesh(parent: Node3D, shape: Mesh, position: Vector3, surface: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = surface
	node.position = position
	parent.add_child(node)
	return node

func cylinder(radius: float, height: float) -> CylinderMesh:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 40
	return shape

func _ready() -> void:
	var porcelain := material("e7c9aa", .28)
	var coffee := material("422619", .23)
	var coaster := mesh(self, cylinder(.17,.012), CUP_POSITION, material("315c56"))
	coaster.name = "CupCoaster"
	cup = Node3D.new()
	cup.name = "CupPivot"
	cup.position = CUP_POSITION + Vector3(0,.01,0)
	add_child(cup)
	mesh(cup, cylinder(.108,.225), Vector3(0,.115,0), porcelain)
	var rim := TorusMesh.new()
	rim.inner_radius = .091
	rim.outer_radius = .113
	ring_segments(rim)
	mesh(cup,rim,Vector3(0,.23,0),porcelain)
	mesh(cup,cylinder(.092,.005),Vector3(0,.223,0),coffee)
	var handle := TorusMesh.new()
	handle.inner_radius = .05
	handle.outer_radius = .073
	ring_segments(handle)
	var handle_node := mesh(cup,handle,Vector3(-.118,.12,0),porcelain)
	handle_node.rotation.x = PI / 2
	puddle = mesh(self,cylinder(.3,.006),Vector3(-1.43,.946,-1.2),coffee)
	puddle.name = "CoffeeSpill"
	puddle.scale = Vector3(.01,1,.01)
	puddle.hide()
	# Individual droplets make the spill readable beside the keyboard.
	for i in 7:
		var drop := mesh(puddle,cylinder(.025 + .004*(i%3),.004),Vector3(.34+.025*i,0,sin(i*2.0)*.16),coffee)
		drop.name = "Droplet%d" % i

func ring_segments(ring: TorusMesh) -> void:
	ring.rings = 32
	ring.ring_segments = 12

func spill() -> void:
	if dirty: return
	dirty = true
	spill_age = 0
	puddle.show()

func tap(amount: float) -> void:
	if not dirty: tap_target=clampf(amount,0,1)*.05

func _process(delta: float) -> void:
	if spill_age < 0:
		cup.rotation.z=lerpf(cup.rotation.z,tap_target,1-exp(-delta*28))
		return
	spill_age = minf(spill_age+delta, .65)
	var t := smoothstep(0,.65,spill_age)
	cup.rotation.z = PI/2*t
	cup.position.y = CUP_POSITION.y + .01 + .086*t
	puddle.scale = Vector3(lerpf(.01,1.1,t),1,lerpf(.01,.55,t))

func clean_progress(progress: float) -> void:
	puddle.transparency = clampf(progress*.85,0,.85)

func clean() -> void:
	dirty = false
	spill_age = -1
	tap_target = 0
	puddle.hide()
	puddle.transparency = 0
	cup.rotation = Vector3.ZERO
	cup.position = CUP_POSITION+Vector3(0,.01,0)
