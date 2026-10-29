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
const STICK_R = 78.0
# name : [offset from bottom-right (x, y), radius, label, kind]
const BTN = {
	"fire": [Vector2(-170, -150), 74.0, "FIRE", "hold"],
	"aim": [Vector2(-335, -105), 48.0, "AIM", "tap"],
	"dodge": [Vector2(-95, -325), 46.0, "ROLL", "tap"],
	"reload": [Vector2(-330, -245), 40.0, "RLD", "tap"],
	"interact": [Vector2(-215, -330), 44.0, "USE", "tap"],
	"decoy": [Vector2(-445, -190), 42.0, "ECHO", "tap"],
	"crouch": [Vector2(-95, -450), 38.0, "DUCK", "tap"],
	"pause": [Vector2(-60, -672), 30.0, "II", "tap"],
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
	var o = BTN[n][0]
	return Vector2(sz.x + o.x, sz.y + o.y + (0.0 if n != "pause" else 0.0))

func _hit_button(p: Vector2) -> String:
	for n in BTN:
		if p.distance_to(_bpos(n)) < BTN[n][1] * 1.2:
			return n
	return ""

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			var b = _hit_button(event.position)
			if b != "":
				touches[event.index] = "btn:" + b
				if BTN[b][3] == "hold":
					held[b] = true
				else:
					queued[b] = true
			elif event.position.x < get_viewport_rect().size.x * 0.42 and stick_finger == -1:
				stick_finger = event.index
				stick_origin = event.position
				stick_pos = event.position
				touches[event.index] = "stick"
			else:
				touches[event.index] = "look"
		else:
			var role = touches.get(event.index, "")
			if role == "stick":
				stick_finger = -1
				move = Vector2.ZERO
			elif role.begins_with("btn:"):
				var n = role.substr(4)
				if BTN[n][3] == "hold":
					held[n] = false
			touches.erase(event.index)
	elif event is InputEventScreenDrag:
		var role = touches.get(event.index, "")
		if role == "stick":
			stick_pos = event.position
			var v = (stick_pos - stick_origin) / STICK_R
			if v.length() > 1.0:
				v = v.normalized()
				stick_origin = stick_pos - v * STICK_R   # floating base follows the thumb
			move = v if v.length() > 0.12 else Vector2.ZERO
		elif role == "look":
			look_accum += event.relative

func _process(delta):
	pulse += delta
	queue_redraw()

func _draw():
	var f = ThemeDB.fallback_font
	var base = stick_origin if stick_finger != -1 else Vector2(190, get_viewport_rect().size.y - 170)
	var knob = stick_pos if stick_finger != -1 else base
	draw_circle(base, STICK_R, Color(0.95, 0.8, 0.5, 0.12))
	draw_arc(base, STICK_R, 0, TAU, 40, Color(0.35, 1.0, 0.92, 0.5), 3.0)
	draw_circle(knob, 34.0, Color(0.35, 1.0, 0.92, 0.35))
	for n in BTN:
		var p = _bpos(n)
		var r = BTN[n][1]
		var active = held.get(n, false)
		var col = Color(0.35, 1.0, 0.92, 0.85) if n != "fire" else Color(1.0, 0.6, 0.3, 0.9)
		if n == "interact" and not show_use:
			col.a = 0.3
		draw_circle(p, r, Color(0.12, 0.08, 0.06, 0.45 if not active else 0.7))
		draw_arc(p, r, 0, TAU, 36, col, 3.0)
		draw_string(f, p + Vector2(-r, 7), BTN[n][2], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20 if r > 40 else 16, Color(1, 0.95, 0.85, 0.95))
