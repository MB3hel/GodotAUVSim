################################################################################
# file: vehicle.gd
# author: Marcus Behel
################################################################################
# Manges vehicle motion and properties
################################################################################

extends RigidBody

################################################################################
# Thruster map
################################################################################

# Physical thruster properties
# Each thruster's behavior is defined by three properties:
#   - Force Position: The position relative to the origin of the vehicle at
#                     which the thruster excerpts a force on the vehicle.
#   - Force Vector:   The direction vector in the direction force is applied
#                     to the vehicle by the thruster. UNIT VECTORS!
#   - Force Strength: Magnitude of the force the thruster excerpts on the
#                     vehicle. This is split into positive (forward) and
#                     negative magnitudes b/c most motors except different
#                     torque in the positive and negative directions. These
#                     magnitudes are for full throttle (+100% or -100%).
# Each of these is defined in an array below and associated with a thruster by
# index. Thruster index = thruster number - 1 therefore 0 = T1, 1 = T2, ...

var _thr_force_pos = [
	Vector3(-0.309, -0.241, 0),				# T1
	Vector3(0.309, -0.241, 0),				# T2
	Vector3(-0.309, 0.241, 0),				# T3
	Vector3(0.309, 0.241, 0),				# T4
	Vector3(-0.396, -0.117, 0),				# T5
	Vector3(0.396, -0.117, 0),				# T6
	Vector3(-0.396, 0.117, 0),				# T7
	Vector3(0.396, 0.117, 0)				# T8
]

var _thr_force_vec = [
	Vector3(1, -1, 0).normalized(),			# T1
	Vector3(-1, -1, 0).normalized(),		# T2
	Vector3(-1, -1, 0).normalized(),		# T3
	Vector3(1, -1, 0).normalized(),			# T4
	Vector3(0, 0, 1).normalized(),			# T5
	Vector3(0, 0, -1).normalized(),			# T6
	Vector3(0, 0, -1).normalized(),			# T7
	Vector3(0, 0, 1).normalized(),			# T8
]

# Values for T200@16V
var _thr_force_pos_mag = [
	5.25,									# T1
	5.25,									# T2
	5.25,									# T3
	5.25,									# T4
	5.25,									# T5
	5.25,									# T6
	5.25,									# T7
	5.25									# T8
]

# Values for T200@16V
var _thr_force_neg_mag = [
	4.1,									# T1
	4.1,									# T2
	4.1,									# T3
	4.1,									# T4
	4.1,									# T5
	4.1,									# T6
	4.1,									# T7
	4.1										# T8
]

################################################################################



################################################################################
# Globals
################################################################################

# Cached thruster forces
var _thr_forces = [
	Vector3(0, 0, 0),
	Vector3(0, 0, 0),
	Vector3(0, 0, 0),
	Vector3(0, 0, 0),
	Vector3(0, 0, 0),
	Vector3(0, 0, 0),
	Vector3(0, 0, 0),
	Vector3(0, 0, 0)
]

################################################################################



################################################################################
# Godot Engine Functions
################################################################################

func _ready():
	pass

func _process(delta):
	# Apply forces & torques at center of the vehicle
	for i in range(8):
		self.add_force(to_global(_thr_forces[i]) - global_transform.origin, to_global(_thr_force_pos[i]) - global_transform.origin)

################################################################################



################################################################################
# Motion functions
################################################################################

# Element wise multiply of vectors
func _ewmul(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(a.x*b.x, a.y*b.y, a.z*b.z)

func move_raw(speeds: Array):
	if speeds.size() != 8:
		return
	for i in range(8):
		_thr_forces[i] = _thr_force_vec[i]
		if speeds[i] > 0.0:
			_thr_forces[i] *= speeds[i] * _thr_force_pos_mag[i]
		else:
			_thr_forces[i] *= speeds[i] * _thr_force_neg_mag[i]

################################################################################
