extends Control
class_name TouchControls
# Fixed Console-Style Virtual Joystick & Non-Overlapping Action Buttons for Mobile

var move = Vector2.ZERO
var look_accum = Vector2.ZERO
var held = {}        # name -> bool (hold buttons)
var queued = {}      # name -> bool (tap buttons)
var touches = {}     # finger index -> role

# Fixed Joystick ("الكير") Configuration
const STICK_BASE_OFFSET = Vector2(195, -185) # Offset from bottom-left
const STICK_R = 86.0
const KNOB_R = 40.0
const DEADZONE = 0.08
var stick_finger = -1
var stick_knob = Vector2.ZERO

# Right-Side Action Buttons (offset from bottom-right, radius, label, type)
# Perfectly spaced to guarantee ZERO overlapping hitboxes!
const BTN = {
	"fire": [Vector2(-140, -140), 70.0, "FIRE", "hold"],
	"aim": [Vector2(-285, -110), 50.0, "AIM", "tap"],
	"dodge": [Vector2(-90, -275), 48.0, "ROLL", "tap"],
	"reload": [Vector2(-270, -225), 44.0, "RLD", "tap"],
	"interact": [Vector2(-180, -320), 46.0, "USE", "tap"],
	"decoy": [Vector2(-285, -345), 44.0, "ECHO", "tap"],
	"crouch": [Vector2(-80, -405), 42.0, "DUCK", "tap"],
	"pause": [Vector2(-65, 55), 34.0, "II", "tap"],
}

var pulse = 0.0
var show_use = false

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func btn(n: String) -> bool:
	return held.get(n, false)

func consume(n: String) -> bool:
	if queued.get(n, false):
		queued[n] = false
		return true
	return false

func consume_look() -> Vector2:
	var v = look_accum
	look_accum = Vector2.ZERO
	return v

func get_stick_base() -> Vector2:
	var sz = get_viewport_rect().size
	return Vector2(STICK_BASE_OFFSET.x, sz.y + STICK_BASE_OFFSET.y)

func _sprint_pos() -> Vector2:
	var sb = get_stick_base()
	return Vector2(sb.x, sb.y - STICK_R - 55.0)

func _bpos(n: String) -> Vector2:
	var sz = get_viewport_rect().size
	if n == "pause":
		return Vector2(sz.x - 65, 55)
	var o = BTN[n][0]
	return Vector2(sz.x + o.x, sz.y + o.y)

func _hit_button(p: Vector2) -> String:
	var closest_btn = ""
	var min_dist = 999999.0
	for n in BTN:
		var bp = _bpos(n)
		var r = BTN[n][1]
		var d = p.distance_to(bp)
		if d < r * 1.15 and d < min_dist:
			min_dist = d
			closest_btn = n
	return closest_btn

func _update_stick(pos: Vector2):
	var sb = get_stick_base()
	var diff = pos - sb
	var dist = diff.length()
	if dist > STICK_R:
		stick_knob = sb + diff.normalized() * STICK_R
	else:
		stick_knob = pos
	
	var norm = (stick_knob - sb) / STICK_R
	if norm.length() > DEADZONE:
		move = norm
	else:
		move = Vector2.ZERO

func _handle_touch(finger: int, pos: Vector2, pressed: bool):
	if pressed:
		# 1. Action buttons on the right
		var b = _hit_button(pos)
		if b != "":
			touches[finger] = "btn:" + b
			if BTN[b][3] == "hold":
				held[b] = true
			else:
				queued[b] = true
			return
		
		# 2. SPRINT button above the joystick
		if pos.distance_to(_sprint_pos()) < 48.0:
			touches[finger] = "btn:sprint"
			held["sprint"] = not held.get("sprint", false)
			return
		
		# 3. Movement Joystick ("الكير") zone (Left side of screen)
		var sb = get_stick_base()
		var sz = get_viewport_rect().size
		if (pos.x < sz.x * 0.44 and pos.y > sz.y * 0.32) or pos.distance_to(sb) < STICK_R * 1.8:
			if stick_finger == -1:
				stick_finger = finger
				touches[finger] = "stick"
				_update_stick(pos)
				return
		
		# 4. Camera Swipe / Look (Any touch on right side outside buttons)
		touches[finger] = "look"
	else:
		var role = touches.get(finger, "")
		if role == "stick":
			stick_finger = -1
			stick_knob = get_stick_base()
			move = Vector2.ZERO
		elif role == "btn:sprint":
			pass # Keep sprint state toggled
		elif role.begins_with("btn:"):
			var n = role.substr(4)
			if BTN.has(n) and BTN[n][3] == "hold":
				held[n] = false
		touches.erase(finger)

func _handle_drag(finger: int, pos: Vector2, rel: Vector2):
	var role = touches.get(finger, "")
	if role == "stick":
		_update_stick(pos)
	elif role == "look":
		look_accum += rel
	elif role == "btn:fire":
		look_accum += rel * 0.75

func _input(event):
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position, event.relative)
	elif event is InputEventMouseButton and not event.is_emulated():
		_handle_touch(0, event.position, event.pressed)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and not event.is_emulated():
		_handle_drag(0, event.position, event.relative)

func _process(delta):
	pulse += delta
	queue_redraw()

func _draw():
	var f = ThemeDB.fallback_font
	var sb = get_stick_base()
	var sk = stick_knob if stick_finger != -1 else sb
	
	# -------------------------------------------------------------
	# 1. FIXED JOYSTICK ("الكير")
	# -------------------------------------------------------------
	# Outer background plate
	draw_circle(sb, STICK_R + 6.0, Color(0.06, 0.05, 0.04, 0.6))
	draw_circle(sb, STICK_R, Color(0.12, 0.09, 0.07, 0.75))
	draw_arc(sb, STICK_R, 0, TAU, 48, Color(0.35, 1.0, 0.92, 0.85), 3.5)
	
	# Directional notches on the ring (Up, Down, Left, Right)
	for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir_v = Vector2(cos(ang), sin(ang))
		draw_line(sb + dir_v * (STICK_R - 14), sb + dir_v * (STICK_R + 4), Color(0.35, 1.0, 0.92, 0.95), 3.0)
	
	# Connective laser beam from base center to knob when pushed
	if stick_finger != -1 and (sk - sb).length() > 6.0:
		draw_line(sb, sk, Color(0.35, 1.0, 0.92, 0.6), 5.0)
	
	# Thumb Knob ("الكير")
	var knob_active = (stick_finger != -1)
	draw_circle(sk, KNOB_R, Color(0.10, 0.20, 0.22, 0.9 if knob_active else 0.7))
	draw_circle(sk, KNOB_R * 0.65, Color(0.35, 1.0, 0.92, 0.8 if knob_active else 0.5))
	draw_arc(sk, KNOB_R, 0, TAU, 36, Color(1.0, 1.0, 1.0, 0.95 if knob_active else 0.75), 2.5)
	
	if stick_finger == -1:
		draw_string(f, sb + Vector2(-STICK_R, 7), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, STICK_R * 2.0, 18, Color(1, 1, 1, 0.85))

	# -------------------------------------------------------------
	# 2. SPRINT (RUN) BUTTON
	# -------------------------------------------------------------
	var sp = _sprint_pos()
	var sprint_active = held.get("sprint", false) or (move.length() > 0.88)
	var sp_col = Color(1.0, 0.75, 0.2, 0.95) if sprint_active else Color(0.35, 1.0, 0.92, 0.75)
	draw_circle(sp, 36.0, Color(0.12, 0.08, 0.06, 0.75 if not sprint_active else 0.95))
	draw_arc(sp, 36.0, 0, TAU, 32, sp_col, 3.5)
	draw_string(f, sp + Vector2(-36, 6), "RUN", HORIZONTAL_ALIGNMENT_CENTER, 72.0, 16, Color(1, 1, 1, 1.0))

	# -------------------------------------------------------------
	# 3. ACTION BUTTONS (Right Side)
	# -------------------------------------------------------------
	for n in BTN:
		var p = _bpos(n)
		var r = BTN[n][1]
		var active = held.get(n, false)
		var is_fire = (n == "fire")
		var is_use = (n == "interact")
		
		var col = Color(0.35, 1.0, 0.92, 0.95)
		if is_fire:
			col = Color(1.0, 0.45, 0.2, 0.95)
		elif is_use:
			col = Color(1.0, 0.82, 0.3, 0.95) if show_use else Color(0.55, 0.55, 0.55, 0.4)
		
		var bg_col = Color(0.12, 0.08, 0.06, 0.65 if not active else 0.9)
		if active:
			bg_col = col * 0.75
			bg_col.a = 0.9
			
		draw_circle(p, r, bg_col)
		draw_arc(p, r, 0, TAU, 40, col, 4.0 if (active or (is_use and show_use)) else 3.0)
		
		if is_fire:
			draw_arc(p, r * 0.72, 0, TAU, 32, Color(1.0, 0.8, 0.4, 0.45), 2.0)
			
		var font_sz = 22 if r > 50 else (18 if r > 40 else 16)
		draw_string(f, p + Vector2(-r, 7), BTN[n][2], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, font_sz, Color(1, 1, 1, 1.0 if not (is_use and not show_use) else 0.5))
