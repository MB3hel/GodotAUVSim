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
onready var connect_cb_dialog = get_node("UIRoot/ConnectCboardDialog")

################################################################################



################################################################################
# Godot Functions
################################################################################

func _ready():
	connect_cb_dialog.show_dialog()

func _process(delta):
	pass

################################################################################
