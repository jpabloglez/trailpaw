class_name DayCurve
extends RefCounted
## Pure sampling of values keyed by hour of day (0…24), wrapping around midnight: between the
## last key and the first one (+24 h) values are interpolated too, so the day is seamless.


## Linear index and weight for [param hour] among sorted [param hours] (all in [0, 24)):
## returns [i, j, t] — sample = lerp(values[i], values[j], t).
static func locate(hours: PackedFloat32Array, hour: float) -> Array:
	var h := fposmod(hour, 24.0)
	var n := hours.size()
	for k in n:
		var a := hours[k]
		var b := hours[(k + 1) % n] + (24.0 if k == n - 1 else 0.0)
		var hh := h + (24.0 if k == n - 1 and h < a else 0.0)
		if hh >= a and hh <= b:
			return [k, (k + 1) % n, (hh - a) / (b - a) if b > a else 0.0]
	return [0, 0, 0.0]


## Value of [param values] (one per key of [param hours]) at [param hour].
static func sample(hours: PackedFloat32Array, values: PackedFloat32Array, hour: float) -> float:
	var at := locate(hours, hour)
	return lerpf(values[at[0]], values[at[1]], at[2])


## Colour of [param colors] (one per key of [param hours]) at [param hour].
static func sample_color(hours: PackedFloat32Array, colors: PackedColorArray, hour: float) -> Color:
	var at := locate(hours, hour)
	return colors[at[0]].lerp(colors[at[1]], at[2])
