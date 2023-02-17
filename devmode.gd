# Used to hijack simulator for development. Disables standard TCP interface
# and instead adds this as a node. Can use ready and process to control simulator


extends Node


# Set to true to hijack simulator
# Will not work in export templates
var devmode = false

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
	
	# Remove yaw component if yaw control not enabled
	var tgt = target_euler
	if not enable_yaw_control:
		tgt.z = cur.z
	
	# Target quaternion
	var qt = Angles.cboard_euler_to_quat(tgt * PI / 180.0)
	
	# Convert to axis angle and use this to determine angular velocities
	var res = quat_to_axis_angle(diff_quat(q, qt))
	var axis = res[1]
	var angle = res[0]
	var e = axis * angle
	
	# e is currently angular rotaiton about world axes
	# Localize it to the robot
	# Note: Cannot just pass this to global mode
	# since global mode does not account for yaw
	# Thus at 90 yaw, the x and y angular velocities would be swapped.
	e = rotate_vector(e, q.inverse())
	
	# Crude proportional control which is good enough for a simulation
	var pitch_speed = 0.0
	var roll_speed = 0.0
	var yaw_speed = 0.0
	
	pitch_speed = 1.0 * (-e.x);
	pitch_speed = 1.0 if pitch_speed > 1.0 else pitch_speed
	pitch_speed = -1.0 if pitch_speed < -1.0 else pitch_speed

	roll_speed = 1.0 * (-e.y);
	roll_speed = 1.0 if roll_speed > 1.0 else roll_speed
	roll_speed = -1.0 if roll_speed < -1.0 else roll_speed

	if enable_yaw_control:
		yaw_speed = 1.0 * (-e.z)
		yaw_speed = 1.0 if yaw_speed > 1.0 else yaw_speed
		yaw_speed = -1.0 if yaw_speed < -1.0 else yaw_speed
	
	cboard.motor_wdog_feed()
	cboard.mode = cboard.MODE_LOCAL
	cboard.mc_set_local(0, 0, 0, pitch_speed, roll_speed, yaw_speed)


func diff_quat(a: Quat, b: Quat) -> Quat:
	if a.dot(b) < 0.0:
		return a * -b.inverse()
	else:
		return a * b.inverse()


func quat_to_axis_angle(q: Quat) -> Array:
	q = q.normalized()
	var axis = Vector3(q.x, q.y, q.z)
	var angle = 2.0 * atan2(axis.length(), q.w)
	return [angle, axis.normalized()]


func rotate_vector(v: Vector3, q: Quat) -> Vector3:
	var qv = Quat(v.x, v.y, v.z, 0.0)
	var qconj = Quat(-q.x, -q.y, -q.z, q.w)
	var qr = q * qv * qconj
	var r = Vector3(qr.x, qr.y, qr.z)
	return r
