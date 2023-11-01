################################################################################
# file: cboard.gd
# author: Marcus Behel
################################################################################
# Interface to control board
# Handles sending messages to and receiving messages from control board
# Also handles UART communication with real control board or 
# communication with simulated control board via shared variables
################################################################################

extends Node

################################################################################
# Signals
################################################################################

# Connected to control board (UART or SIM)
signal cboard_connected()

# Disconnected from control board (UART or SIM)
signal cboard_disconnected()

# Failed to connect to control board (UART; won't happen for SIM)
signal cboard_connect_fail(reason)

# Emitted when an unhandled message is received from the control board
signal msg_received(msg_full)

# Emitted when a simstat message is received
signal simstat(mode, wdg_killed, speeds)

################################################################################



################################################################################
# Globals
################################################################################

# Constants for cboard communication
const START_BYTE = 253
const END_BYTE = 254
const ESCAPE_BYTE = 255

# Connection status
var _uart_connected = false
var _sim_connected = false

# Holds message read from control board
var _read_msg = PoolByteArray()

# Holds full data of message received from control board
var _read_data = PoolByteArray()

# Parser status
var _parse_escaped = false
var _parse_started = false

# Used by write_msg
var _curr_msg_id = 60000

# Timer for SIMHIJACK timeout
var _simhijack_timer = Timer.new()

# ID of SIMHIJACK message
var _simhijack_id = 0

# ID of SIMDATA messages
var _simdata_ids = []

# GDSerial instance
# NOTE: GDNative instances seem to NOT be thread safe
# Can easily cause crashes in the engine by having two threads
# access the same GDNative object instance. This is why
# read_task is not its own thread, but runs in _process instead.
var _ser = load("res://GDSerial/GDSerial.gdns").new()

# Current serial port name
# SIM means connected to simcb
# "" (empty string) means not connected
var _portname = ""

var _scb = null

################################################################################


################################################################################
# Godot Engine Methods
################################################################################

func _ready():
	add_child(_simhijack_timer)
	_simhijack_timer.one_shot = true
	_simhijack_timer.connect("timeout", self, "_simhijack_timeout")

func _process(delta):
	if self._uart_connected:
		# Check for connection drop
		# Assume connection dropped if there was a UART error
		# This error would either be from a _ser.write or _ser.read call
		if self._ser.isError():
			printerr(self._ser.errorMessage())
			if self._simhijack_timer.time_left > 0:
				# Conncetion lost while waiting for simhijack
				# Emit connect fail signal, not disconnect signal
				self.disconnect_uart(false)
				self.emit_signal("cboard_connect_fail", "UART connection lost while hijacking control board.")
			else:
				self.disconnect_uart()
	if self._sim_connected:
		# TODO: Check for TCP connection drop
		# Probably just a variable set if comms fail in read / write phase
		pass
	
	# Read data if any
	self._read_task()

################################################################################



################################################################################
# Connectivity
################################################################################

# Connect to real control board on the given port
func connect_uart(port: String):
	# Disconnect if already connected
	if self._sim_connected:
		self.disconnect_sim()
	elif self._uart_connected:
		self.disconnect_uart()
	
	# Reset parser data and state
	self._read_data = PoolByteArray()
	self._read_msg = PoolByteArray()
	self._parse_started = false
	self._parse_escaped = false
	
	# Connect to UART (8N1; baud != 1200)
	_ser.setPort(port)
	_ser.setBaudrate(115200)
	_ser.setBytesize(_ser.BYTESIZE_EIGHTBITS)
	_ser.setParity(_ser.PARITY_NONE)
	_ser.setStopbits(_ser.STOPBITS_ONE)
	
	_ser.isError()			# Clear old error flag (if any)
	_ser.open()
	if _ser.isError():
		self.emit_signal("cboard_connect_fail", "Failed to open serial port.")
		return
	self._uart_connected = true
	self._portname = port
	
	# Send SIMHIJACK preparing to wait for ACK
	var cmd = "SIMHIJACK".to_ascii()
	cmd.append(1)
	self._simhijack_id = self._next_msg_id()
	self._write_msg(self._simhijack_id, cmd)
	
	# Start SIMHIJACK timeout timer
	self._simhijack_timer.start(1)

# Disconnect from real control board
func disconnect_uart(sig: bool = true):
	if not self._uart_connected:
		return
	
	# Cancel simhijack timer
	self._simhijack_timer.stop()
	
	# Disconnect UART
	_ser.close()
	self._uart_connected = false
	self._portname = ""
	
	# Emit signal if required
	if sig:
		self.emit_signal("cboard_disconnected")

# Connect to simulated control board (via TCP)
func connect_sim(port: int):
	# Disconnect if already connected
	if self._sim_connected:
		self.disconnect_sim()
	elif self._uart_connected:
		self.disconnect_uart()
	
	# Reset parser data and state
	self._read_data = PoolByteArray()
	self._read_msg = PoolByteArray()
	self._parse_started = false
	self._parse_escaped = false
	
	# TODO: Actually connect

	self._sim_connected = true
	self._portname = "SIM(" + str(port) + ")"
	
	# Send SIMHIJACK preparing to wait for ACK
	var cmd = "SIMHIJACK".to_ascii()
	cmd.append(1)
	self._simhijack_id = self._next_msg_id()
	self._write_msg(self._simhijack_id, cmd)
	
	# Start SIMHIJACK timeout timer
	self._simhijack_timer.start(1)

# Disconnect from simulated control board (internal)
func disconnect_sim(sig: bool = true):
	if not self._sim_connected:
		return
	
	# Cancel simhijack timer
	self._simhijack_timer.stop()
	
	# TODO: Disconnect TCP
	
	self._sim_connected = false
	self._portname = ""
	
	# Emit signal if required
	if sig:
		self.emit_signal("cboard_disconnected")

# Called when timeout while waiting on SIMHIJACK command
func _simhijack_timeout():
	# Disconnect now (no signal)
	if self._uart_connected:
		self.disconnect_uart(false)
	elif self._sim_connected:
		self.disconnect_sim(false)
	
	# Emit failure signal
	self.emit_signal("cboard_connect_fail", "Timeout while hijacking control board.")

func get_portname() -> String:
	return self._portname

################################################################################



################################################################################
# Communication
################################################################################

# Send SIMDAT command (no wait for ACK)
func send_simdat(quat: Quat, depth: float):
	var msgbuf = StreamPeerBuffer.new()
	msgbuf.big_endian = false
	msgbuf.put_data("SIMDAT".to_ascii())
	msgbuf.put_float(quat.w)
	msgbuf.put_float(quat.x)
	msgbuf.put_float(quat.y)
	msgbuf.put_float(quat.z)
	msgbuf.put_float(depth)
	var msg_id = self._next_msg_id()
	self._simdata_ids.append(msg_id)
	self._write_msg(msg_id, msgbuf.data_array)

# Calcualte 16-bit CRC (CCITT-FALSE algorithm) on some data
func _crc16_ccitt_false(msg: PoolByteArray, initial: int = 0xFFFF) -> int:
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

func _next_msg_id() -> int:
	var msg_id = self._curr_msg_id
	self._curr_msg_id += 1
	return msg_id

# Write a message to the control board
# The provided data is the PAYLOAD not a formatted message
func _write_msg(msg_id: int, data: PoolByteArray):
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
	for b in data:
		if b == START_BYTE or b == END_BYTE or b == ESCAPE_BYTE:
			msg_full.put_u8(ESCAPE_BYTE)
		msg_full.put_u8(b)
	
	# Calculate and write CRC
	var idbuf = PoolByteArray([id_high, id_low])
	var crc = _crc16_ccitt_false(data, _crc16_ccitt_false(idbuf))
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

# Write to the control board
# The provided data must already be in the format of a message
func write_raw(data: PoolByteArray):
	if _uart_connected:
		self._ser.write(data)
	elif _sim_connected:
		# TODO: Write over TCP
		pass

# Read any available bytes from connected control board
# Returns true when a complete message is in _read_buf
func _read_task():
	if _uart_connected:
		var avail = self._ser.available()
		if avail == 0:
			return # Nothing to read
		var data = self._ser.read(avail)
		if data.size() != avail:
			return # Probably an error. Let _process handle it.
		self._parse_msg(data)
	elif _sim_connected:
		var data = null
		# TODO: Read over TCP
		if data.size() == 0:
			return
		self._parse_msg(data)

# Parse some bytes as a control board message
# Modified version of the parser used on cboard and in iface scripts
# This version keeps the full message data (_read_data)
# in addition to the parsed pessage (_read_msg)
# This allows echoing unhandled messages to the network interface
# without modifying them at all (including their IDs)
func _parse_msg(data: PoolByteArray):
	for b in data:
		self._read_data.append(b)
		if _parse_escaped:
			if b == START_BYTE or b == END_BYTE or b == ESCAPE_BYTE:
				self._read_msg.append(b)
			_parse_escaped = false
		elif _parse_started:
			if b == START_BYTE:
				_read_msg = PoolByteArray()
				_read_data = PoolByteArray()
				_read_data.append(b)
			elif b == END_BYTE:
				var calc_crc = _crc16_ccitt_false(_read_msg.subarray(0, _read_msg.size() - 3))
				var read_crc = _read_msg[_read_msg.size() - 2] << 8 | _read_msg[_read_msg.size() - 1]
				if read_crc == calc_crc:
					var read_id = _read_msg[0] << 8 | _read_msg[1]
					_handle_msg(read_id, _read_msg.subarray(2, _read_msg.size() - 3), _read_data)
			elif b == ESCAPE_BYTE:
				_parse_escaped = true
			else:
				_read_msg.append(b)
		elif b == START_BYTE:
			_parse_started = true
			_read_msg = PoolByteArray()
			_read_data = PoolByteArray()
			_read_data.append(b)

# Handle a complete (valid) message in the read buffer
func _handle_msg(read_id: int, msg: PoolByteArray, msg_full: PoolByteArray):
	# If ack to simhijack msg id
	# 	Cancel timer
	# 	Either emit connection failed or connected signal
	# Else If ack to simdata msg id:
	# 	ignore the message
	# Else If SIMSTAT message
	#   Parse message and emit simstat signal
	# Else
	# 	Emit msg_received signal
	if _data_starts_with(msg, "ACK".to_ascii()):
		var ack_id = msg[3] << 8 | msg[4]
		var ack_err = msg[5]
		var ack_dat
		if msg.size() > 6:
			ack_dat = msg.subarray(6, msg.size() - 1)
		else:
			ack_dat = PoolByteArray([])
		
		if ack_id == self._simhijack_id:
			# ACK of the SIMHIJACK command
			# Handle the result and don't forward this message
			self._simhijack_id = -1
			self._simhijack_timer.stop()
			if ack_err == 0:
				self.emit_signal("cboard_connected")
			else:
				self.disconnect_uart(false)
				self.emit_signal("cboard_connect_fail", "Control board rejected hijack.")
			return
		elif ack_id in self._simdata_ids:
			# ACK of a SIMDAT command
			# Ignore the results, but don't forward this message
			self._simdata_ids.remove(self._simdata_ids.find(ack_id))
			return
		# All other ACKs should be forwarded
	elif _data_starts_with(msg, "SIMSTAT".to_ascii()):
		# Handle data
		var msgbuf = StreamPeerBuffer.new()
		msgbuf.data_array = msg
		msgbuf.big_endian = false
		msgbuf.seek(7)
		var speeds = []
		speeds.append(msgbuf.get_float())
		speeds.append(msgbuf.get_float())
		speeds.append(msgbuf.get_float())
		speeds.append(msgbuf.get_float())
		speeds.append(msgbuf.get_float())
		speeds.append(msgbuf.get_float())
		speeds.append(msgbuf.get_float())
		speeds.append(msgbuf.get_float())
		var mode = _mode_name(msgbuf.get_u8())
		var wdg_killed = msgbuf.get_u8() != 0
		self.emit_signal("simstat", mode, wdg_killed, speeds)

		# Don't forward this message
		return
	
	# All messages not handled above should be forwarded
	self.emit_signal("msg_received", msg_full)

func _data_starts_with(full: PoolByteArray, prefix: PoolByteArray) -> bool:
	if prefix.size() > full.size():
		return false
	for i in range(prefix.size()):
		if full[i] != prefix[i]:
			return false
	return true

func _data_matches(a: PoolByteArray, b: PoolByteArray) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true

func _mode_name(mode: int) -> String:
	if mode == 0:
		return "RAW"
	elif mode == 1:
		return "LOCAL"
	elif mode == 2:
		return "GLOBAL"
	elif mode == 3:
		return "SASSIST"
	elif mode == 4:
		return "DHOLD"
	elif mode == 5:
		return "OHOLD"
	else:
		return "UNKNOWN"

################################################################################
