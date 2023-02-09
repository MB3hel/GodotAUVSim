extends Node

####################################################################################################
# NOTE: Control board and godot use different euler angle conventions
# Godot uses a "first Y, then X, and Z last" convention (doesn't explicitly 
# state intrinsic vs extrinsic either). Note: This is composition order
# Control board uses extrinsic angles. First around world X, then around world Y, 
# then around world Z. Note: this is composition order.
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
	var t0 = +2.0 * (q.w * q.x + q.y * q.z)
	var t1 = +1.0 - 2.0 * (q.x * q.x + q.y * q.y)
	var pitch = atan2(t0, t1)
	var t2 = +2.0 * (q.w * q.y - q.z * q.x)
	t2 = +1.0 if t2 > +1.0 else t2
	t2 = -1.0 if t2 < -1.0 else t2
	var roll = asin(t2)
	var t3 = +2.0 * (q.w * q.z + q.x * q.y)
	var t4 = +1.0 - 2.0 * (q.y * q.y + q.z * q.z)
	var yaw = atan2(t3, t4)
	return Vector3(pitch, roll, yaw)

func cboard_euler_to_quat(e: Vector3) -> Quat:
	var q = Quat(0, 0, 0, 0)
	var p = e.x;
	var r = e.y;
	var y = e.z;
	q.x = sin(p/2.0) * cos(r/2.0) * cos(y/2.0) - cos(p/2.0) * sin(r/2.0) * sin(y/2.0)
	q.y = cos(p/2.0) * sin(r/2.0) * cos(y/2.0) + sin(p/2.0) * cos(r/2.0) * sin(y/2.0)
	q.z = cos(p/2.0) * cos(r/2.0) * sin(y/2.0) - sin(p/2.0) * sin(r/2.0) * cos(y/2.0)
	q.w = cos(p/2.0) * cos(r/2.0) * cos(y/2.0) + sin(p/2.0) * sin(r/2.0) * sin(y/2.0)
	return q

func cboard_euler_to_godot_euler(ce: Vector3) -> Vector3:
	return quat_to_godot_euler(cboard_euler_to_quat(ce))

func godot_euler_to_cboard_euler(ge: Vector3) -> Vector3:
	return quat_to_cboard_euler(godot_euler_to_quat(ge))
