extends Area3D
class_name Interactable
# World interaction point (mission objective, supply cache, workbench lantern).

signal activated(id)
var id = ""
var prompt = "Use"
var enabled = true
var marker: Node3D
var beam: MeshInstance3D
var t = 0.0

func setup(i: String, p: String, radius := 2.0, with_marker := true, beam_h := 0.0):
	id = i
	prompt = p
	collision_layer = 16
	collision_mask = 0
	monitorable = true
	monitoring = false
	var cs = CollisionShape3D.new()
	var sp = SphereShape3D.new()
	sp.radius = radius
	cs.shape = sp
	add_child(cs)
	if with_marker:
		marker = Assets.build_env("p_shard", false)
		marker.scale = Vector3.ONE * 2.2
		marker.position.y = 1.6
		add_child(marker)
	if beam_h > 0.0:
		beam = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = 0.25
		cm.bottom_radius = 0.4
		cm.height = beam_h
		cm.radial_segments = 8
		beam.mesh = cm
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.3, 1.0, 0.92, 0.28)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = m
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position.y = beam_h * 0.5
		add_child(beam)

func set_active(on: bool):
	enabled = on
	if marker:
		marker.visible = on
	if beam:
		beam.visible = on

func _process(delta):
	t += delta
	if marker and marker.visible:
		marker.rotation.y = t * 1.5
		marker.position.y = 1.6 + sin(t * 2.0) * 0.15

func activate(pl):
	if enabled:
		activated.emit(id)
