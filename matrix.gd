class_name Matrix



var rows: int = 0;
var cols: int = 0;
var data: Array = [];


func _init(rows: int, cols: int):
	self.rows = rows;
	self.cols = cols;
	self.data = [];
	for _i in range(rows*cols):
		self.data.append(0.0)

func custom_new(rows: int, cols: int):
	var m = self.duplicate()
	m.rows = rows;
	m.cols = cols;
	m.data = [];
	for _i in range(m.rows*m.cols):
		m.data.append(0.0)
	return m

func mat_idx(row: int, col: int) -> int:
	return self.cols * row + col

func duplicate() -> Matrix:
	var d = get_script().new(rows, cols);
	d.data = self.data.duplicate()
	return d;

func fill_zeros():
	for i in range(rows*cols):
		data[i] = 0.0

func fill_ones():
	for i in range(rows*cols):
		data[i] = 1.0

func fill_ident():
	for row in range(rows):
		for col in range(cols):
			if row == col:
				data[mat_idx(row, col)] = 1.0;
			else:
				data[mat_idx(row, col)] = 0.0;

func set_item(row: int, col: int, value: float):
	if row >= rows or col >= cols:
		return
	data[mat_idx(row, col)] = value

func set_row(row: int, data: Array):
	if row >= rows:
		return
	for col in range(cols):
		self.data[mat_idx(row, col)] = data[col];

func set_col(col: int, data: Array):
	if col > cols:
		return
	for row in range(rows):
		self.data[mat_idx(row, col)] = data[row]

func get_item(row: int, col: int) -> float:
	if row >= rows or col >= cols:
		return 0.0
	return data[mat_idx(row, col)]

func get_row(row: int) -> Array:
	if row >= rows:
		return []
	var data = Array()
	for col in range(cols):
		data.append(self.data[mat_idx(row, col)])
	return data

func get_col(col: int) -> Array:
	if col > cols:
		return []
	var data = Array()
	for row in range(rows):
		data.append(self.data[mat_idx(row, col)])
	return data

func add(other: Matrix) -> Matrix:
	if self.rows != other.rows || self.cols != other.cols:
		return self.custom_new(0, 0);
	var m = self.custom_new(self.rows, self.cols)
	for row in range(rows):
		for col in range(cols):
			m.data[mat_idx(row, col)] = self.data[mat_idx(row, col)] + other.data[mat_idx(row, col)]
	return m;

func sub(other: Matrix) -> Matrix:
	if self.rows != other.rows || self.cols != other.cols:
		return self.custom_new(0, 0);
	var m = self.custom_new(self.rows, self.cols)
	for row in range(rows):
		for col in range(cols):
			m.data[mat_idx(row, col)] = self.data[mat_idx(row, col)] - other.data[mat_idx(row, col)]
	return m;

func ew_mul(other: Matrix) -> Matrix:
	if self.rows != other.rows || self.cols != other.cols:
		return self.custom_new(0, 0);
	var m = self.custom_new(self.rows, self.cols)
	for row in range(rows):
		for col in range(cols):
			m.data[mat_idx(row, col)] = self.data[mat_idx(row, col)] * other.data[mat_idx(row, col)]
	return m;

func ew_div(other: Matrix) -> Matrix:
	if self.rows != other.rows || self.cols != other.cols:
		return self.custom_new(0, 0);
	var m = self.custom_new(self.rows, self.cols)
	for row in range(rows):
		for col in range(cols):
			m.data[mat_idx(row, col)] = self.data[mat_idx(row, col)] / other.data[mat_idx(row, col)]
	return m;

func sc_mul(other: float) -> Matrix:
	var m = self.custom_new(self.rows, self.cols)
	for row in range(rows):
		for col in range(cols):
			m.data[mat_idx(row, col)] = self.data[mat_idx(row, col)] * other
	return m;
	
func sc_div(other: float) -> Matrix:
	var m = self.custom_new(self.rows, self.cols)
	for row in range(rows):
		for col in range(cols):
			m.data[mat_idx(row, col)] = self.data[mat_idx(row, col)] / other
	return m;

func mul(other: Matrix) -> Matrix:
	if self.cols != other.rows:
		return self.custom_new(0, 0)
	var m = self.custom_new(rows, other.cols)
	m.fill_zeros()
	for i in range(rows):
		for j in range(other.cols):
			for k in range(cols):
				m.data[m.mat_idx(i, j)] += self.data[mat_idx(i, k)] * other.data[other.mat_idx(k, j)]
	return m

func transpose() -> Matrix:
	var m = self.custom_new(cols, rows)
	for row in range(m.rows):
		for col in range(m.cols):
			m.data[m.mat_idx(row, col)] = self.data[self.mat_idx(col, row)]
	return m

func det() -> float:
	if self.rows != self.cols:
		return -999999.0;
	var det = 0.0;
	if rows == 1:
		det = data[mat_idx(0 ,0)];
	elif rows == 2:
		det = data[mat_idx(0, 0)] * data[mat_idx(1, 1)] - data[mat_idx(1, 0)] * data[mat_idx(0, 1)];
	else:
		for j1 in range(rows):
			var subm = self.custom_new(rows - 1, rows - 1);
			for i in range(rows):
				var j2 = 0;
				for j in range(rows):
					if j == j1:
						continue
					subm.data[subm.mat_idx(i-1, j2)] = data[mat_idx(i, j)]
					j2 += 1
			var subdet = subm.det();
			det += pow(-1, j1 + 2.0) * data[mat_idx(0, j1)] * subdet;
	return det;

func cofactor() -> Matrix:
	if rows != cols:
		return self.custom_new(0, 0)
	var tmp = self.custom_new(rows - 1, rows - 1)
	var dest = self.custom_new(rows, cols)
	for j in range(rows):
		for i in range(rows):
			var i1 = 0;
			for ii in range(rows):
				if ii == i:
					continue
				var j1 = 0
				for jj in range(rows):
					if jj == j:
						continue
					tmp.data[tmp.mat_idx(i1, j1)] = data[mat_idx(ii, jj)]
					j1 += 1
				i1 += 1
			var det = tmp.det()
			dest.data[dest.mat_idx(i, j)] = pow(-1, i+j+2) * det;
	return dest

func inv() -> Matrix:
	if rows != cols:
		return self.custom_new(0, 0)
	var det = det()
	var cof = self.cofactor()
	var adj = cof.transpose()
	adj.sc_div(det);
	return adj

func vdot(other: Matrix) -> float:
	var d = 0.0;
	if self.rows == 1 and other.rows == 1:
		# Row vector
		if self.cols != other.cols:
			return -999999.0
		for i in range(self.cols):
			d += self.data[mat_idx(0, i)] * other.data[other.mat_idx(0, i)]
		return d
	elif self.cols == 1 and other.cols == 1:
		# Column vector
		if self.rows != other.rows:
			return -999999.0
		for i in range(self.rows):
			d += self.data[mat_idx(i, 0)] * other.data[other.mat_idx(i, 0)]
		return d
	else:
		# Invalid (different dimensions)
		return -999999.0

func vcross(other: Matrix) -> Matrix:
	var m = self.custom_new(rows, cols)
	if self.cols == 1 and self.rows == 3 and other.cols == 1 and other.rows == 3:
		m.data[m.mat_idx(0, 0)] = self.data[self.mat_idx(1, 0)] * other.data[other.mat_idx(2, 0)] - self.data[self.mat_idx(2, 0)] * other.data[other.mat_idx(1, 0)];
		m.data[m.mat_idx(1, 0)] = self.data[self.mat_idx(2, 0)] * other.data[other.mat_idx(0, 0)] - self.data[self.mat_idx(0, 0)] * other.data[other.mat_idx(2, 0)];
		m.data[m.mat_idx(2, 0)] = self.data[self.mat_idx(0, 0)] * other.data[other.mat_idx(1, 0)] - self.data[self.mat_idx(1, 0)] * other.data[other.mat_idx(0, 0)];
		return m
	elif self.cols == 3 and self.rows == 1 and other.cols == 3 and other.rows == 1:
		m.data[m.mat_idx(0, 0)] = self.data[self.mat_idx(0, 1)] * other.data[other.mat_idx(0, 2)] - self.data[self.mat_idx(0, 2)] * other.data[other.mat_idx(0, 1)];
		m.data[m.mat_idx(0, 1)] = self.data[self.mat_idx(0, 2)] * other.data[other.mat_idx(0, 0)] - self.data[self.mat_idx(0, 0)] * other.data[other.mat_idx(0, 2)];
		m.data[m.mat_idx(0, 2)] = self.data[self.mat_idx(0, 0)] * other.data[other.mat_idx(0, 1)] - self.data[self.mat_idx(0, 1)] * other.data[other.mat_idx(0, 0)];
		return m
	else:
		return self.custom_new(0, 0)

func l2vnorm() -> float:
	var d = 0.0;
	if self.cols == 1:
		for row in range(rows):
			d += pow(data[mat_idx(row, 0)], 2.0);
		return sqrt(d);
	elif self.rows == 1:
		for col in range(cols):
			d += pow(data[mat_idx(0, col)], 2.0);
		return sqrt(d);
	else:
		return -99999.0;

# Returns location and value of largest magnitude value
# [value, row, col]
func absmax() -> Array:
	var r = 0;
	var c = 0;
	var v = data[mat_idx(0, 0)];
	for row in range(rows):
		for col in range(cols):
			var tmp = abs(data[mat_idx(row, col)]);
			if tmp > v:
				v = tmp;
				r = row;
				c = col;
	return [v, r, c];
