## Robot script handles moving the robot itself
## Control baord equivilent math is implemented here

extends Spatial


# Max speeds of robot
var max_rotation = 0;				# Degrees per second
var max_translation = 0;			# Translation units per second


# Current motion in robot-relative DoFs
var curr_translation = Vector3(0.0, 0.0, 0.0);
var curr_rotation = Vector3(0.0, 0.0, 0.0);

####################################################################################################
# Godot functions
####################################################################################################

func _ready():
	pass


func _process(delta):
	# Performs actual motion (LOCAL mode implementation)
	var rotation_change = curr_rotation * (max_rotation * PI / 180.0) * delta;
	var translation_change = curr_translation * max_translation * delta;
	self.translate_object_local(translation_change);
	self.rotate_object_local(Vector3(1, 0, 0), rotation_change.x)
	self.rotate_object_local(Vector3(0, 1, 0), rotation_change.y)
	self.rotate_object_local(Vector3(0, 0, 1), rotation_change.z)	

####################################################################################################
