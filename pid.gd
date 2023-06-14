class_name PIDController

# Gains
var kP = 0.0
var kI = 0.0
var kD = 0.0

# Output limits
var omin = 0.0
var omax = 0.0

# True to negate output
var invert = false

# State info (zero to reset)
var integral = 0.0
var last_error = 0.0


func reset():
	integral = 0.0
	last_error = 0.0

func calculate(curr_err: float):
	# P
	var output = kP * curr_err
	
	# I
	integral += curr_err
	output += kI * integral
	
	# D
	output += kD * (curr_err - last_error)
	last_error = curr_err
	
	# Output limit
	output = max(omin, min(output, omax))
	
	return output
	
