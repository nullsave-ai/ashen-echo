extends Node
# Loads SDF-sculpted GLB models (vertex-painted) and wraps them in the hand-painted shader. Synthesises audio.

var _painted: ShaderMaterial
var _painted_o: ShaderMaterial
var _outline: ShaderMaterial
var _meshes = {}
var _shapes = {}
var _sounds = {}
var ring_tex: ImageTexture
var detail = 1.0

func _ready():
	_outline = ShaderMaterial.new()
	_outline.shader = load("res://shaders/outline.gdshader")
	_painted = ShaderMaterial.new()
	_painted.shader = load("res://shaders/painted.gdshader")
	_painted.set_shader_parameter("grain", load("res://assets/grain.png"))
	_painted_o = _painted.duplicate()
	_painted_o.next_pass = _outline
	_make_ring_tex()
	for k in ["shot", "shot_sup", "step", "reload", "hit", "pickup", "dodge", "growl", "decoy", "hurt", "click", "eruption"]:
		_sounds[k] = _synth(k)
	_sounds["wind"] = _synth("wind")

func mat(_k := "", outlined := false) -> Material:
	return _painted_o if outlined else _painted

func _find_mesh(n: Node):
	if n is MeshInstance3D and n.mesh != null:
		return n.mesh
	for c in n.get_children():
		var r = _find_mesh(c)
		if r != null:
			return r
	return null

func _get_mesh(fn: String) -> Mesh:
	if not _meshes.has(fn):
		var ps = load("res://assets/models/" + fn)
		var inst = ps.instantiate()
		_meshes[fn] = _find_mesh(inst)
		inst.free()
	return _meshes[fn]

func build_model(key: String, outlined := true, shadows := true) -> Dictionary:
	var data = RigData.DATA[key]
	var root = Node3D.new()
	var piv = {}
	for p in data["pivots"]:
		var n = Node3D.new()
		n.name = p["name"]
		n.position = Vector3(p["pos"][0], p["pos"][1], p["pos"][2])
		var par = root if p["parent"] == "" else piv[p["parent"]]
		par.add_child(n)
		piv[p["name"]] = n
	for part in data["parts"]:
		var mi = MeshInstance3D.new()
		mi.mesh = _get_mesh(part["mesh"])
		mi.name = part["mesh"].get_basename()
		mi.material_override = mat("", outlined)
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piv[part["pivot"]].add_child(mi)
	return {"root": root, "piv": piv}

func build_env(piece: String, collide := true, vis_end := 0.0) -> Node3D:
	var body: Node3D
	if collide:
		var sb = StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		body = sb
	else:
		body = Node3D.new()
	for part in RigData.DATA["env"][piece]:
		var mesh = _get_mesh(part["mesh"])
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _painted
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end * detail
			mi.visibility_range_end_margin = 10.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		body.add_child(mi)
		if collide:
			if not _shapes.has(part["mesh"]):
				_shapes[part["mesh"]] = mesh.create_trimesh_shape()
			var cs = CollisionShape3D.new()
			cs.shape = _shapes[part["mesh"]]
			body.add_child(cs)
	return body

func build_terrain() -> StaticBody3D:
	var sb = StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var mesh = _get_mesh(RigData.DATA["terrain"])
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _painted
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb.add_child(mi)
	var cs = CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	sb.add_child(cs)
	return sb

func _make_ring_tex():
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d = Vector2(x - 63.5, y - 63.5).length() / 64.0
			var a = clampf(1.0 - absf(d - 0.9) * 14.0, 0.0, 1.0) * 0.9 + clampf(1.0 - d, 0.0, 1.0) * 0.12
			img.set_pixel(x, y, Color(1, 1, 1, a if d < 1.0 else 0.0))
	ring_tex = ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- audio
func play(kind: String, pos = null, vol_db := 0.0) -> void:
	if not _sounds.has(kind):
		return
	var p
	if pos == null:
		p = AudioStreamPlayer.new()
	else:
		p = AudioStreamPlayer3D.new()
		p.max_distance = 70.0
		p.unit_size = 9.0
	p.stream = _sounds[kind]
	p.volume_db = vol_db
	get_tree().current_scene.add_child(p)
	if pos != null:
		p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

func play_loop(kind: String, vol_db := -18.0) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.stream = _sounds[kind]
	p.volume_db = vol_db
	add_child(p)
	p.play()
	return p

func _synth(kind: String) -> AudioStreamWAV:
	var rate = 22050
	var dur = 0.3
	match kind:
		"shot": dur = 0.32
		"shot_sup": dur = 0.2
		"step": dur = 0.14
		"reload": dur = 0.45
		"hit": dur = 0.12
		"pickup": dur = 0.3
		"dodge": dur = 0.3
		"growl": dur = 0.6
		"decoy": dur = 0.25
		"hurt": dur = 0.25
		"click": dur = 0.05
		"eruption": dur = 0.7
		"wind": dur = 3.0
	var n = int(rate * dur)
	var bytes = PackedByteArray()
	bytes.resize(n * 2)
	var lp = 0.0
	var ph = 0.0
	for i in n:
		var t = float(i) / rate
		var f = float(i) / n
		var v = 0.0
		var noise = randf() * 2.0 - 1.0
		match kind:
			"shot":
				lp += (noise - lp) * 0.35
				v = lp * exp(-f * 7.0) * 0.9 + sin(t * 140.0 * 6.283 * (1.0 - f * 0.6)) * exp(-f * 9.0) * 0.6
			"shot_sup":
				lp += (noise - lp) * 0.12
				v = lp * exp(-f * 9.0) * 0.5 + sin(t * 200.0 * 6.283) * exp(-f * 14.0) * 0.25
			"step":
				lp += (noise - lp) * 0.08
				v = lp * exp(-f * 10.0) * 0.8
			"reload":
				var c1 = exp(-absf(f - 0.15) * 90.0)
				var c2 = exp(-absf(f - 0.7) * 90.0)
				v = noise * (c1 + c2) * 0.5 + sin(t * 900.0 * 6.283) * c2 * 0.2
			"hit":
				v = noise * exp(-f * 12.0) * 0.7
			"pickup":
				v = (sin(t * 880.0 * 6.283) * (1.0 - f) + sin(t * 1320.0 * 6.283) * maxf(0.0, f - 0.4)) * 0.3
			"dodge":
				lp += (noise - lp) * (0.05 + f * 0.2)
				v = lp * sin(f * 3.14159) * 0.6
			"growl":
				ph += (70.0 + sin(t * 24.0) * 14.0) * 6.283 / rate
				v = (fmod(ph, 6.283) / 3.1416 - 1.0) * 0.4 * sin(f * 3.14159) + noise * 0.05
			"decoy":
				v = sin(t * (600.0 + f * 900.0) * 6.283) * 0.3 * (1.0 - f)
			"hurt":
				lp += (noise - lp) * 0.2
				v = lp * exp(-f * 6.0) * 0.7 + sin(t * 110.0 * 6.283) * exp(-f * 8.0) * 0.4
			"click":
				v = noise * exp(-f * 20.0) * 0.6
			"eruption":
				lp += (noise - lp) * 0.06
				v = lp * sin(minf(f * 4.0, 1.0) * 1.57) * exp(-f * 3.0) * 1.1
			"wind":
				lp += (noise - lp) * 0.012
				v = lp * (0.6 + 0.4 * sin(t * 1.9)) * 3.2
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	if kind == "wind":
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s
