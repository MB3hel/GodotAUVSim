extends Spatial


# Resousrces used during simulation
onready var robot = get_node("Robot")
onready var ui = get_node("UIRoot")
onready var cboard = ControlBoard.new(robot)

# Store default parameters
onready var robot_def_transform = robot.transform
onready var robot_def_max_translation = robot.max_translation
onready var robot_def_max_rotation = robot.max_rotation

# TCP stuff
var cmd_server = TCP_Server.new()
var cboard_server = TCP_Server.new()
var cmd_client = null
var cboard_client = null
const listen_addr = "127.0.0.1"
const cmd_port = 5011
const cboard_port = 5012


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
		# TODO: Handle possible disconnects
		# TODO: Connected. Handle data if any.
		pass
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
