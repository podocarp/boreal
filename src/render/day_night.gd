## Day/night: sun angle, sky gradient, fog and ambient driven by the sim's
## game-hour (never wall-clock). Cheap two-palette lerp, arctic-flavored.
class_name DayNight
extends Node

const DAY_TOP := Color(0.36, 0.55, 0.80)
const DAY_HORIZON := Color(0.80, 0.78, 0.76)
const DUSK_TOP := Color(0.20, 0.18, 0.34)
const DUSK_HORIZON := Color(0.92, 0.52, 0.34)
const NIGHT_TOP := Color(0.03, 0.05, 0.10)
const NIGHT_HORIZON := Color(0.12, 0.15, 0.24)

var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var environment: Environment


## hour: sim hourOfDay (0..24). Deterministic pure function of the hour.
func apply(hour: float) -> void:
	# daylight 0 at/below the horizon, 1 at noon; dusk band around 0.25/0.75
	var s := sin((hour - 6.0) / 12.0 * PI)          # -1..1, + at day
	var day := clampf(s * 2.0, 0.0, 1.0)            # full day by mid-morning
	var dusk := clampf(1.0 - absf(s) * 4.0, 0.0, 1.0)  # peaks at sunrise/set
	var elev := lerpf(-6.0, 34.0, maxf(0.0, s))
	var azim := lerpf(100.0, 260.0, clampf((hour - 6.0) / 12.0, 0.0, 1.0))
	sun.rotation_degrees = Vector3(-maxf(elev, -2.0), -azim, 0.0)
	sun.light_energy = 0.05 + day * 2.6
	sun.light_color = Color(1.0, lerpf(0.55, 0.85, day), lerpf(0.30, 0.72, day))
	var top: Color = NIGHT_TOP.lerp(DAY_TOP, day).lerp(DUSK_TOP, dusk * 0.7)
	var hor: Color = NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.8)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_bottom_color = top.darkened(0.25)
	sky_mat.ground_horizon_color = hor
	environment.ambient_light_energy = 0.10 + day * 0.28
	environment.fog_light_color = hor.lerp(Color(0.75, 0.78, 0.85), 0.5)
	environment.fog_density = lerpf(0.008, 0.005, day)  # thicker at night for depth
