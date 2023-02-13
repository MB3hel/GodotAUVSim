# Used to hijack simulator for development. Disables standard TCP interface
# and instead adds this as a node. Can use ready and process to control simulator


extends Node


# Set to true to hijack simulator
# Will not work in export templates
var devmode = true

var sim: Simulator = null
var robot: Robot = null
var cboard: ControlBoard = null


func should_hijack():
	# Do not hijack on standalone builds
	if OS.has_feature("standalone"):
		return false
	
	# Do not hijack on release builds
	if not OS.is_debug_build():
		return false
	
	return self.devmode


####################################################################################################
# Hard coded stuff for development use
####################################################################################################

var t = Timer.new()

func _ready():
	sim.reset_sim()
	var cboard_rot = Vector3(0.0, 180.0, 0.0);
	robot.rotation = Angles.cboard_euler_to_godot_euler(cboard_rot * PI / 180.0);
	print("Orientation: ", Angles.godot_euler_to_cboard_euler(robot.rotation) * 180.0 / PI)
	
	t.one_shot = false
	t.connect("timeout", self, "dothings")
	add_child(t)
	t.start(0.02)

func _process(delta):
	pass

func dothings():
	var q = Angles.godot_euler_to_quat(robot.rotation)
	var vgm = Vector3(0, 0, 0)
	vgm.x = 2.0 * (-q.x*q.z + q.w*q.y)
	vgm.y = 2.0 * (-q.w*q.x - q.y*q.z)
	vgm.z = -q.w*q.w + q.x*q.x + q.y*q.y - q.z*q.z
	
	# Note: Singularity at pitch / roll of 90 because vgm.z == 0
	# Also works wrong for pitch / roll of 180
	var scale = -1.0 / vgm.z
	var vdir = Vector3(vgm.y, vgm.x, 0.0) * scale
	
	print(vdir)

