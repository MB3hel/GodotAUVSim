class_name ControlBoard


####################################################################################################
# Godot class stuff
####################################################################################################

var robot = null

func _init(robot):
	self.robot = robot

func _ready():
	pass

func _process(_delta):
	pass

####################################################################################################


# TODO: Implement command processing
# TODO: Implement periodic speed sets in global and sassist modes


####################################################################################################
# Motor Control
####################################################################################################

# Motor control speed set in GLOBAL mode
func mc_set_global(x: float, y: float, z: float, pitch: float, roll: float, yaw: float, curr_quat: Quat):
	# Construct current gravity vector from quaternion
	var gravity_vector = Matrix.new(3, 1)
	gravity_vector.set_item(0 ,0, 2.0 * (-curr_quat.x*curr_quat.z + curr_quat.w*curr_quat.y))
	gravity_vector.set_item(1, 0, 2.0 * (-curr_quat.w*curr_quat.x - curr_quat.y*curr_quat.z))
	gravity_vector.set_item(2, 0, -curr_quat.w*curr_quat.w + curr_quat.x*curr_quat.x + curr_quat.y*curr_quat.y - curr_quat.z*curr_quat.z)

	# b is unit gravity vector
	var gravl2norm = gravity_vector.l2vnorm()
	if gravl2norm < 0.1:
		return # Invalid gravity vector. Norm should be 1
	var b = gravity_vector.sc_div(gravl2norm);
	
	# Expected unit gravity vector when "level"
	var a = Matrix.new(3, 1);
	a.set_col(0, [0, 0, -1]);
	
	# Construct rotation matrix
	var v = a.vcross(b);
	var c = a.vdot(b);
	var sk = skew3(v);
	var I = Matrix.new(3, 3);
	I.fill_ident();
	var R = sk.mul(sk);
	R = R.sc_div(1.0+c);
	R = R.add(sk);
	R = R.add(I);
	
	# Split and rotate translation and rotation targets
	var tgtarget = Matrix.new(3, 1);		# tg = translation global
	var rgtarget = Matrix.new(3, 1);		# rg = rotation global
	tgtarget.set_col(0, [x, y, z]);
	rgtarget.set_col(0, [pitch, roll, yaw]);
	var tltarget = R.mul(tgtarget);			# tl = translation local
	var rltarget = R.mul(rgtarget);			# rl = rotation local
	
	var ltranslation = tltarget.get_col(0);
	var lrotation = rltarget.get_col(0);
	
	# Pass on to local mode
	mc_set_local(ltranslation[0], ltranslation[1], ltranslation[2], lrotation[0], lrotation[1], lrotation[2]);

# Motor control speed set in LOCAL mode
func mc_set_local(x: float, y: float, z: float, pitch: float, roll: float, yaw: float):
	# Base level of motion supported in simulator is LOCAL mode motion
	# RAW mode is not supported. Thus, this function applies the desired motion to the
	# provided robot object (see robot.gd)
	x = limit(x, -1.0, 1.0)
	y = limit(y, -1.0, 1.0)
	z = limit(z, -1.0, 1.0)
	pitch = limit(pitch, -1.0, 1.0)
	roll = limit(roll, -1.0, 1.0)
	yaw = limit(yaw, -1.0, 1.0)
	robot.curr_translation.x = x
	robot.curr_translation.y = y
	robot.curr_translation.z = z
	robot.curr_rotation.x = pitch
	robot.curr_rotation.y = roll
	robot.curr_rotation.z = yaw

####################################################################################################


####################################################################################################
# Helper functions
####################################################################################################

func limit(v: float, lower: float, upper: float) -> float:
	if v > upper:
		return upper
	if v < lower:
		return lower
	return v
	
func skew3(invec: Matrix) -> Matrix:
	var m = Matrix.new(3, 3);
	var v = [];
	if invec.rows == 1 and invec.cols == 3:
		v = invec.get_row(0)
	elif invec.cols == 1 and invec.rows == 3:
		v = invec.get_col(0)
	else:
		return Matrix.new(0, 0)
	m.set_row(0, [0.0, -v[2], v[1]]);
	m.set_row(1, [v[2], 0.0, -v[0]]);
	m.set_row(2, [-v[1], v[0], 0.0]);
	return m;
	

####################################################################################################
