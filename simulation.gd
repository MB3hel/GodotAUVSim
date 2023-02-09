## Top level simulation control script
## Attach to root node in scene

extends Spatial

####################################################################################################
# Godot node functions
####################################################################################################

onready var robot = get_node("Robot")
onready var ui = get_node("UIRoot")

func _ready():
	# Setup robot parameters
	robot.max_rotation = 75
	robot.max_translation = 1
	
	# Test move the robot in LOCAL mode
	#                   x    y    z    p    r    y
	robot.mc_set_local(0.0, 0.0, 0.3, 0.0, 0.0, 0.5)


func _process(_delta):
	ui.curr_translation = robot.curr_translation
	ui.curr_rotation = robot.curr_rotation
	ui.robot_euler = robot.rotation_degrees
	ui.robot_quat = Quat(robot.rotation)
	
####################################################################################################
