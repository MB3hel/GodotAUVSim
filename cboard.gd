class_name ControlBoard


# TODO: Implement command processing
# TODO: Implement periodic speed sets in global and sassist modes
# TODO: Enable simulated sensor data reads
# TODO: Motor watchdog simulation


####################################################################################################
# Initialization & control of cboard simulation
####################################################################################################

var robot = null

func _init(robot):
	self.robot = robot

func reset():
	# TODO: Reset to default state
	# Periodic sensor data reads disabled
	# Local mode with all zeros for last speed
	pass

func crc16_ccitt_false(data: Array, length: int, initial: int = 0xFFFF) -> int:
	var crc = initial
	var pos = 0
	while(pos < length):
		var b = data[pos]
		for i in range(8):
			var bit = ((b >> (7 - i) & 1))
			var c15 = ((crc >> 15 & 1))
			crc <<= 1;
			if(c15 ^ bit):
				crc ^= 0x1021
		pos += 1
	return crc & 0xFFFF

####################################################################################################

####################################################################################################
# Communication and command processing
####################################################################################################

const ACK_ERR_NONE = 0				# No error
const ACK_ERR_UNKNOWN_MSG = 1		# Message is not recognized
const ACK_ERR_INVALID_ARGS = 2		# Arguments are invalid
const ACK_ERR_INVALID_CMD = 3		# Command is known, but invalid at this time 
									# Also used for "not implemented in simulator"

const START_BYTE = 253
const END_BYTE = 254
const ESCAPE_BYTE = 255

var write_buffer = StreamPeerBuffer.new()
var write_buffer_mutex = Mutex.new()

var read_buffer = StreamPeerBuffer.new()

var curr_msg_id = 0
var parse_started = false;
var parse_escaped = false;


# Read bytes and decode message
func handle_data(data):
	for byte in data:
		if parse_escaped:
			if byte == START_BYTE or byte == END_BYTE or byte == ESCAPE_BYTE:
				read_buffer.put_8(byte)
			parse_escaped = false
		elif parse_started:
			if byte == START_BYTE:
				read_buffer.clear()
			elif byte == END_BYTE:
				parse_started = false
				if read_buffer.get_size() < 4:
					# Too short to contain msg_id and crc bytes. Invalid msg.
					break
				else:
					var calc_crc = crc16_ccitt_false(read_buffer.data_array, read_buffer.get_size() - 2)
					read_buffer.seek(read_buffer.get_size() - 2)
					read_buffer.big_endian = true
					var read_crc = read_buffer.get_u16()
					if read_crc == calc_crc:
						read_buffer.seek(0)
						handle_msg(read_buffer)
						read_buffer.clear()
			elif byte == ESCAPE_BYTE:
				parse_escaped = true
			else:
				read_buffer.put_8(byte)
		elif byte == START_BYTE:
			parse_started = true
			read_buffer.clear()


# Handle a single complete message
func handle_msg(buf: StreamPeerBuffer):
	buf.big_endian = true
	var msg_id = buf.get_u16()
	var msg_len = buf.get_size() - 4
	buf.seek(2)
	var msg_str = buf.get_string(msg_len)
	buf.big_endian = false
	
	print(buf.data_array.subarray(2, buf.get_size() - 4))
	if msg_str.begins_with("LOCAL"):
		# L, O, C, A, L, [x], [y], [z], [pitch], [roll], [yaw]
		buf.seek(2 + 5)
		local_x = buf.get_float()
		local_y = buf.get_float()
		local_z = buf.get_float()
		local_pitch = buf.get_float()
		local_roll = buf.get_float()
		local_yaw = buf.get_float()
		mc_set_local(local_x, local_y, local_z, local_pitch, local_roll, local_yaw)


func write_msg(data: Array):
	pass


func acknowledge(msg_id: int):
	pass

####################################################################################################


####################################################################################################
# Motor Control
####################################################################################################

const MODE_RAW = 0
const MODE_LOCAL = 1
const MODE_GLOBAL = 2
const MODE_SASSIST = 3

var mode = MODE_LOCAL

# Cached local mode target
var local_x = 0.0
var local_y = 0.0
var local_z = 0.0
var local_pitch = 0.0
var local_roll = 0.0
var local_yaw = 0.0


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
