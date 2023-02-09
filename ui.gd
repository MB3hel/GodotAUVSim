extends Control

# Data to be displayed in UI
var curr_translation = Vector3(0.0, 0.0, 0.0)
var curr_rotation = Vector3(0.0, 0.0, 0.0)
var robot_euler = Vector3(0.0, 0.0, 0.0)
var robot_quat = Quat(0.0, 0.0, 0.0, 1.0)

# UI elements
onready var translation_label = get_node("VBoxContainer/HBoxContainer/StatusPanel/TranslationValue")
onready var rotation_label = get_node("VBoxContainer/HBoxContainer/StatusPanel/RotationValue")
onready var euler_label = get_node("VBoxContainer/HBoxContainer/StatusPanel/EulerValue")
onready var quat_label = get_node("VBoxContainer/HBoxContainer/StatusPanel/QuatValue")


const translation_template = "(x={0}, y={1}, z={2})"
const rotation_template = "(p={0}, r={1}, y={2})"
const euler_template = "(p={0}, r={1}, y={2})"
const quat_template = "(w={0}, x={1}, y={2}, z={3})"


func _ready():
	pass

func _process(_delta):
	translation_label.text = translation_template.format(
		[curr_translation.x, curr_translation.y, curr_translation.z]
	)
	rotation_label.text = rotation_template.format(
		[curr_rotation.x, curr_rotation.y, curr_rotation.z]
	)
	euler_label.text = euler_template.format(
		[robot_euler.x, robot_euler.y, robot_euler.z]
	)
	quat_label.text = quat_template.format(
		[robot_quat.w, robot_quat.x, robot_quat.y, robot_quat.z]
	)
