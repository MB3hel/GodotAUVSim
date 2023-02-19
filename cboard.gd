extends Node
class_name ControlBoard


# TODO: Enable simulated sensor data reads
# TODO: Motor watchdog simulation


####################################################################################################
# Initialization & control of cboard simulation
####################################################################################################

var robot = null
var speed_set_timer = Timer.new()
var motor_wdog_timer = Timer.new()
var sensor_data_timer = Timer.new()


func _init(robot):
	self.robot = robot


func _ready():
	self.speed_set_timer.connect("timeout", self, "periodic_speed_set")
	self.speed_set_timer.one_shot = false
	self.motor_wdog_timer.connect("timeout", self, "motor_wdog_timeout")
	self.motor_wdog_timer.one_shot = true
	self.sensor_data_timer.connect("timeout", self, "periodic_sensor_data")
	self.sensor_data_timer.one_shot = false
	add_child(self.speed_set_timer)
	add_child(self.motor_wdog_timer)
	add_child(self.sensor_data_timer)
	self.speed_set_timer.start(0.02)   # 20ms matches what cboard firmware does
	self.sensor_data_timer.start(0.02) # 20ms matches what cboard firmware does


func reset():
	mode = MODE_LOCAL
	local_x = 0.0
	local_y = 0.0
	local_z = 0.0
	local_pitch = 0.0
	local_roll = 0.0
	local_yaw = 0.0
	periodic_bno055 = false;
	periodic_ms5837 = false;


func crc16_ccitt_false(data: Array, length: int, initial: int = 0xFFFF) -> int:
	var crc = initial
	var pos = 0
	while pos < length:
		var b = data[pos]
		for i in range(8):
			var bit = int((b >> (7 - i) & 1) == 1)
			var c15 = int((crc >> 15 & 1) == 1)
			crc <<= 1
			crc &= 0xFFFF
			if c15 ^ bit:
				crc ^= 0x1021
				crc &= 0xFFFF
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

var periodic_bno055 = false;
var periodic_ms5837 = false;


# Read bytes and decode message
func handle_data(data):
	for byte in data:
		if parse_escaped:
			if byte == START_BYTE or byte == END_BYTE or byte == ESCAPE_BYTE:
				read_buffer.put_u8(byte)
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
				read_buffer.put_u8(byte)
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
	
	if msg_str.begins_with("LOCAL"):
		# L, O, C, A, L, [x], [y], [z], [pitch], [roll], [yaw]
		if buf.get_size() - 4 != 29:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS)
			return
		buf.seek(2 + 5)
		local_x = buf.get_float()
		local_y = buf.get_float()
		local_z = buf.get_float()
		local_pitch = buf.get_float()
		local_roll = buf.get_float()
		local_yaw = buf.get_float()
		mode = MODE_LOCAL
		motor_wdog_feed()
		mc_set_local(local_x, local_y, local_z, local_pitch, local_roll, local_yaw)
		acknowledge(msg_id, ACK_ERR_NONE)
	elif msg_str.begins_with("GLOBAL"):
		# G, L, O, B, A, L, [x], [y], [z], [pitch], [roll], [yaw]
		if buf.get_size() - 4 != 30:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS)
			return
		buf.seek(2 + 6)
		global_x = buf.get_float()
		global_y = buf.get_float()
		global_z = buf.get_float()
		global_pitch = buf.get_float()
		global_roll = buf.get_float()
		global_yaw = buf.get_float()
		mode = MODE_GLOBAL
		motor_wdog_feed()
		mc_set_global(global_x, global_y, global_z, global_pitch, global_roll, global_yaw, Angles.godot_euler_to_quat(robot.rotation))
		acknowledge(msg_id, ACK_ERR_NONE)
	elif msg_str.begins_with("SASSIST1"):
		# S, A, S, S, I, S, T, 1, [x], [y], [yaw], [target_pitch], [taget_roll], [target_depth]
		if buf.get_size() - 4 != 32:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS)
			return
		buf.seek(2 + 8)
		sassist_variant = 1
		sassist_x = buf.get_float()
		sassist_y = buf.get_float()
		sassist_yawspeed = buf.get_float()
		sassist_pitch = buf.get_float()
		sassist_roll = buf.get_float()
		sassist_depth = buf.get_float()
		mode = MODE_SASSIST
		motor_wdog_feed()
		mc_set_sassist(sassist_x, sassist_y, sassist_yawspeed, 
			Vector3(sassist_pitch, sassist_roll, sassist_yaw),
			sassist_depth,
			Angles.godot_euler_to_quat(robot.rotation),
			robot.translation.z,
			true
		)
		acknowledge(msg_id, ACK_ERR_NONE)
	elif msg_str.begins_with("SASSIST2"):
		# S, A, S, S, I, S, T, 2, [x], [y], [target_pitch], [taget_roll], [target_yaw], [target_depth]
		if buf.get_size() - 4 != 32:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS)
			return
		buf.seek(2 + 8)
		sassist_variant = 2
		sassist_x = buf.get_float()
		sassist_y = buf.get_float()
		sassist_pitch = buf.get_float()
		sassist_roll = buf.get_float()
		sassist_yaw = buf.get_float()
		sassist_depth = buf.get_float()
		mode = MODE_SASSIST
		motor_wdog_feed()
		mc_set_sassist(sassist_x, sassist_y, sassist_yawspeed, 
			Vector3(sassist_pitch, sassist_roll, sassist_yaw),
			sassist_depth,
			Angles.godot_euler_to_quat(robot.rotation),
			robot.translation.z,
			false
		)
		acknowledge(msg_id, ACK_ERR_NONE)
	elif msg_str.begins_with("SASSISTTN"):
		# S, A, S, S, I, S, T, T, N, [which], [kp], [ki], [kd], [kf], [limit]
		if buf.get_size() - 4 != 30:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS)
			return
		buf.seek(2 + 9)
		var w = buf.get_u8()
		if w == 80:
			# P
			pitch_pid.kP = buf.get_float()
			pitch_pid.kI = buf.get_float()
			pitch_pid.kD = buf.get_float()
			buf.get_float()
			var l = abs(buf.get_float())
			pitch_pid.out_min = -l
			pitch_pid.out_max = l
		elif w == 82:
			# R
			roll_pid.kP = buf.get_float()
			roll_pid.kI = buf.get_float()
			roll_pid.kD = buf.get_float()
			buf.get_float()
			var l = abs(buf.get_float())
			roll_pid.out_min = -l
			roll_pid.out_max = l
		elif w == 89:
			# Y
			yaw_pid.kP = buf.get_float()
			yaw_pid.kI = buf.get_float()
			yaw_pid.kD = buf.get_float()
			buf.get_float()
			var l = abs(buf.get_float())
			yaw_pid.out_min = -l
			yaw_pid.out_max = l
		elif w == 68:
			# D
			depth_pid.kP = buf.get_float()
			depth_pid.kI = buf.get_float()
			depth_pid.kD = buf.get_float()
			buf.get_float()
			var l = abs(buf.get_float())
			depth_pid.out_min = -l
			depth_pid.out_max = l
		else:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS)
			return
		acknowledge(msg_id, ACK_ERR_NONE)
	elif msg_str == "WDGF" and buf.get_size() - 4 == 4:
		motor_wdog_feed()
		acknowledge(msg_id, ACK_ERR_NONE)
	elif msg_str == "SSTAT" and buf.get_size() - 4 == 5:
		# Both sensors are always "ready" in simulation
		acknowledge(msg_id, ACK_ERR_NONE, [3]);
	elif msg_str == "BNO055R" and buf.get_size() - 4 == 7:
		acknowledge(msg_id, ACK_ERR_NONE, build_bno055_data());
	elif msg_str == "MS5837R" and buf.get_size() - 4 == 7:
		acknowledge(msg_id, ACK_ERR_NONE, build_ms5837_data());
	elif msg_str.begins_with("BNO055P"):
		# B, N, O, 0, 5, 5, P, [enable]
		if buf.get_size() - 4 != 8:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS);
		buf.seek(2 + 7)
		if buf.get_u8() == 1:
			periodic_bno055 = true
		else:
			periodic_bno055 = false
		acknowledge(msg_id, ACK_ERR_NONE)
	elif msg_str.begins_with("MS5837P"):
		# M, S, 5, 8, 3, 7, [enable]
		if buf.get_size() - 4 != 8:
			acknowledge(msg_id, ACK_ERR_INVALID_ARGS);
		buf.seek(2 + 7)
		if buf.get_u8() == 1:
			periodic_ms5837 = true
		else:
			periodic_ms5837 = false
		acknowledge(msg_id, ACK_ERR_NONE)
	else:
		acknowledge(msg_id, ACK_ERR_UNKNOWN_MSG)


func write_msg(data: Array):
	write_buffer_mutex.lock()
	
	# Write start byte
	write_buffer.put_u8(START_BYTE)
	
	# Write message id (big endian) escape as needed
	var msg_id = curr_msg_id
	curr_msg_id += 1
	var tmp = StreamPeerBuffer.new()
	tmp.big_endian = true
	tmp.put_u16(msg_id)
	tmp.seek(0)
	for _i in range(tmp.get_size()):
		var b = tmp.get_u8()
		if b == START_BYTE or b == END_BYTE or b == ESCAPE_BYTE:
			write_buffer.put_u8(ESCAPE_BYTE)
		write_buffer.put_u8(b)
	
	 # Write each byte escaping it as needed
	for i in range(data.size()):
		var b = data[i]
		if b == START_BYTE or b == END_BYTE or b == ESCAPE_BYTE:
			write_buffer.put_u8(ESCAPE_BYTE)
		write_buffer.put_u8(b)
	
	# Calculate crc and write it. CRC includes message id bytes
	var crc = crc16_ccitt_false(tmp.data_array, 2)
	crc = crc16_ccitt_false(data, data.size(), crc)
	var high_byte = (crc >> 8) & 0xFF
	var low_byte = crc & 0xFF
	if high_byte == START_BYTE or high_byte == END_BYTE or high_byte == ESCAPE_BYTE:
		write_buffer.put_u8(ESCAPE_BYTE)
	write_buffer.put_u8(high_byte)
	if low_byte == START_BYTE or low_byte == END_BYTE or low_byte == ESCAPE_BYTE:
		write_buffer.put_u8(ESCAPE_BYTE)
	write_buffer.put_u8(low_byte)
	
	# Write end byte
	write_buffer.put_u8(END_BYTE)
	
	write_buffer_mutex.unlock()


func acknowledge(msg_id: int, ec: int, data: Array = []):
	var buf = StreamPeerBuffer.new()
	buf.put_data("ACK".to_ascii())
	buf.big_endian = true
	buf.put_u16(msg_id)
	buf.put_u8(ec)
	buf.put_data(data)
	write_msg(buf.data_array)


func periodic_sensor_data():
	if periodic_bno055:
		var buf = StreamPeerBuffer.new()
		buf.big_endian = false
		buf.put_data("BNO055D".to_ascii())
		buf.put_data(build_bno055_data())
		self.write_msg(buf.data_array)
	if periodic_ms5837:
		var buf = StreamPeerBuffer.new()
		buf.big_endian = false
		buf.put_data("MS5837D".to_ascii())
		buf.put_data(build_ms5837_data())
		self.write_msg(buf.data_array)

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

# Cached global mode target
var global_x = 0.0
var global_y = 0.0
var global_z = 0.0
var global_pitch = 0.0
var global_roll = 0.0
var global_yaw = 0.0

# Cached sassist mode target
var sassist_variant = 1
var sassist_x = 0.0
var sassist_y = 0.0
var sassist_yawspeed = 0.0
var sassist_pitch = 0.0
var sassist_roll = 0.0
var sassist_yaw = 0.0
var sassist_depth = 0.0

# Stability assist PID controllers
var depth_pid = PIDController.new()
var pitch_pid = PIDController.new()
var roll_pid = PIDController.new()
var yaw_pid = PIDController.new()

# Motor watchdog stuff
var motors_killed = true
const MOTOR_WDOG_TIME = 1.5


# Run by a timer periodically
func periodic_speed_set():
	if mode == MODE_GLOBAL or mode == MODE_SASSIST:
		apply_saved_speed()


func apply_saved_speed():
	if mode == MODE_GLOBAL:
		mc_set_global(global_x, global_y, global_z, global_pitch, global_roll, global_yaw, Angles.godot_euler_to_quat(robot.rotation))


# Called when motor watchdog times out
func motor_wdog_timeout():
	motors_killed = true
	robot.curr_translation.x = 0.0
	robot.curr_translation.y = 0.0
	robot.curr_translation.z = 0.0
	robot.curr_rotation.x = 0.0
	robot.curr_rotation.y = 0.0
	robot.curr_rotation.z = 0.0
	var buf = StreamPeerBuffer.new()
	buf.put_data("WDGS".to_ascii())
	buf.put_u8(0)
	self.write_msg(buf.data_array)


func motor_wdog_feed():
	motor_wdog_timer.stop()
	motor_wdog_timer.start(MOTOR_WDOG_TIME)
	if motors_killed:
		var buf = StreamPeerBuffer.new()
		buf.put_data("WDGS".to_ascii())
		buf.put_u8(1)
		self.write_msg(buf.data_array)
		motors_killed = false
		apply_saved_speed()


# Motor control speed set in SASSIST mode
func mc_set_sassist(x: float, y: float, yaw: float, target_euler: Vector3, target_depth: float, curr_quat: Quat, curr_depth: float, ignore_yaw: bool):
	# Ensure zero yaw error if ignoring yaw
	# This is necessary because the shortest rotation path is calculated
	# Thus, yaw must be aligned top prevent that shortest path from including a yaw component
	if ignore_yaw:
		var curr_euler = Angles.quat_to_cboard_euler(curr_quat)
		target_euler.z = curr_euler.z
		
	# Convert target to quaternion
	var target_quat = Angles.cboard_euler_to_quat(target_euler)
	
	# Construct difference quaternion and convert it to angular velocity
	var res = quat_to_axis_angle(diff_quat(curr_quat, target_quat))
	var err = res[0] * res[1]
	
	# Use PID controllers to calculate current outputs
	var z = depth_pid.calculate(curr_depth - target_depth)
	var pitch = pitch_pid.calculate(-err.x)
	var roll = roll_pid.calculate(-err.y)
	if not ignore_yaw:
		yaw = yaw_pid.calculate(-err.z)
	
	# Error vector is in global axis DOFs. Rotate onto local axes
	# Note that yaw drift is not a big deal as yaw drift redefines "zero yaw"
	# Since zero yaw aligns with world axes, this redefines the world axes in
	# this context too (by the same amount)
	var world_rot = Vector3(pitch, roll, yaw)
	var local_rot = rotate_vector(world_rot, curr_quat.inverse())
	
	# Apply same rotation as in GLOBAL mode to translation vector
	var grav = Vector3(0.0, 0.0, 0.0)
	grav.x = 2.0 * (-curr_quat.x*curr_quat.z + curr_quat.w*curr_quat.y)
	grav.y = 2.0 * (-curr_quat.w*curr_quat.x - curr_quat.y*curr_quat.z)
	grav.z = -curr_quat.w*curr_quat.w + curr_quat.x*curr_quat.x + curr_quat.y*curr_quat.y - curr_quat.z*curr_quat.z
	grav = grav.normalized()
	var stdgrav = Vector3(0.0, 0.0, -1.0)
	var qrot = quat_between(grav, stdgrav).inverse()
	var world_translation = Vector3(x, y, z)
	var local_translation = rotate_vector(world_translation, qrot)
	
	# Target motion now relative to the robot's axes
	self.mc_set_local(world_translation.x, world_translation.y, world_translation.z, world_rot.x, world_rot.y, world_rot.z)


# Motor control speed set in GLOBAL mode
func mc_set_global(x: float, y: float, z: float, pitch: float, roll: float, yaw: float, curr_quat: Quat):
	# Get gravity vector from current quaternion orientation
	var grav = Vector3(0.0, 0.0, 0.0)
	grav.x = 2.0 * (-curr_quat.x*curr_quat.z + curr_quat.w*curr_quat.y)
	grav.y = 2.0 * (-curr_quat.w*curr_quat.x - curr_quat.y*curr_quat.z)
	grav.z = -curr_quat.w*curr_quat.w + curr_quat.x*curr_quat.x + curr_quat.y*curr_quat.y - curr_quat.z*curr_quat.z
	grav = grav.normalized()
	
	# Gravity vector when level
	var stdgrav = Vector3(0.0, 0.0, -1.0)
	
	# Quaternion rotation from measured to standard gravity vector
	var qrot = quat_between(grav, stdgrav).inverse()
	
	# Apply rotation to translation and rotation DOF targets
	var global_translation = Vector3(x, y, z)
	var global_rotation = Vector3(pitch, roll, yaw)
	var local_translation = rotate_vector(global_translation, qrot)
	var local_rotation = rotate_vector(global_rotation, qrot)
	
	# Pass on to local mode
	mc_set_local(local_translation.x, local_translation.y, local_translation.z, local_rotation.x, local_rotation.y, local_rotation.z)


# Motor control speed set in LOCAL mode
func mc_set_local(x: float, y: float, z: float, pitch: float, roll: float, yaw: float):
	if motors_killed:
		return
		
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

func build_bno055_data() -> Array:
	var buf = StreamPeerBuffer.new()
	buf.big_endian = false
	var q = Angles.godot_euler_to_quat(robot.rotation)
	buf.put_float(q.w)
	buf.put_float(q.x)
	buf.put_float(q.y)
	buf.put_float(q.z)
	# TODO: Implement euler angle accumulation and sent it here instead of zeros
	buf.put_float(0.0)
	buf.put_float(0.0)
	buf.put_float(0.0)
	return buf.data_array


func build_ms5837_data() -> Array:
	var buf = StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_float(robot.translation.z)
	return buf.data_array


func limit(v: float, lower: float, upper: float) -> float:
	if v > upper:
		return upper
	if v < lower:
		return lower
	return v


# Rotate vector v by quaternion q
func rotate_vector(v: Vector3, q: Quat) -> Vector3:
	var qv = Quat(v.x, v.y, v.z, 0.0)
	var qconj = Quat(-q.x, -q.y, -q.z, q.w)
	var qr = q * qv * qconj
	var r = Vector3(qr.x, qr.y, qr.z)
	return r


# Quaternion rotation from vector a to vector b
func quat_between(a: Vector3, b: Vector3) -> Quat:
	var dot = a.dot(b)
	var summag = sqrt(a.length_squared() * b.length_squared())
	
	if dot / summag == -1:
		# 180 degree rotation
		var v = a.cross(b).normalized()
		return Quat(v.x, v.y, v.z, 0)
	
	var v = a.cross(b)
	return Quat(v.x, v.y, v.z, dot + summag).normalized()


# Minimum difference from quaternion a to quaternion b
func diff_quat(a: Quat, b: Quat) -> Quat:
	if a.dot(b) < 0.0:
		return a * -b.inverse()
	else:
		return a * b.inverse()


# Convert quaternion to axis angle representation
func quat_to_axis_angle(q: Quat) -> Array:
	q = q.normalized()
	var axis = Vector3(q.x, q.y, q.z)
	var angle = 2.0 * atan2(axis.length(), q.w)
	return [angle, axis.normalized()]

####################################################################################################
