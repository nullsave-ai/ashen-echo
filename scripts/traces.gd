extends Node
# LIVING TRACES: every footstep, gunshot, energy burst and decoy leaves a decaying trace.
# Enemies query traces through their species profile (multipliers per trace type).

const FOOT = 0
const SHOT = 1
const ENERGY = 2
const DECOY = 3
const THUMP = 4

var traces = []
var show_ripples = true

func add_trace(pos: Vector3, type: int, radius: float, life := 3.0, ground := true, ripple := true) -> void:
	traces.append({"pos": pos, "type": type, "radius": radius, "life": life, "left": life, "ground": ground})
	if ripple and show_ripples and radius > 4.0:
		_ripple(pos, type, radius, minf(life, 1.4))

func _process(delta):
	var i = traces.size() - 1
	while i >= 0:
		traces[i]["left"] -= delta
		if traces[i]["left"] <= 0.0:
			traces.remove_at(i)
		i -= 1

func query(from: Vector3, mult: Dictionary, ground_only := false):
	var best = null
	var best_i = 0.0
	for t in traces:
		var m = mult.get(t["type"], 0.0)
		if m <= 0.0:
			continue
		if ground_only and not t["ground"]:
			continue
		var r = t["radius"] * m
		var d = Vector2(from.x - t["pos"].x, from.z - t["pos"].z).length()
		if d >= r:
			continue
		var inten = (1.0 - d / r) * clampf(t["left"] / t["life"] * 1.6, 0.0, 1.0)
		if inten > best_i:
			best_i = inten
			best = {"pos": t["pos"], "type": t["type"], "i": inten}
	return best

func clear_all():
	traces.clear()

func _ripple(pos: Vector3, type: int, radius: float, life: float):
	var scene = get_tree().current_scene
	if scene == null:
		return
	var mi = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = Assets.ring_tex
	var col = [Color(0.95, 0.8, 0.5), Color(1.0, 0.55, 0.25), Color(0.25, 1.0, 0.9), Color(0.4, 1.0, 0.95), Color(0.9, 0.7, 0.4)][type]
	col.a = 0.55 if type == FOOT else 0.8
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	mi.global_position = Vector3(pos.x, Terrain.height(pos.x, pos.z) + 0.2, pos.z)
	mi.rotation.x = -PI / 2
	mi.scale = Vector3(0.5, 0.5, 1.0)
	var tw = mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius * 2.0, radius * 2.0, 1.0), life).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)
