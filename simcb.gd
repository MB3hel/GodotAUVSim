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
#   - Does not allow testing of math under "real conditions. Meaning single
#     precision floating point math andcorrect timings.
#   - Does not allow testing of firmware bugs. Ex: issues in firmware math 
#     libraries, firmware crashes, firmware deadlocks
#   - Does not handle some commands that configure a physical system. Ex:
#     thruster inversion, IMU axis config, motor matrix commands, 
#     RAW mode speed set.
################################################################################

extends Node

# TODO: Implement this and add support in cboard.gd
