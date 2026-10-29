extends CanvasLayer
class_name Hud

signal resume_pressed
signal save_pressed
signal quality_pressed
signal menu_pressed
signal bought

var root: Control
var hp_fill: ColorRect
var noise_fill: ColorRect
var stats: Label
var objective: Label
var prompt: Label
var toast_l: Label
var flash: ColorRect
var cross: Control
var hit: Label
var panel: PanelContainer
var upg_box: VBoxContainer
var shard_l: Label
var qual_btn: Button
var death_l: Label
var center_l: Label
var toast_t = 0.0
var hit_t = 0.0
var upg_btns = {}
var show_prompt_text = ""

func _ready():
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	flash = _rect(Color(0.8, 0.05, 0.02, 0.0), Vector2.ZERO, Vector2(2400, 1400))
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	# health
	_rect(Color(0, 0, 0, 0.5), Vector2(24, 22), Vector2(284, 22))
	hp_fill = _rect(Color(0.9, 0.35, 0.25), Vector2(26, 24), Vector2(280, 18))
	_rect(Color(0, 0, 0, 0.4), Vector2(24, 50), Vector2(140, 10))
	noise_fill = _rect(Color(0.4, 1.0, 0.9), Vector2(25, 51), Vector2(2, 8))
	var nl = _label("NOISE", Vector2(170, 44), 14)
	nl.modulate = Color(0.4, 1.0, 0.9, 0.8)
	stats = _label("", Vector2(24, 66), 22)
	objective = _label("", Vector2(0, 14), 22)
	objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective.size = Vector2(700, 60)
	objective.position = Vector2(290, 14)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt = _label("", Vector2(440, 520), 26)
	prompt.size = Vector2(400, 40)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.modulate = Color(0.5, 1.0, 0.95)
	toast_l = _label("", Vector2(340, 110), 24)
	toast_l.size = Vector2(600, 80)
	toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	center_l = _label("", Vector2(240, 250), 40)
	center_l.size = Vector2(800, 140)
	center_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	cross = Control.new()
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross)
	root.add_child(cross)
	hit = _label("x", Vector2(0, 0), 36)
	hit.set_anchors_preset(Control.PRESET_CENTER)
	hit.position = Vector2(-10, -22)
	hit.visible = false
	death_l = _label("SIGNAL LOST", Vector2(380, 280), 56)
	death_l.modulate = Color(1, 0.4, 0.3)
	death_l.visible = false
	_build_menu()

func _rect(c: Color, p: Vector2, s: Vector2) -> ColorRect:
	var r = ColorRect.new()
	r.color = c
	r.position = p
	r.size = s
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r

func _label(t: String, p: Vector2, sz: int) -> Label:
	var l = Label.new()
	l.text = t
	l.position = p
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(1, 0.93, 0.78))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.04))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l

func _draw_cross():
	var c = Color(0.5, 1.0, 0.95, 0.8)
	for a in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		cross.draw_line(a * 7.0, a * 15.0, c, 2.0)
	cross.draw_circle(Vector2.ZERO, 1.8, c)

func _build_menu():
	panel = PanelContainer.new()
	panel.visible = false
	panel.position = Vector2(250, 40)
	panel.size = Vector2(780, 640)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.06, 0.92)
	sb.border_color = Color(0.35, 1.0, 0.92)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title = Label.new()
	title.text = "FIELD WORKBENCH"
	title.add_theme_font_size_override("font_size", 30)
	v.add_child(title)
	shard_l = Label.new()
	shard_l.add_theme_font_size_override("font_size", 22)
	v.add_child(shard_l)
	for k in GameState.UPG:
		var b = Button.new()
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_buy.bind(k))
		v.add_child(b)
		upg_btns[k] = b
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	for pair in [["Resume", "resume"], ["Save", "save"], ["Quality", "quality"], ["Main menu", "menu"]]:
		var b = Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(160, 60)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_menu_btn.bind(pair[1]))
		h.add_child(b)
		if pair[1] == "quality":
			qual_btn = b

func _menu_btn(w: String):
	match w:
		"resume": resume_pressed.emit()
		"save": save_pressed.emit()
		"quality": quality_pressed.emit()
		"menu": menu_pressed.emit()

func _buy(k: String):
	if GameState.buy(k):
		Assets.play("pickup", null, -6.0)
		bought.emit()
	refresh_menu()

func refresh_menu():
	shard_l.text = "Shards: %d     (ammo and decoys refill at lanterns)" % GameState.shards
	for k in GameState.UPG:
		var c = GameState.upgrade_cost(k)
		var lv = GameState.upgrades[k]
		var b = upg_btns[k]
		if c < 0:
			b.text = "%s   [MAX]" % GameState.UPG[k]["name"]
			b.disabled = true
		else:
			b.text = "%s   Lv%d  -  %d shards" % [GameState.UPG[k]["name"], lv, c]
			b.disabled = GameState.shards < c
	qual_btn.text = "Quality: " + ["Low", "Medium", "High"][GameState.quality]

func open_menu(on: bool):
	panel.visible = on
	if on:
		refresh_menu()

# ------------------------------------------------------------ live updates
func set_player_state(p):
	hp_fill.size.x = 280.0 * clampf(p.hp / 100.0, 0.0, 1.0)
	noise_fill.size.x = maxf(2.0, 138.0 * p.noise_level)
	noise_fill.color = Color(0.4, 1.0, 0.9).lerp(Color(1.0, 0.4, 0.25), clampf(p.noise_level, 0.0, 1.0))
	var rl = "  RELOADING" if p.reloading else ""
	stats.text = "AMMO %d / %d%s     ECHO x%d     SHARDS %d" % [p.ammo, p.reserve, rl, GameState.decoys, GameState.shards]

func set_objective(text: String, dist: float):
	objective.text = text if dist < 0.0 else "%s  -  %d m" % [text, int(dist)]

func set_prompt(text: String):
	prompt.text = text

func toast(t: String, secs := 3.2):
	toast_l.text = t
	toast_t = secs

func damage_flash():
	flash.color.a = 0.45

func hit_marker(hs: bool):
	hit.visible = true
	hit.modulate = Color(1, 0.3, 0.2) if hs else Color(1, 1, 1)
	hit_t = 0.12

func show_death(on: bool):
	death_l.visible = on

func big_text(t: String):
	center_l.text = t

func _process(delta):
	toast_t -= delta
	if toast_t <= 0.0:
		toast_l.text = ""
	hit_t -= delta
	if hit_t <= 0.0:
		hit.visible = false
	flash.color.a = maxf(0.0, flash.color.a - delta * 1.4)
