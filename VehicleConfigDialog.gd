extends PopupDialog

signal applied(x, y, z, p, r, h)

onready var xBox = find_node("xBox")
onready var yBox = find_node("yBox")
onready var zBox = find_node("zBox")
onready var pBox = find_node("pBox")
onready var rBox = find_node("rBox")
onready var hBox = find_node("hBox")
onready var btn_ok = find_node("OkButton")
onready var btn_cancel = find_node("CancelButton")

func _ready():
	btn_cancel.connect("pressed", self, "hide_dialog")
	btn_ok.connect("pressed", self, "do_apply")	


func show_dialog(x, y, z, p, r, h):
	xBox.value = x
	yBox.value = y
	zBox.value = z
	pBox.value = p
	rBox.value = r
	hBox.value = h
	self.popup()

func hide_dialog():
	self.hide()

func do_apply():
	var x = xBox.value
	var y = yBox.value
	var z = zBox.value
	var p = pBox.value
	var r = rBox.value
	var h = hBox.value
	self.hide_dialog()
	self.emit_signal("applied", x, y, z, p, r, h)
