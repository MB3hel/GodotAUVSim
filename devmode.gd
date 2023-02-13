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
	var cboard_rot = Vector3(15.0, 45.0, 0.0);
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
	# print("Angle: ", a * 180.0 / PI)
	# print("Axis: ", v)
	# print("Error: ", err * 180.0 / PI)
	
	# Simple proportional control
	var pitch_speed = 5.0 * err.x
	pitch_speed = 1.0 if pitch_speed > 1.0 else pitch_speed
	pitch_speed = -1.0 if pitch_speed < -1.0 else pitch_speed
	var pitch_change_deg = pitch_speed * robot.max_rotation * 0.02
	
	var roll_speed = 5.0 * err.y
	roll_speed = 1.0 if roll_speed > 1.0 else roll_speed
	roll_speed = -1.0 if roll_speed < -1.0 else roll_speed
	var roll_change_deg = roll_speed * robot.max_rotation * 0.02
	
	robot.rotate_x(-pitch_change_deg * PI / 180.0)
	robot.rotate_y(-roll_change_deg * PI / 180.0)
	
