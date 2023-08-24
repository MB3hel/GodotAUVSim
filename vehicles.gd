################################################################################
# file: vehicle.gd
# author: Marcus Behel
################################################################################
# Manges vehicle motion and properties
################################################################################

extends Spatial

################################################################################
# Vehicle Definition Class
################################################################################

class Vehicle:
	# DO NOT CHANGE THIS FUNCTION IN SUBCLASSES!
	# Return bool, string (valid, reason) reason is description if invalid
	func validate(vehicles: Node) -> Array:
		# Make sure node_name is correct
		var nname = node_name()
		if nname == "":
			return [false, "node_name() cannot return empty string."]
		if not vehicles.has_node(nname):
			return [false, "node_name() returns an invalid node."]
		
		# Make sure thr_force_pos is correct
		var tfp = thr_force_pos()
		if len(tfp) != 8:
			return [false, "thr_force_pos() must return an 8 element Array."]
		for item in tfp:
			if not (item is Vector3):
				return [false, "Each element in thr_force_pos() Array must be a Vector3."]
		
		# Make sure thr_force_vec is correct
		var tfv = thr_force_vec()
		if len(tfv) != 8:
			return [false, "thr_force_vec() must return an 8 element Array."]
		for item in tfv:
			if not (item is Vector3):
				return [false, "Each element in thr_force_vec() Array must be a Vector3."]
		
		# Make sure thr_force_pos_mag is correct
		var tfpm = thr_force_pos_mag()
		if len(tfpm) != 8:
			return [false, "thr_force_pos_mag() must return an 8 element Array."]
		for item in tfpm:
			if not ((item is float) or (item is int)):
				return [false, "Each element in thr_force_pos_mag() Array must be a float."]
		
		# Make sure thr_force_neg_mag is correct
		var tfnm = thr_force_neg_mag()
		if len(tfnm) != 8:
			return [false, "thr_force_neg_mag() must return an 8 element Array."]
		for item in tfnm:
			if not ((item is float) or (item is int)):
				return [false, "Each element in thr_force_neg_mag() Array must be a float."]
		
		return [true, ""]
	
	# Name of the node for this vehicle under the "Vehicles" object in the scene
	func node_name() -> String:
		return ""
	
	# Return an array of 8 Vector3's corresponding to thrusters 1-8
	# Each vector is the location (relative to the origin of the vehicle)
	# at which the thruster excerts a force on the vehicle.
	func thr_force_pos() -> Array:
		return []
	
	# Return an array of 8 Vector3's corresponding to thrusters 1-8
	# Each vector is the direction the thruster applies force to the vehicle
	# (NOT the direction water is moved by the thruster!)
	# These MUST be unit vectors!
	func thr_force_vec() -> Array:
		return []
	
	# Return an array of 8 floats corresponding to thrusters 1-8
	# Each number is the force applied by the thruster when operating at positive speed
	func thr_force_pos_mag() -> Array:
		return []
	
	# Return an array of 8 floats corresponding to thrusters 1-8
	# Each number is the force applied by the thruster when operating at negative speed
	func thr_force_neg_mag() -> Array:
		return []

################################################################################


################################################################################
# Define a subclass of "Vehicle" here for each vehicle
# MAKE SURE TO ADD EACH VEHICLE TO THE _vehicle_dict!
# See base "Vehicle" calss above for required functions and descriptions
#
# Steps to create new vehicle:
# - Create 3D RigidBody (give this a name matching the vehicle key)
# - Add mesh instance under RigidBody
# - Create CollisionShape
# - Disable the collision shape (the name MUST stay CollisionShape)
# - Set gravity of rigidbody to zero
# - Set mass and weight of rigidbody as needed (note: use mass = weight / 9.8)
# - Hide the rigidbody in the scene
# - Create a new vehicle class below
# - Add vehicle class to vehicle dictionary
################################################################################

# AquaPack Robotics's SeaWolf VIII
class SW8 extends Vehicle:
	# Name of the node for this vehicle under the "Vehicles" object in the scene
	func node_name() -> String:
		return "SW8"

	func thr_force_pos() -> Array:
		return [
			Vector3(-0.309, -0.241, 0),				# T1
			Vector3(0.309, -0.241, 0),				# T2
			Vector3(-0.309, 0.241, 0),				# T3
			Vector3(0.309, 0.241, 0),				# T4
			Vector3(-0.396, -0.117, 0),				# T5
			Vector3(0.396, -0.117, 0),				# T6
			Vector3(-0.396, 0.117, 0),				# T7
			Vector3(0.396, 0.117, 0)				# T8
		]

	func thr_force_vec() -> Array:
		return [
			Vector3(1, -1, 0).normalized(),			# T1
			Vector3(-1, -1, 0).normalized(),		# T2
			Vector3(-1, -1, 0).normalized(),		# T3
			Vector3(1, -1, 0).normalized(),			# T4
			Vector3(0, 0, 1).normalized(),			# T5
			Vector3(0, 0, -1).normalized(),			# T6
			Vector3(0, 0, -1).normalized(),			# T7
			Vector3(0, 0, 1).normalized(),			# T8
		]

	func thr_force_pos_mag() -> Array:
		# Values for T200 at 16V
		return [
			5.25,									# T1
			5.25,									# T2
			5.25,									# T3
			5.25,									# T4
			5.25,									# T5
			5.25,									# T6
			5.25,									# T7
			5.25									# T8
		]

	func thr_force_neg_mag() -> Array:
		# Value for T200 at 16V
		return [
			4.1,									# T1
			4.1,									# T2
			4.1,									# T3
			4.1,									# T4
			4.1,									# T5
			4.1,									# T6
			4.1,									# T7
			4.1										# T8
		]

# NOTE: Vehicle ids (key) must not contain spaces!
var _vehicle_dict = {
	"SW8": SW8.new()
}

var _default_vehicle = "SW8"

################################################################################

################################################################################
# Globals
################################################################################

var vehicle_body: RigidBody = null
var vehicle_def: Vehicle = null

var _selected_vehicle_id = ""

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
	# Validate all vehicle definitions
	var vkeys = _vehicle_dict.keys()
	var vvalues = _vehicle_dict.values()
	for i in range(_vehicle_dict.size()):
		var key = vkeys[i]
		var val = vvalues[i]
		var res = val.validate(self)
		if not res[0]:
			var msg = "Vehicle '%s' definition invalid: '%s'" % [key, res[1]]
			assert(false, msg)
	
	# Setup default vehicle
	set_vehicle(_default_vehicle)

func _process(delta):
	# Apply forces & torques at center of the vehicle
	var thr_force_pos = vehicle_def.thr_force_pos()
	for i in range(8):
		var pos = thr_force_pos[i]
		var force = _thr_forces[i]
		var pos_local = vehicle_body.transform.basis.xform(pos)
		var force_local = vehicle_body.transform.basis.xform(force)
		vehicle_body.add_force(force_local, pos_local)

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
	var thr_force_vec = vehicle_def.thr_force_vec()
	var thr_force_pos_mag = vehicle_def.thr_force_pos_mag()
	var thr_force_neg_mag = vehicle_def.thr_force_neg_mag()
	for i in range(8):
		_thr_forces[i] = thr_force_vec[i]
		if speeds[i] > 0.0:
			_thr_forces[i] *= speeds[i] * thr_force_pos_mag[i]
		else:
			_thr_forces[i] *= speeds[i] * thr_force_neg_mag[i]

################################################################################

func get_vehicle() -> String:
	return _selected_vehicle_id

func set_vehicle(veh_id: String):
	if vehicle_body != null:
		vehicle_body.visible = false
		var cshape = vehicle_body.get_node("CollisionShape")
		cshape.disabled = true
	_selected_vehicle_id = veh_id
	vehicle_def = _vehicle_dict[veh_id]
	vehicle_body = get_node(vehicle_def.node_name())
	reset_vehicle()
	vehicle_body.visible = true
	var cshape = vehicle_body.get_node("CollisionShape")
	cshape.disabled = false

func all_vehicle_ids() -> Array:
	return _vehicle_dict.keys()

func reset_vehicle():
	move_raw([0, 0, 0, 0, 0, 0, 0, 0])
	vehicle_body.linear_velocity = Vector3(0, 0, 0)
	vehicle_body.angular_velocity = Vector3(0, 0, 0)
	vehicle_body.translation = Vector3(0, 0, 0)
	vehicle_body.rotation = Vector3(0, 0, 0)
