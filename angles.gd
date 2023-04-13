################################################################################
# file: angles.gd
# author: Marcus Behel
################################################################################
# The control board and Godot use different euler angle conventions.
# Godot uses a Y-X'-Z'' convention
# Control Board uses a Z-X'-Y'' convention
# NOTE THAT ALL EULER ANGLES MUST BE IN RADIANS FOR THESE FUNCTIONS TO WORK
################################################################################

extends Node

func quat_to_godot_euler(q: Quat) -> Vector3:
	return q.get_euler()

func godot_euler_to_quat(e: Vector3) -> Quat:
	return Quat(e)
	
func quat_to_cboard_euler(q: Quat) -> Vector3:
	var pitch = asin(2.0 * (q.y*q.z + q.w*q.x))
	var roll
	var yaw
	
	var pitchdeg = 180.0 * pitch / PI
	if abs(90 - abs(pitchdeg)) < 0.1:
		# Pitch is +/- 90 degrees
		# This is gimbal lock scenario
		# Roll and yaw mean the same thing
		# roll + yaw = 2 * atan2(q.y, q.w)
		# Can split among roll and yaw any way (not unique)
		yaw = 2.0 * atan2(q.y, q.w)
		roll = 0.0
	else:
		var roll_numer = 2.0 * (q.w*q.y - q.x*q.z)
		var roll_denom = 1.0 - 2.0 * (q.x*q.x + q.y*q.y)
		roll = atan2(roll_numer, roll_denom)
		
		var yaw_numer = -2.0 * (q.x*q.y - q.w*q.z)
		var yaw_denom = 1.0 - 2.0 * (q.x*q.x + q.z*q.z)
		yaw = atan2(yaw_numer, yaw_denom)
	
	return Vector3(pitch, roll, yaw)

func cboard_euler_to_quat(e: Vector3) -> Quat:
	var pitch = e.x
	var roll = e.y
	var yaw = e.z
	var q = Quat()
	var cr = cos(roll / 2.0)
	var sr = sin(roll / 2.0)
	var cp = cos(pitch / 2.0)
	var sp = sin(pitch / 2.0)
	var cy = cos(yaw / 2.0)
	var sy = sin(yaw / 2.0)
	q.w = cy * cp * cr - sy * sp * sr
	q.x = cy * cr * sp - sy * cp * sr
	q.y = cy * cp * sr + sy * cr * sp
	q.z = cy * sp * sr + sy * cp * cr
	return q

func cboard_euler_to_godot_euler(ce: Vector3) -> Vector3:
	return quat_to_godot_euler(cboard_euler_to_quat(ce))

func godot_euler_to_cboard_euler(ge: Vector3) -> Vector3:
	return quat_to_cboard_euler(godot_euler_to_quat(ge))
