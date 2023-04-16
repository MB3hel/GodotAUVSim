################################################################################
# file: vehicle.gd
# author: Marcus Behel
################################################################################
# Manges vehicle motion and properties
################################################################################

extends RigidBody

################################################################################
# Properties (public)
################################################################################

# Additional (custom) properties
var thruster_force = Vector3()
var thruster_torque = Vector3()

################################################################################



################################################################################
# Globals (private)
################################################################################

# Current net force and torque from thrusters
var _cf = Vector3(0.0, 0.0, 0.0)
var _ct = Vector3(0.0, 0.0, 0.0)

################################################################################



################################################################################
# Godot Engine Functions
################################################################################

func _ready():
	# Initialize robot / physics properties
	self.thruster_force = Vector3(3.8, 3.8, 3.8)
	self.thruster_torque = Vector3(0.25, 0.5, 1.0)

func _process(delta):
	# Apply forces & torques at center of the vehicle
	self.add_central_force(to_global(_cf) - global_transform.origin)
	self.add_torque(to_global(_ct) - global_transform.origin)

################################################################################



################################################################################
# Motion functions
################################################################################

# Element wise multiply of vectors
func _ewmul(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(a.x*b.x, a.y*b.y, a.z*b.z)

func move_local(x: float, y: float, z: float, p: float, r: float, h: float):
	_cf = _ewmul(Vector3(x, y, z), thruster_force)
	_ct = _ewmul(Vector3(p, r, h), thruster_torque)

################################################################################
