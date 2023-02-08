
extends Node


# Declare member variables here. Examples:
# var a = 2
# var b = "text"
onready var obj = get_node("Object")


func _ready():
	
	var curr_x = 0
	var curr_y = 90
	var curr_z = 0
	
	var target_x = 0
	var target_y = 0
	var target_z = 0
	
	obj.rotate_z(curr_z * PI / 180.0)
	obj.rotate_y(curr_y * PI / 180.0)
	obj.rotate_x(curr_x * PI / 180.0)
	
	var q_curr = Quat(obj.rotation)
	var q_target = Quat(Vector3(target_x, target_y, target_z))
	
	var q_rot = q_target * q_curr.inverse()
	
	print(q_rot)

