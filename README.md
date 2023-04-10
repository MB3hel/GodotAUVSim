# GodotAUVSim

Simulator used for testing [AUVControlBoard](https://github.com/MB3hel/AUVControlBoard) designed using [Godot Engine](https://godotengine.org/).

The simulator implements motion at a LOCAL mode level (not RAW mode) and relies on a real control board to actually perform any movement.


## TCP Commands

The command port is used to control the simulation. This is port `5011`. The command port uses a string-based command interface in the following format.

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

## Development

The simulator was built using v3.5.1 of Godot. There is a single scene (`pool.tscn`) using the default world environment (`default_env.tres`) as configured. Currently, no environment for the robot to operate in is configured. The simulator currently includes a simplified model of SeaWolf 8 (a robot designed and built by AquaPack Robotics at NC State University).

Important to note is that Godot's world system differs from the coordinate system defined by the control board. Both use a right hand coordinate system, however Godot uses a "y up" convention and the control board uses a "z up" convention. The robot and cameras are setup for a control board system. This doesn't really impact much in the engine, however it is best to be explicit about directions (ie don't use named directions in the engine, always explicitly specify x, y, and z components).

Additionally, Godot uses a different euler angle convention that the control board. When assigning or using euler rotations from game engine objects, Godot's convention must be used. When specifying orientations for the control board, the control board convention must be used. There is a helper class `Angles` implemented to perform conversions between these euler angle conventions and quaternions. Note that this class requires euler angles in radians, not degrees.

Script Files:

- `angles.gd`: Angle conversion helper. Converts from either euler convention to/from quaternions or to/from each other.
- `robot.gd`: Script attached to the robot object itself. Handles motion at a local level.
- `simulation.gd`: Simulation manager / "entry level" script. Manges TCP communication and primary data flow. Consider this the "entry point" of the simulator.
- `ui.gd`: Handles the on-screen UI.
