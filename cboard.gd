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

# Emitted on connection state changes
signal cboard_connected()
signal cboard_disconnected()
signal cboard_connect_fail(reason)

# Emitted when a message is received from the control board
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
onready var _ser = preload("res://GDSerial/GDSerial.gdns").new()

# Current serial port name
var _portname = ""

################################################################################


################################################################################
# Godot Engine Methods
################################################################################

func _ready():
	add_child(_simhijack_timer)
	_simhijack_timer.one_shot = true

func _process(delta):
	# TODO: If connected to UART check for connection drop
	# Primarily check by isError function
	
	# TODO: Run read task (limit to reading finite bytes to ensure bounded time)
	pass

################################################################################



################################################################################
# Connectivity
################################################################################

# Connect to real control board on the given port
func connect_uart(port: String):
	# Connect to UART
	# Send SIMHIJACK command
	# Do NOT wait for ACK
	# Make sure to set _portname
	pass

# Disconnect from real control board
func disconnect_uart():
	# TODO: Disconnect UART
	# Make sure to clear _portname
	# Emit signal
	pass

# Connect to simulated control board (internal)
func connect_sim():
	# TODO: Implement
	pass

# Disconnect from simulated control board (internal)
func disconnect_sim():
	# TODO: Implement
	# TODO: Cancel any simhijack timer
	pass

# Called when timeout while waiting on SIMHIJACK command
func _connect_timeout():
	self.emit_signal("cboard_connect_fail", "Timeout while hijacking control board.")

################################################################################



################################################################################
# Communication
################################################################################

# Write a message to the control board
# The provided data is the PAYLOAD not a formatted message
# NOTE: There is currently no support for waiting for ACK
# returns msg_id
func write_msg(data: PoolByteArray) -> int:
	# TODO: Implement
	return 0

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
