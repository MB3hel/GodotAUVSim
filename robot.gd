## Robot script handles moving the robot itself
## Control baord equivilent math is implemented here

extends RigidBody
class_name Robot

# Done the same way control board does this
# Done using 15ms timer so calculated at roughly the same rate
# Must be mutex protected since simulator commands (set_rot) will need to manually
# correct this.
var accum_euler_mutex = Mutex.new()
var accum_euler = Vector3(0, 0, 0)
var accum_timer = Timer.new()
var prev_quat = Quat(0, 0, 0, 1)

var max_force = Vector3(4.2, 4.2, 4.2)
var max_torque = Vector3(0.15, 0.3, 0.6)


# If not ideal motion:
#   These are "percent of max force or torque" (-1.0 to 1.0)
var curr_force = Vector3(0.0, 0.0, 0.0);
var curr_torque = Vector3(0.0, 0.0, 0.0);


####################################################################################################
# Godot functions
####################################################################################################

func ewmul(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(a.x * b.x, a.y * b.y, a.z * b.z)

func _ready():
	self.weight = 9.8
	self.linear_damp = 3.8
	self.angular_damp = 2.9
	
	add_child(accum_timer)
	accum_timer.connect("timeout", self, "do_euler_accum")
	accum_timer.one_shot = false
	accum_timer.start(0.015)

func _process(delta):
	var f = ewmul(curr_force, max_force)
	self.add_central_force(to_global(f) - global_transform.origin)
	var t = ewmul(curr_torque, max_torque)
	self.add_torque(to_global(t) - global_transform.origin)


####################################################################################################

func do_euler_accum():
	var quat = Angles.godot_euler_to_quat(self.rotation)
	var quat_same = (quat.w == prev_quat.w) and (quat.x == prev_quat.x) and (quat.y == prev_quat.y) and (quat.z == prev_quat.z)
	if not quat_same:
		var dot_f = quat.dot(prev_quat)
		var diff_quat = Quat(0, 0, 0, 1)
		if dot_f < 0:
			diff_quat = -prev_quat
		else:
			diff_quat = prev_quat
		diff_quat = diff_quat.inverse()
		diff_quat = quat * diff_quat
		var diff_euler = Angles.quat_to_cboard_euler(diff_quat)
		diff_euler = diff_euler * 180.0 / PI
		accum_euler += diff_euler
	prev_quat = quat


func set_trans(trans):
	self.translation = trans

func set_rot(rot):
	self.accum_euler_mutex.lock()
	var oldrot = self.rotation
	self.rotation = rot
	accum_euler += rot - oldrot
	self.accum_euler_mutex.unlock()
