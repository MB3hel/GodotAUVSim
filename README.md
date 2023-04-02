# GodotAUVSim

Simulator used for testing math for [AUVControlBoard](https://github.com/MB3hel/AUVControlBoard). Simulator implements a minimal control board compatible API using same comm spec, but over TCP instead of UART.

Simulator is run through [Godot Engine](https://godotengine.org/)


Note that simulator translation speeds are in units/sec and rotation speeds are in degrees per second. Note that "units/sec" refers to one unit of distance on the game engine's world axes.


## TCP Communication & Control

Two TCP ports are used. A connection to both ports must be made by the same client to use the simulator.

*Note: currently, the simulator only accepts connections from the same device (`127.0.0.1`).*

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

*NOTE: The command parser is very simple. It will not properly handle extra whitespace including carriage return characters, tab characters, or multiple spaces.*

The following commands are implemented


- Set robot position in simulator: `set_pos x y z -> EC`
- Get robot position in simulator: `get_pos -> EC [x y z]`
- Set robot rotation in simulator: `set_rot w x y z -> EC`
- Get robot rotation in simulator: `get_rot -> EC [w x y z]`
- Reset simulator: `reset_sim -> EC`


*Note that get commands may not return with all arguments if the error code is non-zero*.

### Control Board port

This port is used to send / receive the same data that would normally be sent over UART between control board and PC. It uses the same data format and messages (just over TCP not UART). This is port `5012`.

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


## Development

The simulator was built using v3.5.1 of Godot. There is a single scene (`pool.tscn`) using the default world environment (`default_env.tres`) as configured. Currently, no environment for the robot to operate in is configured. The simulator currently includes a simplified model of SeaWolf 8 (a robot designed and built by AquaPack Robotics at NC State University).

Important to note is that Godot's world system differs from the coordinate system defined by the control board. Both use a right hand coordinate system, however Godot uses a "y up" convention and the control board uses a "z up" convention. The robot and cameras are setup for a control board system. This doesn't really impact much in the engine, however it is best to be explicit about directions (ie don't use named directions in the engine, always explicitly specify x, y, and z components).

Additionally, Godot uses a different euler angle convention that the control board. When assigning or using euler rotations from game engine objects, Godot's convention must be used. When specifying orientations for the control board, the control board convention must be used. There is a helper class `Angles` implemented to perform conversions between these euler angle conventions and quaternions. Note that this class requires euler angles in radians, not degrees.

Script Files:

- `angles.gd`: Angle conversion helper. Converts from either euler convention to/from quaternions or to/from each other.
- `cboard.gd`: Control board simulator. Implements message handling in the same way the control board itself does.
- `devmode.gd`: Development script. Set the `devmode` variable to true to hijack the simulator (only works when running through the editor, not when exported). This will disable the tcp interface to the simulator. This is intended to allow hard-coded math / development testing to occur using this script's ready and process functions.
- `matrix.gd`: Port of my C matrix math library from the AUVControlBoard firmware to godot. Used by `cboard.gd` to implement math the same way it is implemented on the control board. Note that while this is not strictly necessary (Godot does technically include implementations of most / all operations required), this makes the code more readable from a math context and more similar to the actual firmware (makes porting changes easier).
- `robot.gd`: Script attached to the robot object itself. Handles motion at a local level.
- `simulation.gd`: Simulation manager / "entry level" script. Manges UI values, the robot, and the control board instance. Also manages the tcp servers and communication.
- `ui.gd`: Handles the on-screen UI.
