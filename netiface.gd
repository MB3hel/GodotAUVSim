################################################################################
# file: netiface.gd
# author: Marcus Behel
################################################################################
# Network interface to the simulator
# The simulator runs two TCP servers
#   - Port 5011: Command Server
#   - Port 5012: Control Board Server
#
# The control board server forwards messages it receives to the control board 
# the simulator is using. Messages received from the simulator-managed control 
# board will be send to the client on the control board server.
# The intent is that a program written for a control board can instead connect
# to the simulator over TCP and send the same data over TCP that would have
# been sent to a control board via UART.
#
# The command port is a way to also control the simulator itself via TCP. This
# allows scripts to be written that define initial conditions for simulation.
# This allows for unit testing via simulation.
################################################################################

extends Node

################################################################################
# Signals
################################################################################

# Received a message from cboard client port (should be forwarded)
signal cboard_data_received(data)

# Client conncetion state changes (used by simulation.gd for UI)
signal client_connected()
signal client_disconnected()

################################################################################



################################################################################
# Globals
################################################################################

var _cmd_server = TCP_Server.new()
var _cboard_server = TCP_Server.new()

var _cmd_client: StreamPeerTCP = null
var _cboard_client: StreamPeerTCP = null
var _connected = false
var _client_addr = ""

const listen_addr = "*"
const cmd_port = 5011
const cboard_port = 5012

var _allow_connections = false

var _cmd_buffer = ""

# This is always instantiated by and added as a child of simulation.gd
onready var _sim = get_parent()

################################################################################



################################################################################
# Godot Engine functions
################################################################################

func _ready():
	if _cmd_server.listen(cmd_port, listen_addr) != OK:
		OS.alert("Failed to start command sever (%s:%d)" % [listen_addr, cmd_port], "Startup Error")
		get_tree().quit()
	if _cboard_server.listen(cboard_port, listen_addr) != OK:
		OS.alert("Failed to start cboard sever (%s:%d)" % [listen_addr, cboard_port], "Startup Error")
		get_tree().quit()

func _process(delta):
	if self._connected:
		# Check for and handle disconnects
		if _cmd_client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			disconnect_client()
		elif _cboard_client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			disconnect_client()
		
		# Reject further connections when something is already connected
		if _cmd_server.is_connection_available():
			self._cmd_server.take_connection().disconnect_from_host()
		if _cboard_server.is_connection_available():
			self._cboard_server.take_connection().disconnect_from_host()
	else:
		if not self._allow_connections:
			# Reject connections when not allowed
			if _cmd_server.is_connection_available():
				self._cmd_server.take_connection().disconnect_from_host()
			if _cboard_server.is_connection_available():
				self._cboard_server.take_connection().disconnect_from_host()
		elif _cmd_server.is_connection_available() and _cboard_server.is_connection_available():
			# Accept incoming connection from same address on both ports
			_cmd_client = _cmd_server.take_connection()
			_cboard_client = _cboard_server.take_connection()
			if _cmd_client.get_connected_host() != _cboard_client.get_connected_host():
				self.disconnect_client()
			else:
				self._connected = true
				self._client_addr = _cmd_client.get_connected_host()
				self.emit_signal("client_connected")
	
	# Process network stuff
	if self._connected:
		_process_cmd()
		_process_cboard()

################################################################################

func get_client_addr() -> String:
	return self._client_addr

func _process_cmd():
	if _cmd_client.get_available_bytes() > 0:
		var new_str = _cmd_client.get_string(_cmd_client.get_available_bytes())
		while true:
			var idx = new_str.find("\n")
			if idx == -1:
				_cmd_buffer += new_str
				break
			else:
				var res = _handle_cmd(_cmd_buffer + new_str.substr(0, idx))
				_cmd_client.put_data(("%s\n" % res).to_ascii())
				_cmd_buffer = ""
				new_str = new_str.substr(idx+1)

func _handle_cmd(line: String) -> String:
	var parts = line.split(" ")
	
	# EC is an error code (0 = none, 1 = invalid arguments, 2 = unknown command)
	
	# NOTE: Commands are not handled by emitting signals for sim to handle later.
	# Instead, a reference to simulation.gd is kept and its functions are called
	# directly. This is done for two reasons
	#   1. Once a command is acknowledged it has finished (blocking)
	#   2. Commands that query for data that requires the sim can acknowledge with the data
	#      Ex: get_pos -> EC x y z   requires x, y, and z from sim's vehicle instance
	
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
		_sim.set_pos(x, y, z)
		return "0"
	
	# get_pos -> EC [x y z]
	if parts[0] == "get_pos":
		if len(parts) != 1:
			# Invalid arts
			return "1"
		var pos = _sim.get_pos()
		return "%d %f %f %f" % [0, pos.x, pos.y, pos.z]
		
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
		_sim.set_rot(w, x, y, z)
		return "0"
	
	# get_rot -> EC [w x y z]
	if parts[0] == "get_rot":
		if len(parts) != 1:
			# Invalid args
			return "1"
		var q = _sim.get_rot()
		return "%d %f %f %f %f" % [0, q.w, q.x, q.y, q.z]
	
	# reset_vehicle -> EC
	if parts[0] == "reset_vehicle":
		if len(parts) != 1:
			return "1"
		_sim.reset_vehicle()
		return "0"
	
	# Unknown command
	return "2"

# This is  not a parser. Bytes read from TCP are just written to the
# control board directly.
# Unlike data coming from the control board, the simulator never
# needs to use any data being sent to the control board.
func _process_cboard():
	if _cboard_client.get_available_bytes() > 0:
		var res = _cboard_client.get_data(_cboard_client.get_available_bytes())
		self.emit_signal("cboard_data_received", res[1])

func disconnect_client():
	if self._connected:
		self._cmd_client.disconnect_from_host()
		self._cboard_client.disconnect_from_host()
		self._connected = false
		self._client_addr = ""
		self.emit_signal("client_disconnected")

func allow_connections():
	self._allow_connections = true

func disallow_connections():
	disconnect_client()
	self._allow_connections = false
