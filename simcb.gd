################################################################################
# file: simcb.gd
# author: Marcus Behel
################################################################################
# Simulated control board
# Implements the same math and command processing as a real control board would
# but does it using Godot itself.
# This allows some testing without a real control board
#   - Test or validate math implementation or changes
#   - Test the logic of code using control board (motion)
#   - Test code to communicate with the control board (messages and format)
# However there are some limitations (which is why using a real control board 
# is supported at all)
#   - Does not allow testing of math under "real" conditions. Mostly related to
#     timing and CPU load conditions.
#   - Does not allow testing of firmware bugs. Ex: issues in firmware math 
#     libraries, firmware crashes, firmware deadlocks
#
# Note that this implementation is not the most efficient dataflow. The simcb
# is meant to be a "drop in" replacement for a real control board.
# As such, messages are formatted here before they are given to the cboard
# layer. This means the cboard layer technically performs some unnecessary
# parsing. Likewise, the netiface parses a message, the it is written raw
# to simcb only to be parsed again. This is not the most efficient method of
# doing things, however it ensures that cboard is almost identical for a real
# control board or with simcb. It also means that no simcb logic or data
# data handling need to be in cboard. This makes the simulator more maintainable
# and shouldn't impact simulator performance too much.
#
# Note that simcb ONLY operates in SIMHIJACK mode
# However, it will still acknowledge SIMHIJACK commands.
# It will always be sending SIMSTAT commands and always process SIMDAT
# commands as a control board in SIMHIJACK mode would.
#
# Note that most functions in this class closely match the names of functions
# used in the actual control board firmware. This should allow quicly porting
# changes between control board firmware and simcb
#
# Important differences of simcb (important for implementation of simcb)
# - Sensors are alwasy simulated, and thus are always ready
# - Always acts as if it is in sim hijack. It will acknowledge simhijack commands
#   but will not ever leave simhijack. Thus, it will always send simstat messages.
# - No attempt is made to emulate correct timings of math. But the timers
#   performing periodic tasks do use the same times as the actual firmware.
# - Everything here is implemented using signals, and thus this is all single
#   threaded. Thus, unlike in the actual firmware, there are no mutexes.
# - Reset command will not be handled (it will be acknowledge with INVALID_CMD)
# - Why reset will always return code 0
# - matrix.gd is a port of my custom matrix library used with the control board
#   to gdscript. 
# - There is no port of angles.c to gdscript. Native godot Quat data type is
#   used instead. angles.gd is a conversion helper to convert between
#   formats and euler angle conventions (godot convention vs cboard convention)
# - Because sensors are all simulated, BNO055 axis config does nothing (but is
#   properly acknowledged)
################################################################################

extends Node

################################################################################
# Globals
################################################################################

# Data to be written out from simcb
var _write_buf = PoolByteArray()

# Data waiting to be read by simcb
var _read_buf = PoolByteArray()

################################################################################



################################################################################
# Godot Engine functions
################################################################################

var _wdog_timer = Timer.new()
var _periodic_speed_timer = Timer.new()

func _ready():
	var sensor_read_timer = Timer.new()
	add_child(sensor_read_timer)
	sensor_read_timer.one_shot = false
	sensor_read_timer.connect("timeout", self, "cmdctrl_send_sensor_data")
	sensor_read_timer.start(0.020)
	
	
	add_child(_periodic_speed_timer)
	_periodic_speed_timer.one_shot = false
	_periodic_speed_timer.connect("timeout", self, "cmdctrl_periodic_reapply_speed")
	_periodic_speed_timer.start(0.020)
	
	add_child(_wdog_timer)
	_wdog_timer.one_shot = true
	_wdog_timer.connect("timeout", self, "mc_wdog_timeout")
	
	var simstat_timer = Timer.new()
	add_child(simstat_timer)
	simstat_timer.one_shot = false
	simstat_timer.connect("timeout", self, "cmdctrl_send_simstat")
	simstat_timer.start(0.020)
	
	var euler_accum_timer = Timer.new()
	add_child(euler_accum_timer)
	euler_accum_timer.one_shot = false
	euler_accum_timer.connect("timeout", self, "bno055_do_accum")
	euler_accum_timer.start(0.015) # Same as firmware's sample rate for bno055

func _process(delta):
	self.pccomm_read_and_parse()

################################################################################



################################################################################
# EXTERNAL Communication (called by cboard)
################################################################################

# EXTERNAL write
# write data TO simcb
# this data will later be read by simcb
func ext_write(data: PoolByteArray):
	_read_buf.append_array(data)

# EXTERNAL read
# read data FROM simcb
# this data must first be written by simcb
func ext_read() -> PoolByteArray:
	var res = _write_buf
	_write_buf = PoolByteArray()
	return res

################################################################################



################################################################################
# Sim pccomm
################################################################################

var _pccomm_parse_started = false
var _pccomm_parse_escaped = false
var _pccomm_read_buf = StreamPeerBuffer.new()

var _curr_msg_id = 0

const START_BYTE = 253
const END_BYTE = 254
const ESCAPE_BYTE = 255

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

# Construct a properly formatted message and write it from simcb
# This is equivalent to writing from control board to PC
func pccomm_write(msg: PoolByteArray):
	var write_buffer = StreamPeerBuffer.new()
	
	# Write start byte
	write_buffer.put_u8(START_BYTE)
	
	# Write message id (big endian) escape as needed
	var msg_id = _curr_msg_id
	_curr_msg_id += 1
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
	for i in range(msg.size()):
		var b = msg[i]
		if b == START_BYTE or b == END_BYTE or b == ESCAPE_BYTE:
			write_buffer.put_u8(ESCAPE_BYTE)
		write_buffer.put_u8(b)
	
	# Calculate crc and write it. CRC includes message id bytes
	var crc = crc16_ccitt_false(tmp.data_array, 2)
	crc = crc16_ccitt_false(msg, msg.size(), crc)
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
	
	# Add to actual buffer
	_write_buf.append_array(write_buffer.data_array)
	

# Read messages sent to simcb
# This is equivalent of reading messages from PC on control board
func pccomm_read_and_parse():
	while not _read_buf.empty():
		var byte = _read_buf[0]
		_read_buf.remove(0)
		if _pccomm_parse_escaped:
			if byte == START_BYTE or byte == END_BYTE or byte == END_BYTE:
				_pccomm_read_buf.put_u8(byte)
			_pccomm_parse_escaped = false
		elif _pccomm_parse_started:
			if byte == START_BYTE:
				_pccomm_read_buf.clear()
			elif byte == END_BYTE:
				_pccomm_parse_started = false
				if _pccomm_read_buf.get_size() >= 4:
					var calc_crc = crc16_ccitt_false(_pccomm_read_buf.data_array, _pccomm_read_buf.get_size() - 2)
					_pccomm_read_buf.seek(_pccomm_read_buf.get_size() - 2)
					_pccomm_read_buf.big_endian = true
					var read_crc = _pccomm_read_buf.get_u16()
					if read_crc == calc_crc:
						_pccomm_read_buf.seek(0)
						cmdctrl_handle_message(_pccomm_read_buf.data_array)
						_pccomm_read_buf.clear()
			elif byte == ESCAPE_BYTE:
				_pccomm_parse_escaped = true
			else:
				_pccomm_read_buf.put_u8(byte)
		elif byte == START_BYTE:
			_pccomm_parse_started = true
			_pccomm_read_buf.clear()

################################################################################



################################################################################
# Sim cmdctrl
################################################################################

const CMDCTRL_MODE_RAW = 0
const CMDCTRL_MODE_LOCAL = 1
const CMDCTRL_MODE_GLOBAL = 2
const CMDCTRL_MODE_SASSIST = 3
const CMDCTRL_MODE_DHOLD = 4

const ACK_ERR_NONE = 0
const ACK_ERR_UNKNOWN_MSG = 1
const ACK_ERR_INVALID_ARGS = 2
const ACK_ERR_INVALID_CMD = 3

var cmdctrl_periodic_bno055 = false
var cmdctrl_periodic_ms5837 = false

var cmdctrl_motors_enabled = false

# State tracking similar to cmdctrl in firmware
var cmdctrl_mode = CMDCTRL_MODE_RAW

# Last used raw mode target
var cmdctrl_raw_target = PoolRealArray([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

# Last used local mode target
var cmdctrl_local_x = 0.0
var cmdctrl_local_y = 0.0
var cmdctrl_local_z = 0.0
var cmdctrl_local_xrot = 0.0
var cmdctrl_local_yrot = 0.0
var cmdctrl_local_zrot = 0.0

# Last used global mode target
var cmdctrl_global_x = 0.0
var cmdctrl_global_y = 0.0
var cmdctrl_global_z = 0.0
var cmdctrl_global_pitch_spd = 0.0
var cmdctrl_global_roll_spd = 0.0
var cmdctrl_global_yaw_spd = 0.0

# Last used sassist mode target
var cmdctrl_sassist_valid = false
var cmdctrl_sassist_variant = 1
var cmdctrl_sassist_x = 0.0
var cmdctrl_sassist_y = 0.0
var cmdctrl_sassist_yaw_spd = 0.0
var cmdctrl_sassist_target_euler = Vector3(0.0, 0.0, 0.0)
var cmdctrl_sassist_depth_target = 0.0

# Last used depth hold target
var cmdctrl_dhold_x = 0.0
var cmdctrl_dhold_y = 0.0
var cmdctrl_dhold_pitch_spd = 0.0
var cmdctrl_dhold_roll_spd = 0.0
var cmdctrl_dhold_yaw_spd = 0.0
var cmdctrl_dhold_depth = 0.0


# Store received from SIMDAT
# NOTE: simcb is always in SIMHIJACK, thus no need to track sensor states or full sets of data
#       only the data from SIMDAT will ever be used
#       Thus these are equivalents of sim_quat and sim_depth in the actual firmware
var cmdctrl_curr_quat = Quat(0, 0, 0, 1)
var cmdctrl_curr_depth = 0.0
var cmdctrl_curr_pressure = 0.0		# MS5837 Pressure reading (calculated from depth in sim)
var cmdctrl_curr_temp = 25.0		# MS5837 Temperature (constant in sim)

func cmdctrl_send_sensor_data():
	if cmdctrl_periodic_bno055:
		var msg = StreamPeerBuffer.new()
		msg.big_endian = false
		msg.put_data("BNO055D".to_ascii())
		msg.put_float(cmdctrl_curr_quat.w)
		msg.put_float(cmdctrl_curr_quat.x)
		msg.put_float(cmdctrl_curr_quat.y)
		msg.put_float(cmdctrl_curr_quat.z)
		msg.put_float(bno055_accum.x)
		msg.put_float(bno055_accum.y)
		msg.put_float(bno055_accum.z)
		pccomm_write(msg.data_array)
	if cmdctrl_periodic_ms5837:
		var msg = StreamPeerBuffer.new()
		msg.big_endian = false
		msg.put_data("MS5837D".to_ascii())
		msg.put_float(cmdctrl_curr_depth)
		msg.put_float(cmdctrl_curr_pressure)
		msg.put_float(cmdctrl_curr_temp)
		pccomm_write(msg.data_array)

func cmdctrl_periodic_reapply_speed():
	if cmdctrl_mode == CMDCTRL_MODE_GLOBAL or cmdctrl_mode == CMDCTRL_MODE_SASSIST or cmdctrl_mode == CMDCTRL_MODE_DHOLD:
		cmdctrl_apply_saved_speed()

func cmdctrl_apply_saved_speed():
	if cmdctrl_mode == CMDCTRL_MODE_RAW:
		mc_set_raw(cmdctrl_raw_target)
	elif cmdctrl_mode == CMDCTRL_MODE_LOCAL:
		mc_set_local(cmdctrl_local_x, cmdctrl_local_y, cmdctrl_local_z, cmdctrl_local_xrot, cmdctrl_local_yrot, cmdctrl_local_zrot)
	elif cmdctrl_mode == CMDCTRL_MODE_GLOBAL:
		mc_set_global(cmdctrl_global_x, cmdctrl_global_y, cmdctrl_global_z, cmdctrl_global_pitch_spd, cmdctrl_global_roll_spd, cmdctrl_global_yaw_spd, cmdctrl_curr_quat)
	elif cmdctrl_mode == CMDCTRL_MODE_SASSIST:
		if cmdctrl_sassist_valid and cmdctrl_sassist_variant == 1:
			mc_set_sassist(cmdctrl_sassist_x, cmdctrl_sassist_y, cmdctrl_sassist_yaw_spd, cmdctrl_sassist_target_euler, cmdctrl_sassist_depth_target, cmdctrl_curr_quat, cmdctrl_curr_depth, false)
		elif cmdctrl_sassist_valid and cmdctrl_sassist_variant == 2:
			mc_set_sassist(cmdctrl_sassist_x, cmdctrl_sassist_y, 0.0, cmdctrl_sassist_target_euler, cmdctrl_sassist_depth_target, cmdctrl_curr_quat, cmdctrl_curr_depth, true)
	elif cmdctrl_mode == CMDCTRL_MODE_DHOLD:
		mc_set_dhold(cmdctrl_dhold_x, cmdctrl_dhold_y, cmdctrl_dhold_pitch_spd, cmdctrl_dhold_roll_spd, cmdctrl_dhold_yaw_spd, cmdctrl_dhold_depth, cmdctrl_curr_quat, cmdctrl_curr_depth)

func cmdctrl_acknowledge(msg_id: int, error_code: int, result: PoolByteArray):
	var data = StreamPeerBuffer.new()
	data.big_endian = true
	data.put_data("ACK".to_ascii())
	data.put_16(msg_id)
	data.put_u8(error_code)
	if result.size() > 0:
		data.put_data(result)
	pccomm_write(data.data_array)

func limit(v: float) -> float:
	# Limit to -1.0 to 1.0
	if v > 1.0:
		return 1.0
	if v < -1.0:
		return -1.0
	return v 

func limit_pos(v: float) -> float:
	# Limit to 0.0 to 1.0
	if v > 1.0:
		return 1.0
	if v < 0.0:
		return 0.0
	return v 

func cmdctrl_handle_message(data: PoolByteArray):
	# Construct StreamPeerBuffer using data
	var buf = StreamPeerBuffer.new()
	buf.put_data(data)
	buf.seek(0)
	
	# Get message id from buffer
	buf.big_endian = true
	var msg_id = buf.get_u16()
	
	# Get both string and byte representations of message
	var msg_len = buf.get_size() - 4
	buf.seek(2)
	var msg_str = buf.get_string(msg_len)
	buf.seek(2)
	var msg = buf.get_data(msg_len)[1]
	
	# Return to start of buffer (after CRC)
	buf.seek(2)
	
	# Arguments for commands are usually little endian
	buf.big_endian = false
	
	var reset_cmd = PoolByteArray([])
	reset_cmd.append_array("RESET".to_ascii())
	reset_cmd.append(0x0D)
	reset_cmd.append(0x1E)
	
	# Note: command processing is mostly a direct port of what is 
	#       contained in the control board firmware's cmdctrl.c
	#       But, I was too lazy to copy the comments. So, see the
	#       actual firmware for comments.
	if msg_str.begins_with("RAW"):
		if msg_len != 35:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 3)
			cmdctrl_raw_target[0] = buf.get_float()
			cmdctrl_raw_target[1] = buf.get_float()
			cmdctrl_raw_target[2] = buf.get_float()
			cmdctrl_raw_target[3] = buf.get_float()
			cmdctrl_raw_target[4] = buf.get_float()
			cmdctrl_raw_target[5] = buf.get_float()
			cmdctrl_raw_target[6] = buf.get_float()
			cmdctrl_raw_target[7] = buf.get_float()
			for i in range(8):
				if cmdctrl_raw_target[i] < -1.0:
					cmdctrl_raw_target[i] = -1.0
				elif cmdctrl_raw_target[i] > 1.0:
					cmdctrl_raw_target = 1.0
			_periodic_speed_timer.stop()
			_periodic_speed_timer.start()
			cmdctrl_mode = CMDCTRL_MODE_RAW
			mc_wdog_feed()
			mc_set_raw(cmdctrl_raw_target)		
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("TINV"):
		if msg_len != 5:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 4)
			var inv = buf.get_u8()
			for i in range(8):
				mc_invert[i] = true if (inv & 1) else false
				inv >>= 1
			cmdctrl_apply_saved_speed()
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("RELDOF"):
		if msg_len != 30:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 6)
			var x = buf.get_float()
			var y = buf.get_float()
			var z = buf.get_float()
			var xrot = buf.get_float()
			var yrot = buf.get_float()
			var zrot = buf.get_float()
			x = limit_pos(x)
			y = limit_pos(y)
			z = limit_pos(z)
			xrot = limit_pos(xrot)
			yrot = limit_pos(yrot)
			zrot = limit_pos(zrot)
			mc_relscale[0] = 1.0 if x == 0.0 else min(x, min(y, z)) / x
			mc_relscale[1] = 1.0 if y == 0.0 else min(x, min(y, z)) / y
			mc_relscale[2] = 1.0 if z == 0.0 else min(x, min(y, z)) / z
			mc_relscale[3] = 1.0 if xrot == 0.0 else min(xrot, min(yrot, zrot)) / xrot
			mc_relscale[4] = 1.0 if yrot == 0.0 else min(xrot, min(yrot, zrot)) / yrot
			mc_relscale[5] = 1.0 if zrot == 0.0 else min(xrot, min(yrot, zrot)) / zrot
			cmdctrl_apply_saved_speed()
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "WDGF":
		var was_killed = mc_wdog_feed()
		if was_killed:
			cmdctrl_apply_saved_speed()
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("MMATS"):
		if msg_len != 30:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 5)
			var thr = buf.get_u8()
			var d = PoolRealArray([])
			d.append(buf.get_float())
			d.append(buf.get_float())
			d.append(buf.get_float())
			d.append(buf.get_float())
			d.append(buf.get_float())
			d.append(buf.get_float())
			mc_set_dof_matrix(thr, d)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "MMATU":
		mc_recalc()
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("LOCAL"):
		if msg_len != 29:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 5)
			cmdctrl_local_x = buf.get_float()
			cmdctrl_local_y = buf.get_float()
			cmdctrl_local_z = buf.get_float()
			cmdctrl_local_xrot = buf.get_float()
			cmdctrl_local_yrot = buf.get_float()
			cmdctrl_local_zrot = buf.get_float()
			cmdctrl_local_x = limit(cmdctrl_local_x)
			cmdctrl_local_y = limit(cmdctrl_local_y)
			cmdctrl_local_z = limit(cmdctrl_local_z)
			cmdctrl_local_xrot = limit(cmdctrl_local_xrot)
			cmdctrl_local_yrot = limit(cmdctrl_local_yrot)
			cmdctrl_local_zrot = limit(cmdctrl_local_zrot)
			_periodic_speed_timer.stop()
			_periodic_speed_timer.start()
			cmdctrl_mode = CMDCTRL_MODE_LOCAL
			mc_wdog_feed()
			mc_set_local(cmdctrl_local_x, cmdctrl_local_y, cmdctrl_local_z, cmdctrl_local_xrot, cmdctrl_local_yrot, cmdctrl_local_zrot)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "SSTAT":
		var response = PoolByteArray([])
		response.append(0)
		response[0] |= 1
		response[0] |= (1 << 1)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, response)
	elif msg_str.begins_with("BNO055A"):
		# This has no effect in simulation, but will be acknowledged correctly
		if msg_len != 8:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 7)
			if buf.get_u8() > 7:
				cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
			else:
				cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("GLOBAL"):
		if msg_len != 30:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 6)
			cmdctrl_global_x = buf.get_float()
			cmdctrl_global_y = buf.get_float()
			cmdctrl_global_z = buf.get_float()
			cmdctrl_global_pitch_spd = buf.get_float()
			cmdctrl_global_roll_spd = buf.get_float()
			cmdctrl_global_yaw_spd = buf.get_float()
			cmdctrl_global_x = limit(cmdctrl_global_x)
			cmdctrl_global_y = limit(cmdctrl_global_y)
			cmdctrl_global_z = limit(cmdctrl_global_z)
			cmdctrl_global_pitch_spd = limit(cmdctrl_global_pitch_spd)
			cmdctrl_global_roll_spd = limit(cmdctrl_global_roll_spd)
			cmdctrl_global_yaw_spd = limit(cmdctrl_global_yaw_spd)
			_periodic_speed_timer.stop()
			_periodic_speed_timer.start()
			cmdctrl_mode = CMDCTRL_MODE_GLOBAL
			mc_wdog_feed()
			mc_set_global(cmdctrl_global_x, cmdctrl_global_y, cmdctrl_global_z, cmdctrl_global_pitch_spd, cmdctrl_global_roll_spd, cmdctrl_global_yaw_spd, cmdctrl_curr_quat)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "BNO055R":
		var response = StreamPeerBuffer.new()
		response.big_endian = false
		response.put_float(cmdctrl_curr_quat.w)
		response.put_float(cmdctrl_curr_quat.x)
		response.put_float(cmdctrl_curr_quat.y)
		response.put_float(cmdctrl_curr_quat.z)
		msg.put_float(bno055_accum.x)
		msg.put_float(bno055_accum.y)
		msg.put_float(bno055_accum.z)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, response.data_array)
	elif msg_str.begins_with("BNO055P"):
		if msg_len != 8:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 7)
			cmdctrl_periodic_bno055 = true if buf.get_u8() != 0 else false
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "MS5837R":
		var response = StreamPeerBuffer.new()
		response.big_endian = false
		response.put_float(cmdctrl_curr_depth)
		response.put_float(cmdctrl_curr_pressure)
		response.put_float(cmdctrl_curr_temp)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, response.data_array)
	elif msg_str.begins_with("MS5837P"):
		if msg_len != 8:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 7)
			cmdctrl_periodic_ms5837 = true if buf.get_u8() != 0 else false
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("SASSISTTN"):
		if msg_len != 27:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 9)
			var which = buf.get_data(1)[1].get_string_from_ascii()
			var kp = buf.get_float()
			var ki = buf.get_float()
			var kd = buf.get_float()
			var lim = buf.get_float()
			var inv = true if buf.get_u8() != 0 else false
			if which == "X":
				mc_sassist_tune_xrot(kp, ki, kd, lim, inv)
			elif which == "Y":
				mc_sassist_tune_yrot(kp, ki, kd, lim, inv)
			elif which == "Z":
				mc_sassist_tune_zrot(kp, ki, kd, lim, inv)
			elif which == "D":
				mc_sassist_tune_depth(kp, ki, kd, lim, inv)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("SASSIST1"):
		if msg_len != 32:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 8)
			cmdctrl_sassist_valid = true
			cmdctrl_sassist_variant = 1
			cmdctrl_sassist_x = buf.get_float()
			cmdctrl_sassist_y = buf.get_float()
			cmdctrl_sassist_yaw_spd = buf.get_float()
			cmdctrl_sassist_target_euler.x = buf.get_float()
			cmdctrl_sassist_target_euler.y = buf.get_float()
			cmdctrl_sassist_depth_target = buf.get_float()
			cmdctrl_sassist_x = limit(cmdctrl_sassist_x)
			cmdctrl_sassist_y = limit(cmdctrl_sassist_y)
			cmdctrl_sassist_yaw_spd = limit(cmdctrl_sassist_yaw_spd)
			_periodic_speed_timer.stop()
			_periodic_speed_timer.start()
			cmdctrl_mode = CMDCTRL_MODE_SASSIST
			mc_wdog_feed()
			mc_set_sassist(cmdctrl_sassist_x, cmdctrl_sassist_y, cmdctrl_sassist_yaw_spd, cmdctrl_sassist_target_euler, cmdctrl_sassist_depth_target, cmdctrl_curr_quat, cmdctrl_curr_depth, false)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("SASSIST2"):
		if msg_len != 32:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 8)
			cmdctrl_sassist_valid = true
			cmdctrl_sassist_variant = 2
			cmdctrl_sassist_x = buf.get_float()
			cmdctrl_sassist_y = buf.get_float()
			cmdctrl_sassist_target_euler.x = buf.get_float()
			cmdctrl_sassist_target_euler.y = buf.get_float()
			cmdctrl_sassist_target_euler.z = buf.get_float()
			cmdctrl_sassist_depth_target = buf.get_float()
			cmdctrl_sassist_x = limit(cmdctrl_sassist_x)
			cmdctrl_sassist_y = limit(cmdctrl_sassist_y)
			cmdctrl_sassist_yaw_spd = limit(cmdctrl_sassist_yaw_spd)
			_periodic_speed_timer.stop()
			_periodic_speed_timer.start()
			cmdctrl_mode = CMDCTRL_MODE_SASSIST
			mc_wdog_feed()
			mc_set_sassist(cmdctrl_sassist_x, cmdctrl_sassist_y, 0.0, cmdctrl_sassist_target_euler, cmdctrl_sassist_depth_target, cmdctrl_curr_quat, cmdctrl_curr_depth, true)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg == reset_cmd:
		# Not supported in simulation
		cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_CMD, PoolByteArray([]))
	elif msg_str.begins_with("DHOLD"):
		if msg_len != 29:
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 5)
			cmdctrl_dhold_x = buf.get_float()
			cmdctrl_dhold_y = buf.get_float()
			cmdctrl_dhold_pitch_spd = buf.get_float()
			cmdctrl_dhold_roll_spd = buf.get_float()
			cmdctrl_dhold_yaw_spd = buf.get_float()
			cmdctrl_dhold_depth = buf.get_float()
			cmdctrl_dhold_x = limit(cmdctrl_dhold_x)
			cmdctrl_dhold_y = limit(cmdctrl_dhold_y)
			cmdctrl_dhold_pitch_spd = limit(cmdctrl_dhold_pitch_spd)
			cmdctrl_dhold_roll_spd = limit(cmdctrl_dhold_roll_spd)
			cmdctrl_dhold_yaw_spd = limit(cmdctrl_dhold_yaw_spd)
			_periodic_speed_timer.stop()
			_periodic_speed_timer.start()
			cmdctrl_mode = CMDCTRL_MODE_DHOLD
			mc_wdog_feed()
			mc_set_dhold(cmdctrl_dhold_x, cmdctrl_dhold_y, cmdctrl_dhold_pitch_spd, cmdctrl_dhold_roll_spd, cmdctrl_dhold_yaw_spd, cmdctrl_dhold_depth, cmdctrl_curr_quat, cmdctrl_curr_depth)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "RSTWHY":
		var response = StreamPeerBuffer.new()
		response.put_32(0)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, response.data_array)
	elif msg_str.begins_with("SIMHIJACK"):
		if msg_len != 10:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 9)
			cmdctrl_simhijack(buf.get_u8())
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("SIMDAT"):
		if msg_len != 26:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			buf.seek(buf.get_position() + 6)
			cmdctrl_curr_quat.w = buf.get_float()
			cmdctrl_curr_quat.x = buf.get_float()
			cmdctrl_curr_quat.y = buf.get_float()
			cmdctrl_curr_quat.z = buf.get_float()
			cmdctrl_curr_depth = buf.get_float()
			cmdctrl_curr_pressure = 101325.0 - (9777.23005 * cmdctrl_curr_depth)
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "SCBNO055R":
		# CALIBRATION DOES NOT MAKE SENSE & IS NOT SUPPORTED IN SIMUALTION
		# THIS IS A DUMMY IMPLEMENTATION JUST SO THE COMMAND IS ACKNOWLEDGED PROPERLY!
		var res = StreamPeerBuffer.new()
		res.big_endian = false
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, res.data_array)
	elif msg_str == "SCBNO055E":
		# CALIBRATION DOES NOT MAKE SENSE & IS NOT SUPPORTED IN SIMUALTION
		# THIS IS A DUMMY IMPLEMENTATION JUST SO THE COMMAND IS ACKNOWLEDGED PROPERLY!
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str.begins_with("SCBNO055S"):
		# CALIBRATION DOES NOT MAKE SENSE & IS NOT SUPPORTED IN SIMUALTION
		# THIS IS A DUMMY IMPLEMENTATION JUST SO THE COMMAND IS ACKNOWLEDGED PROPERLY!
		if msg_len != 23:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	elif msg_str == "BNO055CS":
		# CALIBRATION DOES NOT MAKE SENSE & IS NOT SUPPORTED IN SIMUALTION
		# THIS IS A DUMMY IMPLEMENTATION JUST SO THE COMMAND IS ACKNOWLEDGED PROPERLY!
		var res = PoolByteArray([])
		res.append(0xFF)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, res)
	elif msg_str == "BNO055CV":
		# CALIBRATION DOES NOT MAKE SENSE & IS NOT SUPPORTED IN SIMUALTION
		# THIS IS A DUMMY IMPLEMENTATION JUST SO THE COMMAND IS ACKNOWLEDGED PROPERLY!
		var res = StreamPeerBuffer.new()
		res.big_endian = false
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		res.put_16(0)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, res.data_array)
	elif msg_str == "MS5837CALG":
		# CALIBRATION DOES NOT MAKE SENSE & IS NOT SUPPORTED IN SIMUALTION
		# THIS IS A DUMMY IMPLEMENTATION JUST SO THE COMMAND IS ACKNOWLEDGED PROPERLY!
		var res = StreamPeerBuffer.new()
		res.big_endian = false
		res.put_float(101325.0)
		res.put_float(997.0)
		cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, res.data_array)
	elif msg_str.begins_with("MS5837CALS"):
		if msg_len != 28:
			cmdctrl_acknowledge(msg_id, ACK_ERR_INVALID_ARGS, PoolByteArray([]))
		else:
			cmdctrl_acknowledge(msg_id, ACK_ERR_NONE, PoolByteArray([]))
	else:
		cmdctrl_acknowledge(msg_id, ACK_ERR_UNKNOWN_MSG, PoolByteArray([]))

func cmdctrl_simhijack(hijack: bool):
	if hijack:
		cmdctrl_curr_quat = Quat(0, 0, 0, 0)
		cmdctrl_curr_depth = 0.0
		for i in range(8):
			sim_speeds[i] = 0.0
		cmdctrl_mode = CMDCTRL_MODE_RAW
		for i in range(8):
			cmdctrl_raw_target[i] = 0.0
		mc_set_raw(cmdctrl_raw_target)
		bno055_reset_accum_euler()
	else:
		# Doesn't actually support this.
		# Just do nothing.
		pass

func cmdctrl_mwdog_change(motors_enabled: bool):
	cmdctrl_motors_enabled = motors_enabled
	var msg = StreamPeerBuffer.new()
	msg.put_data("WDGS".to_ascii())
	if motors_enabled:
		msg.put_u8(1)
	else:
		msg.put_u8(0)
	pccomm_write(msg.data_array)
	
func cmdctrl_send_simstat():
	var msg = StreamPeerBuffer.new()
	msg.big_endian = false
	msg.put_data("SIMSTAT".to_ascii())
	msg.put_float(sim_speeds[0])
	msg.put_float(sim_speeds[1])
	msg.put_float(sim_speeds[2])
	msg.put_float(sim_speeds[3])
	msg.put_float(sim_speeds[4])
	msg.put_float(sim_speeds[5])
	msg.put_float(sim_speeds[6])
	msg.put_float(sim_speeds[7])
	msg.put_u8(cmdctrl_mode)
	if cmdctrl_motors_enabled:
		msg.put_u8(0)
	else:
		msg.put_u8(1)
	pccomm_write(msg.data_array)

################################################################################


################################################################################
# Sim motor_control
################################################################################

var pid_last_target = Vector3(0, 0, 0)
var pid_last_yaw_target = false
var pid_last_depth = -999.0

var mc_motors_killed = true

var sim_speeds = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

var mc_relscale = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

var mc_invert = [false, false, false, false, false, false, false, false]

var dof_matrix = Matrix.new(8, 6)
var overlap_vectors = [
	Matrix.new(8, 1),
	Matrix.new(8, 1),
	Matrix.new(8, 1),
	Matrix.new(8, 1),
	Matrix.new(8, 1),
	Matrix.new(8, 1),
	Matrix.new(8, 1),
	Matrix.new(8, 1)
]

var xrot_pid = PIDController.new()
var yrot_pid = PIDController.new()
var zrot_pid = PIDController.new()
var depth_pid = PIDController.new()


func mc_set_dof_matrix(tnum: int, row_data: PoolRealArray):
	dof_matrix.set_row(tnum - 1, row_data)

func mc_recalc():
	# Construct contribution matrix
	var contribution_matrix = Matrix.new(8, 6)
	for row in range(contribution_matrix.rows):
		for col in range(contribution_matrix.cols):
			var dof_item = dof_matrix.get_item(row, col)
			contribution_matrix.set_item(row, col, 1 if dof_item != 0 else 0)
	
	# Construct overlap vectors
	for r in range(contribution_matrix.rows):
		var rowdata = contribution_matrix.get_row(r)
		var v = Matrix.new(6, 1)
		v.set_row(0, rowdata)
		overlap_vectors[r] = contribution_matrix.mul(v)
		for row in range(overlap_vectors[r].rows):
			for col in range(overlap_vectors[r].cols):
				var item = overlap_vectors[r].get_item(row, col)
				overlap_vectors[r].set_item(row, col, 1 if item != 0 else 0)

func mc_wdog_timeout():
	mc_motors_killed = true
	for i in range(8):
		sim_speeds[i] = 0.0
	cmdctrl_mwdog_change(false)

func mc_wdog_feed() -> bool:
	var ret = mc_motors_killed
	_wdog_timer.stop()
	_wdog_timer.start(1.5)
	if(mc_motors_killed):
		cmdctrl_mwdog_change(true)
	mc_motors_killed = false
	return ret


# Rotate v by q
func rotate_vector(v: Vector3, q: Quat) -> Vector3:
	var qv = Quat(v.x, v.y, v.z, 0)
	var qconj = q.inverse()
	var qr = q * qv * qconj
	return Vector3(qr.x, qr.y, qr.z)

# Rotate v by q.inverse()
func rotate_vector_inv(v: Vector3, q: Quat) -> Vector3:
	var qv = Quat(v.x, v.y, v.z, 0)
	var qconj = q.inverse()
	var qr = qconj * qv * q
	return Vector3(qr.x, qr.y, qr.z)

# Minimum rotation from a to b (as quaternion)
func quat_diff(a: Quat, b: Quat) -> Quat:
	var dot = a.dot(b)
	var b_inv = b.inverse()
	if(dot < 0.0):
		b_inv = -1 * b_inv
	return a * b_inv

# Quaternion rotation from vector a to vector b
func quat_between(a: Vector3, b: Vector3) -> Quat:
	var dot = a.dot(b)
	var a_len2 = a.length_squared()
	var b_len2 = b.length_squared()
	var p = sqrt(a_len2 * b_len2)
	var cross = a.cross(b)
	if(dot / p == -1):
		# 180 degree
		return Quat(cross.x, cross.y, cross.z, 0).normalized()
	else:
		return Quat(cross.x, cross.y, cross.z, dot + p).normalized()

# Twist part of swing-twist decomposition
# Calculates twist of q around axis described by vector d
# d must be normalized!
func quat_twist(q: Quat, d: Vector3) -> Quat:
	var r = Vector3(q.x, q.y, q.z)
	var dot = r.dot(d)
	var p = dot * d
	var twist = Quat(p.x, p.y, p.z, q.w).normalized()
	if(dot < 0.0):
		return -twist
	else:
		return twist

# Resitrict angle to -PI to PI rad or -180 to 180 deg
func restrict_angle(angle: float, isdeg: bool):
	if isdeg:
		while angle > 180.0:
			angle -= 360.0
		while angle < -180.0:
			angle += 360.0
	else:
		while angle > PI:
			angle -= 2.0 * PI
		while angle < -PI:
			angle += 2.0 * PI
	return angle

# Get alternate (equivalent, but imprpper) euler angle
func euler_alt(src: Vector3, isdeg: bool) -> Vector3:
	var dest = Vector3(0, 0, 0)
	if isdeg:
		dest.x = 180.0 - src.x
		dest.y = src.y - 180.0
		dest.z = src.z - 180.0
	else:
		dest.x = PI - src.x
		dest.y = src.y - PI
		dest.z = src.z - PI
	dest.x = restrict_angle(dest.x, isdeg)
	dest.y = restrict_angle(dest.y, isdeg)
	dest.z = restrict_angle(dest.z, isdeg)
	return dest

# Get magnitude of largest magnitude element of vector
func vec_max_mag(v: Vector3):
	return max(abs(v.x), max(abs(v.y), abs(v.z)))


# Use mc_relscale factors to scale speeds down as needed
func mc_downscale_reldof(src: Vector3, angular: bool) -> Vector3:
	var scale_x = mc_relscale[3] if angular else mc_relscale[0]
	var scale_y = mc_relscale[4] if angular else mc_relscale[1]
	var scale_z = mc_relscale[5] if angular else mc_relscale[2]
	
	# If a component of the input is zero, no reason to consider that component when downscaling
	if abs(src.x) < 1e-4:
		scale_x = 0.0
	if abs(src.y) < 1e-4:
		scale_y = 0.0
	if abs(src.z) < 1e-4:
		scale_z = 0.0
	
	# Rebalance so largest factor is 1.0
	var maxscale = max(scale_x, max(scale_y, scale_z))
	if maxscale == 0.0:
		maxscale = 1.0
	scale_x /= maxscale
	scale_y /= maxscale
	scale_z /= maxscale
	
	# Do scaling
	return Vector3(src.x * scale_x, src.y * scale_y, src.z * scale_z)

# Scale src proportionally so largest element is v
func mc_upscale_vec(src: Vector3, v: float) -> Vector3:
	if abs(v) < 1e-4:
		return Vector3(0, 0, 0)
	else:
		var max_mag = vec_max_mag(src)
		return Vector3(
			(src.x / max_mag) * abs(v),
			(src.y / max_mag) * abs(v),
			(src.z / max_mag) * abs(v)
		)

# Ensure all elements of src have magnitude less than or equal to 1
func mc_downscale_if_needed(src: Vector3) -> Vector3:
	var maxmag = vec_max_mag(src)
	if(maxmag > 1.0):
		return src / maxmag
	else:
		return src

# Use quat to construct pitch / roll compensation using gravity vectors
func mc_grav_rot(qcurr: Quat) -> Quat:
	var grav = Vector3(
		2.0 * (-qcurr.x*qcurr.z + qcurr.w*qcurr.y),
		2.0 * (-qcurr.w*qcurr.x - qcurr.y*qcurr.z),
		-qcurr.w*qcurr.w + qcurr.x*qcurr.x + qcurr.y*qcurr.y - qcurr.z*qcurr.z
	).normalized()
	return quat_between(Vector3(0, 0, -1), grav)

# Convert quat to euler angles. Choose euler angle with minimal roll
# RETURNED EULER ANGLES WILL BE IN RADIANS!
func mc_baseline_euler(qcurr: Quat) -> Vector3:
	var e_orig = Angles.quat_to_cboard_euler(qcurr)
	var e_alt = euler_alt(e_orig, false)
	if abs(e_orig.y) < abs(e_alt.y):
		return e_orig
	else:
		return e_alt

# Split euler e into three quaternions for pitch, roll, yaw
# Euler angles must be in RADIANS!
# returns [q_pitch, q_roll, q_yaw]
func mc_euler_to_split_quat(e: Vector3) -> Array:
	var e_pitch = Vector3(e.x, 0, 0)
	var e_roll = Vector3(0, e.y, 0)
	var e_yaw = Vector3(0, 0, e.z)
	var q_pitch = Angles.cboard_euler_to_quat(e_pitch)
	var q_roll = Angles.cboard_euler_to_quat(e_roll)
	var q_yaw = Angles.cboard_euler_to_quat(e_yaw)
	return [q_pitch, q_roll, q_yaw]


func mc_sassist_tune_xrot(kp: float, ki: float, kd: float, limit: float, invert: bool):
	xrot_pid.kP = kp
	xrot_pid.kI = ki
	xrot_pid.kD = kd
	xrot_pid.omin = -limit
	xrot_pid.omax = limit
	xrot_pid.invert = invert

func mc_sassist_tune_yrot(kp: float, ki: float, kd: float, limit: float, invert: bool):
	yrot_pid.kP = kp
	yrot_pid.kI = ki
	yrot_pid.kD = kd
	yrot_pid.omin = -limit
	yrot_pid.omax = limit
	yrot_pid.invert = invert

func mc_sassist_tune_zrot(kp: float, ki: float, kd: float, limit: float, invert: bool):
	zrot_pid.kP = kp
	zrot_pid.kI = ki
	zrot_pid.kD = kd
	zrot_pid.omin = -limit
	zrot_pid.omax = limit
	zrot_pid.invert = invert

func mc_sassist_tune_depth(kp: float, ki: float, kd: float, limit: float, invert: bool):
	depth_pid.kP = kp
	depth_pid.kI = ki
	depth_pid.kD = kd
	depth_pid.omin = -limit
	depth_pid.omax = limit
	depth_pid.invert = invert


func mc_set_raw(speeds: PoolRealArray):
	if not mc_motors_killed:
		for i in range(8):
			if mc_invert[i]:
				speeds[i] *= -1
		for i in range(8):
			sim_speeds[i] = speeds[i]

func mc_set_local(x: float, y: float, z: float, xrot: float, yrot: float, zrot: float):
	# Limit speeds to valid range
	x = min(1, max(x, -1))
	y = min(1, max(y, -1))
	z = min(1, max(z, -1))
	xrot = min(1, max(xrot, -1))
	yrot = min(1, max(yrot, -1))
	zrot = min(1, max(zrot, -1))
	
	var target = Matrix.new(6, 1)
	target.set_col(0, [x, y, z, xrot, yrot, zrot])
	
	# Base speed calculation
	var speed_vec = dof_matrix.mul(target)
	
	# Scale motor speeds down as needed
	while true:
		var res = speed_vec.absmax()
		var mval = res[0]
		var idxrow = res[1]
		var idxcol = res[2]
		if mval <= 1:
			break
		for i in range(overlap_vectors[idxrow].rows):
			var cval = overlap_vectors[idxrow].get_item(i, 0)
			if cval == 1:
				cval = speed_vec.get_item(i, 0)
				cval /= mval
				speed_vec.set_item(i, 0, cval)
	
	var speeds = speed_vec.get_col(0)
	mc_set_raw(speeds)

func mc_set_global(x: float, y: float, z: float, pitch_spd: float, roll_spd: float, yaw_spd: float, curr_quat: Quat):
	var qrot = mc_grav_rot(curr_quat)
	var tx = mc_upscale_vec(rotate_vector(Vector3(x, 0, 0), qrot), x)
	var ty = mc_upscale_vec(rotate_vector(Vector3(0, y, 0), qrot), y)
	var tz = mc_upscale_vec(rotate_vector(Vector3(0, 0, z), qrot), z)
	
	var l = tx + ty + tz
	l = mc_downscale_reldof(l, false)
	l = mc_downscale_if_needed(l)
	
	var e_base = mc_baseline_euler(curr_quat)
	var res = mc_euler_to_split_quat(e_base)
	var q_pitch = res[0]
	var q_roll = res[1]
	var q_yaw = res[2]
	
	var w_roll = Vector3(0, roll_spd, 0)
	var s_pitch = Vector3(pitch_spd, 0, 0)
	var w_pitch = rotate_vector_inv(s_pitch, q_roll)
	var s_yaw = Vector3(0, 0, yaw_spd)
	var w_yaw = rotate_vector_inv(rotate_vector_inv(s_yaw, q_pitch), q_roll)
	w_pitch = mc_upscale_vec(w_pitch, pitch_spd)
	w_yaw = mc_upscale_vec(w_yaw, yaw_spd)
	
	var rot = w_pitch + w_roll + w_yaw
	rot = mc_downscale_reldof(rot, true)
	rot = mc_downscale_if_needed(rot)
	
	mc_set_local(l.x, l.y, l.z, rot.x, rot.y, rot.z)

func mc_set_sassist(x: float, y: float, yaw_spd: float, target_euler: Vector3, target_depth: float, curr_quat: Quat, curr_depth: float, yaw_target: bool):
	var base_rot = Vector3(0, 0, 0)
	var qrot = mc_grav_rot(curr_quat)
	
	if not yaw_target:
		var curr_twist = quat_twist(curr_quat, Vector3(0, 0, 1))
		var curr_yaw = atan2(-2.0 * (curr_twist.x*curr_twist.y - curr_twist.w*curr_twist.z), 1.0 - 2.0 * (curr_twist.x*curr_twist.x + curr_twist.z*curr_twist.z))
		curr_yaw *= 180.0 / PI
		target_euler.z = curr_yaw
		base_rot = rotate_vector(Vector3(0, 0, yaw_spd), qrot)
		base_rot = mc_upscale_vec(base_rot, yaw_spd)
	
	var target_quat = Angles.cboard_euler_to_quat(target_euler * PI / 180.0)
	var dot = curr_quat.dot(target_quat)
	var q_c_conj = Quat(0, 0, 0, 0)
	if dot < 0.0:
		var temp = -curr_quat
		q_c_conj = temp.inverse()
	else:
		q_c_conj = curr_quat.inverse()
	var q_d = q_c_conj * target_quat
	var mag = sqrt(q_d.x*q_d.x + q_d.y*q_d.y + q_d.z*q_d.z)
	var theta = 2.0 * atan2(mag, q_d.w)
	var a = Vector3(q_d.x, q_d.y, q_d.z)
	if mag > 0.001:
		a = a / mag
	var e = a * theta
	
	if abs(pid_last_depth - target_depth) > 0.01:
		depth_pid.reset()
	var do_reset = false
	if yaw_target != pid_last_yaw_target:
		do_reset = true
	elif yaw_target and \
			(abs(target_euler.x - pid_last_target.x) > 1e-2 or \
			abs(target_euler.y - pid_last_target.y) > 1e-2 or \
			abs(target_euler.z - pid_last_target.z) > 1e-2):
		do_reset = true
	elif not yaw_target and \
			(abs(target_euler.x - pid_last_target.x) > 1e-2 or \
			abs(target_euler.y - pid_last_target.y) > 1e-2):
		do_reset = true
	if do_reset:
		xrot_pid.reset()
		yrot_pid.reset()
		zrot_pid.reset()
	
	var z = -depth_pid.calculate(curr_depth - target_depth)
	var xrot = xrot_pid.calculate(e.x)
	var yrot = yrot_pid.calculate(e.y)
	var zrot = zrot_pid.calculate(e.z)
	
	pid_last_depth = target_depth
	pid_last_target = target_euler
	pid_last_yaw_target = yaw_target
	
	var rot = Vector3(xrot, yrot, zrot) + base_rot
	rot = mc_downscale_reldof(rot, true)
	rot = mc_downscale_if_needed(rot)
	
	var tx = mc_upscale_vec(rotate_vector(Vector3(x, 0, 0), qrot), x)
	var ty = mc_upscale_vec(rotate_vector(Vector3(0, y, 0), qrot), y)
	var tz = mc_upscale_vec(rotate_vector(Vector3(0, 0, z), qrot), z)
	
	var l = tx + ty + tz
	l = mc_downscale_reldof(l, false)
	l = mc_downscale_if_needed(l)
	
	mc_set_local(l.x, l.y, l.z, rot.x, rot.y, rot.z)

func mc_set_dhold(x: float, y: float, pitch_spd: float, roll_spd: float, yaw_spd: float, target_depth: float, curr_quat: Quat, curr_depth: float):
	if abs(pid_last_depth - target_depth) > 0.01:
		depth_pid.reset()
	var z = -depth_pid.calculate(curr_depth - target_depth)
	pid_last_depth = target_depth
	mc_set_global(x, y, z, pitch_spd, roll_spd, yaw_spd, curr_quat)
	

################################################################################


################################################################################
# BNO055 (accumulated angle stuff only)
################################################################################

var bno055_accum = Vector3(0, 0, 0)
var bno055_prev_quat_valid = false
var bno055_prev_quat = Quat(0, 0, 0, 0)


func bno055_do_accum():
	var curr_quat = cmdctrl_curr_quat
	var quat_same = (curr_quat.w == bno055_prev_quat.w) and \
		(curr_quat.x == bno055_prev_quat.x) and \
		(curr_quat.y == bno055_prev_quat.y) and \
		(curr_quat.z == bno055_prev_quat.z)
	if bno055_prev_quat_valid and not quat_same:
		var dot = curr_quat.dot(bno055_prev_quat)
		var diff_quat = Quat(0, 0, 0, 0)
		if dot < 0.0:
			diff_quat = -bno055_prev_quat
		else:
			diff_quat = bno055_prev_quat
		diff_quat = diff_quat.inverse()
		diff_quat = curr_quat * diff_quat
		var diff_euler = Angles.quat_to_cboard_euler(diff_quat) * 180.0 / PI
		bno055_accum += diff_euler
	bno055_prev_quat = curr_quat
	bno055_prev_quat_valid = curr_quat.w != 0 or curr_quat.x != 0 or curr_quat.y != 0 or curr_quat.z != 0
	
func bno055_reset_accum_euler():
	bno055_accum = Vector3(0, 0, 0)
	bno055_prev_quat_valid = false
