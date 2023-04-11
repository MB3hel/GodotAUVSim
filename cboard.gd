extends Node
class_name ControlBoard

# Used to signal simulation manager that there is a message to be forwarded
# to TCP interface
# This is NOT called for messages that are handled by this class
# Messages handled by this class include
#   SIMSTAT messages
#   ACK messages for an id for which this class is waiting
# Everything else is forwarded without alteration.
signal msg_received(msgfull)

# Emitted when uart disconnects (due to read / write failure or due to call of disconnect_uart)
signal disconnected_uart

enum AckError {NONE = 0, UNKNOWN_MSG = 1, INVALID_ARGS = 2, INVALID_CMD = 3, TIMEOUT = 255}

const START_BYTE = 253
const END_BYTE = 254
const ESCAPE_BYTE = 255

# Array of ack_waits[msg_id] = [err, res]
var ack_waits = {}

# Sercomm instance (used for UART)
onready var ser = get_node("GDSercomm")
onready var robot = get_parent().get_node("Robot")

# Is connected to control board via UART
var connected = false
var portname = ""

# Current msg_id
# Simulator uses IDs 60000-65535
var curr_msg_id_mutex = Mutex.new()
var curr_msg_id = 60000

# Received from control board periodically
var mode = "UNKNOWN"
var watchdog_killed = true
var local_x = 0.0		# x
var local_y = 0.0		# y
var local_z = 0.0		# z
var local_p = 0.0		# pitch
var local_r = 0.0		# roll
var local_h = 0.0		# yaw / heading

# Write simulated sensor data periodically
var sensor_data_timer = Timer.new()

# Thread to read messages from control board
var read_thread = null


func _ready():
	add_child(sensor_data_timer)
	sensor_data_timer.one_shot = false
	sensor_data_timer.connect("timeout", self, "write_sensor_data")


################################################################################
# Connection management
################################################################################

func connect_uart(port: String) -> String:
	if connected:
		disconnect_uart()
	var ports = ser.list_ports()
	if not port in ports:
		return "Invalid port. Did the port get disconnected?"
	ser.open(port, 115200, 0)
	
	read_thread = Thread.new()
	connected = true
	portname = port
	read_thread.start(self, "read_task")
	
	if self.sim_hijack(true) != AckError.NONE:
		disconnect_uart()
		return "Failed to hijack control board. Is the selected port really a control board? Is the firmware flashed?"
	
	sensor_data_timer.start(0.015)
	return "No error."


func disconnect_uart():
	if not connected:
		return
	sensor_data_timer.stop()
	connected = false
	portname = ""
	ser.close()
	read_thread.wait_to_finish()
	read_thread = null
	emit_signal("disconnected_uart")

################################################################################


################################################################################
# Simulation commands to control board
################################################################################

# Hijack control board for simulation
# true to hijack, false to release
func sim_hijack(hijack: bool) -> int:
	var msg = "SIMHIJACK".to_ascii()
	if hijack:
		msg.append(1)
	else:
		msg.append(0)
	var msg_id = self.write_msg(msg, true)
	var res = self.wait_for_ack(msg_id, 0.5)
	return res[0]
	

# Called periodically by timer to write sensor data to control board
func write_sensor_data() -> int:
	var curr_quat = Angles.godot_euler_to_quat(robot.rotation)
	var curr_depth = robot.translation.z
	var accum_euler = robot.accum_euler
	
	var buf = StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_data("SIMDAT".to_ascii())
	buf.put_float(curr_quat.w)
	buf.put_float(curr_quat.x)
	buf.put_float(curr_quat.y)
	buf.put_float(curr_quat.z)
	buf.put_float(accum_euler.x)
	buf.put_float(accum_euler.y)
	buf.put_float(accum_euler.z)
	buf.put_float(curr_depth)
	
	var msg_id = self.write_msg(buf.data_array, true)
	var res = self.wait_for_ack(msg_id, 0.1)
	return res[0]

################################################################################

################################################################################
# Control board communication
################################################################################

# Called to make sure ack for message is captured
func prepare_for_ack(msg_id: int):
	ack_waits[msg_id] = null


# Wait for message ack
# timeout in seconds
# Returns [AckError, StreamPeerBuffer]
func wait_for_ack(msg_id: int, timeout: float) -> Array:
	if not ack_waits.has(msg_id):
		return [null, null]
	while ack_waits[msg_id] == null && timeout > 0:
		OS.delay_msec(1)
		timeout -= 0.001
	var err = AckError.NONE
	var res = StreamPeerBuffer.new()
	if timeout <= 0:
		err = AckError.TIMEOUT
	else:
		err = ack_waits[msg_id][0]
		res.put_data(ack_waits[msg_id][1])
	ack_waits.erase(msg_id)
	return [err, res]


# Write a message to control board formatted properly
# THIS MESSAGE WRITES A PAYLOAD!!! DO NOT USE FOR FORMATTED DATA!
func write_msg(msg: PoolByteArray, ack: bool = false) -> int:
	curr_msg_id_mutex.lock()
	var msg_id = curr_msg_id
	curr_msg_id += 1
	if curr_msg_id == 65535:
		curr_msg_id = 60000
	curr_msg_id_mutex.unlock()
	if ack:
		self.prepare_for_ack(msg_id)
	
	var msg_full = StreamPeerBuffer.new()
	
	# Write start byte
	msg_full.put_u8(START_BYTE)
	
	# Write msg_id (escaped as needed)
	var id_high = (msg_id >> 8) & 0xFF
	var id_low = msg_id & 0xFF
	if id_high == START_BYTE or id_high == END_BYTE or id_high == ESCAPE_BYTE:
		msg_full.put_u8(ESCAPE_BYTE)
	msg_full.put_u8(id_high)
	if id_low == START_BYTE or id_low == END_BYTE or id_low == ESCAPE_BYTE:
		msg_full.put_u8(ESCAPE_BYTE)
	msg_full.put_u8(id_low)
	
	# Write each byte of msg escaping as needed
	for b in msg:
		if b == START_BYTE or b == END_BYTE or b == ESCAPE_BYTE:
			msg_full.put_u8(ESCAPE_BYTE)
		msg_full.put_u8(b)
	
	# Calculate and write CRC
	var idbuf = PoolByteArray([id_high, id_low])
	var crc = crc16_ccitt_false(msg, crc16_ccitt_false(idbuf))
	var crc_high = (crc >> 8) & 0xFF
	var crc_low =  crc & 0xFF
	if crc_high == START_BYTE or crc_high == END_BYTE or crc_high == ESCAPE_BYTE:
		msg_full.put_u8(ESCAPE_BYTE)
	msg_full.put_u8(crc_high)
	if crc_low == START_BYTE or crc_low == END_BYTE or crc_low == ESCAPE_BYTE:
		msg_full.put_u8(ESCAPE_BYTE)
	msg_full.put_u8(crc_low)
	
	# Write end byte
	msg_full.put_u8(END_BYTE)
	
	self.write_raw(msg_full.data_array)
	return msg_id


# Write raw data to control board
func write_raw(data: PoolByteArray):
	for b in data:
		if ser.write_raw(b) < 0:
			disconnect_uart()



# Read and handle messages from control board
# Modified version of the same parser used on cboard and in iface scripts
# However, in this version msgfull contains escape characters
# msg does not
# This way msg can be used for comparison, but msgfull can be forwarded to TCP
# when needed. This ensures that message IDs on messages forwarded from control
# board to TCP are not altered.
func read_task(userdata):
	var msg = PoolByteArray([])
	var msgfull = PoolByteArray([])
	var parse_escaped = false
	var parse_started = true
	while connected:
		var b = ser.read(true)
		if b < 0:
			disconnect_uart()
			break
		
		# Unparsed (full) message here
		msgfull.append(b)
		
		# Parse into msg
		if parse_escaped:
			if b == START_BYTE or b == END_BYTE or b == ESCAPE_BYTE:
				msg.append(b)
			parse_escaped = false
		elif parse_started:
			if b == START_BYTE:
				msg = PoolByteArray([])
				msgfull = PoolByteArray([])
				msgfull.append(b)
			elif b == END_BYTE:
				var calc_crc = crc16_ccitt_false(msg.subarray(0, msg.size() - 3))
				var read_crc = msg[msg.size() - 2] << 8 | msg[msg.size() - 1]
				if read_crc == calc_crc:
					var read_id = msg[0] << 8 | msg[1]
					handle_msg(read_id, msg.subarray(2, msg.size() - 1), msgfull)
			elif b == ESCAPE_BYTE:
				parse_escaped = true
			else:
				msg.append(b)
		elif b == START_BYTE:
			parse_started = true
			msg = PoolByteArray([])
			msgfull = PoolByteArray([])
			msgfull.append(b)

func handle_msg(read_id: int, msg: PoolByteArray, msgfull: PoolByteArray):
	if data_starts_with(msg, "ACK".to_ascii()):
		var ack_id = msg[3] << 8 | msg[4]
		var ack_err = msg[5]
		var ack_dat
		if msg.size() > 6:
			ack_dat = msg.subarray(6, msg.size() - 1)
		else:
			ack_dat = PoolByteArray([])
		if ack_waits.has(ack_id):
			ack_waits[ack_id] = [ack_err, ack_dat]
			return # This message is handled here. Do not forward.
	elif data_starts_with(msg, "SIMSTAT".to_ascii()):
		var buf = StreamPeerBuffer.new()
		buf.data_array = msg
		buf.big_endian = false
		buf.seek(7)
		local_x = buf.get_float()
		local_y = buf.get_float()
		local_z = buf.get_float()
		local_p = buf.get_float()
		local_r = buf.get_float()
		local_h = buf.get_float()
		mode = mode_name(buf.get_u8())
		watchdog_killed = buf.get_u8() == 1
		return # This message is handled here. Do not forward.
	
	self.emit_signal("msg_received", msgfull)


func mode_name(i: int) -> String:
	if i == 0:
		return "RAW"
	elif i == 1:
		return "LOCAL"
	elif i == 2:
		return "GLOBAL"
	elif i == 3:
		return "SASSIST"
	elif i == 4:
		return "DHOLD"
	else:
		return "UNKNOWN"


# Calcualte 16-bit CRC (CCITT-FALSE algorithm) on some data
func crc16_ccitt_false(msg: PoolByteArray, initial: int = 0xFFFF) -> int:
	var crc = initial
	var pos = 0
	while pos < msg.size():
		var b = msg[pos]
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

################################################################################

func data_starts_with(full: PoolByteArray, prefix: PoolByteArray) -> bool:
	if prefix.size() > full.size():
		return false
	for i in range(prefix.size()):
		if full[i] != prefix[i]:
			return false
	return true

func data_matches(a: PoolByteArray, b: PoolByteArray) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true
