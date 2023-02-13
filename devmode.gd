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
	sim.reset_sim()
	var cboard_rot = Vector3(15.0, 10.0, 0.0);
	robot.rotation = Angles.cboard_euler_to_godot_euler(cboard_rot * PI / 180.0);
	t.one_shot = false
	t.connect("timeout", self, "dothings")
	add_child(t)
	t.start(0.02)

func _process(delta):
	pass


var delaycount = 0.0

func dothings():
	if delaycount < 50:
		delaycount += 1
		return
	var q = Angles.godot_euler_to_quat(robot.rotation)
	var vgm = Vector3(0, 0, 0)
	vgm.x = 2.0 * (-q.x*q.z + q.w*q.y)
	vgm.y = 2.0 * (-q.w*q.x - q.y*q.z)
	vgm.z = -q.w*q.w + q.x*q.x + q.y*q.y - q.z*q.z
	
	var vgm_xz = project_xz(vgm)
	var vgm_yz = project_yz(vgm)
	
	var rollerr = 0.0
	var pitcherr = 0.0
	
	if vgm_xz.length() < 0.8:
		rollerr = 0.0
	else:
		rollerr = angle_between_in_plane(vgm_xz, Vector3(0, 0, -1), Vector3(0, 1, 0))
		rollerr *= 180.0 / PI
	
	if vgm_yz.length() < 0.8:
		pitcherr = 0.0
	else:
		pitcherr = angle_between_in_plane(vgm_yz, Vector3(0, 0, -1), Vector3(1, 0, 0))
		pitcherr *= 180.0 / PI
	
	if abs(pitcherr) > 90.0 or abs(rollerr) > 90.0:
		# There are two solutions (one with more roll and one with more pitch)
		# Calculate both and pick the smaller magnitude sum
		var p1 = pitcherr
		var r1 = 180.0 - rollerr
		var s1 = abs(p1) + abs(r1)
		
		var p2 = 180.0 - pitcherr
		var r2 = rollerr
		var s2 = abs(p2) + abs(r2)

		if s1 < s2:
			pitcherr = p1
			rollerr = r1
		else:
			pitcherr = p2
			rollerr = r2
	
	
	# Proportional control for sasssist orientation control
	var pitch_speed = 1.0 * (-pitcherr);
	pitch_speed = 1.0 if pitch_speed > 1.0 else pitch_speed
	pitch_speed = -1.0 if pitch_speed < -1.0 else pitch_speed
	var roll_speed = 1.0 * (-rollerr);
	roll_speed = 1.0 if roll_speed > 1.0 else roll_speed
	roll_speed = -1.0 if roll_speed < -1.0 else roll_speed
	
	cboard.motor_wdog_feed()
	cboard.mc_set_global(0, 0, 0, pitch_speed, roll_speed, 0, q)
	

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

# Signed right hand angle between a and b in the plane to which n is normal
func angle_between_in_plane(a: Vector3, b: Vector3, n: Vector3):
	return atan2(a.cross(b).dot(n), a.dot(b))
