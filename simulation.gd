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
# onready var net = preload("res://netiface.gd).new()

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
	
	# Add cboard as a child so "_ready" actually gets called
	add_child(cboard)
	
	# Connect signals
	connect_cb_dialog.connect("connect_cboard", self, "conncet_cboard")
	btn_disconnect_cb.connect("pressed", self, "disconnect_cboard")
	cboard.connect("cboard_connect_fail", self, "cboard_connect_fail")
	cboard.connect("cboard_connected", self, "cboard_connected")
	cboard.connect("cboard_disconnected", self, "cboard_disconnected")
	cboard.connect("simstat", self, "cboard_simstat")
	
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
	self.connect_cb_dialog.hide_dialog()

# When cboard disconnected (comm lost or due to user request)
func cboard_disconnected():
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
