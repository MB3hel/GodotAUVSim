extends PopupDialog

# Emitted when user clicks "connect" button
signal connect_cboard(port)

# UI elements
onready var lbl_error = find_node("ErrorLabel")
onready var obtn_uart = find_node("PortsSelector")
onready var btn_connect = find_node("ConnectButton")
onready var btn_exit = find_node("ExitButton")
onready var cbx_uart = find_node("UartCheckbox")
onready var cbx_sim = find_node("SimCheckbox")

# GDSerial instance used to list serial ports for dropdown
var ser = load("res://GDSerial/GDSerial.gdns").new()

# Timer to update ports list
var update_ports_timer = Timer.new()

# Current list of ports
var curr_ports = PoolStringArray()

func _ready():
	var simcb_script = load("res://simcb.gd")
	
	var vertype = ""
	if simcb_script.FW_VER_TYPE == "a":
		vertype = "alpha"
	elif simcb_script.FW_VER_TYPE == "b":
		vertype = "beta"
	if simcb_script.FW_VER_TYPE == "c":
		vertype = "rc"
	
	var ver_str = ""
	if vertype == "":
		# Full release
		ver_str = "%d.%d.%d" % [simcb_script.FW_VER_MAJOR, simcb_script.FW_VER_MINOR, simcb_script.FW_VER_REVISION]
	else:
		# Pre-release
		ver_str = "%d.%d.%d-%s%d" % [simcb_script.FW_VER_MAJOR, simcb_script.FW_VER_MINOR, simcb_script.FW_VER_REVISION, vertype, simcb_script.FW_VER_BUILD]
	cbx_sim.text = "%s (%s)" % [cbx_sim.text, ver_str]
	
	self.add_child(update_ports_timer)
	self.update_ports_timer.one_shot = false
	self.update_ports_timer.connect("timeout", self, "update_ports")
	self.update_ports_timer.start(1)
	
	self.btn_connect.connect("pressed", self, "do_connect")
	self.btn_exit.connect("pressed", self, "do_exit")
	self.cbx_uart.connect("toggled", self, "update_ui_radiobtn")

func update_ui_radiobtn(uart_pressed: bool):
	obtn_uart.disabled = not uart_pressed

func ports_list_matches(a: PoolStringArray, b: PoolStringArray) -> bool:
	if len(a) != len(b):
		return false
	for a_item in a:
		if not a_item in b:
			return false
	return true

func update_ports():
	var ports = ser.list_ports()
	for i in range(ports.size()-1, -1, -1):
		var port = ports[i]
		if port.begins_with("/dev/ttyS"):
			ports.remove(i)
		if port.begins_with("LPT"):
			ports.remove(i)
	
	# Update dropdown if number of ports changed
	# keep the same selection unless that port is no longer present
	if not ports_list_matches(ports, self.curr_ports):
		var selIdx = obtn_uart.get_selected_id()
		var sel = ""
		if selIdx >= 0:
			sel = obtn_uart.get_item_text(selIdx)
		selIdx = -1
		obtn_uart.clear()
		for opt in ports:
			obtn_uart.add_item(opt)
			if opt == sel:
				selIdx = obtn_uart.get_item_count() - 1
		obtn_uart.select(selIdx)
		self.curr_ports = ports

func do_connect():
	self.btn_connect.disabled = true
	var cb = "SIM"
	if cbx_uart.is_pressed():
		cb = self.obtn_uart.get_item_text(self.obtn_uart.selected)

	self.emit_signal("connect_cboard", cb)

func do_exit():
	get_tree().quit()

func show_dialog():
	self.btn_connect.disabled = false
	self.update_ports()
	self.popup()

func hide_dialog():
	self.hide()

func show_error(msg: String):
	self.btn_connect.disabled = false
	lbl_error.text = msg
