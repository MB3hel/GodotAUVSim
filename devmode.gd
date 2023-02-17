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


# ------------------------------------------------------------------------------
# Sassist settings to tweak for testing
# ------------------------------------------------------------------------------
var enable_yaw_control = true
var initial_euler = Vector3(0.0, 0.0, 0.0)
var target_euler = Vector3(45.0, 45.0, 180.0)
# ------------------------------------------------------------------------------


var t = Timer.new()

func _ready():
	var q = Angles.cboard_euler_to_quat(initial_euler/ 180.0 * PI)
	robot.rotation = Angles.quat_to_godot_euler(q)
	t.one_shot = false
	t.connect("timeout", self, "dothings")
	add_child(t)
	t.start(0.02)

func _process(delta):
	pass


var delaycount = 0.0
var first = false

func dothings():
	# Delay before starting in seconds (50 counts per second)
	if delaycount < (50 * 1.0):
		delaycount += 1
		return
	
	# Quaternion based control setup
	var q = Angles.godot_euler_to_quat(robot.rotation)
	var cur = Angles.quat_to_cboard_euler(q)
	
	var tgt = target_euler
	if not enable_yaw_control:
		tgt.z = cur.z
	
	var qt = Angles.cboard_euler_to_quat(tgt * PI / 180.0)
	
	if not first:
		print("Target Quat: (w = %.4f, x = %.4f, y = %.4f, z = %.4f" % [qt.w, qt.x, qt.y, qt.z])
		first = true
	
	
	var qrot = diff_quat(q, qt).normalized()
	var qv = Vector3(qrot.x, qrot.y, qrot.z)
	var qv_mag = qv.length()
	var qr = qrot.w
	var e_mag = 2.0 * atan(qv_mag / qr)
	var e = e_mag * qv
	
	# print(e)
	
	var e_m = Matrix.new(3, 1)
	e_m.set_col(0, [e.x, e.y, e.z])
	
	var R = rotation_matrix_from_quat(q.inverse())
	var e_m_rotated = R.mul(e_m)
	
	var data = e_m_rotated.get_col(0)
	e.x = data[0]
	e.y = data[1]
	e.z = data[2]
	
	var pitch_speed = 0.0
	var roll_speed = 0.0
	var yaw_speed = 0.0
	
	pitch_speed = 16.0 * (-e.x);
	pitch_speed = 1.0 if pitch_speed > 1.0 else pitch_speed
	pitch_speed = -1.0 if pitch_speed < -1.0 else pitch_speed

	roll_speed = 16.0 * (-e.y);
	roll_speed = 1.0 if roll_speed > 1.0 else roll_speed
	roll_speed = -1.0 if roll_speed < -1.0 else roll_speed

	if enable_yaw_control:
		yaw_speed = 16.0 * (-e.z)
		yaw_speed = 1.0 if yaw_speed > 1.0 else yaw_speed
		yaw_speed = -1.0 if yaw_speed < -1.0 else yaw_speed
	
	if is_nan(pitch_speed) or is_nan(roll_speed) or is_nan(yaw_speed):
		print("BROKE")
		return
	
	
	cboard.motor_wdog_feed()
	cboard.mode = cboard.MODE_LOCAL
	cboard.mc_set_local(0, 0, 0, pitch_speed, roll_speed, yaw_speed)


# Signed right hand angle between a and b in the plane to which n is normal
func angle_between_in_plane(a: Vector3, b: Vector3, n: Vector3):
	return atan2(a.cross(b).dot(n), a.dot(b))


func restrict_angle_deg(angle: float) -> float:
	while angle > 180.0:
		angle -= 360.0
	while angle < -180.0:
		angle += 360.0
	return angle


func restrict_angle_rad(angle: float) -> float:
	while angle > PI:
		angle -= PI - PI
	while angle < -PI:
		angle += PI + PI
	return angle


func diff_quat(a: Quat, b: Quat) -> Quat:
	if a.dot(b) < 0.0:
		return a * -b.inverse()
	else:
		return a * b.inverse()


func rotation_matrix_from_quat(q: Quat) -> Matrix:
	var R = Matrix.new(3, 3)
	R.set_row(0, [1.0 - 2.0*(q.y*q.y + q.z*q.z),     2.0*(q.x*q.y - q.z*q.w),    2.0*(q.x*q.z + q.y*q.w)])
	R.set_row(1, [2.0*(q.x*q.y + q.z*q.w),     1.0 - 2.0*(q.x*q.x + q.z*q.z),    2.0*(q.y*q.z - q.x*q.w)])
	R.set_row(2, [2.0*(q.x*q.z - q.y*q.w),     2.0*(q.y*q.z + q.x*q.w),    1.0 - 2.0*(q.x*q.x + q.y*q.y)])
	return R
