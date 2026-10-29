extends Node3D
class_name Decoy
# Echo decoy: thrown, lands, then fakes footsteps / ground thumps / energy pulses to mislead enemies.

var vel = Vector3.ZERO
var landed = false
var life = 9.0
var pulse = 0.0
var n = 0
var model: Node3D

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("decoys")
	model = Assets.build_env("p_decoy", false)
	model.scale = Vector3.ONE * 1.4
	add_child(model)

func _physics_process(delta):
	if not landed:
		vel.y -= 18.0 * delta
		var np = global_position + vel * delta
		var q = PhysicsRayQueryParameters3D.create(global_position, np, 1)
		var r = get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			global_position = r["position"] + r["normal"] * 0.05
			_land()
		elif np.y <= Terrain.height(np.x, np.z) + 0.05:
			global_position = Vector3(np.x, Terrain.height(np.x, np.z) + 0.05, np.z)
			_land()
		else:
			global_position = np
			model.rotate_y(delta * 8.0)
		return
	life -= delta
	pulse -= delta
	var s = 1.0 + 0.25 * sin(life * 14.0)
	model.scale = Vector3.ONE * 1.4 * s
	if pulse <= 0.0:
		pulse = 0.8
		n += 1
		var ground = not Terrain.inside_complex(global_position)
		Traces.add_trace(global_position, Traces.DECOY, 24.0, 1.6, ground)
		Traces.add_trace(global_position, Traces.THUMP, 22.0, 1.4, true, false)
		if n % 2 == 0:
			Traces.add_trace(global_position, Traces.ENERGY, 28.0, 1.5, false, false)
		Assets.play("decoy", global_position, -4.0)
	if life <= 0.0:
		fizzle()

func _land():
	landed = true
	Traces.add_trace(global_position, Traces.THUMP, 26.0, 1.5, true)
	Assets.play("step", global_position, -2.0)

func fizzle():
	Traces.add_trace(global_position, Traces.ENERGY, 20.0, 1.0, false)
	queue_free()
