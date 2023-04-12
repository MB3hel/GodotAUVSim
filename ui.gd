extends Control

# Data to be displayed in UI
var curr_translation = Vector3(0.0, 0.0, 0.0)
var curr_rotation = Vector3(0.0, 0.0, 0.0)
var robot_euler = Vector3(0.0, 0.0, 0.0)
var robot_quat = Quat(0.0, 0.0, 0.0, 1.0)
var robot_pos = Vector3(0.0, 0.0, 0.0)
var mode_value = "LOCAL"
var wdg_status = "Killed"
var portname = ""
var tcpclient = ""

var uart_ports = []
var old_uart_ports = []

onready var translation_label = find_node("TranslationValue")
onready var rotation_label = find_node("RotationValue")
onready var pos_label = find_node("PosValue")
onready var euler_label = find_node("EulerValue")
onready var quat_label = find_node("QuatValue")
onready var mode_label = find_node("ModeValue")
onready var wdg_label = find_node("MotorWDGValue")
onready var conn_label = find_node("ConnLabel")
onready var netconn_label = find_node("NetConnLabel")

onready var copy_button = find_node("CopyButton")
onready var reset_button = find_node("ResetButton")
onready var disconnect_button = find_node("DisconnectButton")
onready var disconnect_tcp_button = find_node("DisconnectNetButton")
onready var config_button = find_node("SetButton")

onready var connect_dialog = get_node("ConnectDialog")
onready var connect_btn = connect_dialog.find_node("ConnectButton")
onready var exit_btn = connect_dialog.find_node("ExitButton")
onready var uart_dropdown = connect_dialog.find_node("PortsSelector")
onready var connect_err = connect_dialog.find_node("ErrorLabel")

onready var config_dialog = get_node("SetRobotDialog")
onready var config_ok_btn = config_dialog.find_node("OkButton")
onready var config_cancel_btn = config_dialog.find_node("CancelButton")
onready var config_xbox = config_dialog.find_node("xBox")
onready var config_ybox = config_dialog.find_node("yBox")
onready var config_zbox = config_dialog.find_node("zBox")
onready var config_pbox = config_dialog.find_node("pBox")
onready var config_rbox = config_dialog.find_node("rBox")
onready var config_hbox = config_dialog.find_node("hBox")


const translation_template = "(x=%+.2f, y=%+.2f, z=%+.2f)"
const rotation_template = "(p=%+.2f, r=%+.2f, y=%+.2f)"
const euler_template = "(p=%+.2f, r=%+.2f, h=%+.2f)"
const quat_template = "(w=%+.4f, x=%+.4f, y=%+.4f, z=%+.4f)"


signal sim_reset
signal cboard_connect(port)
signal cboard_disconnect
signal net_disconnect
signal sim_config
signal do_configure_vehicle(x, y, z, p, r, h)


func _ready():
	copy_button.connect("pressed", self, "copy_to_clipboard")
	reset_button.connect("pressed", self, "reset_pressed")
	connect_btn.connect("pressed", self, "connect_pressed")
	exit_btn.connect("pressed", self, "exit_pressed")
	config_button.connect("pressed", self, "config_pressed")
	config_ok_btn.connect("pressed", self, "do_configure")
	config_cancel_btn.connect("pressed", self, "hide_config_dialog")
	disconnect_button.connect("pressed", self, "disconnect_pressed")
	disconnect_tcp_button.connect("pressed", self, "disconnect_net_pressed")

func _process(_delta):
	if connect_dialog.visible and len(uart_ports) != len(old_uart_ports):
		var sel = uart_dropdown.get_item_text(uart_dropdown.get_selected_id())
		var selIdx = -1
		uart_dropdown.clear()
		for opt in uart_ports:
			uart_dropdown.add_item(opt)
			if opt == sel:
				selIdx = uart_dropdown.get_item_count() - 1
		old_uart_ports = uart_ports
		uart_dropdown.select(selIdx)
	
	translation_label.text = translation_template % [curr_translation.x, curr_translation.y, curr_translation.z]
	rotation_label.text = rotation_template % [curr_rotation.x, curr_rotation.y, curr_rotation.z]
	pos_label.text = translation_template % [robot_pos.x, robot_pos.y, robot_pos.z]
	euler_label.text = euler_template % [robot_euler.x, robot_euler.y, robot_euler.z]
	quat_label.text = quat_template % [robot_quat.w, robot_quat.x, robot_quat.y, robot_quat.z]
	mode_label.text = mode_value
	wdg_label.text = wdg_status
	if portname == "":
		conn_label.text = "Control Board: Not Connected"
	else:
		conn_label.text = "Control Board: {0}".format([portname])
	if tcpclient == "":
		netconn_label.text = "Sim TCP: Not Connected"
	else:
		netconn_label.text = "Sim TCP: {0}".format([tcpclient])

func copy_to_clipboard():
	# TODO: Update this
	var info = "Local Translation: {0}\r\nLocal Rotation: {1}\r\nEuler Orientation: {2}\r\nQuaternion Orientation: {3}\r\nCboard Mode: {4}\r\nMotor Watchdog: {5}\r\n"
	info = info.format(
		[translation_label.text, rotation_label.text, euler_label.text, quat_label.text, mode_label.text, wdg_label.text]
	)
	OS.set_clipboard(info)

func reset_pressed():
	self.emit_signal("sim_reset")

func config_pressed():
	self.emit_signal("sim_config")

func show_connect_dialog():
	if not self.connect_dialog.visible:
		connect_err.text = ""
		self.connect_dialog.popup()

func hide_connect_dialog():
	self.connect_dialog.hide()

func show_config_dialog(x, y, z, p, r, h):
	if not config_dialog.visible:
		config_xbox.value = x
		config_ybox.value = y
		config_zbox.value = z
		config_pbox.value = p
		config_rbox.value = r
		config_hbox.value = h
		config_dialog.popup()

func do_configure():
	var x = config_xbox.value
	var y = config_ybox.value
	var z = config_zbox.value
	var p = config_pbox.value
	var r = config_rbox.value
	var h = config_hbox.value
	config_dialog.hide()
	emit_signal("do_configure_vehicle", x, y, z, p, r, h)

func hide_config_dialog():
	config_dialog.hide()

func set_connect_error(err: String):
	connect_err.text = err

func connect_pressed():
	if uart_dropdown.get_selected_id() == -1:
		return
	var port = uart_dropdown.get_item_text(uart_dropdown.get_selected_id())
	self.emit_signal("cboard_connect", port)

func disconnect_pressed():
	self.emit_signal("cboard_disconnect")

func disconnect_net_pressed():
	self.emit_signal("net_disconnect")

func exit_pressed():
	get_tree().quit()

func set_robot():
	pass
