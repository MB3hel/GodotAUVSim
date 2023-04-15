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
signal msg_received(msgfull)

# Emitted when a simstat message is received
signal simstat(mode, wdg_killed, x, y, z, p, r, h)

################################################################################



################################################################################
# Globals
################################################################################

# Connection status
var _uart_connected = false
var _sim_connected = false

# Holds message read from control board
var _read_msg = PoolByteArray()

# Holds full data of message received from control board
var _read_data = PoolByteArray()

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
var _portname = ""

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

# Connect to simulated control board (internal)
func connect_sim():
	# TODO: Implement
	pass

# Disconnect from simulated control board (internal)
func disconnect_sim(sig: bool = true):
	# TODO: Implement
	pass

# Called when timeout while waiting on SIMHIJACK command
func _simhijack_timeout():
	# Disconnect now (no signal)
	if self._uart_connected:
		self.disconnect_uart(false)
	elif self._sim_connected:
		self.disconnect_sim(false)
	
	# Emit failure signal
	self.emit_signal("cboard_connect_fail", "Timeout while hijacking control board.")

################################################################################



################################################################################
# Communication
################################################################################

func _next_msg_id() -> int:
	var msg_id = self._curr_msg_id
	self._curr_msg_id += 1
	return msg_id

# Write a message to the control board
# The provided data is the PAYLOAD not a formatted message
func _write_msg(msg_id: int, data: PoolByteArray):
	# TODO: Implement
	pass

# Write to the control board
# The provided data must already be in the format of a message
func write_raw(data: PoolByteArray):
	if _uart_connected:
		# TODO: Write to uart
		pass
	elif _sim_connected:
		# TODO: Read from uart
		pass

# Read any available bytes from connected control board
# Returns true when a complete message is in _read_buf
func _read_task():
	if _uart_connected:
		# TODO: Read from UART until no bytes available
		pass
	elif _sim_connected:
		# TODO: Read from simcb until no bytes available
		pass

# Handle a complete (valid) message in the read buffer
func _handle_msg():
	# If ack to simhijack msg id
	# 	Cancel timer
	# 	Either emit connection failed or connected signal
	# Else If ack to simdata msg id:
	# 	ignore the message
	# Else If SIMSTAT message
	#   Parse message and emit simstat signal
	# Else
	# 	Emit msg_received signal
	pass

################################################################################
