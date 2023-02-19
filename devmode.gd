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
var enable_yaw_control = false
var yaw_spd_fb = 0.5
var initial_euler = Vector3(0.0, 0.0, 0.0)
var target_euler = Vector3(180.0, 0.0, 0.0)
# ------------------------------------------------------------------------------


var t = Timer.new()

func _ready():
	var q = Angles.cboard_euler_to_quat(initial_euler/ 180.0 * PI)
	pitch_pid.kP = 1.0
	roll_pid.kP = 1.0
	yaw_pid.kP = 1.0
	robot.rotation = Angles.quat_to_godot_euler(q)
	t.one_shot = false
	t.connect("timeout", self, "dothings")
	add_child(t)
	t.start(0.02)

func _process(delta):
	pass


var delaycount = 0.0
var first = false

var pitch_pid = PIDController.new()
var roll_pid = PIDController.new()
var yaw_pid = PIDController.new()

func dothings():
	# Delay before starting in seconds (50 counts per second)
	if delaycount < (50 * 1.0):
		delaycount += 1
		return
	
	# Quaternion based control setup
	var q = Angles.godot_euler_to_quat(robot.rotation)
	var cur = Angles.quat_to_cboard_euler(q)
	
	# Simulate IMU yaw drift of 15 degrees
	# var qdrift = Angles.cboard_euler_to_quat(Vector3(0.0, 0.0, 15.0) * PI / 180.0)
	# q = qdrift * q
	
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
	
	# Crude proportional control which is good enough for a simulation
	var pitch_speed = 0.0
	var roll_speed = 0.0
	var yaw_speed = 0.0
	
	pitch_speed = pitch_pid.calculate(-e.x)
	roll_speed = roll_pid.calculate(-e.y)

	if enable_yaw_control:
		yaw_speed = yaw_pid.calculate(-e.z)
	else:
		yaw_speed = yaw_spd_fb
	
	# e is currently angular rotaiton about world axes
	# Localize it to the robot
	# Note: Cannot just pass this to global mode
	# since global mode does not account for yaw
	# Thus at 90 yaw, the x and y angular velocities would be swapped.
	var world_rot = Vector3(pitch_speed, roll_speed, yaw_speed)
	var local_rot = rotate_vector(world_rot, q.inverse())
	
	cboard.motor_wdog_feed()
	cboard.mode = cboard.MODE_LOCAL
	cboard.mc_set_local(0, 0, 0, local_rot.x, local_rot.y, local_rot.z)


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
