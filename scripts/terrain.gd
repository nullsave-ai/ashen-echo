class_name Terrain
extends RefCounted
# Shared height function: world mesh, enemies and props all sample this.

const ZONES = {"st": Vector2(0, 0), "se": Vector2(120, -40), "co": Vector2(60, -150), "fr": Vector2(-70, -170)}
const ZONE_Y = {"st": 0.0, "se": 1.0, "co": 0.0, "fr": -2.5}
const BOUNDS = Rect2(-180, -290, 400, 350)
static var _hp: PackedFloat32Array

static func height(x: float, z: float) -> float:
	if _hp.is_empty():
		_hp = PackedFloat32Array(TerrainData.H)
	var fx = clampf((x - TerrainData.X0) / TerrainData.STEP, 0.0, TerrainData.NX - 1.001)
	var fz = clampf((z - TerrainData.Z0) / TerrainData.STEP, 0.0, TerrainData.NZ - 1.001)
	var ix = int(fx)
	var iz = int(fz)
	var tx = fx - ix
	var tz = fz - iz
	var nx = TerrainData.NX
	var h00 = _hp[iz * nx + ix]
	var h10 = _hp[iz * nx + ix + 1]
	var h01 = _hp[(iz + 1) * nx + ix]
	var h11 = _hp[(iz + 1) * nx + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

static func zone_of(p: Vector3) -> String:
	var best = ""
	var bd = 1e9
	for k in ZONES:
		var d = Vector2(p.x, p.z).distance_to(ZONES[k])
		if d < bd:
			bd = d
			best = k
	return best if bd < 70.0 else ""

static func inside_complex(p: Vector3) -> bool:
	var c = ZONES["co"]
	return absf(p.x - c.x) < 9.5 and p.z - c.y > -9.5 and p.z - c.y < 26.0
