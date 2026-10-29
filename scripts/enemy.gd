extends CharacterBody3D
class_name Enemy
# Three species react differently to Living Traces.
#  hound    : hears footsteps + gunfire, fast, calls its pack
#  husk     : near-deaf to footsteps, drawn to energy (coil shots, decoy pulses), sight is poor vs crouching
#  burrower : senses ground vibration only (footsteps on sand, decoy thumps), erupts to strike

enum S {PATROL, INVESTIGATE, SEARCH, CHASE, ATTACK, DEAD, BURIED, ERUPT}

# trace type keys: 0 FOOT, 1 SHOT, 2 ENERGY, 3 DECOY, 4 THUMP
const PROF = {
	"hound": {"hp": 60.0, "walk": 2.0, "inv": 5.0, "run": 8.6, "dmg": 11.0, "sight": 24.0, "fov": 115.0, "reach": 1.9, "cd": 0.85,
		"mult": {0: 1.3, 1: 1.0, 2: 0.3, 3: 1.2, 4: 0.4}, "reward": 6, "aim": 0.7, "head": 0.9, "radius": 0.45, "height": 1.1},
	"husk": {"hp": 150.0, "walk": 1.5, "inv": 2.6, "run": 5.2, "dmg": 24.0, "sight": 36.0, "fov": 70.0, "reach": 2.7, "cd": 1.5,
		"mult": {0: 0.45, 1: 0.9, 2: 1.8, 3: 1.3, 4: 0.2}, "reward": 14, "aim": 1.4, "head": 1.65, "radius": 0.5, "height": 2.1},
	"burrower": {"hp": 220.0, "walk": 0.0, "inv": 6.0, "run": 6.5, "dmg": 32.0, "sight": 0.0, "fov": 0.0, "reach": 3.0, "cd": 2.0,
		"mult": {0: 1.7, 1: 0.12, 2: 0.2, 3: 0.5, 4: 2.0}, "reward": 22, "aim": 1.0, "head": 1.6, "radius": 0.7, "height": 2.0},
}

var species = "hound"
var prof = {}
var uid = ""
var hp = 60.0
var state = S.PATROL
var home = Vector3.ZERO
var target = Vector3.ZERO
var last_known = Vector3.ZERO
var player: Player
var model: Node3D
var piv = {}
var alert = 0.0
var timer = 0.0
var cd = 0.0
var sense_t = 0.0
var anim_t = 0.0
var search_pts = []
var los_lost = 0.0
var exposed = 0.0
var stuck_t = 0.0
var last_pos = Vector3.ZERO
var aim_height = 0.7
var head_height = 0.9
var flag: Label3D
var mound: MeshInstance3D
var windup = 0.0
var hit_flash = 0.0
var world_ref = null
var from_trace_decoy = false

func setup(sp: String, pos: Vector3, id: String, pl: Player):
	species = sp
	prof = PROF[sp]
	uid = id
	hp = prof["hp"]
	home = pos
	player = pl
	aim_height = prof["aim"]
	head_height = prof["head"]
	position = pos
	last_pos = pos

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.6
	var cap = CapsuleShape3D.new()
	cap.radius = prof["radius"]
	cap.height = prof["height"]
	var cs = CollisionShape3D.new()
	cs.shape = cap
	cs.position.y = prof["height"] * 0.5
	add_child(cs)
	var m = Assets.build_model(species, true, GameState.quality > 0)
	model = m["root"]
	piv = m["piv"]
	add_child(model)
	flag = Label3D.new()
	flag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flag.no_depth_test = true
	flag.font_size = 96
	flag.outline_size = 16
	flag.pixel_size = 0.006
	flag.position.y = prof["height"] + 0.6
	flag.visible = false
	add_child(flag)
	target = home
	if species == "burrower":
		_bury(true)
	timer = randf() * 3.0

func _bury(instant := false):
	state = S.BURIED
	model.visible = false
	collision_layer = 0
	flag.visible = false
	if mound == null:
		mound = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.9
		sm.height = 0.6
		mound.mesh = sm
		mound.material_override = Assets.mat("sandstone")
		mound.top_level = true
		add_child(mound)
	mound.visible = true

func _erupt():
	state = S.ERUPT
	timer = 0.6
	model.visible = true
	collision_layer = 4
	mound.visible = false
	exposed = 4.5
	Assets.play("eruption", global_position, 2.0)
	Traces.add_trace(global_position, Traces.THUMP, 18.0, 1.0, true, false)

func _set_flag(txt: String, col: Color):
	flag.text = txt
	flag.modulate = col
	flag.visible = txt != ""

func _physics_process(delta):
	if state == S.DEAD:
		return
	var dist = global_position.distance_to(player.global_position)
	if dist > 95.0 and state != S.CHASE:
		model.visible = false if state != S.BURIED else false
		return
	if state != S.BURIED:
		model.visible = true
	cd = maxf(0.0, cd - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	sense_t -= delta
	if sense_t <= 0.0:
		sense_t = 0.16 + randf() * 0.08
		_sense(dist)
	alert = maxf(0.0, alert - delta * 0.18)
	match state:
		S.PATROL: _do_patrol(delta)
		S.INVESTIGATE: _do_investigate(delta)
		S.SEARCH: _do_search(delta)
		S.CHASE: _do_chase(delta, dist)
		S.ATTACK: _do_attack(delta, dist)
		S.BURIED: _do_buried(delta, dist)
		S.ERUPT: _do_erupt(delta, dist)
	if state != S.BURIED:
		_gravity_move(delta)
	_animate(delta)

# ------------------------------------------------------------ perception
func _sense(dist: float):
	# --- hearing (Living Traces)
	var tr = Traces.query(global_position, prof["mult"], species == "burrower")
	if tr != null and state != S.DEAD:
		var i = tr["i"]
		var is_decoy = tr["type"] == Traces.DECOY or tr["type"] == Traces.THUMP
		if state == S.CHASE or state == S.ATTACK or state == S.ERUPT:
			if tr["type"] == Traces.SHOT:
				last_known = player.global_position
		elif i > 0.12:
			if state == S.BURIED:
				target = tr["pos"]
				from_trace_decoy = is_decoy
			elif state != S.INVESTIGATE or i > alert:
				target = tr["pos"]
				from_trace_decoy = is_decoy
				state = S.INVESTIGATE
				timer = 0.0
				alert = maxf(alert, i)
				_set_flag("?", Color(1, 0.85, 0.3))
				if species == "hound":
					Assets.play("growl", global_position, -4.0)
	# --- sight
	var sight = prof["sight"]
	if sight > 0.0 and dist < sight and not player.dead:
		var eye = global_position + Vector3(0, prof["height"] * 0.85, 0)
		var to = player.global_position + Vector3(0, 1.2, 0) - eye
		var fwd = -global_transform.basis.z if model == null else -model.global_transform.basis.z
		var ang = rad_to_deg(fwd.angle_to(Vector3(to.x, 0, to.z).normalized() if to.length() > 0.1 else fwd))
		var in_cone = ang < prof["fov"] * 0.5 or dist < 3.5 or state == S.CHASE
		if in_cone:
			var vis = _los_amount(eye)
			if vis > 0.0:
				vis *= player.visibility()
				if species == "husk" and player.crouching:
					vis *= 0.5
				var gain = vis * (1.2 - dist / sight) * 1.8
				alert = minf(1.5, alert + gain * 0.2)
				last_known = player.global_position
				los_lost = 0.0
				if alert > 0.95 and state != S.CHASE and state != S.ATTACK:
					_start_chase()
				elif alert > 0.35 and state in [S.PATROL, S.SEARCH]:
					state = S.INVESTIGATE
					target = player.global_position
					_set_flag("?", Color(1, 0.85, 0.3))
			elif state == S.CHASE:
				los_lost += 0.2

func _los_amount(eye: Vector3) -> float:
	var space = get_world_3d().direct_space_state
	var hit = 0
	for off in [1.55, 0.9]:
		var q = PhysicsRayQueryParameters3D.create(eye, player.global_position + Vector3(0, off * (0.7 if player.crouching else 1.0), 0), 1)
		if space.intersect_ray(q).is_empty():
			hit += 1
	return hit * 0.5

func _start_chase():
	state = S.CHASE
	los_lost = 0.0
	_set_flag("!", Color(1, 0.25, 0.2))
	Assets.play("growl", global_position, -2.0)
	if species == "hound":
		for e in get_tree().get_nodes_in_group("enemies"):
			if e != self and e.species == "hound" and e.state in [S.PATROL, S.SEARCH] and e.global_position.distance_to(global_position) < 32.0:
				e.target = player.global_position
				e.state = S.INVESTIGATE
				e.alert = 0.6
				e._set_flag("?", Color(1, 0.85, 0.3))

# ------------------------------------------------------------ states
var move_goal = Vector3.ZERO
var move_speed = 0.0
var move_active = false

func _do_patrol(delta):
	_set_flag("", Color.WHITE)
	timer -= delta
	var d = Vector2(global_position.x - target.x, global_position.z - target.z).length()
	if timer <= 0.0 or d < 1.2:
		if d < 1.2 and timer < -0.01:
			pass
		var a = randf() * TAU
		var r = 3.0 + randf() * 9.0
		target = home + Vector3(cos(a) * r, 0, sin(a) * r)
		timer = 5.0 + randf() * 5.0
		if randf() < 0.4:
			move_active = false
			timer = 2.5
			return
	_goto(target, prof["walk"])

func _do_investigate(delta):
	var d = Vector2(global_position.x - target.x, global_position.z - target.z).length()
	if d > 1.8 and timer <= 0.0:
		_goto(target, prof["inv"])
		stuck_t += delta
		if stuck_t > 8.0:
			d = 0.0
	else:
		move_active = false
		if timer <= 0.0:
			timer = 2.2
			_inspect_target()
		timer -= delta
		if timer <= 0.0:
			stuck_t = 0.0
			last_known = target
			_begin_search(target)

func _inspect_target():
	# husks smash decoys; hounds sniff them out
	if from_trace_decoy:
		for dcy in get_tree().get_nodes_in_group("decoys"):
			if dcy.global_position.distance_to(global_position) < 4.0:
				dcy.fizzle()
				break

func _begin_search(c: Vector3):
	state = S.SEARCH
	search_pts.clear()
	for i in 3:
		var a = randf() * TAU
		search_pts.append(c + Vector3(cos(a), 0, sin(a)) * (4.0 + randf() * 5.0))
	timer = 9.0
	_set_flag("?", Color(1, 0.7, 0.2))

func _do_search(delta):
	timer -= delta
	if search_pts.is_empty() or timer <= 0.0:
		state = S.PATROL
		alert = 0.0
		target = home
		timer = 0.0
		return
	var p = search_pts[0]
	if Vector2(global_position.x - p.x, global_position.z - p.z).length() < 1.5:
		search_pts.pop_front()
	else:
		_goto(p, prof["inv"] * 0.7)

func _do_chase(delta, dist):
	if player.dead:
		_begin_search(last_known)
		return
	if species == "burrower":
		return
	var goal = player.global_position if los_lost < 0.6 else last_known
	_goto(goal, prof["run"])
	if dist < prof["reach"] and cd <= 0.0:
		state = S.ATTACK
		windup = 0.4 if species == "hound" else 0.7
		move_active = false
	elif los_lost > 3.5:
		_begin_search(last_known)

func _do_attack(delta, dist):
	move_active = false
	windup -= delta
	_face(player.global_position, delta)
	if windup <= 0.0:
		if dist < prof["reach"] + 0.6:
			player.hurt(prof["dmg"], global_position)
		cd = prof["cd"]
		state = S.CHASE if species != "burrower" else S.ERUPT
		if species == "burrower":
			timer = 0.9

func _do_buried(delta, dist):
	var gy = Terrain.height(global_position.x, global_position.z)
	var tr = Traces.query(global_position, prof["mult"], true)
	if tr != null and tr["i"] > 0.1:
		target = tr["pos"]
	var d = Vector2(global_position.x - target.x, global_position.z - target.z).length()
	if d > 1.5 and Vector2(target.x - home.x, target.z - home.z).length() < 70.0:
		var dir = (target - global_position)
		dir.y = 0.0
		global_position += dir.normalized() * 5.5 * delta
	global_position.y = Terrain.height(global_position.x, global_position.z) - 0.1
	mound.global_position = Vector3(global_position.x, gy + 0.05, global_position.z)
	mound.scale = Vector3(1.0 + sin(anim_t * 3.0) * 0.1, 0.6, 1.0)
	_set_flag("", Color.WHITE)
	# strike when the player (or a thumping decoy) is right above
	if dist < 3.4 and tr != null and tr["type"] != Traces.THUMP and not player.dead:
		_erupt()
	elif tr != null and tr["type"] == Traces.THUMP and d < 2.5:
		_erupt()

func _do_erupt(delta, dist):
	global_position.y = Terrain.height(global_position.x, global_position.z)
	timer -= delta
	exposed -= delta
	_face(player.global_position, delta)
	if timer <= 0.0 and cd <= 0.0 and dist < prof["reach"] + 1.0 and not player.dead:
		state = S.ATTACK
		windup = 0.5
		_set_flag("!", Color(1, 0.25, 0.2))
	if exposed <= 0.0:
		_bury()

# ------------------------------------------------------------ movement
func _goto(p: Vector3, speed: float):
	move_goal = p
	move_speed = speed
	move_active = true

func _face(p: Vector3, delta: float):
	var d = p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-d.x, -d.z), clampf(delta * 8.0, 0.0, 1.0))

func _gravity_move(delta):
	var hv = Vector3.ZERO
	if move_active and state != S.ATTACK:
		var to = move_goal - global_position
		to.y = 0.0
		if to.length() > 0.3:
			var dir = to.normalized()
			dir = _avoid(dir)
			hv = dir * move_speed
			_face(global_position + dir, delta)
	velocity.x = lerpf(velocity.x, hv.x, clampf(delta * 8.0, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, hv.z, clampf(delta * 8.0, 0.0, 1.0))
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 22.0 * delta
	move_and_slide()
	# unstick
	if move_active and hv.length() > 0.5:
		if global_position.distance_to(last_pos) < 0.05:
			stuck_t += delta
		else:
			stuck_t = 0.0
		if stuck_t > 1.4:
			stuck_t = 0.0
			var a = randf() * TAU
			target = global_position + Vector3(cos(a), 0, sin(a)) * 6.0
			move_goal = target
	last_pos = global_position

func _avoid(dir: Vector3) -> Vector3:
	var space = get_world_3d().direct_space_state
	var o = global_position + Vector3(0, 0.6, 0)
	var q = PhysicsRayQueryParameters3D.create(o, o + dir * 2.4, 1)
	if space.intersect_ray(q).is_empty():
		return dir
	for ang in [0.7, -0.7, 1.4, -1.4]:
		var d2 = dir.rotated(Vector3.UP, ang)
		var q2 = PhysicsRayQueryParameters3D.create(o, o + d2 * 2.4, 1)
		if space.intersect_ray(q2).is_empty():
			return d2
	return dir.rotated(Vector3.UP, 2.4)

# ------------------------------------------------------------ damage
func hurt(dmg: float, from_pos := Vector3.ZERO, _hs := false):
	if state == S.DEAD or state == S.BURIED:
		return
	hp -= dmg
	hit_flash = 0.12
	if state in [S.PATROL, S.SEARCH, S.INVESTIGATE]:
		last_known = player.global_position
		_start_chase()
		if species == "burrower":
			state = S.ERUPT
			timer = 0.3
	if hp <= 0.0:
		_die()

func _die():
	state = S.DEAD
	collision_layer = 0
	flag.visible = false
	GameState.killed.append(uid)
	Assets.play("growl", global_position, -8.0)
	var tw = create_tween()
	tw.tween_property(model, "rotation:z", 1.5 if species != "burrower" else 0.0, 0.5)
	tw.parallel().tween_property(model, "position:y", -0.25, 0.5)
	if species == "burrower":
		tw.parallel().tween_property(model, "scale", Vector3(1, 0.1, 1), 0.8)
	if world_ref:
		world_ref.on_enemy_died(self)
	get_tree().create_timer(14.0).timeout.connect(queue_free)

# ------------------------------------------------------------ animation
func _animate(delta):
	anim_t += delta * (2.0 + Vector2(velocity.x, velocity.z).length() * 1.6)
	var sp = clampf(Vector2(velocity.x, velocity.z).length() / prof["run"], 0.0, 1.0)
	var t = Time.get_ticks_msec() / 1000.0
	var s = sin(anim_t * 1.7)
	match species:
		"hound":
			piv["fr"].rotation.x = s * 0.8 * sp
			piv["bl"].rotation.x = s * 0.8 * sp
			piv["fl"].rotation.x = -s * 0.8 * sp
			piv["br"].rotation.x = -s * 0.8 * sp
			piv["body"].position.y = 0.8 + absf(s) * 0.05 * sp
			piv["body"].rotation.x = 0.1 * sp
			piv["head"].rotation.x = 0.55 if state == S.INVESTIGATE else (-0.1 if state == S.CHASE else 0.1 * sin(t * 1.3))
			piv["jaw"].rotation.x = 0.7 if state == S.ATTACK else (0.15 if state == S.CHASE else 0.0)
			piv["tail"].rotation.y = sin(t * 5.0) * 0.4
		"husk":
			piv["th_r"].rotation.x = s * 0.55 * sp
			piv["th_l"].rotation.x = -s * 0.55 * sp
			piv["kn_r"].rotation.x = -maxf(0.0, s) * 0.7 * sp
			piv["kn_l"].rotation.x = -maxf(0.0, -s) * 0.7 * sp
			var atk = 1.0 if state == S.ATTACK else 0.0
			piv["sh_r"].rotation.x = -s * 0.3 * sp + (-2.2 + windup * -1.0) * atk
			piv["sh_l"].rotation.x = s * 0.3 * sp + (-2.0) * atk
			piv["spine"].rotation.x = 0.08 * sp + 0.25 * atk
			piv["head"].rotation.y = sin(t * 0.9) * 0.5 if state == S.PATROL else 0.0
			piv["hips"].position.y = 1.0 + absf(s) * 0.04 * sp
		"burrower":
			for i in 6:
				piv["seg%d" % i].rotation.z = sin(t * 2.2 - i * 0.7) * 0.12
				piv["seg%d" % i].rotation.x = cos(t * 1.7 - i * 0.6) * 0.08
			var open = 0.0 if state != S.ATTACK else 0.5
			piv["head"].rotation.x = sin(t * 3.0) * 0.1 + open
	if hit_flash > 0.0:
		model.scale = Vector3.ONE * (1.0 + hit_flash * 0.25)
	elif species != "burrower" or state != S.DEAD:
		model.scale = model.scale.lerp(Vector3.ONE, clampf(delta * 10.0, 0.0, 1.0))
