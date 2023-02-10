extends Spatial


# Resousrces used during simulation
onready var robot = get_node("Robot")
onready var ui = get_node("UIRoot")
onready var cboard = ControlBoard.new(robot)

# Store default parameters
onready var robot_def_translation = robot.translation
onready var robot_def_rotation = robot.rotation
onready var robot_def_max_translation = robot.max_translation
onready var robot_def_max_rotation = robot.max_rotation

# TCP stuff
var cmd_server = TCP_Server.new()
var cboard_server = TCP_Server.new()
var cmd_client: StreamPeerTCP = null
var cboard_client: StreamPeerTCP = null
const listen_addr = "127.0.0.1"
const cmd_port = 5011
const cboard_port = 5012


# Buffer for received command data
var cmd_buffer = "";


func _ready():
	# Start TCP servers
	if cmd_server.listen(cmd_port, listen_addr) != OK:
		OS.alert("Failed to start command sever (%s:%d)" % [listen_addr, cmd_port], "Startup Error")
		get_tree().quit()
	if cboard_server.listen(cboard_port, listen_addr) != OK:
		OS.alert("Failed to start cboard sever (%s:%d)" % [listen_addr, cboard_port], "Startup Error")
		get_tree().quit()


func _process(_delta):
	# Network stuff
	if cmd_client != null and cboard_client != null:
		# Handle disconnects
		if cmd_client.get_status() != StreamPeerTCP.STATUS_CONNECTED or cboard_client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			cmd_client.disconnect_from_host()
			cmd_client = null
			cboard_client.disconnect_from_host()
			cboard_client = null
	if cmd_client != null and cboard_client != null:
		# Connected. Handle data if any.
		if cmd_client.get_available_bytes() > 0:
			var new_str = cmd_client.get_string(cmd_client.get_available_bytes())
			while true:
				var idx = new_str.find("\n")
				if idx == -1:
					cmd_buffer += new_str
					break
				else:
					var res = handle_command(cmd_buffer + new_str.substr(0, idx))
					cmd_client.put_data(("%s\n" % res).to_ascii())
					print(res)
					cmd_buffer = ""
					new_str = new_str.substr(idx+1)
		# TODO: Handle cboard data
	else:
		# Check for and handle new connections
		if cmd_server.is_connection_available() and cboard_server.is_connection_available():
			cmd_client = cmd_server.take_connection()
			cboard_client= cboard_server.take_connection()
			if cmd_client.get_connected_host() != cboard_client.get_connected_host():
				# Connections from two different hosts. Invalid setup.
				cmd_client.disconnect_from_host()
				cmd_client = null
				cboard_client.disconnect_from_host()
				cboard_client = null
	
	# Update UI 
	ui.curr_translation = robot.curr_translation
	ui.curr_rotation = robot.curr_rotation
	ui.robot_quat = Quat(robot.rotation)
	ui.robot_euler = Angles.quat_to_cboard_euler(ui.robot_quat) * 180.0 / PI


# Error codes:
# 0 = OK
# 1 = INVALID_ARGS
# 2 = UNKNOWN_CMD
func handle_command(cmd: String) -> String:
	
	# get_pos -> EC x y z
	# set_rot w x y z -> EC
	# get_rot -> EC w x y z
	# reset_sim
	var parts = cmd.split(" ")
	
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
		robot.translation = Vector3(x, y, z)
		return "0"
		
	# Unknown command
	return "2"

