## Robot script handles moving the robot itself
## Control baord equivilent math is implemented here

extends Spatial
class_name Robot


# Max speeds of robot
var max_rotation = 75;				# Degrees per second
var max_translation = 1;			# Translation units per second

# Used to make simulation more "realistic"
# Not really making motion realistic, but adding types of errors that real world causes
var ideal_motion = false			# true to add errors (more like real world)
var max_translation_err = 0.0001	# Max translation error (for random errors)
var max_rotation_err = 0.005		# Max rotation error (for random errors)
var trans_hyst_points = 40
var rot_hyst_points = 40


# Current motion in robot-relative DoFs
var curr_translation = Vector3(0.0, 0.0, 0.0);
var curr_rotation = Vector3(0.0, 0.0, 0.0);

var trans_history = []
var rot_history = []

####################################################################################################
# Godot functions
####################################################################################################

# Simulates random drift / errors
# Could be caused by random currents in the water
# or by random variation in thruster power
func translation_error() -> Vector3:
	var x = rand_range(-max_translation_err, max_translation_err)
	var y = rand_range(-max_translation_err, max_translation_err)
	var z = rand_range(-max_translation_err, max_translation_err)
	return Vector3(x, y, z)

# Simulates random drift / errors
# Could be caused by random currents in the water
# or by random variation in thruster power
func rotation_error() -> Vector3:
	var x = rand_range(-max_rotation_err, max_rotation_err)
	var y = rand_range(-max_rotation_err, max_rotation_err)
	var z = rand_range(-max_rotation_err, max_rotation_err)
	return Vector3(x, y, z)


# Simulates "momentum" (not in the physics sense, but in the hysteresis of motion sense)
func trans_hyst() -> Vector3:
	trans_history.push_front(curr_translation)
	if trans_history.size() > trans_hyst_points:
		trans_history.pop_back()

	var result = Vector3(0.0, 0.0, 0.0)
	for i in range(trans_history.size()):
		# Logistic model
		var weight = 0.95 / (1.0 + exp((0.1 / (trans_hyst_points / 10.0)) * (i - 5))) + 0.05
		result += weight * trans_history[i]
	return result / float(trans_history.size())

# Simulates "momentum" (not in the physics sense, but in the hysteresis of motion sense)
func rot_hyst() -> Vector3:
	rot_history.push_front(curr_rotation)
	if rot_history.size() > rot_hyst_points:
		rot_history.pop_back()
	var result = Vector3(0.0, 0.0, 0.0)
	for i in range(rot_history.size()):
		# Logistic model
		var weight = 0.95 / (1.0 + exp((0.1 / (rot_hyst_points / 10.0)) * (i - 5))) + 0.05
		result += weight * rot_history[i]
	return result / float(rot_history.size())





func calc_curr_rotation() -> Vector3:
	if self.ideal_motion:
		return curr_rotation
	else:
		return rot_hyst() + rotation_error()

func calc_curr_translation() -> Vector3:
	if self.ideal_motion:
		return curr_translation
	else:
		return trans_hyst() + translation_error()

func _ready():
	pass


func _process(delta):
	# Performs actual motion (LOCAL mode implementation)
	var rot = calc_curr_rotation()
	var trans = calc_curr_translation()
	var rotation_change = rot * (max_rotation * PI / 180.0) * delta;
	var translation_change = trans * max_translation * delta;
	self.translate_object_local(translation_change);
	self.rotate_object_local(Vector3(1, 0, 0), rotation_change.x)
	self.rotate_object_local(Vector3(0, 1, 0), rotation_change.y)
	self.rotate_object_local(Vector3(0, 0, 1), rotation_change.z)	

####################################################################################################
