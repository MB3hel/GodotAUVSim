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

################################################################################



################################################################################
# Godot Functions
################################################################################

func _ready():
	# Add cboard as a child so "_ready" actually gets called
	add_child(cboard)
	
	# Connect signals
	connect_cb_dialog.connect("connect_cboard", self, "conncet_cboard")
	btn_disconnect_cb.connect("pressed", self, "disconnect_cboard")
	cboard.connect("cboard_connect_fail", self, "cboard_connect_fail")
	cboard.connect("cboard_connected", self, "cboard_connected")
	cboard.connect("cboard_disconnected", self, "cboard_disconnected")
	
	# Show connect dialog at startup
	connect_cb_dialog.show_dialog()

func _process(delta):
	pass

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
