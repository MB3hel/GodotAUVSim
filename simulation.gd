extends Spatial
class_name Simulator


# Resousrces used during simulation
onready var robot = get_node("Robot")
onready var ui = get_node("UIRoot")


# Store default parameters
onready var def_robot_rotation = robot.rotation
onready var def_robot_translation = robot.translation
onready var def_robot_weight = robot.weight
onready var def_robot_mass = robot.mass
onready var def_robot_linear_damp = robot.linear_damp
onready var def_robot_angular_damp = robot.angular_damp
onready var def_robot_max_force = robot.max_force
onready var def_robot_max_torque = robot.max_torque

# TCP stuff
var cmd_server = TCP_Server.new()
var cmd_client: StreamPeerTCP = null
const listen_addr = "127.0.0.1"
const cmd_port = 5011
var cmd_buffer = "";

# Control board state information
var cboard_connected = false
var cboard_wdog_killed = true
var cboard_mode = "LOCAL"


func _ready():
	self.ui.connect("sim_reset", self, "reset_sim")
	
	# Start TCP servers
	if cmd_server.listen(cmd_port, listen_addr) != OK:
		OS.alert("Failed to start command sever (%s:%d)" % [listen_addr, cmd_port], "Startup Error")
		get_tree().quit()


# Called every frame
# delta is time between last call and now in seconds
# This function is called as fast as possible!
func _process(delta):
	process_ui(delta)
	process_network(delta)


func process_ui(_delta):
	ui.curr_translation = robot.curr_force
	ui.curr_rotation = robot.curr_torque
	ui.robot_pos = robot.translation
	ui.robot_quat = Quat(robot.rotation)
	ui.robot_euler = Angles.quat_to_cboard_euler(ui.robot_quat) / PI * 180.0
	ui.connected = cboard_connected
	ui.mode_value = cboard_mode


func process_network(_delta):
	if cmd_client != null:
		# Make sure still connected
		if cmd_client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			# Connection lost
			cboard_connected = false
			cboard_wdog_killed = true
			move_local(0, 0, 0, 0, 0, 0)
		
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
	elif cmd_server.is_connection_available():
		# Accept incoming connections if nothing currently connected
		cmd_client = cmd_server.take_connection()
		cboard_connected = true


func reset_sim():
	robot.curr_force = Vector3(0, 0, 0)
	robot.curr_torque = Vector3(0, 0, 0)
	robot.linear_velocity = Vector3(0, 0, 0)
	robot.angular_velocity = Vector3(0, 0, 0)
	robot.translation = def_robot_translation
	robot.rotation = def_robot_rotation
	robot.max_force = def_robot_max_force
	robot.max_torque = def_robot_max_torque
	robot.weight = def_robot_weight
	robot.mass = def_robot_mass
	robot.linear_damp = def_robot_linear_damp
	robot.angular_damp = def_robot_angular_damp


func move_local(x, y, z, pitch, roll, yaw):
	robot.curr_force = Vector3(x, y, z)
	robot.curr_torque = Vector3(pitch, roll, yaw)


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
	
	# from_cboard mode wdg_killed x y z pitch roll yaw
	if parts[0] == "cboard_state":
		if len(parts) != 9:
			return "1"
		# TODO: Handle data
		return "0"
	
	# to_cboard -> EC [w x y z depth]
	if parts[0] == "to_cboard":
		if len(parts) != 1:
			return "1"
		# TODO: Handle data
		return "0"
	
	# Unknown command
	return "2"
