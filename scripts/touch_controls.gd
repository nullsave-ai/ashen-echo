extends Control
class_name TouchControls
# Multi-touch HUD controls: floating left stick, right-side look drag, action buttons.

var move = Vector2.ZERO
var look_accum = Vector2.ZERO
var held = {}        # name -> bool (hold buttons)
var queued = {}      # name -> bool (tap buttons)
var touches = {}     # finger index -> role
var stick_origin = Vector2.ZERO
var stick_pos = Vector2.ZERO
var stick_finger = -1
const STICK_R = 82.0

# name : [offset from bottom-right (x, y), radius, label, kind]
const BTN = {
	"fire": [Vector2(-175, -155), 78.0, "FIRE", "hold"],
	"aim": [Vector2(-340, -110), 52.0, "AIM", "tap"],
	"dodge": [Vector2(-105, -330), 48.0, "ROLL", "tap"],
	"reload": [Vector2(-335, -245), 44.0, "RLD", "tap"],
	"interact": [Vector2(-225, -330), 48.0, "USE", "tap"],
	"decoy": [Vector2(-445, -190), 46.0, "ECHO", "tap"],
	"crouch": [Vector2(-105, -455), 42.0, "DUCK", "tap"],
	"pause": [Vector2(-70, 60), 34.0, "II", "tap"],
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

func _bpos(n: String) -> Vector2:
	var sz = get_viewport_rect().size
	if n == "pause":
		return Vector2(sz.x - 70, 60)
	var o = BTN[n][0]
	return Vector2(sz.x + o.x, sz.y + o.y)

func _hit_button(p: Vector2) -> String:
	for n in BTN:
		if p.distance_to(_bpos(n)) < BTN[n][1] * 1.35:
			return n
	return ""

func _handle_touch(finger: int, pos: Vector2, pressed: bool):
	if pressed:
		var b = _hit_button(pos)
		if b != "":
			touches[finger] = "btn:" + b
			if BTN[b][3] == "hold":
				held[b] = true
			else:
				queued[b] = true
		elif pos.x < get_viewport_rect().size.x * 0.45 and stick_finger == -1:
			stick_finger = finger
			stick_origin = pos
			stick_pos = pos
			touches[finger] = "stick"
		else:
			touches[finger] = "look"
	else:
		var role = touches.get(finger, "")
		if role == "stick":
			stick_finger = -1
			move = Vector2.ZERO
		elif role.begins_with("btn:"):
			var n = role.substr(4)
			if BTN[n][3] == "hold":
				held[n] = false
		touches.erase(finger)

func _handle_drag(finger: int, pos: Vector2, rel: Vector2):
	var role = touches.get(finger, "")
	if role == "stick":
		stick_pos = pos
		var v = (stick_pos - stick_origin) / STICK_R
		if v.length() > 1.0:
			v = v.normalized()
			stick_origin = stick_pos - v * STICK_R
		move = v if v.length() > 0.12 else Vector2.ZERO
	elif role == "look":
		look_accum += rel
	elif role == "btn:fire":
		look_accum += rel * 0.75

func _input(event):
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position, event.relative)
	elif event is InputEventMouseButton:
		_handle_touch(0, event.position, event.pressed)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_handle_drag(0, event.position, event.relative)

func _process(delta):
	pulse += delta
	queue_redraw()

func _draw():
	var f = ThemeDB.fallback_font
	var sz = get_viewport_rect().size
	
	# Left Stick (Joystick)
	var base = stick_origin if stick_finger != -1 else Vector2(190, sz.y - 180)
	var knob = stick_pos if stick_finger != -1 else base
	
	# Joystick Base & Outer Ring
	draw_circle(base, STICK_R, Color(0.1, 0.08, 0.07, 0.5))
	draw_arc(base, STICK_R, 0, TAU, 48, Color(0.35, 1.0, 0.92, 0.75), 3.5)
	
	# Joystick Thumb Knob
	draw_circle(knob, 36.0, Color(0.35, 1.0, 0.92, 0.6 if stick_finger != -1 else 0.4))
	draw_arc(knob, 36.0, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.8), 2.0)
	
	if stick_finger == -1:
		draw_string(f, base + Vector2(-STICK_R, 7), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, STICK_R * 2.0, 18, Color(1, 1, 1, 0.65))

	# Action Buttons
	for n in BTN:
		var p = _bpos(n)
		var r = BTN[n][1]
		var active = held.get(n, false)
		var is_fire = (n == "fire")
		var is_use = (n == "interact")
		
		# Base & border colors
		var col = Color(0.35, 1.0, 0.92, 0.95)
		if is_fire:
			col = Color(1.0, 0.45, 0.2, 0.95)
		elif is_use:
			col = Color(1.0, 0.82, 0.3, 0.95) if show_use else Color(0.6, 0.6, 0.6, 0.35)
		
		var bg_col = Color(0.12, 0.08, 0.06, 0.65 if not active else 0.9)
		if active:
			bg_col = col * 0.75
			bg_col.a = 0.85
			
		draw_circle(p, r, bg_col)
		draw_arc(p, r, 0, TAU, 40, col, 4.0 if (active or (is_use and show_use)) else 3.0)
		
		# Inner subtle ring for FIRE button
		if is_fire:
			draw_arc(p, r * 0.75, 0, TAU, 32, Color(1.0, 0.8, 0.4, 0.4), 2.0)
			
		var font_sz = 22 if r > 50 else (18 if r > 40 else 16)
		draw_string(f, p + Vector2(-r, 7), BTN[n][2], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, font_sz, Color(1, 1, 1, 1.0 if not (is_use and not show_use) else 0.5))
