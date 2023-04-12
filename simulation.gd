extends Spatial
class_name Simulator


var port_refresh_timer = Timer.new()

# Resousrces used during simulation
onready var robot = get_node("Robot")
onready var ui = get_node("UIRoot")
onready var cboard = get_node("ControlBoard")
onready var netiface = get_node("NetIface")


# Store default parameters
onready var def_robot_rotation = robot.rotation
onready var def_robot_translation = robot.translation


func _ready():
	self.ui.connect("sim_reset", self, "reset_vehicle")
	self.ui.connect("cboard_connect", self, "do_cboard_connect")
	self.ui.connect("cboard_disconnect", cboard, "disconnect_uart")
	self.ui.connect("net_disconnect", netiface, "do_disconnect")
	self.ui.connect("sim_config", self, "config_vehicle")
	
	self.cboard.connect("disconnected_uart", self, "cboard_disconnected")
	self.cboard.connect("msg_received", netiface, "write_raw")
	
	self.netiface.connect("msg_received", cboard, "write_raw")
	self.netiface.connect("reset_vehicle", self, "reset_vehicle")
	
	add_child(port_refresh_timer)
	port_refresh_timer.connect("timeout", self, "refresh_ports")
	port_refresh_timer.start(1)
	
	cboard_disconnected()
	refresh_ports()


# Called every frame
# delta is time between last call and now in seconds
# This function is called as fast as possible!
func _process(_delta):
	update_ui()


func update_ui():
	# Update data to be displayed in UI
	ui.curr_translation = robot.curr_force
	ui.curr_rotation = robot.curr_torque
	ui.robot_pos = robot.translation
	ui.robot_quat = Quat(robot.rotation)
	ui.robot_euler = Angles.quat_to_cboard_euler(ui.robot_quat) / PI * 180.0
	ui.mode_value = cboard.mode
	ui.wdg_status = "Killed" if cboard.watchdog_killed else "Not Killed"
	ui.portname = cboard.portname
	ui.tcpclient = netiface.tcpclient


func reset_vehicle():
	# Set force and torque (local mode targets) to zero
	robot.curr_force = Vector3(0, 0, 0)
	robot.curr_torque = Vector3(0, 0, 0)
	
	# Stop motion fully now
	robot.linear_velocity = Vector3(0, 0, 0)
	robot.angular_velocity = Vector3(0, 0, 0)
	
	# Set position and rotation
	robot.set_trans(def_robot_translation)
	robot.set_rot(def_robot_rotation)

func config_vehicle():
	var curr_rot = Angles.godot_euler_to_cboard_euler(robot.rotation)
	var curr_pos = robot.translation
	ui.show_config_dialog(curr_pos.x, curr_pos.y, curr_pos.z, curr_rot.x, curr_rot.y, curr_rot.z)


func refresh_ports():
	if not cboard.connected:
		var allports = cboard.ser.list_ports()
		var subports = []
		for p in allports:
			# Omit /dev/ttyS devices on Linux. There are a lot of these...
			# Control board will be ACM device anyways
			if p.begins_with("/dev/ttyS"):
				continue
			
			# Skip LPT devices on windows. Control board will be COM port
			if p.begins_with("LPT"):
				continue
			
			subports.append(p)
		ui.uart_ports = subports


func do_cboard_connect(port):
	var err = cboard.connect_uart(port)
	if cboard.connected:
		ui.hide_connect_dialog()
		netiface.accepts_connections = true
	else:
		ui.set_connect_error(err)


func cboard_disconnected():
	netiface.accepts_connections = false
	robot.curr_force = Vector3(0, 0, 0)
	robot.curr_torque = Vector3(0, 0, 0)
	ui.show_connect_dialog()
