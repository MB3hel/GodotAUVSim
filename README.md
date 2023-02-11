# GodotAUVSim

Simulator used for testing math for [AUVControlBoard](https://github.com/MB3hel/AUVControlBoard). Simulator implements a minimal control board compatible API using same comm spec, but over TCP instead of UART.

Simulator is run through [Godot Engine](https://godotengine.org/)


Note that simulator translation speeds are in "world distance units" and rotation speeds are in "degrees per second".


## TCP Communication & Control

Two TCP ports are used. A connection to both ports must be made by the same client to use the simulator.

### Command port

The command port is used to control the simulation itself. This is port `5011`. The command port uses a string-based command interface in the following format.

```
command_name [arg_1] [arg_2] [arg_3] ...
```

Commands are newline delimited. Note that arguments are **not** placed within brackets.

Each command will receive a response in the following format

```
[EC] [arg_1] [arg_2] [arg_3] ...
```

Response are also newline (ASCII 10) delimited. EC is an error code (0 = no error, 1 = invalid arguments, 2 = unknown command). Responses are sent in the same order commands are sent in, thus it is possible to send multiple commands before handling / waiting for responses.

***NOTE: The command parser is very simple. It will not properly handle extra whitespace including carriage return characters, tab characters, or multiple spaces.***

The following commands are implemented


- Set robot position in simulator: `set_pos x y z -> EC`
- Get robot position in simulator: `get_pos -> EC [x y z]`
- Set robot rotation in simulator: `set_rot w x y z -> EC`
- Get robot rotation in simulator: `get_rot -> EC [w x y z]`
- Set robot max translation speed: `set_max_trans m -> EC`
- Get robot max translation speed: `get_max_trans -> EC [m]`
- Set robot max rotation speed: `set_max_rot m -> EC`
- Get robot max rotation speed: `get_max_rot -> EC [m]`
- Reset simulator: `reset_sim -> EC`


*Note that get commands may not return with arguments if the error code is non-zero*.

### Control Board port

This port is used to send / receive the same data that would normally be sent over UART between control board and PC. It uses the same data format and messages (just over TCP not UART).

Note that not all commands are implemented by the simulator. Commands that are not implemented will be acknowledged with the error code `ACK_ERR_UNKNOWN_MSG` or the error code `ACK_ERR_INVALID_CMD`.

The following commands / queries are currently supported:

- LOCAL mode speed set
- GLOBAL mode speed set
- Motor Watchdog Feed
- Read BNO055 once
- Read MS5837 once
- Read BNO055 periodic
- Read MS5837 periodic

The following status messages are implemented:

- Motor Watchdog Status
- BNO055 data (note that accumulated euler angles are not implemented yet)
- MS5837 data

The following are not (and will never be) implemented. The simulator does not work at a thruster level.

- RAW mode speed set
- Thruster inversion set
- Motor matrix set
- Motor matrix update
- BNO055 axis configure (sensor axes always match robot axes in simulation)
- Reset command (use reset_sim command to reset simulator including control board state)
