extends Node
class_name ControlBoard

enum AckError {NONE = 0, UNKNOWN_MSG = 1, INVALID_ARGS = 2, INVALID_CMD = 3, TIMEOUT = 255}

# Sercomm instance (used for UART)
onready var ser = get_node("GDSercomm")

# Is connected to control board via UART
var connected = false

# Current msg_id
var curr_msg_id = 0

# Received from control board periodically
var watchdog_killed = true
var local_x = 0.0		# x
var local_y = 0.0		# y
var local_z = 0.0		# z
var local_p = 0.0		# pitch
var local_r = 0.0		# roll
var local_h = 0.0		# yaw / heading

# Sent to control board periodically
var curr_quat = Quat(0.0, 0.0, 0.0, 1.0)
var curr_depth = 0.0

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

func connect_uart(port: String) -> bool:
	if connected:
		disconnect_uart()
	var ports = ser.list_ports()
	if not port in ports:
		return false
	ser.open(port, 115200, 0)
	if self.sim_hijack(true) != AckError.NONE:
		ser.close()
		return false
	read_thread = Thread.new()
	connected = true
	read_thread.start(self, "read_task")
	sensor_data_timer.start(0.015)
	return true


func disconnect_uart():
	sensor_data_timer.stop()
	connected = false
	read_thread.wait_to_finish()
	ser.close()

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
	var res = self.wait_for_ack(msg_id, 0.1)
	return res[0]
	

# Called periodically by timer to write sensor data to control board
func write_sensor_data():
	# TODO: Write sensor data
	pass

################################################################################

################################################################################
# Control board communication
################################################################################

func prepare_for_ack(msg_id: int):
	# TODO
	pass


# Wait for message ack
# timeout in seconds
# Returns [AckError, PoolByteArray]
func wait_for_ack(msg_id: int, timeout: float) -> Array:
	# TODO
	return []


# Write a message to control board formatted properly
func write_msg(msg: PoolByteArray, ack: bool = false) -> int:
	var msg_id = curr_msg_id
	curr_msg_id += 1
	if ack:
		self.prepare_for_ack(msg_id)
	# TODO: Construct and write message
	return msg_id


# Write raw data to control board (must already be formatted properly)
func write_raw(msg: PoolByteArray):
	# TODO
	pass

# Read and handle messages from control board
func read_task(userdata):
	var msg = PoolByteArray([])
	while connected:
		# TODO
		pass

################################################################################
