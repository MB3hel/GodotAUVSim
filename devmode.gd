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
	var cboard_rot = Vector3(0.0, 0.0, 0.0)
	robot.rotation = Angles.cboard_euler_to_godot_euler(cboard_rot * PI / 180.0)
	t.one_shot = false
	t.connect("timeout", self, "dothings")
	add_child(t)
	t.start(0.02)

func _process(delta):
	pass


var delaycount = 0.0
var enable_yaw_control = true

var target_euler = Vector3(15.0, 120.0, 90.0)
var first = false

func dothings():
	# Delay before starting in seconds (50 counts per second)
	if delaycount < (50 * 1.0):
		delaycount += 1
		return
	
	# Quaternion based control setup
	var q = Angles.godot_euler_to_quat(robot.rotation)
	var qt = Angles.cboard_euler_to_quat(target_euler * PI / 180.0)
	
	if not first:
		print("Target Quat: (w = %.4f, x = %.4f, y = %.4f, z = %.4f" % [qt.w, qt.x, qt.y, qt.z])
		first = true
	
	var qrot = diff_quat(q, qt).normalized()
	
	
	# var angle = acos(qrot.w) * 2.0
	# var axis = Vector3(0.0, 0.0, 0.0)
	# if angle != 0.0:
	# 	axis.x = qrot.x / sin(angle / 2.0)
	# 	axis.y = qrot.y / sin(angle / 2.0)
	# 	axis.z = qrot.z / sin(angle / 2.0)
	# angle = restrict_angle_deg(angle * 180.0 / PI)
	# var angular_velocity = angle * axis.normalized()
	# var e = angular_velocity
	# NOTE: Signs on e are not always what would be expected
	# Example: (both start at 0, 0, 0)
	# Target of 0, 120, 0 requires negative e.y (-x, +z)
	# Target of 15, 180, 170 requires positive e.y (-x, +z)
	# Perhaps an issue because of the 180 specifically???
	# Also 15, 120, 0 just doesn't work at all??? Very wrong signs??? No clue.
	# Target of 15, 120, 0 requires (+x, -y, +z)
	# The "shortest path" motion also doesn't seem to work quite right in cases with multiple axes of motion
	# It seems to move away then back most of the time. Possibly releated. Possibly not. Possibly just bad tuning
	
	# Alt e vector??? Maybe works??? Maybe doesn't???
	var qv = Vector3(qrot.x, qrot.y, qrot.z)
	var qv_mag = qv.length()
	var qr = qrot.w
	var e_mag = 2.0 * atan(qv_mag / qr)
	var e = e_mag * qv
	
	var pitch_speed = 0.0
	var roll_speed = 0.0
	var yaw_speed = 0.0
	
	pitch_speed = 16.0 * (-e.x);
	pitch_speed = 1.0 if pitch_speed > 1.0 else pitch_speed
	pitch_speed = -1.0 if pitch_speed < -1.0 else pitch_speed

	roll_speed = 16.0 * (-e.y);
	roll_speed = 1.0 if roll_speed > 1.0 else roll_speed
	roll_speed = -1.0 if roll_speed < -1.0 else roll_speed

	yaw_speed = 16.0 * (-e.z)
	yaw_speed = 1.0 if yaw_speed > 1.0 else yaw_speed
	yaw_speed = -1.0 if yaw_speed < -1.0 else yaw_speed
	
	if is_nan(pitch_speed) or is_nan(roll_speed) or is_nan(yaw_speed):
		print("BROKE")
		return
		
	
	cboard.motor_wdog_feed()
	cboard.mode = cboard.MODE_LOCAL
	cboard.mc_set_global(0, 0, 0, pitch_speed, roll_speed, yaw_speed, q)


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

