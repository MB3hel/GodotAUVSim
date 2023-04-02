extends Spatial
class_name Simulator


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


var hijacked = false;
var devmode_node = null


func _ready():
	add_child(cboard)
	self.ui.connect("sim_reset", self, "reset_sim")
	
	# See devmode.gd for details
	var dm = load("res://devmode.gd").new()
	if dm.should_hijack():
		hijacked = true
		dm.sim = self
		dm.robot = robot
		dm.cboard = cboard
		devmode_node = dm
		add_child(dm)
		get_node("UIRoot/DevmodeLabel").show()
		# Simulator hijacked. Not starting tcp.
		return
		
	
	# Start TCP servers
	if cmd_server.listen(cmd_port, listen_addr) != OK:
		OS.alert("Failed to start command sever (%s:%d)" % [listen_addr, cmd_port], "Startup Error")
		get_tree().quit()
	if cboard_server.listen(cboard_port, listen_addr) != OK:
		OS.alert("Failed to start cboard sever (%s:%d)" % [listen_addr, cboard_port], "Startup Error")
		get_tree().quit()


func _process(_delta):
	# Update UI 
	ui.curr_translation = robot.curr_translation
	ui.curr_rotation = robot.curr_rotation
	ui.robot_pos = robot.translation
	ui.robot_quat = Quat(robot.rotation)
	ui.robot_euler = Angles.quat_to_cboard_euler(ui.robot_quat) / PI * 180.0
	if cboard.mode == cboard.MODE_LOCAL:
		ui.mode_value = "LOCAL"
	elif cboard.mode == cboard.MODE_GLOBAL:
		ui.mode_value = "GLOBAL"
	elif cboard.mode == cboard.MODE_SASSIST:
		ui.mode_value = "SASSIST"
	elif cboard.mode == cboard.MODE_DHOLD:
		ui.mode_value = "DHOLD"
	else:
		ui.mode_value = "???"
	if cboard.motors_killed:
		ui.wdg_status = "Killed"
	else:
		ui.wdg_status = "Active"
		
	
	# Skip network stuff if devmode override
	if self.hijacked:
		return
	
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
					cmd_buffer = ""
					new_str = new_str.substr(idx+1)
		
		# Handle data if any
		if cboard_client.get_available_bytes() > 0:
			var res = cboard_client.get_data(cboard_client.get_available_bytes())
			cboard.handle_data(res[1])
		
		# Send data back from cboard if any
		cboard.write_buffer_mutex.lock()
		if cboard.write_buffer.get_size() > 0:
			cboard_client.put_data(cboard.write_buffer.data_array)
			cboard.write_buffer.clear()
		cboard.write_buffer_mutex.unlock()
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
	


# Error codes:
# 0 = OK
# 1 = INVALID_ARGS
# 2 = UNKNOWN_CMD
func handle_command(cmd: String) -> String:
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
		robot.rotation = Angles.quat_to_godot_euler(Quat(x, y, z, w))
		return "0"
	
	# get_rot -> EC [w x y z]
	if parts[0] == "get_rot":
		if len(parts) != 1:
			# Invalid arts
			return "1"
		var q = Angles.godot_euler_to_quat(robot.rotation)
		return "%d %f %f %f %f" % [0, q.w, q.x, q.y, q.z]
	
	# reset_sim -> EC
	if parts[0] == "reset_sim":
		if len(parts) != 1:
			return "1"
		reset_sim()
		return "0"
	
	# set_max_trans m -> EC
	if parts[0] == "set_max_trans":
		if len(parts) != 2:
			return "1"
		if not parts[1].is_valid_float():
			return "1"
		robot.max_translation = float(parts[1])
		return "0"
	
	# get_max_trans -> EC [m]
	if parts[0] == "get_max_trans":
		if len(parts) != 1:
			return "1"
		return "%d %f" % [0, robot.max_translation]
	
	# set_max_rot m -> EC
	if parts[0] == "set_max_rot":
		if len(parts) != 2:
			return "1"
		if not parts[1].is_valid_float():
			return "1"
		robot.max_rotation = float(parts[1])
		return "0"
	
	# get_max_rot -> EC [m]
	if parts[0] == "get_max_rot":
		if len(parts) != 1:
			return "1"
		return "%d %f" % [0, robot.max_rotation]
	
	# Unknown command
	return "2"


func reset_sim():
	cboard.reset()
	robot.curr_rotation = Vector3(0, 0, 0)
	robot.curr_translation = Vector3(0, 0, 0)
	robot.translation = robot_def_translation
	robot.rotation = robot_def_rotation
	robot.max_translation = robot_def_max_translation
	robot.max_rotation = robot_def_max_rotation
	
	if devmode_node != null:
		# Reset devmode script too
		remove_child(devmode_node)
		var dm = load("res://devmode.gd").new()
		dm.sim = self
		dm.robot = robot
		dm.cboard = cboard
		devmode_node = dm
		add_child(dm)
