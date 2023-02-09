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

# Motor control speed set in LOCAL mode (equivilent of control board LOCAL mode)
func mc_set_local(x: float, y: float, z: float, pitch: float, roll: float, yaw: float):
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
	
####################################################################################################
