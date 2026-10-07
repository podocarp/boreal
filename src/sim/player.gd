## Player movement (pure sim) — port of player.ts.
class_name PlayerSim

static func _angle_lerp(a: float, b: float, t: float) -> float:
	var d := b - a
	while d > PI:
		d -= TAU
	while d < -PI:
		d += TAU
	return a + d * t


## intent: {fwd, strafe, run, camYaw}; dt REAL seconds.
static func update_player(w: WorldSim, intent: Dictionary, dt: float) -> void:
	var p := w.player
	var cy: float = intent.camYaw
	# camera basis: forward = (-sin yaw, -cos yaw); right = (cos yaw, -sin yaw)
	var fwdX := -sin(cy)
	var fwdZ := -cos(cy)
	var rightX := cos(cy)
	var rightZ := -sin(cy)

	var mx: float = fwdX * intent.fwd + rightX * intent.strafe
	var mz: float = fwdZ * intent.fwd + rightZ * intent.strafe
	var mlen := sqrt(mx * mx + mz * mz)
	if mlen > 1.0:
		mx /= mlen
		mz /= mlen

	var zone := Terrain.zoneAt(p.x, p.z)
	var base: float = Config.PLAYER.RUN_SPEED_MPS if intent.run else Config.PLAYER.WALK_SPEED_MPS
	var speed := base * Terrain.speedMulAt(zone)
	p.speed = sqrt(mx * mx + mz * mz) * speed
	p.moving = p.speed > 0.05

	var nx: float = p.x + mx * speed * dt
	var nz: float = p.z + mz * speed * dt

	# prop collision: slide (push out of circle)
	for c in w.colliders:
		var dx: float = nx - c.x
		var dz: float = nz - c.z
		var d2: float = dx * dx + dz * dz
		var rr: float = c.r + Config.PLAYER.RADIUS_M
		if d2 < rr * rr and d2 > 1e-9:
			var d := sqrt(d2)
			nx = c.x + (dx / d) * rr
			nz = c.z + (dz / d) * rr

	# world edge
	var r: float = Config.WORLD.SIZE_M
	var dist := sqrt(nx * nx + nz * nz)
	if dist > r:
		nx = (nx / dist) * r
		nz = (nz / dist) * r

	p.x = nx
	p.z = nz
	p.y = Terrain.heightAt(nx, nz)
	p.zone = zone

	# face movement direction, smoothed
	if p.moving:
		var target := atan2(mx, mz)
		p.yaw = _angle_lerp(p.yaw, target, minf(1.0, Config.PLAYER.TURN_RATE_RADPS * dt))
