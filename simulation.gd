## Top level simulation control script
## Attach to root node in scene

extends Spatial

####################################################################################################
# Godot node functions
####################################################################################################

onready var robot = get_node("Robot")

func _ready():
	# Setup robot parameters
	robot.max_rotation = 75
	robot.max_translation = 1
	
	# Test move the robot in LOCAL mode
	#                   x    y    z    p    r    y
	robot.mc_set_local(0.0, 0.0, 0.1, 0.0, 0.0, 0.0)

func _process(delta):
	pass
	
####################################################################################################
