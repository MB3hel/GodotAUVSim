################################################################################
# file: simulatoin.gd
# author: Marcus Behel
################################################################################
# Manges UI and acts as an interface between
# - Network Interface (netiface.gd)
# - Control Board Interface (cboard.gd)
# - Vehicle (vehicle.gd)
################################################################################

extends Node

################################################################################
# Globals
################################################################################

# Simulation objects
onready var vehicle = get_node("Vehicle")
var cboard = load("res://cboard.gd").new()
var netiface = load("res://netiface.gd").new()

# UI Elements
onready var ui_root = get_node("UIRoot")
onready var connect_cb_dialog = ui_root.find_node("ConnectCboardDialog")
onready var btn_disconnect_cb = ui_root.find_node("DisconnectCboardButton")
onready var lbl_mode = ui_root.find_node("ModeValue")
onready var lbl_wdg = ui_root.find_node("MotorWDGValue")
onready var lbl_trans = ui_root.find_node("TranslationValue")
onready var lbl_rot = ui_root.find_node("RotationValue")
onready var lbl_pos = ui_root.find_node("PosValue")
onready var lbl_euler = ui_root.find_node("EulerValue")
onready var lbl_quat = ui_root.find_node("QuatValue")
onready var lbl_cboard_conn = ui_root.find_node("CboardConnLabel")
onready var btn_reset_vehicle = ui_root.find_node("ResetVehicleButton")
onready var btn_copy_status = ui_root.find_node("CopyStatusButton")
onready var status_panel = ui_root.find_node("StatusPanel")
onready var btn_config_vehicle = ui_root.find_node("ConfigVehicleButton")
onready var config_vehicle_dialog = ui_root.find_node("VehicleConfigDialog")
onready var btn_disconnect_tcp = ui_root.find_node("DisconnectNetButton")

# Used to send SIMDAT messages to control board periodically
# Sends simulated sensor data (orientation and depth) to control board
var timer_simdat = Timer.new()

################################################################################



################################################################################
# Godot Functions
################################################################################

func _ready():
	# Setup timers
	add_child(self.timer_simdat)
	self.timer_simdat.one_shot = false
	timer_simdat.connect("timeout", self, "send_simdat")
	self.timer_simdat.start(0.015)		# Send every 15ms (same rate control board polls sensors)
	
	# Add as children so "_ready" actually gets called
	# Also means these nodes can add things like timers as their children
	add_child(cboard)
	add_child(netiface)
	
	# Connect signals
	connect_cb_dialog.connect("connect_cboard", self, "conncet_cboard")
	btn_disconnect_cb.connect("pressed", self, "disconnect_cboard")
	cboard.connect("cboard_connect_fail", self, "cboard_connect_fail")
	cboard.connect("cboard_connected", self, "cboard_connected")
	cboard.connect("cboard_disconnected", self, "cboard_disconnected")
	cboard.connect("simstat", self, "cboard_simstat")
	btn_reset_vehicle.connect("pressed", self, "reset_vehicle")
	btn_copy_status.connect("pressed", self, "copy_to_clipboard")
	btn_config_vehicle.connect("pressed", self, "config_vehicle")
	config_vehicle_dialog.connect("applied", self, "apply_vehicle_config")
	btn_disconnect_tcp.connect("pressed", netiface, "disconnect_client")
	netiface.connect("cboard_data_received", cboard, "write_raw")
	
	# Show connect dialog at startup
	connect_cb_dialog.show_dialog()

func _process(delta):
	# Update UI labels for vehicle information
	var pos = vehicle.translation
	var quat = Angles.godot_euler_to_quat(vehicle.rotation)
	var euler = Angles.quat_to_cboard_euler(quat) * 180.0 / PI
	lbl_pos.text = "(x=%+.2f, y=%+.2f, z=%+.2f)" % [pos.x, pos.y, pos.z]
	lbl_euler.text = "(p=%+.2f, r=%+.2f, y=%+.2f)" % [euler.x, euler.y, euler.z]
	lbl_quat.text = "(w=%+.4f, x=%+.4f, y=%+.4f, z=%+.4f)" %  [quat.w, quat.x, quat.y, quat.z]

################################################################################



################################################################################
# Signal handlers
################################################################################

# When user clicks Connect button in connect dialog
func conncet_cboard(port):
	if port == "SIM":
		self.cboard.connect_sim()
	else:
		self.cboard.connect_uart(port)

# When user clicks disconnect control board button in UI
func disconnect_cboard():
	if self.cboard.get_portname() == "SIM":
		self.cboard.disconnect_sim()
	else:
		self.cboard.disconnect_uart()

# When connect to control board fails
func cboard_connect_fail(reason: String):
	self.connect_cb_dialog.show_error(reason)

# When connceted to control board successfully
func cboard_connected():
	lbl_cboard_conn.text = "Control Board: " + cboard.get_portname()
	self.connect_cb_dialog.hide_dialog()
	self.netiface.allow_connections()

# When cboard disconnected (comm lost or due to user request)
func cboard_disconnected():
	# Make vehicle stop on disconnect from control board
	cboard_simstat("RAW", true, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	
	self.netiface.disallow_connections()
	lbl_cboard_conn.text = "Control Board: Not Connected"
	self.connect_cb_dialog.show_dialog()

# Called by timer to send SIMDAT periodically
func send_simdat():
	if self.cboard.get_portname() != "":
		self.cboard.send_simdat(Angles.godot_euler_to_quat(vehicle.rotation), vehicle.translation.z)

# When control board interface receives SIMSTAT (periodic)
func cboard_simstat(mode: String, wdg_killed: bool, x: float, y: float, z: float, p: float, r: float, h: float):
	lbl_mode.text = mode
	if wdg_killed:
		lbl_wdg.text = "Killed"
	else:
		lbl_wdg.text = "Not Killed"
	lbl_trans.text = "(x=%+.2f, y=%+.2f, z=%+.2f)" % [x, y, z]
	lbl_rot.text = "(p=%+.2f, r=%+.2f, y=%+.2f)" % [p, r, h]
	vehicle.move_local(x, y, z, p, r, h)

# When user clicks reset vehicle button
# Can also be called direclty from netiface
func reset_vehicle():
	vehicle.move_local(0, 0, 0, 0, 0, 0)
	vehicle.translation = Vector3(0, 0, 0)
	vehicle.rotation = Vector3(0, 0, 0)

# When user clicks copy to clipboard button
func copy_to_clipboard():
	var data = ""
	for i in range(0, status_panel.get_child_count(), 2):
		var label = status_panel.get_child(i)
		var value = status_panel.get_child(i+1)
		data += label.text + " " + value.text + "\n"
	OS.set_clipboard(data)

# When user clicks configure vehicle button
func config_vehicle():
	var trans = vehicle.translation
	var rot = Angles.godot_euler_to_cboard_euler(vehicle.rotation) * 180.0 / PI
	config_vehicle_dialog.show_dialog(trans.x, trans.y, trans.z, rot.x, rot.y, rot.z)

# When user applies (ok button) vehicle config
func apply_vehicle_config(x, y, z, p, r, h):
	vehicle.translation = Vector3(x, y, z)
	vehicle.rotation = Angles.cboard_euler_to_godot_euler(Vector3(p, r, h) * PI / 180.0)

# Called by netiface
func set_pos(x: float, y: float, z: float):
	vehicle.translation = Vector3(x, y, z)

# Called by netiface
func get_pos() -> Vector3:
	return vehicle.translation

# Called by netiface
func set_rot(w:float, x: float, y: float, z: float):
	vehicle.rotation = Angles.quat_to_godot_euler(Quat(x, y, z, w))

# Called by netiface
func get_rot() -> Quat:
	return Angles.godot_euler_to_quat(vehicle.rotation)

################################################################################
