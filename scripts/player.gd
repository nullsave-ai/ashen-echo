extends CharacterBody3D
class_name Player

signal died

var controls = null
var hud = null
var piv = {}
var flip: Node3D
var face_node: Node3D
var cam_rig: Node3D
var pitch_node: Node3D
var shoulder: Node3D
var arm: SpringArm3D
var cam: Camera3D
var capsule: CapsuleShape3D
var col: CollisionShape3D
var sense: Area3D
var muzzle: Node3D
var flash: MeshInstance3D
var tracer_mat: StandardMaterial3D

var yaw = 0.0
var pitch = -0.08
var face_yaw = 0.0
var hp = 100.0
var ammo = 24
var reserve = 96
var aiming = false
var crouching = false
var sprinting = false
var reloading = false
var reload_t = 0.0
var fire_cd = 0.0
var shoot_recent = 0.0
var dodge_t = 0.0
var dodge_cd = 0.0
var dodge_dir = Vector3.ZERO
var invuln = 0.0
var interact_t = 0.0
var throw_t = 0.0
var step_dist = 0.0
var anim_t = 0.0
var aim_blend = 0.65
var crouch_blend = 0.0
var recoil = 0.0
var dead = false
var near = []
var noise_level = 0.0
var hip_base_y = 0.95
var weapon_base = Vector3.ZERO
var flash_t = 0.0
var cam_pos = Vector3.ZERO
var AIM = {}
var last_aim_dir = Vector3.FORWARD
var press_prev = {}

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = 0.5
	AIM = RigData.DATA["aim_pose"]
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	col = CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.85
	add_child(col)
	face_node = Node3D.new()
	add_child(face_node)
	flip = Node3D.new()
	flip.position.y = 0.9
	face_node.add_child(flip)
	var m = Assets.build_model("hero", true, true)
	m["root"].position.y = -0.9
	flip.add_child(m["root"])
	piv = m["piv"]
	hip_base_y = piv["hips"].position.y
	weapon_base = piv["weapon"].position
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.01, -0.75)
	piv["weapon"].add_child(muzzle)
	flash = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	flash.mesh = sm
	var fm = StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.85, 0.45)
	flash.material_override = fm
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(flash)
	tracer_mat = StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.albedo_color = Color(0.7, 1.0, 0.95)
	# camera rig (over-the-shoulder)
	cam_rig = Node3D.new()
	cam_rig.top_level = true
	add_child(cam_rig)
	pitch_node = Node3D.new()
	pitch_node.position.y = 1.55
	cam_rig.add_child(pitch_node)
	shoulder = Node3D.new()
	shoulder.position.x = 0.75
	pitch_node.add_child(shoulder)
	arm = SpringArm3D.new()
	arm.spring_length = 3.3
	arm.collision_mask = 1
	arm.margin = 0.25
	arm.add_excluded_object(get_rid())
	shoulder.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 68
	cam.far = 420
	cam.near = 0.12
	arm.add_child(cam)
	cam.current = true
	cam_rig.global_position = global_position
	# interaction sensor
	sense = Area3D.new()
	sense.collision_layer = 0
	sense.collision_mask = 16
	sense.monitoring = true
	var ss = CollisionShape3D.new()
	var sp = SphereShape3D.new()
	sp.radius = 2.6
	ss.shape = sp
	ss.position.y = 1.0
	sense.add_child(ss)
	add_child(sense)
	sense.area_entered.connect(func(a): near.append(a))
	sense.area_exited.connect(func(a): near.erase(a))
	hp = GameState.hp
	ammo = GameState.ammo
	reserve = GameState.reserve
	apply_upgrades()

func apply_upgrades():
	for n in ["hero_rifle_coil", "hero_rifle_scope", "hero_rifle_maglong", "hero_rifle_suppressor"]:
		var node = piv["weapon"].get_node_or_null(n)
		if node:
			node.visible = false
	var u = GameState.upgrades
	if u["coil"] > 0: piv["weapon"].get_node("hero_rifle_coil").visible = true
	if u["scope"] > 0: piv["weapon"].get_node("hero_rifle_scope").visible = true
	if u["mag"] > 0:
		piv["weapon"].get_node("hero_rifle_maglong").visible = true
	if u["suppressor"] > 0:
		piv["weapon"].get_node("hero_rifle_suppressor").visible = true
	ammo = mini(ammo, GameState.mag_size())

# ------------------------------------------------------------ helpers
func visibility() -> float:
	var v = 1.0
	if crouching: v *= 0.55
	if Vector2(velocity.x, velocity.z).length() < 0.4: v *= 0.7
	return v

func _pressed(name: String) -> bool:
	var now = Input.is_action_pressed(name) or (controls != null and controls.btn(name))
	var edge = now and not press_prev.get(name, false)
	press_prev[name] = now
	return edge

func give(kind: String, amount: int):
	match kind:
		"shard":
			GameState.shards += amount
			Assets.play("pickup", null, -8.0)
		"ammo":
			reserve += amount
			GameState.reserve = reserve
			Assets.play("pickup", null, -8.0)
			if hud: hud.toast("+%d ammo" % amount)
		"med":
			hp = minf(100.0, hp + amount)
			GameState.hp = hp
			Assets.play("pickup", null, -8.0)
			if hud: hud.toast("Medicine applied")
		"decoy":
			GameState.decoys = mini(GameState.max_decoys(), GameState.decoys + amount)
			Assets.play("pickup", null, -8.0)
			if hud: hud.toast("+%d echo decoy" % amount)

func respawn(pos: Vector3):
	dead = false
	global_position = pos
	velocity = Vector3.ZERO
	hp = 100.0
	GameState.hp = hp
	ammo = GameState.mag_size()
	reserve = maxi(reserve, 48)
	GameState.ammo = ammo
	GameState.reserve = reserve
	flip.rotation.x = 0.0
	invuln = 2.0
	reloading = false

func hurt(dmg: float, from_pos := Vector3.ZERO, _hs := false):
	if dead or invuln > 0.0:
		return
	hp -= dmg
	GameState.hp = hp
	invuln = 0.3
	Assets.play("hurt", null, -4.0)
	if hud: hud.damage_flash()
	var kb = (global_position - from_pos)
	kb.y = 0.0
	velocity += kb.normalized() * 4.5
	if hp <= 0.0:
		dead = true
		died.emit()

# ------------------------------------------------------------ main loop
func _physics_process(delta):
	if dead:
		flip.rotation.x = lerpf(flip.rotation.x, 1.45, delta * 4.0)
		piv["hips"].position.y = lerpf(piv["hips"].position.y, hip_base_y - 0.3, delta * 4.0)
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 20.0 * delta
		move_and_slide()
		_update_camera(delta)
		return
	var mv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var look = Vector2.ZERO
	if controls:
		mv += controls.move
		if mv.length() > 1.0:
			mv = mv.normalized()
		look = controls.consume_look()
	if _pressed("aim") and controls == null:
		aiming = not aiming
	if controls and controls.consume("aim"):
		aiming = not aiming
	if (controls and controls.consume("crouch")) or Input.is_action_just_pressed("crouch"):
		crouching = not crouching
	var fire_held = Input.is_action_pressed("fire") or (controls != null and controls.btn("fire"))
	var want_sprint = (mv.length() > 0.88 and controls != null) or Input.is_action_pressed("sprint") or (controls != null and controls.btn("sprint"))
	sprinting = want_sprint and not aiming and not crouching and mv.length() > 0.1 and not reloading
	# camera look
	var sens = 0.0070 * (0.55 if aiming else 1.0)
	yaw -= look.x * sens
	pitch = clampf(pitch - look.y * sens, -0.95, 1.05)
	var basis = Basis(Vector3.UP, yaw)
	var dir = basis * Vector3(mv.x, 0.0, mv.y)
	# timers
	fire_cd = maxf(0.0, fire_cd - delta)
	shoot_recent = maxf(0.0, shoot_recent - delta)
	dodge_cd = maxf(0.0, dodge_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	interact_t = maxf(0.0, interact_t - delta)
	throw_t = maxf(0.0, throw_t - delta)
	flash_t = maxf(0.0, flash_t - delta)
	flash.visible = flash_t > 0.0
	recoil = lerpf(recoil, 0.0, delta * 10.0)
	# actions
	if (controls and controls.consume("dodge")) or Input.is_action_just_pressed("dodge"):
		_try_dodge(dir, basis)
	if (controls and controls.consume("reload")) or Input.is_action_just_pressed("reload"):
		_start_reload()
	if (controls and controls.consume("decoy")) or Input.is_action_just_pressed("decoy"):
		_throw_decoy()
	if (controls and controls.consume("interact")) or Input.is_action_just_pressed("interact"):
		_interact()
	if dodge_t <= 0.0 and not reloading:
		if fire_held and fire_cd <= 0.0:
			if ammo > 0:
				_shoot()
			else:
				_start_reload()
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()
	# movement
	var spd = 4.3
	if sprinting: spd = 7.4
	elif crouching: spd = 2.3
	elif aiming or shoot_recent > 0.0: spd = 3.0
	var hv = Vector3(velocity.x, 0, velocity.z)
	if dodge_t > 0.0:
		dodge_t -= delta
		hv = dodge_dir * 9.5
	else:
		hv = hv.move_toward(dir * spd, delta * (40.0 if dir.length() > 0.01 else 30.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 22.0 * delta
	move_and_slide()
	var hspeed = Vector2(velocity.x, velocity.z).length()
	# facing
	var face_target = face_yaw
	if aiming or shoot_recent > 0.0 or interact_t > 0.0 or throw_t > 0.0:
		face_target = yaw
	elif dodge_t > 0.0:
		face_target = atan2(-dodge_dir.x, -dodge_dir.z)
	elif hspeed > 0.5:
		face_target = atan2(-velocity.x, -velocity.z)
	face_yaw = lerp_angle(face_yaw, face_target, clampf(delta * (14.0 if aiming else 9.0), 0.0, 1.0))
	face_node.rotation.y = face_yaw
	# crouch collision
	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, delta * 6.0)
	capsule.height = lerpf(1.7, 1.15, crouch_blend)
	col.position.y = capsule.height * 0.5
	# footsteps -> Living Traces
	if is_on_floor() and hspeed > 0.8 and dodge_t <= 0.0:
		step_dist += hspeed * delta
		var stride = 2.4 if sprinting else 1.7
		if step_dist > stride:
			step_dist = 0.0
			var r = 3.0 if crouching else (16.0 if sprinting else 8.0)
			if Terrain.inside_complex(global_position):
				r *= 1.35
			Traces.add_trace(global_position, Traces.FOOT, r, 2.2, not Terrain.inside_complex(global_position))
			Assets.play("step", global_position, -16.0 if crouching else -10.0)
	var tn = 0.1
	if hspeed > 0.8:
		tn = 0.25 if crouching else (1.0 if sprinting else 0.55)
	if shoot_recent > 0.2:
		tn = 1.0 if GameState.upgrades["suppressor"] == 0 else 0.5
	noise_level = lerpf(noise_level, tn, delta * 6.0)
	_animate(delta, hspeed)
	_update_camera(delta)
	if hud:
		hud.set_player_state(self)
	GameState.hp = hp
	GameState.ammo = ammo
	GameState.reserve = reserve

func _update_camera(delta):
	var target = global_position
	cam_rig.global_position = cam_rig.global_position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))
	cam_rig.rotation.y = yaw
	pitch_node.rotation.x = pitch
	var py = lerpf(1.55, 1.1, crouch_blend)
	pitch_node.position.y = lerpf(pitch_node.position.y, py, delta * 8.0)
	var scoped = aiming and GameState.upgrades["scope"] > 0
	var tf = 68.0
	if aiming: tf = 40.0 if scoped else 54.0
	cam.fov = lerpf(cam.fov, tf, delta * 9.0)
	arm.spring_length = lerpf(arm.spring_length, 2.0 if aiming else 3.3, delta * 8.0)
	shoulder.position.x = lerpf(shoulder.position.x, 0.62 if aiming else 0.78, delta * 8.0)

# ------------------------------------------------------------ actions
func _try_dodge(dir: Vector3, basis: Basis):
	if dodge_cd > 0.0 or dodge_t > 0.0 or dead:
		return
	dodge_dir = dir.normalized() if dir.length() > 0.1 else (basis * Vector3(0, 0, 1))
	dodge_t = 0.42
	dodge_cd = 0.95
	invuln = 0.4
	reloading = false
	Assets.play("dodge", null, -6.0)
	Traces.add_trace(global_position, Traces.FOOT, 9.0, 1.5, not Terrain.inside_complex(global_position))

func _start_reload():
	if reloading or ammo >= GameState.mag_size() or reserve <= 0 or dodge_t > 0.0:
		return
	reloading = true
	reload_t = GameState.reload_time()
	Assets.play("reload", null, -6.0)

func _finish_reload():
	reloading = false
	var need = GameState.mag_size() - ammo
	var take = mini(need, reserve)
	ammo += take
	reserve -= take

func _interact():
	for a in near:
		if is_instance_valid(a) and a.enabled:
			interact_t = 0.6
			a.activate(self)
			return

func _throw_decoy():
	if GameState.decoys <= 0:
		if hud: hud.toast("No echo decoys left")
		return
	if get_tree().get_nodes_in_group("decoys").size() >= 2:
		if hud: hud.toast("Two decoys already active")
		return
	GameState.decoys -= 1
	throw_t = 0.5
	var d = Decoy.new()
	get_tree().current_scene.add_child(d)
	d.global_position = global_position + Vector3(0, 1.5, 0) + (-cam.global_transform.basis.z) * 0.6
	d.vel = (-cam.global_transform.basis.z) * 13.0 + Vector3.UP * 5.5
	Assets.play("decoy", null, -6.0)

func _spread_deg() -> float:
	var s = 2.4
	if aiming: s = 0.55
	elif crouching: s = 1.5
	if GameState.upgrades["scope"] > 0: s *= 0.7
	if Vector2(velocity.x, velocity.z).length() > 1.0: s += 0.9
	return s

func _assist(from: Vector3, dir: Vector3) -> Vector3:
	var best = null
	var best_a = deg_to_rad(5.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state == Enemy.S.DEAD or e.state == Enemy.S.BURIED:
			continue
		var tp = e.global_position + Vector3(0, e.aim_height, 0)
		var v = tp - from
		if v.length() > 45.0:
			continue
		var a = dir.angle_to(v.normalized())
		if a < best_a:
			best_a = a
			best = v.normalized()
	if best != null:
		return dir.lerp(best, 0.45).normalized()
	return dir

func _shoot():
	fire_cd = 0.14
	ammo -= 1
	shoot_recent = 1.6
	flash_t = 0.045
	recoil = 1.0
	pitch += 0.006
	var from = cam.global_position
	var dir = _assist(from, -cam.global_transform.basis.z)
	var sp = deg_to_rad(_spread_deg())
	dir = (dir + cam.global_transform.basis.x * randf_range(-1, 1) * sp + cam.global_transform.basis.y * randf_range(-1, 1) * sp).normalized()
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(from + dir * 0.4, from + dir * 130.0, 1 | 4)
	q.exclude = [get_rid()]
	var r = space.intersect_ray(q)
	var tgt = from + dir * 130.0
	if not r.is_empty():
		tgt = r["position"]
	var mpos = muzzle.global_position
	var md = (tgt - mpos).normalized()
	var q2 = PhysicsRayQueryParameters3D.create(mpos, mpos + md * 131.0, 1 | 4)
	q2.exclude = [get_rid()]
	var r2 = space.intersect_ray(q2)
	var hitp = mpos + md * 130.0
	if not r2.is_empty():
		hitp = r2["position"]
		var c = r2["collider"]
		if c.has_method("hurt"):
			var dmg = GameState.damage()
			var hs = hitp.y > c.global_position.y + c.head_height
			if hs: dmg *= 1.8
			if GameState.upgrades["coil"] > 0 and c.species == "husk": dmg *= 1.6
			c.hurt(dmg, global_position, hs)
			if hud: hud.hit_marker(hs)
			Assets.play("hit", hitp, -6.0)
		else:
			_impact(hitp, r2["normal"])
	_tracer(mpos, hitp)
	var sup = GameState.upgrades["suppressor"] > 0
	Assets.play("shot_sup" if sup else "shot", null, -4.0)
	Traces.add_trace(global_position, Traces.SHOT, GameState.gunshot_radius(), 3.5)
	if GameState.upgrades["coil"] > 0:
		Traces.add_trace(global_position, Traces.ENERGY, 26.0, 2.0, false)

func _tracer(a: Vector3, b: Vector3):
	var len = a.distance_to(b)
	if len < 0.5:
		return
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, len)
	mi.mesh = bm
	mi.material_override = tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)

func _impact(pos: Vector3, normal: Vector3):
	var p = CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 6
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 50.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9, 0)
	var sm = SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 4
	sm.rings = 2
	p.mesh = sm
	p.material_override = tracer_mat
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)

# ------------------------------------------------------------ procedural animation
func _q(a) -> Quaternion:
	var ax = Vector3(a[0], a[1], a[2])
	if ax.length() < 0.001:
		return Quaternion.IDENTITY
	return Quaternion(ax.normalized(), a[3])

func _animate(delta, hspeed):
	var t = Time.get_ticks_msec() / 1000.0
	anim_t += delta * (2.0 + hspeed * 1.55)
	var run = clampf(hspeed / 6.0, 0.0, 1.0)
	var sw = sin(anim_t * 1.6)
	var tgt = 0.65
	if aiming or shoot_recent > 0.0 or reloading: tgt = 1.0
	elif sprinting: tgt = 0.0
	aim_blend = move_toward(aim_blend, tgt, delta * 5.0)
	var cb = crouch_blend
	var dodging = dodge_t > 0.0
	var sy = AIM["spine_yaw"] * aim_blend
	var br = sin(t * 1.7) * 0.012
	piv["hips"].position.y = hip_base_y - 0.3 * cb + absf(sw) * 0.035 * run - (0.25 if dodging else 0.0)
	piv["spine"].rotation = Vector3(-0.12 * run * (1.0 - aim_blend) - 0.12 * cb + br, sy, 0)
	piv["head"].rotation = Vector3(clampf(pitch, -0.5, 0.6) * 0.55 + 0.1 * cb, -sy, 0)
	var amp = 0.85 * run * (1.0 - 0.5 * cb)
	var tk = 1.2 if dodging else 0.0
	for sd in ["r", "l"]:
		var sgn = 1.0 if sd == "r" else -1.0
		var ph = sw * sgn
		piv["th_" + sd].rotation.x = ph * amp + 0.95 * cb + tk
		piv["kn_" + sd].rotation.x = -(0.5 + 0.5 * sin(anim_t * 1.6 * 1.0 + (0.0 if sd == "r" else PI) + 1.0)) * 1.15 * run - 1.5 * cb - tk * 1.5
	# arms
	var axis = Vector3.RIGHT.rotated(Vector3.UP, -sy)
	var pq = Quaternion(axis, clampf(pitch, -0.7, 0.9) * 0.8 * aim_blend)
	for sd in ["r", "l"]:
		var sgn2 = -1.0 if sd == "r" else 1.0
		var rest_sh = Quaternion(Vector3.RIGHT, sgn2 * sw * 0.75 * run)
		var rest_el = Quaternion(Vector3.RIGHT, 0.25 + 0.35 * run)
		var aim_sh = _q(AIM["sh_" + sd])
		var aim_el = _q(AIM["el_" + sd])
		var qs = pq * rest_sh.slerp(aim_sh, aim_blend)
		var qe = rest_el.slerp(aim_el, aim_blend)
		if sd == "l" and reloading:
			var p = 1.0 - reload_t / maxf(GameState.reload_time(), 0.1)
			qe = Quaternion(Vector3.RIGHT, sin(p * PI) * 0.9) * qe
		if sd == "r" and (interact_t > 0.0):
			qs = Quaternion(Vector3.RIGHT, sin(interact_t / 0.6 * PI) * 1.4) * qs
			qe = Quaternion(Vector3.RIGHT, 0.4) * qe
		if sd == "r" and throw_t > 0.0:
			qs = Quaternion(Vector3.RIGHT, -sin(throw_t / 0.5 * PI) * 1.8 + 0.9 * (throw_t / 0.5)) * qs
		piv["sh_" + sd].quaternion = qs
		piv["el_" + sd].quaternion = qe
	# weapon follows aim, kicks on recoil
	var wp = piv["weapon"]
	var wr = clampf(pitch, -0.7, 0.9) * 0.8 * aim_blend + (1.0 - aim_blend) * 0.65 + recoil * 0.06
	var rz = 0.0
	if reloading:
		rz = sin((1.0 - reload_t / maxf(GameState.reload_time(), 0.1)) * PI) * 0.5
	wp.rotation = Vector3(wr, 0, rz)
	wp.position = weapon_base + Vector3(0, 0, recoil * 0.05)
	# dodge roll flip / secondary motion
	if dodging:
		flip.rotation.x = -(1.0 - dodge_t / 0.42) * TAU
	else:
		flip.rotation.x = lerpf(flip.rotation.x, 0.0, clampf(delta * 20.0, 0.0, 1.0))
		if flip.rotation.x < -0.001:
			flip.rotation.x = 0.0
	piv["scarf"].rotation = Vector3(0.12 + run * 0.75 + sin(t * 5.0) * 0.08, sin(t * 2.1) * 0.12, sin(t * 3.0) * 0.1)
	piv["braid"].rotation = Vector3(0.08 + run * 0.4 + sin(t * 4.0) * 0.07, 0, sin(t * 3.3) * 0.12)
