extends Node

onready var robot = get_parent().get_node("Robot")

signal msg_received(msgfull)
signal reset_vehicle()

var write_mutex = Mutex.new()

const listen_addr = "*"
const cmd_port = 5011
const cboard_port = 5012

var cmd_server = TCP_Server.new()
var cboard_server = TCP_Server.new()

var cmd_client: StreamPeerTCP = null
var cboard_client: StreamPeerTCP = null
var connected = false
var tcpclient = ""
var accepts_connections = false   # Only true when connected to control board

func _ready():
	if cmd_server.listen(cmd_port, listen_addr) != OK:
		OS.alert("Failed to start command sever (%s:%d)" % [listen_addr, cmd_port], "Startup Error")
		get_tree().quit()
	if cboard_server.listen(cboard_port, listen_addr) != OK:
		OS.alert("Failed to start cboard sever (%s:%d)" % [listen_addr, cboard_port], "Startup Error")
		get_tree().quit()


func _process(_delta):
	if connected:
		# Handle disconnects
		if cmd_client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			do_disconnect()
		elif cboard_client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			do_disconnect()
		
		# Handle forced disconnects
		if not accepts_connections:
			do_disconnect()
	elif cmd_server.is_connection_available() and cboard_server.is_connection_available():
		# Handle connections.
		if accepts_connections:
			cmd_client = cmd_server.take_connection()
			cboard_client= cboard_server.take_connection()
			if cmd_client.get_connected_host() != cboard_client.get_connected_host():
				# Connections from two different hosts. Invalid setup.
				do_disconnect()
			else:
				connected = true
				tcpclient = cmd_client.get_connected_host()
		else:
			cmd_server.take_connection().disconnect_from_host()
			cboard_server.take_connection().disconnect_from_host()
	
	# Handle network stuff
	if connected:
		process_cmd()
		process_cboard()


func do_disconnect():
	cmd_client.disconnect_from_host()
	cboard_client.disconnect_from_host()
	cmd_client = null
	cboard_client = null
	connected = false
	tcpclient = ""

################################################################################
# Command server
################################################################################
# The command server is used by a program to manipulate simulator's 
# "initial conditions". This allows programs using the simulator's control board
# can also manipualate the simulator for testing.
# This port implements an ASCII "command line" interface
#   command_name [arg_1] [arg_2] [arg_3] ...
# commands are newline delimited (ASCII 10)
# Each command will receive a response in the following format (followed by a 
# newline character ASCII 10)
#   [EC] [res_1] [res_2] [res_3] ...
# EC is an error code (0 = none, 1 = invalid arguments, 2 = unknown command)
# If EC is not 0, other results may not be included.
# The command parser is *very* simple. It will not handle extra whitespace
# including carriage returns, additional spaces, etc
# Note that responses to commands will be written in the order the commands were
# written. Thus it is possible to send two commands before receiving the
# response for the first. The first response received will be to the first 
# command and the second will be to the second command.
# The following "commands" are implemented
#    Set robot position: set_pos x y z -> EC
#    Get robot position: get_pos -> EC x y z
#    Set robot orientation: set_rot w x y z -> EC
#    Get robot orientation: get_rot -> EC w x y z
#    Reset vehicle: reset_vehicle -> EC

var cmd_buffer = ""

func process_cmd():
	if cmd_client.get_available_bytes() > 0:
		var new_str = cmd_client.get_string(cmd_client.get_available_bytes())
		while true:
			var idx = new_str.find("\n")
			if idx == -1:
				cmd_buffer += new_str
				break
			else:
				var res = handle_cmd_line(cmd_buffer + new_str.substr(0, idx))
				cmd_client.put_data(("%s\n" % res).to_ascii())
				cmd_buffer = ""
				new_str = new_str.substr(idx+1)


func handle_cmd_line(line: String) -> String:
	var parts = line.split(" ")
	
	# set_pos x y z -> EC
	if parts[0] == "set_pos":
		if len(parts) != 4:
			# Invalid args
			return "1"
		if not parts[1].is_valid_float() or \
				not parts[2].is_valid_float() or \
				not parts[3].is_valid_float():
			# Invalid args
			return "1"
		var x = float(parts[1])
		var y = float(parts[2])
		var z = float(parts[3])
		robot.set_trans(Vector3(x, y, z))
		return "0"
	
	# get_pos -> EC [x y z]
	if parts[0] == "get_pos":
		if len(parts) != 1:
			# Invalid arts
			return "1"
		var x = robot.translation.x
		var y = robot.translation.y
		var z = robot.translation.z
		return "%d %f %f %f" % [0, x, y, z]
		
	# set_rot w x y z -> EC
	if parts[0] == "set_rot":
		if len(parts) != 5:
			# Invalid args
			return "1"
		if not parts[1].is_valid_float() or \
				not parts[2].is_valid_float() or \
				not parts[3].is_valid_float() or \
				not parts[4].is_valid_float():
			# Invalid args
			return "1"
		var w = float(parts[1])
		var x = float(parts[2])
		var y = float(parts[3])
		var z = float(parts[4])
		robot.set_rot(Angles.quat_to_godot_euler(Quat(x, y, z, w)))
		return "0"
	
	# get_rot -> EC [w x y z]
	if parts[0] == "get_rot":
		if len(parts) != 1:
			# Invalid arts
			return "1"
		var q = Angles.godot_euler_to_quat(robot.rotation)
		return "%d %f %f %f %f" % [0, q.w, q.x, q.y, q.z]
	
	# reset_vehicle -> EC
	if parts[0] == "reset_vehicle":
		if len(parts) != 1:
			return "1"
		emit_signal("reset_vehicle")
		return "0"
	
	# Unknown command
	return "2"

################################################################################

################################################################################
# Control Board server
################################################################################
# A program written for the control board can instead connect to the simulator's
# control board TCP server. This server will receive formatted messages from the 
# client and forward them to the control board managed by the simulator.
# Additionall messages received by the simulator from the control board are
# forwarded to the client connected to this server.
#
# This communication works on a "formatted message" level meaning only recognized
# messages (conforming to control board spec) will be forwarded either direction

func process_cboard():
	pass

# Write raw data to control board client (if connected)
func write_raw(msg: PoolByteArray):
	write_mutex.lock()
	# TODO: Write to client if any
	write_mutex.unlock()

################################################################################
