extends Spatial
class_name Simulator


var port_refresh_timer = Timer.new()

# Resousrces used during simulation
onready var robot = get_node("Robot")
onready var ui = get_node("UIRoot")
onready var cboard = get_node("ControlBoard")


# Store default parameters
onready var def_robot_rotation = robot.rotation
onready var def_robot_translation = robot.translation
onready var def_robot_weight = robot.weight
onready var def_robot_mass = robot.mass
onready var def_robot_linear_damp = robot.linear_damp
onready var def_robot_angular_damp = robot.angular_damp
onready var def_robot_max_force = robot.max_force
onready var def_robot_max_torque = robot.max_torque


func _ready():
	self.ui.connect("sim_reset", self, "reset_sim")
	self.ui.connect("cboard_connect", self, "do_cboard_connect")
	self.ui.connect("cboard_disconnect", cboard, "disconnect_uart")
	
	self.cboard.connect("disconnected_uart", self, "cboard_disconnected")
	
	add_child(port_refresh_timer)
	port_refresh_timer.connect("timeout", self, "refresh_ports")
	port_refresh_timer.start(1)
	
	cboard_disconnected()


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
	ui.mode_value = "???"
	ui.wdg_status = "???"
	ui.portname = cboard.portname


func reset_sim():
	# Set force and torque (local mode targets) to zero
	robot.curr_force = Vector3(0, 0, 0)
	robot.curr_torque = Vector3(0, 0, 0)
	
	# Stop motion fully now
	robot.linear_velocity = Vector3(0, 0, 0)
	robot.angular_velocity = Vector3(0, 0, 0)
	
	# Set position and rotation
	robot.set_trans(def_robot_translation)
	robot.set_rot(def_robot_rotation)
	
	# Set motion / physics parameters
	robot.max_force = def_robot_max_force
	robot.max_torque = def_robot_max_torque
	robot.weight = def_robot_weight
	robot.mass = def_robot_mass
	robot.linear_damp = def_robot_linear_damp
	robot.angular_damp = def_robot_angular_damp


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
		robot.curr_torque = Vector3(0, 0, 0.5)
	else:
		ui.set_connect_error(err)


func cboard_disconnected():
	robot.curr_force = Vector3(0, 0, 0)
	robot.curr_torque = Vector3(0, 0, 0)
	ui.show_connect_dialog()
