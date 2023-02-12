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
	var cboard_rot = Vector3(15.0, 45.0, 0.0);
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
		err = v * a
		
	# This is probably best to use as error input to PID controllers
	print("Angle: ", a * 180.0 / PI)
	print("Axis: ", v)
	print("Error: ", err * 180.0 / PI)
	
	# TODO: Repeatedly run this with a PID and see what happens
	
	# Can euler be used? Should it be?
	# Answer NO. Can't get rid of yaw component!
	# var qdiff = Quat(0.0, 0.0, 0.0, 0.0)
	# qdiff.w = cos(a / 2.0)
	# qdiff.x = v.x * sin(a / 2.0)
	# qdiff.y = v.y * sin(a / 2.0)
	# qdiff.z = v.z * sin(a / 2.0)
	# print("Quat Diff: ", qdiff)
	
	# var ediff = Angles.quat_to_cboard_euler(qdiff)
	# print("Euler Diff: ", ediff)

func _process(delta):
	pass
