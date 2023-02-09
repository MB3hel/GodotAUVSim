class_name ControlBoard


####################################################################################################
# Godot class stuff
####################################################################################################

var robot = null

func _init(robot):
	self.robot = robot

func _ready():
	pass

func _process(_delta):
	pass

####################################################################################################


####################################################################################################
# Motor Control
####################################################################################################

func mc_set_global(x: float, y: float, z: float, pitch: float, roll: float, yaw: float, curr_quat: Quat):
	# Current quaternion to gravity vector
	var gravity_vector = Vector3(0, 0, 0)
	gravity_vector[0] = 2.0 * (-curr_quat.x*curr_quat.z + curr_quat.w*curr_quat.y)
	gravity_vector[1] = 2.0 * (-curr_quat.w*curr_quat.x - curr_quat.y*curr_quat.z)
	gravity_vector[2] = -curr_quat.w*curr_quat.w + curr_quat.x*curr_quat.x + curr_quat.y*curr_quat.y - curr_quat.z*curr_quat.z

# Motor control speed set in LOCAL mode (equivilent of control board LOCAL mode)
func mc_set_local(x: float, y: float, z: float, pitch: float, roll: float, yaw: float):
	# Base level of motion supported in simulator is LOCAL mode motion
	# RAW mode is not supported. Thus, this function applies the desired motion to the
	# provided robot object (see robot.gd)
	x = limit(x, -1.0, 1.0)
	y = limit(y, -1.0, 1.0)
	z = limit(z, -1.0, 1.0)
	pitch = limit(pitch, -1.0, 1.0)
	roll = limit(roll, -1.0, 1.0)
	yaw = limit(yaw, -1.0, 1.0)
	robot.curr_translation.x = x
	robot.curr_translation.y = y
	robot.curr_translation.z = z
	robot.curr_rotation.x = pitch
	robot.curr_rotation.y = roll
	robot.curr_rotation.z = yaw

####################################################################################################


####################################################################################################
# Helper functions
####################################################################################################

func limit(v: float, lower: float, upper: float) -> float:
	if v > upper:
		return upper
	if v < lower:
		return lower
	return v
	
func skew(v: Vector3) -> Basis:
	# return np.matrix([
	# 	[0, -v[2], v[1]],
	# 	[v[2], 0, -v[0]],
	# 	[-v[1], v[0], 0]
	# ])
	pass

####################################################################################################
