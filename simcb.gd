################################################################################
# file: simcb.gd
# author: Marcus Behel
################################################################################
# Simulated control board
# Implements the same math and command processing as a real control board would
# but does it using Godot itself.
# This allows some testing without a real control board
#   - Test or validate math implementation or changes
#   - Test the logic of code using control board (motion)
#   - Test code to communicate with the control board (messages and format)
# However there are some limitations (which is why using a real control board 
# is supported at all)
#   - Does not allow testing of math under "real" conditions. Mostly related to
#     timing and CPU load conditions.
#   - Does not allow testing of firmware bugs. Ex: issues in firmware math 
#     libraries, firmware crashes, firmware deadlocks
#
# Note that this implementation is not the most efficient dataflow. The simcb
# is meant to be a "drop in" replacement for a real control board.
# As such, messages are formatted here before they are given to the cboard
# layer. This means the cboard layer technically performs some unnecessary
# parsing. Likewise, the netiface parses a message, the it is written raw
# to simcb only to be parsed again. This is not the most efficient method of
# doing things, however it ensures that cboard is almost identical for a real
# control board or with simcb. It also means that no simcb logic or data
# data handling need to be in cboard. This makes the simulator more maintainable
# and shouldn't impact simulator performance too much.
#
# Note that simcb ONLY operates in SIMHIJACK mode
# However, it will still acknowledge SIMHIJACK commands.
# It will always be sending SIMSTAT commands and always process SIMDAT
# commands as a control board in SIMHIJACK mode would.
#
# Note that most functions in this class closely match the names of functions
# used in the actual control board firmware. This should allow quicly porting
# changes between control board firmware and simcb
################################################################################

extends Node

################################################################################
# Globals
################################################################################

# Data to be written out from simcb
var _write_buf = PoolByteArray()

# Data waiting to be read by simcb
var _read_buf = PoolByteArray()

################################################################################



################################################################################
# Godot Engine functions
################################################################################

func _ready():
	# TODO: cmdctrl_send_sensor_data timer
	var periodic_speed_timer = Timer.new()
	add_child(periodic_speed_timer)
	periodic_speed_timer.one_shot = false
	periodic_speed_timer.connect("timeout", self, "cmdctrl_periodic_reapply_speed")
	periodic_speed_timer.start(0.020)

func _process(delta):
	self.pccomm_read_and_parse()

################################################################################



################################################################################
# EXTERNAL Communication (called by cboard)
################################################################################

# EXTERNAL write
# write data TO simcb
# this data will later be read by simcb
func ext_write(data: PoolByteArray):
	_read_buf.append_array(data)

# EXTERNAL read
# read data FROM simcb
# this data must first be written by simcb
func ext_read() -> PoolByteArray:
	var res = _write_buf
	_write_buf = PoolByteArray()
	return res

################################################################################



################################################################################
# Sim pccomm
################################################################################

# Construct a properly formatted message and write it from simcb
# This is equivalent to writing from control board to PC
func pccomm_write(msg: PoolByteArray):
	pass

# Read messages sent to simcb
# This is equivalent of reading messages from PC on control board
func pccomm_read_and_parse():
	pass

################################################################################



################################################################################
# Sim cmdctrl
################################################################################

const CMDCTRL_MODE_RAW = 0
const CMDCTRL_MODE_LOCAL = 1
const CMDCTRL_MODE_GLOBAL = 2
const CMDCTRL_MODE_SASSIST = 3
const CMDCTRL_MODE_DHOLD = 4

# State tracking similar to cmdctrl in firmware
var cmdctrl_mode = CMDCTRL_MODE_RAW

# Last used raw mode target
var cmdctrl_raw_target = PoolRealArray([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

# Last used local mode target
var cmdctrl_local_x = 0.0
var cmdctrl_local_y = 0.0
var cmdctrl_local_z = 0.0
var cmdctrl_local_xrot = 0.0
var cmdctrl_local_yrot = 0.0
var cmdctrl_local_zrot = 0.0

# Last used global mode target
var cmdctrl_global_x = 0.0
var cmdctrl_global_y = 0.0
var cmdctrl_global_z = 0.0
var cmdctrl_global_pitch_spd = 0.0
var cmdctrl_global_roll_spd = 0.0
var cmdctrl_global_yaw_spd = 0.0

# Last used sassist mode target
var cmdctrl_sassist_valid = false
var cmdctrl_sassist_variant = 1
var cmdctrl_sassist_x = 0.0
var cmdctrl_sassist_y = 0.0
var cmdctrl_sassist_yaw_spd = 0.0
var cmdctrl_sassist_target_euler = Vector3(0.0, 0.0, 0.0)
var cmdctrl_sassist_depth_target = 0.0

# Last used depth hold target
var cmdctrl_dhold_x = 0.0
var cmdctrl_dhold_y = 0.0
var cmdctrl_dhold_pitch_spd = 0.0
var cmdctrl_dhold_roll_spd = 0.0
var cmdctrl_dhold_yaw_spd = 0.0
var cmdctrl_dhold_depth = 0.0


# Store received from SIMDAT
# NOTE: simcb is always in SIMHIJACK, thus no need to track sensor states or full sets of data
#       only the data from SIMDAT will ever be used
#       Thus these are equivalents of sim_quat and sim_depth in the actual firmware
var cmdctrl_curr_quat = Quat()
var cmdctrl_curr_depth = 0.0

func cmdctrl_send_sensor_data():
	pass

func cmdctrl_periodic_reapply_speed():
	if cmdctrl_mode == CMDCTRL_MODE_GLOBAL or cmdctrl_mode == CMDCTRL_MODE_SASSIST or cmdctrl_mode == CMDCTRL_MODE_DHOLD:
		cmdctrl_apply_saved_speed()

func cmdctrl_apply_saved_speed():
	if cmdctrl_mode == CMDCTRL_MODE_RAW:
		mc_set_raw(cmdctrl_raw_target)
	elif cmdctrl_mode == CMDCTRL_MODE_LOCAL:
		mc_set_local(cmdctrl_local_x, cmdctrl_local_y, cmdctrl_local_z, cmdctrl_local_xrot, cmdctrl_local_yrot, cmdctrl_local_zrot)
	elif cmdctrl_mode == CMDCTRL_MODE_GLOBAL:
		mc_set_global(cmdctrl_global_x, cmdctrl_global_y, cmdctrl_global_z, cmdctrl_global_pitch_spd, cmdctrl_global_roll_spd, cmdctrl_global_yaw_spd, cmdctrl_curr_quat)
	elif cmdctrl_mode == CMDCTRL_MODE_SASSIST:
		if cmdctrl_sassist_valid and cmdctrl_sassist_variant == 1:
			mc_set_sassist(cmdctrl_sassist_x, cmdctrl_sassist_y, cmdctrl_sassist_yaw_spd, cmdctrl_sassist_target_euler, cmdctrl_sassist_depth_target, cmdctrl_curr_quat, cmdctrl_curr_depth, false)
		elif cmdctrl_sassist_valid and cmdctrl_sassist_variant == 2:
			mc_set_sassist(cmdctrl_sassist_x, cmdctrl_sassist_y, 0.0, cmdctrl_sassist_target_euler, cmdctrl_sassist_depth_target, cmdctrl_curr_quat, cmdctrl_curr_depth, true)
	elif cmdctrl_mode == CMDCTRL_MODE_DHOLD:
		mc_set_dhold(cmdctrl_dhold_x, cmdctrl_dhold_y, cmdctrl_dhold_pitch_spd, cmdctrl_dhold_roll_spd, cmdctrl_dhold_yaw_spd, cmdctrl_dhold_depth, cmdctrl_curr_quat, cmdctrl_curr_depth)

func cmdctrl_acknowledge(msg_id: int, error_code: int, result: PoolByteArray):
	pass

func cmdctrl_handle_message(msg: PoolByteArray):
	# TODO: When processing simhijack command make sure to reset things properly
	pass

func cmdctrl_mwdog_change(motors_enabled: bool):
	pass

func cmdctrl_send_simstat():
	pass

################################################################################


################################################################################
# Sim motor_control
################################################################################

var sim_speeds = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# TODO: MC_RELSCALE, invert, all the matrices and math support stuff
# TODO: PID controllers

func mc_set_dof_matrix(tnum: int, row_data: PoolRealArray):
	pass

func mc_recalc():
	pass

# TODO: Motor watchdog logic (either using timer or process function)

# TODO: Implement math helper code (as needed using Godot quaternion library)

# TODO: mc_downscale_reldof, mc_upscale_vec, mc_downscale_if_needed, mc_grav_rot, mc_baseline_euler, mc_euler_to_split_quat

# TODO: PID controller tune

func mc_set_raw(speeds: PoolRealArray):
	pass

func mc_set_local(x: float, y: float, z: float, xrot: float, yrot: float, zrot: float):
	pass

func mc_set_global(x: float, y: float, z: float, pitch_spd: float, roll_spd: float, yaw_spd: float, curr_quat: Quat):
	pass

func mc_set_sassist(x: float, y: float, yaw_spd: float, target_euler: Vector3, target_depth: float, curr_quat: Quat, curr_depth: float, yaw_target: bool):
	pass

func mc_set_dhold(x: float, y: float, pitch_spd: float, roll_spd: float, yaw_spd: float, target_depth: float, curr_quat: Quat, curr_depth: float):
	pass

################################################################################
