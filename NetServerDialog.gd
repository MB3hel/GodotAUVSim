extends PopupDialog

# Emitted when user clicks "Start" button
signal start_servers(cmd_port, cb_port)

# UI elements
onready var lbl_error = find_node("ErrorLabel")
onready var field_cb_port = find_node("CBPortBox")
onready var field_cmd_port = find_node("CMDPortBox")
onready var btn_start = find_node("StartButton")
onready var btn_exit = find_node("ExitButton")


func _ready():	
	self.btn_start.connect("pressed", self, "do_start")
	self.btn_exit.connect("pressed", self, "do_exit")

func do_start():
	self.btn_start.disabled = true
	var cmd = self.field_cmd_port.value
	var cb = self.field_cb_port.value
	self.emit_signal("start_servers", cmd, cb)

func do_exit():
	get_tree().quit()

func show_dialog():
	self.btn_start.disabled = false
	lbl_error.text = ""
	self.popup()

func hide_dialog():
	self.hide()

func show_error(msg: String):
	self.btn_start.disabled = false
	lbl_error.text = msg
