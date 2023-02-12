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

func _ready():
	sim.reset_sim()
	var cboard_rot = Vector3(15.0, 91, 0.0);
	robot.rotation = Angles.cboard_euler_to_godot_euler(cboard_rot * PI / 180.0);
	
	print("Orientation: ", Angles.godot_euler_to_cboard_euler(robot.rotation) * 180.0 / PI)
	
	var q = Angles.godot_euler_to_quat(robot.rotation)
	var stdgrav = Vector3(0, 0, -1)
	var grav = Vector3(0, 0, 0)
	grav.x = 2.0 * (-q.x*q.z + q.w*q.y)
	grav.y = 2.0 * (-q.w*q.x - q.y*q.z)
	grav.z = -q.w*q.w + q.x*q.x + q.y*q.y - q.z*q.z
	var v = grav.cross(stdgrav)
	var a = acos(grav.dot(stdgrav))
	
	var err = null
	if a == 0:
		# Vectors exactly aligned.
		err = Vector3(0.0, 0.0, 0.0)
	elif a == PI:
		# Vectors exactly opposite each other.
		# Could pick either roll or yaw for the error.
		# Picking roll as it will likley impact depth sensor less on most vehicles
		err = Vector3(0.0, 180.0, 0.0)
	else:
		# TODO: Does this work on multi axis rotations???
		err = v * a
		
	print("Angle: ", a * 180.0 / PI)
	print("Axis: ", v)
	print("Error: ", err * 180.0 / PI)
	
	# robot.rotate_z(-err.z)
	# robot.rotate_y(-err.y)
	# robot.rotate_x(-err.x)
	
	# print("New Orientation: ", Angles.godot_euler_to_cboard_euler(robot.rotation) * 180.0 / PI)

func _process(delta):
	pass
