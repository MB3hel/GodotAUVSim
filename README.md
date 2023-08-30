# GodotAUVSim

Simulator used for testing [AUVControlBoard](https://github.com/MB3hel/AUVControlBoard) designed using [Godot Engine](https://godotengine.org/).

The simulator can either use a physical control board (allows testing proper firmware and is considered more correct), or a simulated control board can be used (experimental!).


## Launching the Simulator

Download the release for your OS and

- For windows: run the exe file
- For macOS: run the .app file (right click and choose open since the app is not signed)
- For Linux: run the `.x86_64` file.

The following command line arguments are supported (can be useful to automate some testing using the simulator)

- `--simcb`: connect to the simulated control board on startup. This will cause the simulator to connect to the simulated control board after launching. Thus, no user interaction with the connect dialog will be required before use.
- `--uart port`: connect to the control board on the given uart port on startup. Note that this works like the simcb argument. If connection fails, there will be no error code or any indication of failure to connect to the control board. The connect dialog will simply be shown as usual.

## Simulator Interface

The simulated is interfaced with over two TCP ports. One port is used to send commands to the simulator itself (the "command port") and one is used to communicate with the control board (physical or simulated) via the simulator (the "control board port").

**Note: When using the simulator (even with a physical control board) you must communicate with the simulator, NOT directly with the control board.**


### Command Port

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


- Set vehicle position in simulator: `set_pos x y z -> EC`
- Get vehicle position in simulator: `get_pos -> EC [x y z]`
- Set vehicle rotation in simulator: `set_rot w x y z -> EC`
- Get vehicle rotation in simulator: `get_rot -> EC [w x y z]`
- Reset vehicle: `reset_vehicle -> EC`
- Set current vehicle model: `set_vehicle vehicle_id -> EC`
- Get current vehicle model: `get_vehicle -> EC [vehicle_id]`


*Note that get commands may not return with all arguments if the error code is non-zero*.


### Control Board Port

Instead of communicating directly with a control board, you must communicate with the simulator via TCP on port `5012`. This port will forward messages to / from the actual control board (or simulated control board).

The messages sent to this port should be constructed exactly the same as if they were sent to an actual control board over UART. Just send over TCP instead of UART when using the simulator.



## Modeling Vehicles

TODO: About SW8 model

TODO: Modeling a different vehicle


## Development

The simulator was built using v3.5.2 of Godot. There is a single scene (`pool.tscn`) using the default world environment (`default_env.tres`) as configured. Currently, no environment for the vehicle to operate in is configured. The simulator currently includes a simplified model of SeaWolf 8 (a robot designed and built by AquaPack Robotics at NC State University).

Important to note is that Godot's world system differs from the coordinate system defined by the control board. Both use a right hand coordinate system, however Godot uses a "y up" convention and the control board uses a "z up" convention. The robot and cameras are setup for a control board system. This doesn't really impact much in the engine, however it is best to be explicit about directions (ie don't use named directions in the engine, always explicitly specify x, y, and z components).

Additionally, Godot uses a different euler angle convention that the control board. When assigning or using euler rotations from game engine objects, Godot's convention must be used. When specifying orientations for the control board, the control board convention must be used. There is a helper class `Angles` implemented to perform conversions between these euler angle conventions and quaternions. Note that this class requires euler angles in radians, not degrees.

Script Files:

- `angles.gd`: Angle conversion helper. Converts from either euler convention to/from quaternions or to/from each other.
- `cboard.gd`: Interface to either a physical control board (via uart) or to the simulated control board. Abstracts the difference between sim and real control board. Also handles simulator-side cboard communication.
- `matrix.gd`: GDScript port of the matrix.c library used in the control board firmware
- `netiface.gd`: Handle simulator networking and external interface (TCP)
- `pid.gd`: PID controller implementation (similar to what is used in control board firmware)
- `simcb.gd`: Simulated control board implementation. Acts like an actual control board would. Used via the cboard layer just as a physical control board would be.
- `simulation.gd`: Simulation manager / "entry level" script. Consider this the "entry point" of the simulator. Also handles UI.
- `vehicle.gd`: Script attached to the robot object itself. Handles modeling of thruster forces


## Releasing a New Version

- Take previous release archives from releases page
- Export a pck file with Godot
- Replace the old pck files
- In the macos app, the pck file is in GodotAUVSim.app/Contents/Resources/