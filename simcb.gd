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
# doing things, however it ensures that cboard is almost identacal for a real
# control board or with simcb. It also means that no simcb logic or data
# data handling need to be in cboard. This makes the simulator more maintainable
# and shouldn't impact simulator performance too much.
#
# Note that simcb ONLY operates in SIMHIJACK mode
# However, it will still acknowledge SIMHIJACK commands.
# It will always be sending SIMSTAT commands and always process SIMDAT
# commands as a control board in SIMHIJACK mode would.
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
	pass

func _process(delta):
	pass

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

# TODO

################################################################################



################################################################################
# Sim cmdctrl
################################################################################

# NOTE: Needs curr_bno055 and curr_ms5837 variables here too
#       not simulating real sensors, so just track the SIMDAT values
# TODO

################################################################################



