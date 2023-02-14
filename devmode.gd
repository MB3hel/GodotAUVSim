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
	var cboard_rot = Vector3(0.0, 0.0, 0.0);
	# print("Orientation: ", Angles.quat_to_cboard_euler(Angles.cboard_euler_to_quat(cboard_rot * PI / 180.0)) * 180.0 / PI)
	robot.rotation = Angles.cboard_euler_to_godot_euler(cboard_rot * PI / 180.0);
	t.one_shot = false
	t.connect("timeout", self, "dothings")
	add_child(t)
	t.start(0.02)

func _process(delta):
	pass


var delaycount = 0.0
var enable_yaw_control = false

var target_euler = Vector3(15.0, 120.0, 0.0)

func dothings():
	# Delay before starting in seconds (50 counts per second)
	if delaycount < (50 * 1.0):
		delaycount += 1
		return
	
	var q = Angles.godot_euler_to_quat(robot.rotation)
	var qt = Angles.cboard_euler_to_quat(target_euler * PI / 180.0)
	
	var vgm = Vector3(0, 0, 0)
	vgm.x = 2.0 * (-q.x*q.z + q.w*q.y)
	vgm.y = 2.0 * (-q.w*q.x - q.y*q.z)
	vgm.z = -2.0 * (q.w*q.w + q.z*q.z) + 1.0
	
	var vgt = Vector3(0, 0, 0)
	vgt.x = 2.0 * (-qt.x*qt.z + qt.w*qt.y)
	vgt.y = 2.0 * (-qt.w*qt.x - qt.y*qt.z)
	vgt.z = -2.0 * (qt.w*qt.w + qt.z*qt.z) + 1.0
	
	var vgm_xz = project_xz(vgm)
	var vgm_yz = project_yz(vgm)
	
	var vgt_xz = project_xz(vgt)
	var vgt_yz = project_yz(vgt)
	
	
	var rollerr = 0.0
	var pitcherr = 0.0
	
	
	if vgm_xz.length() < 0.8:
		rollerr = 0.0
	else:
		rollerr = angle_between_in_plane(vgm_xz, vgt_xz, Vector3(0, 1, 0))
		rollerr *= 180.0 / PI
	
	if vgm_yz.length() < 0.8:
		pitcherr = 0.0
	else:
		pitcherr = angle_between_in_plane(vgm_yz, vgt_yz, Vector3(1, 0, 0))
		pitcherr *= 180.0 / PI
	
	pitcherr = restrict_angle_deg(pitcherr)
	rollerr = restrict_angle_deg(rollerr)
	
	if abs(pitcherr) > 90.0 or abs(rollerr) > 90.0:
		# There are two solutions (one with more roll and one with more pitch)
		# Calculate both and pick the smaller magnitude sum
		var p1 = pitcherr
		var r1 = restrict_angle_deg(180.0 - rollerr)
		var s1 = abs(p1) + abs(r1)
		
		var p2 = restrict_angle_deg(180.0 - pitcherr)
		var r2 = rollerr
		var s2 = abs(p2) + abs(r2)

		if s1 < s2:
			pitcherr = p1
			rollerr = r1
		else:
			pitcherr = p2
			rollerr = r2
			
	print(pitcherr)
	print(rollerr)
	print()

	var yawerr = 0.0
	if enable_yaw_control:
		var vhm = Vector3(0.0, 0.0, 0.0)
		vhm.x = 2.0 * (q.x*q.y - q.w*q.z)
		vhm.y = 2.0 * (q.w*q.w + q.y*q.y) - 1.0
		vhm.z = 2.0 * (q.y*q.z + q.w*q.x)
		var vht = Vector3(0.0, 0.0, 0.0)
		vht.x = 2.0 * (qt.x*qt.y - qt.w*qt.z)
		vht.y = 2.0 * (qt.w*qt.w + qt.y*qt.y) - 1.0
		vht.z = 2.0 * (qt.y*qt.z + qt.w*qt.x)
		var vhm_xy = project_xy(vhm)
		var vht_xy = project_xy(vht)
		if vhm_xy.length() < 0.8:
			yawerr = 0.0
		else:
			yawerr = angle_between_in_plane(vhm_xy, vht_xy, Vector3(0, 0, 1))
			yawerr *= 180.0 / PI
	
	yawerr = restrict_angle_deg(yawerr)
	
	var pitch_speed = 0.0
	var roll_speed = 0.0
	var yaw_speed = 0.0
	
	# Roll first, then enable both pitch and yaw
	# If rollerr is too high, pitch and yaw changes may cause issues
	
	roll_speed = 0.05 * (-rollerr);
	roll_speed = 1.0 if roll_speed > 1.0 else roll_speed
	roll_speed = -1.0 if roll_speed < -1.0 else roll_speed
	
	pitch_speed = 0.05 * (-pitcherr);
	pitch_speed = 1.0 if pitch_speed > 1.0 else pitch_speed
	pitch_speed = -1.0 if pitch_speed < -1.0 else pitch_speed
	
	yaw_speed = 0.05 * (yawerr)
	yaw_speed = 1.0 if yaw_speed > 1.0 else yaw_speed
	yaw_speed = -1.0 if yaw_speed < -1.0 else yaw_speed
	
	cboard.motor_wdog_feed()
	cboard.mode = cboard.MODE_GLOBAL
	
	# robot.rotation = Angles.cboard_euler_to_godot_euler(target_euler)
	
	cboard.mc_set_global(0, 0, 0, pitch_speed, roll_speed, yaw_speed, q)
	

func project_yz(v: Vector3) -> Vector3:
	 # Project v onto yz plane
	var n = Vector3(1, 0, 0)
	var u = v - ((v.dot(n) / n.length_squared()) * n)
	return u.normalized()


func project_xz(v: Vector3) -> Vector3:
	 # Project v onto yz plane
	var n = Vector3(0, 1, 0)
	var u = v - ((v.dot(n) / n.length_squared()) * n)
	return u.normalized()


func project_xy(v: Vector3) -> Vector3:
	 # Project v onto yz plane
	var n = Vector3(0, 0, 1)
	var u = v - ((v.dot(n) / n.length_squared()) * n)
	return u.normalized()


# Signed right hand angle between a and b in the plane to which n is normal
func angle_between_in_plane(a: Vector3, b: Vector3, n: Vector3):
	return atan2(a.cross(b).dot(n), a.dot(b))


func restrict_angle_deg(angle: float) -> float:
	while angle > 180.0:
		angle -= 360.0
	while angle < -180.0:
		angle += 360.0
	return angle
