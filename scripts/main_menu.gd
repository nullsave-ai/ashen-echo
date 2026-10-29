extends Node3D
# Title screen: slowly turning sculpted protagonist in a painted desert dusk, with Continue / New / Quality.

var hero_root: Node3D
var t = 0.0

func _ready():
	var env = Environment.new()
	var sky = Sky.new()
	var sm = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.42, 0.55)
	sm.sky_horizon_color = Color(1.0, 0.76, 0.5)
	sm.ground_horizon_color = Color(0.93, 0.72, 0.5)
	sm.ground_bottom_color = Color(0.72, 0.5, 0.36)
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.8, 0.78)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 50, 0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	add_child(sun)
	var cam = Camera3D.new()
	cam.position = Vector3(1.2, 1.35, 3.2)
	cam.fov = 38
	add_child(cam)
	cam.look_at(Vector3(0.2, 1.1, 0), Vector3.UP)
	var m = Assets.build_model("hero", true, false)
	hero_root = m["root"]
	add_child(hero_root)
	# idle pose: ready stance
	var aim = RigData.DATA["aim_pose"]
	var piv = m["piv"]
	piv["spine"].rotation.y = aim["spine_yaw"] * 0.7
	piv["head"].rotation.y = -aim["spine_yaw"] * 0.7
	for sd in ["r", "l"]:
		var a = aim["sh_" + sd]
		var b = aim["el_" + sd]
		piv["sh_" + sd].quaternion = Quaternion(Vector3(a[0], a[1], a[2]).normalized(), a[3]) if Vector3(a[0], a[1], a[2]).length() > 0.01 else Quaternion.IDENTITY
		piv["el_" + sd].quaternion = Quaternion(Vector3(b[0], b[1], b[2]).normalized(), b[3]) if Vector3(b[0], b[1], b[2]).length() > 0.01 else Quaternion.IDENTITY
	piv["weapon"].rotation.x = 0.0
	# painted ground disc
	var d = Assets.build_env("p_lantern", false)
	d.position = Vector3(-1.6, 0, -0.8)
	add_child(d)
	var ground = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 6.0
	cm.height = 0.1
	ground.mesh = cm
	var gm = StandardMaterial3D.new()
	gm.albedo_color = Color(0.95, 0.8, 0.55)
	ground.material_override = gm
	ground.position.y = -0.05
	add_child(ground)
	_ui()

func _ui():
	var cl = CanvasLayer.new()
	add_child(cl)
	var title = Label.new()
	title.text = "ASHEN ECHO"
	title.position = Vector2(60, 70)
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.05))
	title.add_theme_constant_override("outline_size", 14)
	cl.add_child(title)
	var ar = Label.new()
	ar.text = "صَدَى الرماد"
	ar.position = Vector2(66, 175)
	ar.add_theme_font_size_override("font_size", 52)
	ar.add_theme_color_override("font_color", Color(0.45, 1.0, 0.92))
	ar.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.1))
	ar.add_theme_constant_override("outline_size", 10)
	cl.add_child(ar)
	var box = VBoxContainer.new()
	box.position = Vector2(66, 310)
	box.add_theme_constant_override("separation", 14)
	cl.add_child(box)
	if GameState.has_save():
		box.add_child(_btn("CONTINUE", func():
			GameState.load_requested = true
			get_tree().change_scene_to_file("res://scenes/game.tscn")))
	box.add_child(_btn("NEW EXPEDITION", func():
		GameState.load_requested = false
		get_tree().change_scene_to_file("res://scenes/game.tscn")))
	var q = _btn("", func(): pass)
	q.text = "GRAPHICS: " + ["LOW", "MEDIUM", "HIGH"][GameState.quality]
	q.pressed.connect(func():
		GameState.quality = (GameState.quality + 1) % 3
		q.text = "GRAPHICS: " + ["LOW", "MEDIUM", "HIGH"][GameState.quality])
	box.add_child(q)

func _btn(text: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 80)
	b.add_theme_font_size_override("font_size", 32)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.06, 0.85)
	sb.border_color = Color(0.35, 1.0, 0.92)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	b.add_theme_stylebox_override("normal", sb)
	var sb_pressed = sb.duplicate()
	sb_pressed.bg_color = Color(0.2, 0.6, 0.55, 0.95)
	b.add_theme_stylebox_override("pressed", sb_pressed)
	b.add_theme_stylebox_override("hover", sb)
	b.pressed.connect(cb)
	# Direct touch handler fallback for mobile screens
	b.gui_input.connect(func(ev):
		if ev is InputEventScreenTouch and ev.pressed:
			cb.call())
	return b

func _process(delta):
	t += delta
	hero_root.rotation.y = -0.5 + sin(t * 0.4) * 0.5
