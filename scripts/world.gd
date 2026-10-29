extends Node3D
# Builds the four-zone world from the sculpted kit, wires missions / checkpoints / Living Traces gameplay.

var player: Player
var hud: Hud
var controls: TouchControls
var sun: DirectionalLight3D
var wenv: WorldEnvironment
var interacts = {}
var benches = []
var enemy_count = 0
var paused = false
var respawn_t = -1.0
var obj_t = 0.0
var autosave_t = 0.0
var finale_t = -1.0
var finale_spawn_t = 0.0
var gate_block: StaticBody3D
var gate_plane: MeshInstance3D
var wind
var Z = Terrain.ZONES

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameState.load_requested:
		GameState.load_game()
	else:
		GameState.new_game()
	_environment()
	add_child(Assets.build_terrain())
	_zones()
	_player()
	_ui()
	_enemies()
	_missions()
	_apply_quality()
	wind = Assets.play_loop("wind", -20.0)
	hud.toast("Crouch to muffle your steps. Throw an ECHO decoy to pull enemies away.", 6.0)

# ------------------------------------------------------------------ environment / lighting
func _environment():
	var env = Environment.new()
	var sky = Sky.new()
	var sm = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.27, 0.52, 0.62)
	sm.sky_horizon_color = Color(0.98, 0.78, 0.55)
	sm.ground_horizon_color = Color(0.93, 0.74, 0.52)
	sm.ground_bottom_color = Color(0.7, 0.5, 0.36)
	sm.sun_angle_max = 28.0
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.8, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.78
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.78, 0.58)
	env.fog_density = 0.0026
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.05
	wenv = WorldEnvironment.new()
	wenv.environment = env
	add_child(wenv)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 38, 0)
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

func _apply_quality():
	var q = GameState.quality
	var vp = get_viewport()
	var env = wenv.environment
	match q:
		0:
			sun.shadow_enabled = false
			vp.scaling_3d_scale = 0.66
			vp.msaa_3d = Viewport.MSAA_DISABLED
			env.glow_enabled = false
			Assets.detail = 0.6
			Traces.show_ripples = true
		1:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 45.0
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_DISABLED
			env.glow_enabled = false
			Assets.detail = 0.85
		2:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 80.0
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			env.glow_enabled = true
			env.glow_intensity = 0.8
			env.glow_bloom = 0.1
			Assets.detail = 1.2
	if hud:
		hud.refresh_menu()

# ------------------------------------------------------------------ placing kit pieces
func place(piece: String, x: float, z: float, yaw := 0.0, collide := true, vis := 170.0, y_off := 0.0, sc := 1.0) -> Node3D:
	var n = Assets.build_env(piece, collide, vis)
	add_child(n)
	n.position = Vector3(x, Terrain.height(x, z) + y_off, z)
	n.rotation.y = deg_to_rad(yaw)
	if sc != 1.0:
		n.scale = Vector3.ONE * sc
	return n

func scatter(piece: String, zone: String, count: int, rmin: float, rmax: float, seed_v: int, collide := true, vis := 110.0, avoid := 0.0):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	var c = Z[zone]
	var n = int(count * [0.55, 0.8, 1.0][GameState.quality])
	for i in n:
		var a = rng.randf() * TAU
		var r = rng.randf_range(rmin, rmax)
		var p = Vector2(c.x + cos(a) * r, c.y + sin(a) * r)
		place(piece, p.x, p.y, rng.randf() * 360.0, collide, vis, -0.1, rng.randf_range(0.8, 1.3))

func lantern(x: float, z: float, label := "Rest / Workbench"):
	place("p_lantern", x, z, 0.0, true, 120.0)
	var it = Interactable.new()
	it.position = Vector3(x, Terrain.height(x, z) + 1.0, z)
	add_child(it)
	it.setup("bench", label, 3.4, false)
	it.activated.connect(_on_interact)
	var ar = Area3D.new()
	ar.collision_layer = 0
	ar.collision_mask = 2
	var cs = CollisionShape3D.new()
	var sp = SphereShape3D.new()
	sp.radius = 4.6
	cs.shape = sp
	ar.add_child(cs)
	ar.position = it.position
	add_child(ar)
	ar.body_entered.connect(func(b): if b is Player: _checkpoint(Vector3(x, Terrain.height(x, z) + 0.3, z + 2.0)))

func cache(x: float, z: float, id: String, yaw := 0.0):
	place("p_crate_cache", x, z, yaw)
	var it = Interactable.new()
	it.position = Vector3(x, Terrain.height(x, z) + 0.8, z)
	add_child(it)
	it.setup(id, "Open supply cache", 2.2, false)
	it.activated.connect(_on_interact)
	interacts[id] = it

# ------------------------------------------------------------------ zones
func _zones():
	var S = Z["st"]
	# ---- 1. abandoned research station
	place("st_hall", S.x, S.y, 0)
	place("st_dome", S.x - 28, S.y - 8, 35)
	place("st_dish", S.x + 24, S.y - 12, 0, true, 170.0, 0.0)
	place("st_tank", S.x + 20, S.y + 12)
	place("st_generator", S.x + 11, S.y + 13, 200)
	place("p_tent", S.x - 18, S.y + 18, 20); place("p_tent", S.x - 24, S.y + 8, -40)
	place("p_wreck", S.x + 16, S.y + 28, 160)
	place("p_cable", S.x + 8, S.y + 10, 30); place("p_crate", S.x + 14, S.y + 17, 10); place("p_crate", S.x + 15.3, S.y + 17.4, 40); place("p_barrel", S.x - 9, S.y + 9)
	place("p_barrel", S.x - 10.1, S.y + 9.6); place("p_sandbags", S.x + 3, S.y + 21, 0); place("p_sandbags", S.x - 5, S.y + 22, 15)
	place("p_bones", S.x - 6, S.y + 31, 70, false); place("p_deadtree", S.x - 34, S.y + 20, 10); place("p_deadtree", S.x + 38, S.y + 4, 90)
	lantern(S.x, S.y + 16)
	cache(S.x - 14, S.y + 20, "cache_st1")
	scatter("fr_rock", "st", 14, 34, 62, 11); scatter("fr_rock2", "st", 12, 30, 70, 12); scatter("p_shrub", "st", 22, 10, 60, 13, false, 70.0)
	# ---- 2. desert settlement
	var T = Z["se"]
	place("se_house_a", T.x - 14, T.y - 6, 20); place("se_house_b", T.x + 15, T.y - 10, -15); place("se_dome_house", T.x - 17, T.y + 17, 100)
	place("se_tower", T.x, T.y - 32, 0); place("se_well", T.x, T.y + 2); place("se_stall", T.x + 8, T.y + 10, 20); place("se_stall", T.x - 7, T.y + 9, -25)
	place("se_wall", T.x - 28, T.y, 90); place("se_wall", T.x - 28, T.y + 5.6, 90); place("se_wall", T.x + 28, T.y + 3, 95); place("se_wall", T.x + 12, T.y + 26, 10); place("se_wall", T.x - 4, T.y + 27, -5)
	place("p_pot", T.x + 3, T.y + 5, 0); place("p_pot", T.x - 3.5, T.y + 5.5, 0); place("p_crate", T.x + 10, T.y + 14, 25); place("p_barrel", T.x - 11, T.y + 12)
	place("p_tent", T.x + 20, T.y + 14, 70); place("p_deadtree", T.x - 26, T.y - 20, 40); place("p_bones", T.x + 6, T.y - 20, 10, false)
	lantern(T.x + 4, T.y + 19)
	cache(T.x + 18, T.y - 3, "cache_se1", 90)
	scatter("fr_rock", "se", 10, 38, 66, 21); scatter("p_shrub", "se", 20, 12, 62, 22, false, 70.0); scatter("p_pot", "se", 4, 8, 22, 23)
	# ---- 3. buried complex
	var C = Z["co"]
	place("co_hall", C.x, C.y, 0, true, 220.0)
	place("co_corridor", C.x, C.y + 13, 0, true, 220.0); place("co_corridor", C.x, C.y + 21, 0, true, 220.0)
	place("co_door", C.x, C.y + 25.6, 0, true, 220.0)
	place("co_terminal", C.x + 5, C.y - 8.4, 0, false); place("p_crate_cache", C.x - 6, C.y - 8, 0)
	for k in 3:
		place("p_crate", C.x - 7.5 + k * 0.1, C.y + 5 + k * 1.1, k * 30)
	lantern(C.x, C.y + 33)
	cache(C.x + 6.5, C.y + 6.5, "cache_co1", 180)
	gate_block = StaticBody3D.new()
	gate_block.collision_layer = 1
	var bs = CollisionShape3D.new()
	var bx = BoxShape3D.new()
	bx.size = Vector3(4.2, 4.2, 0.4)
	bs.shape = bx
	gate_block.add_child(bs)
	gate_block.position = Vector3(C.x, Terrain.height(C.x, C.y + 25.6) + 2.1, C.y + 25.6)
	add_child(gate_block)
	gate_plane = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(4.0, 4.4)
	gate_plane.mesh = qm
	var gm = StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.25, 1.0, 0.92, 0.45)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gate_plane.material_override = gm
	gate_block.add_child(gate_plane)
	if GameState.mission > 4:
		gate_block.queue_free()
	# ---- 4. fracture zone
	var F = Z["fr"]
	var rim = 22.0
	place("fr_spire_0", F.x - rim - 8, F.y - 30, 20, true, 260.0); place("fr_spire_1", F.x + rim + 6, F.y - 10, 90, true, 260.0)
	place("fr_spire_2", F.x - rim - 14, F.y + 22, 200, true, 300.0); place("fr_spire_0", F.x + rim + 18, F.y + 30, 140, true, 260.0)
	place("fr_spire_1", F.x - 30, F.y - 52, 300, true, 260.0); place("fr_spire_2", F.x + 36, F.y - 55, 60, true, 300.0)
	var cxm = F.x + 8.0 * sin((F.y - 15) * 0.06)
	var hl = Terrain.height(cxm - 7, F.y - 15)
	var hr = Terrain.height(cxm + 7, F.y - 15)
	var arch = place("fr_arch", cxm, F.y - 15, 0, true, 300.0)
	arch.position.y = minf(hl, hr) - 1.0
	for k in 7:
		var zz = F.y + 38 - k * 12.0
		var cx2 = F.x + 8.0 * sin(zz * 0.06)
		place("fr_crack", cx2 - 0.5, zz - 6, 0, false, 120.0, 0.12)
		if k % 2 == 0:
			place("fr_crystal", cx2 + (-3.0 if k % 4 == 0 else 3.5), zz, k * 40.0, true, 140.0, 0.0, 1.3)
	place("fr_slab", F.x + 14, F.y + 12, 120); place("fr_slab", F.x - 16, F.y - 8, 50)
	place("p_wreck", F.x + 20, F.y + 44, 40)
	lantern(F.x + 4, F.y + 52)
	cache(F.x - 12, F.y + 40, "cache_fr1", 30)
	scatter("fr_rock", "fr", 30, 22, 70, 31); scatter("fr_rock2", "fr", 26, 20, 70, 32); scatter("fr_crystal", "fr", 8, 40, 70, 33, true, 130.0)
	# ground-cover dressing inside the zone plateaus
	for zk in ["st", "se", "co", "fr"]:
		scatter("p_shrub", zk, 26, 9, 44, 41 + zk.length(), false, 60.0)
		scatter("fr_rock2", zk, 7, 18, 46, 51 + zk.length(), true, 90.0)
	scatter("p_bones", "se", 3, 12, 40, 61, false, 60.0); scatter("p_deadtree", "st", 3, 26, 46, 62); scatter("p_deadtree", "se", 3, 30, 52, 63)
	# dust / energy motes
	_motes(F, Color(0.3, 1.0, 0.92), 90, 38.0)
	_motes(S, Color(1.0, 0.9, 0.7), 60, 40.0)
	_motes(Z["se"], Color(1.0, 0.9, 0.7), 60, 40.0)

func _motes(c: Vector2, col: Color, amount: int, ext: float):
	var p = CPUParticles3D.new()
	p.amount = int(amount * [0.4, 0.7, 1.0][GameState.quality])
	p.lifetime = 7.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(ext, 6.0, ext)
	p.direction = Vector3(0.4, 1, 0.2)
	p.spread = 40.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0.3, 0.05, 0.1)
	var sm = SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 4
	sm.rings = 2
	p.mesh = sm
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(c.x, Terrain.height(c.x, c.y) + 5.0, c.y)
	add_child(p)

# ------------------------------------------------------------------ player / ui
func _player():
	player = Player.new()
	add_child(player)
	var sp = Vector3(Z["st"].x, 0, Z["st"].y + 19)
	if GameState.has_checkpoint:
		sp = GameState.checkpoint
	else:
		sp.y = Terrain.height(sp.x, sp.z) + 0.3
	player.global_position = sp
	player.cam_rig.global_position = sp
	player.yaw = 0.0
	player.died.connect(_on_player_died)

func _ui():
	hud = Hud.new()
	add_child(hud)
	controls = TouchControls.new()
	hud.root.add_child(controls)
	controls.z_index = 5
	player.controls = controls
	player.hud = hud
	hud.resume_pressed.connect(_toggle_pause)
	hud.save_pressed.connect(func():
		GameState.save_game(player.global_position)
		hud.toast("Progress saved"))
	hud.quality_pressed.connect(func():
		GameState.quality = (GameState.quality + 1) % 3
		_apply_quality())
	hud.menu_pressed.connect(func():
		get_tree().paused = false
		GameState.save_game(player.global_position)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	hud.bought.connect(player.apply_upgrades)

# ------------------------------------------------------------------ enemies
func _enemies():
	var S = Z["st"]; var T = Z["se"]; var C = Z["co"]; var F = Z["fr"]
	_spawn("hound", S.x - 20, S.y + 38, "st_h1"); _spawn("hound", S.x + 30, S.y + 26, "st_h2")
	_spawn("hound", T.x - 8, T.y - 22, "se_h1"); _spawn("hound", T.x + 22, T.y + 8, "se_h2"); _spawn("hound", T.x - 22, T.y + 4, "se_h3")
	_spawn("husk", T.x + 4, T.y - 14, "se_k1"); _spawn("husk", T.x - 5, T.y + 24, "se_k2"); _spawn("burrower", T.x + 40, T.y + 20, "se_b1")
	_spawn("hound", C.x + 4, C.y + 46, "co_h1"); _spawn("husk", C.x - 5, C.y - 4, "co_k1"); _spawn("husk", C.x + 5, C.y + 3, "co_k2"); _spawn("husk", C.x, C.y - 6, "co_k3")
	_spawn("burrower", C.x - 30, C.y + 38, "co_b1")
	_spawn("hound", F.x + 12, F.y + 34, "fr_h1"); _spawn("hound", F.x - 14, F.y + 10, "fr_h2"); _spawn("hound", F.x + 6, F.y - 24, "fr_h3")
	_spawn("husk", F.x - 6, F.y + 20, "fr_k1"); _spawn("husk", F.x + 10, F.y - 8, "fr_k2")
	_spawn("burrower", F.x + 22, F.y + 4, "fr_b1"); _spawn("burrower", F.x - 24, F.y - 22, "fr_b2")

func _spawn(sp: String, x: float, z: float, id: String):
	if id in GameState.killed:
		return
	var e = Enemy.new()
	e.setup(sp, Vector3(x, Terrain.height(x, z) + 0.2, z), id, player)
	e.world_ref = self
	add_child(e)
	enemy_count += 1

func on_enemy_died(e: Enemy):
	for i in 3 + int(e.prof["reward"] / 4):
		_drop("shard", e.global_position + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)), 2 if e.species != "hound" else 1)
	var r = randf()
	if r < 0.3:
		_drop("ammo", e.global_position + Vector3(0.5, 0.5, 0.0), 12)
	elif r < 0.45:
		_drop("med", e.global_position + Vector3(-0.5, 0.5, 0.0), 30)

func _drop(kind: String, pos: Vector3, amount: int):
	var a = Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2
	var cs = CollisionShape3D.new()
	var sp = SphereShape3D.new()
	sp.radius = 1.4
	cs.shape = sp
	a.add_child(cs)
	var model = Assets.build_env("p_shard" if kind == "shard" else ("p_crate_cache" if kind == "ammo" else "p_decoy"), false)
	if kind == "med":
		model.scale = Vector3.ONE * 1.5
	if kind == "ammo":
		model.scale = Vector3.ONE * 0.5
	a.add_child(model)
	add_child(a)
	a.global_position = Vector3(pos.x, Terrain.height(pos.x, pos.z) + 0.5, pos.z)
	a.body_entered.connect(func(b):
		if b is Player:
			b.give(kind, amount)
			a.queue_free())
	var tw = a.create_tween().set_loops()
	tw.tween_property(model, "position:y", 0.25, 0.7)
	tw.tween_property(model, "position:y", 0.0, 0.7)
	get_tree().create_timer(60.0).timeout.connect(func(): if is_instance_valid(a): a.queue_free())

# ------------------------------------------------------------------ missions
func _mission_point(i: int) -> Vector3:
	var S = Z["st"]; var T = Z["se"]; var C = Z["co"]; var F = Z["fr"]
	match GameState.MISSIONS[i]["id"]:
		"st_terminal": return Vector3(S.x + 4.6, Terrain.height(S.x, S.y) + 0.9, S.y - 2.2)
		"st_gen": return Vector3(S.x + 11, Terrain.height(S.x + 11, S.y + 13) + 1.0, S.y + 11.5)
		"se_reach": return Vector3(T.x, Terrain.height(T.x, T.y), T.y + 4)
		"se_journal": return Vector3(T.x - 17, Terrain.height(T.x - 17, T.y + 17) + 0.9, T.y + 17)
		"co_gate": return Vector3(C.x, Terrain.height(C.x, C.y + 23) + 1.0, C.y + 23.4)
		"co_core": return Vector3(C.x, Terrain.height(C.x, C.y) + 1.0, C.y + 3.4)
		"fr_seal":
			var zz = F.y - 52
			return Vector3(F.x + 8.0 * sin(zz * 0.06), Terrain.height(F.x + 8.0 * sin(zz * 0.06), zz) + 1.0, zz)
	return Vector3.ZERO

func _missions():
	for i in GameState.MISSIONS.size():
		var m = GameState.MISSIONS[i]
		var p = _mission_point(i)
		GameState.points[m["id"]] = p
		if m["type"] == "interact":
			var it = Interactable.new()
			it.position = p
			add_child(it)
			it.setup(m["id"], m["prompt"], 2.4, true, 18.0)
			it.activated.connect(_on_interact)
			interacts[m["id"]] = it
	_refresh_missions()

func _refresh_missions():
	for k in interacts:
		var it = interacts[k]
		if k.begins_with("cache"):
			continue
		it.set_active(false)
	if GameState.mission < GameState.MISSIONS.size():
		var id = GameState.MISSIONS[GameState.mission]["id"]
		if interacts.has(id):
			interacts[id].set_active(true)
	GameState.mission_changed.emit()

func _on_interact(id: String):
	if id == "bench":
		_toggle_pause(true)
		return
	if id.begins_with("cache"):
		player.give("ammo", 36)
		player.give("decoy", 2)
		player.give("med", 40)
		if interacts.has(id):
			interacts[id].queue_free()
			interacts.erase(id)
		return
	if GameState.mission >= GameState.MISSIONS.size():
		return
	var m = GameState.MISSIONS[GameState.mission]
	if m["id"] != id:
		return
	hud.toast(m["done"], 6.0)
	Assets.play("pickup", null, -4.0)
	match id:
		"co_gate":
			_open_gate()
		"co_core":
			Traces.add_trace(player.global_position, Traces.ENERGY, 70.0, 6.0, false)
			var C = Z["co"]
			_spawn("husk", C.x - 8, C.y + 9, "co_amb1"); _spawn("hound", C.x + 8, C.y + 9, "co_amb2")
		"fr_seal":
			finale_t = 40.0
			finale_spawn_t = 3.0
	GameState.mission += 1
	_refresh_missions()
	GameState.save_game(player.global_position)

func _open_gate():
	if is_instance_valid(gate_block):
		var tw = create_tween()
		tw.tween_property(gate_plane.material_override, "albedo_color:a", 0.0, 1.2)
		tw.tween_callback(gate_block.queue_free)
		Assets.play("eruption", null, -6.0)

func _checkpoint(pos: Vector3):
	if GameState.has_checkpoint and GameState.checkpoint.distance_to(pos) < 1.0:
		return
	GameState.checkpoint = pos
	GameState.has_checkpoint = true
	player.hp = 100.0
	player.ammo = GameState.mag_size()
	player.reserve = maxi(player.reserve, 72)
	GameState.decoys = maxi(GameState.decoys, 3)
	hud.toast("Checkpoint - rested, resupplied, progress saved")
	GameState.save_game(player.global_position)

func _on_player_died():
	hud.show_death(true)
	respawn_t = 3.0

# ------------------------------------------------------------------ loop
func _toggle_pause(force_open = null):
	paused = (not paused) if force_open == null else bool(force_open)
	get_tree().paused = paused
	hud.open_menu(paused)

func _process(delta):
	if Input.is_action_just_pressed("pause") or controls.consume("pause"):
		_toggle_pause()
	if paused:
		return
	# nearest interaction prompt
	var prompt = ""
	for a in player.near:
		if is_instance_valid(a) and a.enabled:
			prompt = "USE:  " + a.prompt
			break
	hud.set_prompt(prompt)
	controls.show_use = prompt != ""
	# objective line
	obj_t -= delta
	if obj_t <= 0.0:
		obj_t = 0.25
		if finale_t > 0.0:
			hud.set_objective("HOLD THE LINE - seal charging %d s" % int(finale_t), -1.0)
		elif GameState.mission < GameState.MISSIONS.size():
			var m = GameState.MISSIONS[GameState.mission]
			var d = player.global_position.distance_to(GameState.points[m["id"]])
			hud.set_objective(m["text"], d)
			if m["type"] == "reach" and d < m["radius"]:
				hud.toast("Settlement reached", 3.0)
				GameState.mission += 1
				_refresh_missions()
				GameState.save_game(player.global_position)
		else:
			hud.set_objective("The Echo Rift is sealed", -1.0)
	# respawn
	if respawn_t > 0.0:
		respawn_t -= delta
		if respawn_t <= 0.0:
			hud.show_death(false)
			var sp = GameState.checkpoint if GameState.has_checkpoint else Vector3(Z["st"].x, Terrain.height(Z["st"].x, Z["st"].y + 19) + 0.3, Z["st"].y + 19)
			Traces.clear_all()
			player.respawn(sp)
			player.cam_rig.global_position = sp
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.state != Enemy.S.DEAD and e.state != Enemy.S.BURIED:
					e.alert = 0.0
					e.state = Enemy.S.PATROL
					e.target = e.home
	# finale: the rift calls everything
	if finale_t > 0.0:
		finale_t -= delta
		finale_spawn_t -= delta
		if int(finale_t * 2.0) % 3 == 0:
			Traces.add_trace(player.global_position, Traces.ENERGY, 45.0, 2.5, false, false)
		if finale_spawn_t <= 0.0 and enemy_count < 60:
			finale_spawn_t = 5.5
			var a = randf() * TAU
			var pp = player.global_position + Vector3(cos(a), 0, sin(a)) * 30.0
			_spawn("hound" if randf() < 0.6 else "husk", pp.x, pp.z, "fin_%d" % enemy_count)
			Traces.add_trace(pp, Traces.ENERGY, 12.0, 1.0, false)
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.uid.begins_with("fin_") and e.state == Enemy.S.PATROL:
					e.last_known = player.global_position
					e._start_chase()
		if finale_t <= 0.0:
			finale_t = -1.0
			GameState.finale_done = true
			hud.big_text("THE RIFT IS SEALED\n\nصَدَى الرماد - the echo falls silent")
			GameState.save_game(player.global_position)
			get_tree().create_timer(8.0).timeout.connect(func(): hud.big_text(""))
	autosave_t += delta
	if autosave_t > 45.0:
		autosave_t = 0.0
		GameState.save_game(player.global_position)
