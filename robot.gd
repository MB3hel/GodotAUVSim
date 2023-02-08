extends Spatial


# Degrees per second for rotate animation
const dps = 45.0;

# Angle to rotate to
const pitch = 90.0;				# About x
const roll = 90.0;				# About y
const yaw = 0.0;				# About z
const target = Vector3(pitch, roll, yaw);

func _ready():
	var refrobot = get_parent().get_node("RefRobot")
	refrobot.rotate_x(pitch * PI / 180.0);
	refrobot.rotate_y(roll * PI / 180.0);
	refrobot.rotate_z(yaw * PI / 180.0);
	
func _process(delta):
	# Get error in degrees (diff)
	var curr = self.rotation_degrees;
	var diff = target - curr;
	
	# Determine "direction" of change (positive, negative, or zero)
	var signs = Vector3(0, 0, 0);
	if abs(diff.x) > 0.1:
		signs.x = diff.x / abs(diff.x);
	if abs(diff.y) > 0.1:
		signs.y = diff.y / abs(diff.y);
	if abs(diff.z) > 0.1:
		signs.z = diff.z / abs(diff.z);
		
	# Determine change in degrees based on speeds
	var deg_change = signs * dps * delta;
	
	# Don't overshoot
	if abs(deg_change.x) > abs(diff.x):
		deg_change.x = diff.x;
	if abs(deg_change.y) > abs(diff.y):
		deg_change.y = diff.y;
	if abs(deg_change.z) > abs(diff.z):
		deg_change.z = diff.z

	var new = curr + deg_change;
	self.rotation_degrees = new;
