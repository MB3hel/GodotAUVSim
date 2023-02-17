extends Node

####################################################################################################
# NOTE: Control board and godot use different euler angle conventions
# Godot uses a "first Y, then X, and Z last" convention (doesn't explicitly 
# state intrinsic vs extrinsic either). Note: This is composition order
#
# Control baord uses intrinsic angles (specifically Tait–Bryan angles) cooresponding to what
# are typically referred to as pitch (attitude), roll (bank), and yaw (heading)
# However, the control board uses a less standard coordinate system (differnt from what is 
# typically used with aircraft these angles are commonly used with). For the control board,
# yaw is about z, roll is about y, and pitch is about x (and positive z is up not down).
# Thus the convention used is z-x'-y'' (yaw around world z, the pitch about object x, finally
# roll around object y). The terms yaw, roll, and pitch refer to the same things though.
# Yaw is the heading of the robot in the world. Pitch is the front of the robot raising or lowering
# and roll is a banking motion about the pitched (and yawed) y axis.
#
# When applying rotations to godot objects, the godot convention must be used
# When passing angles to the control board script (and displaying in UIs)
# the control board convention is used
#
# Quaternions are used as a go between
# 
# NOTE THAT ALL EULER ANGLES MUST BE IN RADIANS FOR THESE FUNCTIONS!!!
# 
####################################################################################################

func quat_to_godot_euler(q: Quat) -> Vector3:
	return q.get_euler()

func godot_euler_to_quat(e: Vector3) -> Quat:
	return Quat(e)
	
func quat_to_cboard_euler(q: Quat) -> Vector3:
	var pitch = asin(2.0 * (q.y*q.z + q.w*q.x))
	
	# TODO: Handle gimbal lock (pitch +/- 90)
	
	var roll_numer = 2.0 * (q.w*q.y - q.x*q.z)
	var roll_denom = 1.0 - 2.0 * (q.x*q.x + q.y*q.y)
	var roll = atan2(roll_numer, roll_denom)
	
	var yaw_numer = 2.0 * (q.x*q.y - q.w*q.z)
	var yaw_denom = 1.0 - 2.0 * (q.x*q.x + q.z*q.z)
	var yaw = atan2(yaw_numer, yaw_denom)
	
	return Vector3(pitch, roll, yaw)

# z-x'-y'' convention
# Yaw then pitch then roll
# Yaw about z
# Pitch about x'
# Roll about y''
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
