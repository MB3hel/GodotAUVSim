extends Node
class_name PIDController


# Gains
var kP = 0.0
var kI = 0.0
var kD = 0.0

# Output limits
var out_min = -1.0
var out_max = 1.0

# State info
var integral = 0.0
var last_error = 0.0


func reset():
	integral = 0.0
	last_error = 0.0


func calculate(curr_error: float):
	# Proportional gain
	var out = kP * curr_error
	
	# Integral gain
	integral += curr_error
	out += kI * integral
	
	# Derivatie gain
	out += kD * (curr_error - last_error)
	last_error = curr_error
	
	# Limit output range
	return max(out_min, min(out, out_max))
