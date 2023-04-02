## Robot script handles moving the robot itself
## Control baord equivilent math is implemented here

extends RigidBody
class_name Robot


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

func _process(delta):
	var f = ewmul(curr_force, max_force)
	self.add_central_force(to_global(f) - global_transform.origin)
	var t = ewmul(curr_torque, max_torque)
	self.add_torque(to_global(t) - global_transform.origin)


####################################################################################################
