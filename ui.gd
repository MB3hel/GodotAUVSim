extends Control

# Data to be displayed in UI
var curr_translation = Vector3(0.0, 0.0, 0.0)
var curr_rotation = Vector3(0.0, 0.0, 0.0)
var robot_euler = Vector3(0.0, 0.0, 0.0)
var robot_quat = Quat(0.0, 0.0, 0.0, 1.0)

# UI elements
onready var translation_label = get_node("VBoxContainer/HBoxContainer/VBoxContainer/StatusPanel/TranslationValue")
onready var rotation_label = get_node("VBoxContainer/HBoxContainer/VBoxContainer/StatusPanel/RotationValue")
onready var euler_label = get_node("VBoxContainer/HBoxContainer/VBoxContainer/StatusPanel/EulerValue")
onready var quat_label = get_node("VBoxContainer/HBoxContainer/VBoxContainer/StatusPanel/QuatValue")
onready var copy_button = get_node("VBoxContainer/HBoxContainer/VBoxContainer/CopyButton")


const translation_template = "(x=%+.2f, y=%+.2f, z=%+.2f)"
const rotation_template = "(p=%+.2f, r=%+.2f, y=%+.2f)"
const euler_template = "(p=%+.2f, r=%+.2f, y=%+.2f)"
const quat_template = "(w=%+.4f, x=%+.4f, y=%+.4f z=%+.4f)"


func _ready():
	copy_button.connect("pressed", self, "copy_to_clipboard")

func _process(_delta):
	translation_label.text = translation_template % [curr_translation.x, curr_translation.y, curr_translation.z]
	rotation_label.text = rotation_template % [curr_rotation.x, curr_rotation.y, curr_rotation.z]
	euler_label.text = euler_template % [robot_euler.x, robot_euler.y, robot_euler.z]
	quat_label.text = quat_template % [robot_quat.w, robot_quat.x, robot_quat.y, robot_quat.z]

func copy_to_clipboard():
	var info = "Local Translation: {0}\r\nLocal Rotation: {1}\r\nEuler Orientation: {2}\r\nQuaternion Orientation: {3}\r\n"
	info = info.format(
		[translation_label.text, rotation_label.text, euler_label.text, quat_label.text]
	)
	OS.set_clipboard(info)
