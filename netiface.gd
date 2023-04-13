################################################################################
# file: netiface.gd
# author: Marcus Behel
################################################################################
# Network interface to the simulator
# The simulator runs two TCP servers
#   - Port 5011: Command Server
#   - Port 5012: Control Board Server
#
# The control board server forwards messages it receives to the control board 
# the simulator is using. Messages received from the simulator-managed control 
# board will be send to the client on the control board server.
# The intent is that a program written for a control board can instead connect
# to the simulator over TCP and send the same data over TCP that would have
# been sent to a control board via UART.
#
# The command port is a way to also control the simulator itself via TCP. This
# allows scripts to be written that define initial conditions for simulation.
# This allows for unit testing via simulation.
################################################################################

extends Node


# TODO: Implement
