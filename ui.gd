extends Control

# Data to be displayed in UI
var curr_translation = Vector3(0.0, 0.0, 0.0)
var curr_rotation = Vector3(0.0, 0.0, 0.0)
var robot_euler = Vector3(0.0, 0.0, 0.0)
var robot_quat = Quat(0.0, 0.0, 0.0, 1.0)
var robot_pos = Vector3(0.0, 0.0, 0.0)
var mode_value = "LOCAL"
var wdg_status = "Killed"
var connected = false


# UI elements
onready var translation_label = find_node("TranslationValue")
onready var rotation_label = find_node("RotationValue")
onready var pos_label = find_node("PosValue")
onready var euler_label = find_node("EulerValue")
onready var quat_label = find_node("QuatValue")
onready var mode_label = find_node("ModeValue")
onready var wdg_label = find_node("MotorWDGValue")
onready var copy_button = find_node("CopyButton")
onready var reset_button = find_node("ResetButton")


const translation_template = "(x=%+.2f, y=%+.2f, z=%+.2f)"
const rotation_template = "(p=%+.2f, r=%+.2f, y=%+.2f)"
const euler_template = "(p=%+.2f, r=%+.2f, y=%+.2f)"
const quat_template = "(w=%+.4f, x=%+.4f, y=%+.4f, z=%+.4f)"


signal sim_reset


func _ready():
	copy_button.connect("pressed", self, "copy_to_clipboard")
	reset_button.connect("pressed", self, "reset_pressed")

func _process(_delta):
	translation_label.text = translation_template % [curr_translation.x, curr_translation.y, curr_translation.z]
	rotation_label.text = rotation_template % [curr_rotation.x, curr_rotation.y, curr_rotation.z]
	pos_label.text = translation_template % [robot_pos.x, robot_pos.y, robot_pos.z]
	euler_label.text = euler_template % [robot_euler.x, robot_euler.y, robot_euler.z]
	quat_label.text = quat_template % [robot_quat.w, robot_quat.x, robot_quat.y, robot_quat.z]
	mode_label.text = mode_value
	wdg_label.text = wdg_status

func copy_to_clipboard():
	var info = "Local Translation: {0}\r\nLocal Rotation: {1}\r\nEuler Orientation: {2}\r\nQuaternion Orientation: {3}\r\nCboard Mode: {4}\r\nMotor Watchdog: {5}\r\n"
	info = info.format(
		[translation_label.text, rotation_label.text, euler_label.text, quat_label.text, mode_label.text, wdg_label.text]
	)
	OS.set_clipboard(info)

func reset_pressed():
	self.emit_signal("sim_reset")
