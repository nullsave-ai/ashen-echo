extends Node
# Persistent game state: stats, upgrades, missions, checkpoints, saving, input map, quality.

signal message(text)
signal mission_changed

const SAVE_PATH = "user://ashen_echo_save.json"
const MISSIONS = [
	{"id": "st_terminal", "type": "interact", "text": "Read the research terminal in the main hall", "prompt": "Read terminal",
		"done": "Last log: the team dug beneath the dunes and heard the ground answer back."},
	{"id": "st_gen", "type": "interact", "text": "Restore power at the generator", "prompt": "Start generator",
		"done": "Power restored. A teal pulse rolls east across the dunes."},
	{"id": "se_reach", "type": "reach", "text": "Follow the pulse east to the desert settlement", "radius": 26.0},
	{"id": "se_journal", "type": "interact", "text": "Find the team leader's journal in the domed house", "prompt": "Take journal",
		"done": "The journal sketches a buried gate. Whatever lives there listens for footsteps."},
	{"id": "co_gate", "type": "interact", "text": "Unseal the buried complex gate", "prompt": "Unseal gate",
		"done": "The gate grinds open. Teal light spills across the sand."},
	{"id": "co_core", "type": "interact", "text": "Take a resonance sample from the Echo Core", "prompt": "Take sample",
		"done": "The core screams. Something far to the west answers."},
	{"id": "fr_seal", "type": "interact", "text": "Reach the fracture and seal the Echo Rift", "prompt": "Begin seal",
		"done": "The seal is charging. Hold the line until it completes."},
]

var points = {}            # mission id -> Vector3 (filled by world)
var mission = 0
var hp = 100.0
var ammo = 24
var reserve = 96
var shards = 0
var decoys = 3
var upgrades = {"dmg": 0, "mag": 0, "reload": 0, "suppressor": 0, "coil": 0, "scope": 0, "decoy": 0}
var checkpoint = Vector3.ZERO
var has_checkpoint = false
var killed = []
var quality = 1
var load_requested = false
var finale_done = false

const UPG = {
	"dmg": {"name": "Hardened rounds (+18% damage)", "max": 5, "cost": [20, 35, 55, 80, 110]},
	"mag": {"name": "Extended magazine (+6 rounds)", "max": 4, "cost": [25, 40, 60, 90]},
	"reload": {"name": "Quick-feed rail (-14% reload)", "max": 3, "cost": [25, 45, 70]},
	"suppressor": {"name": "Echo-dampener (gunfire 70% quieter)", "max": 1, "cost": [60]},
	"coil": {"name": "Resonance coil (+60% vs husks, loud energy)", "max": 1, "cost": [90]},
	"scope": {"name": "Ridge scope (tighter aim, zoom)", "max": 1, "cost": [50]},
	"decoy": {"name": "Echo satchel (+2 decoys)", "max": 3, "cost": [30, 50, 80]},
}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()

func damage() -> float: return 18.0 * (1.0 + 0.18 * upgrades["dmg"])
func mag_size() -> int: return 24 + 6 * upgrades["mag"]
func reload_time() -> float: return 1.7 * pow(0.86, upgrades["reload"])
func max_decoys() -> int: return 3 + 2 * upgrades["decoy"]
func gunshot_radius() -> float: return 11.0 if upgrades["suppressor"] > 0 else 38.0

func upgrade_cost(k: String) -> int:
	var lv = upgrades[k]
	if lv >= UPG[k]["max"]:
		return -1
	return UPG[k]["cost"][lv]

func buy(k: String) -> bool:
	var c = upgrade_cost(k)
	if c < 0 or shards < c:
		return false
	shards -= c
	upgrades[k] += 1
	if k == "mag":
		ammo = mag_size()
	if k == "decoy":
		decoys = max_decoys()
	return true

func new_game():
	mission = 0; hp = 100.0; shards = 0; decoys = 3; killed = []; has_checkpoint = false
	upgrades = {"dmg": 0, "mag": 0, "reload": 0, "suppressor": 0, "coil": 0, "scope": 0, "decoy": 0}
	ammo = mag_size(); reserve = 96; finale_done = false
	load_requested = false

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(pos: Vector3):
	var d = {"mission": mission, "hp": hp, "ammo": ammo, "reserve": reserve, "shards": shards, "decoys": decoys,
		"upgrades": upgrades, "cp": [checkpoint.x, checkpoint.y, checkpoint.z], "has_cp": has_checkpoint,
		"killed": killed, "quality": quality, "pos": [pos.x, pos.y, pos.z]}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()

func load_game() -> bool:
	if not has_save():
		return false
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	mission = int(d.get("mission", 0)); hp = float(d.get("hp", 100)); ammo = int(d.get("ammo", 24))
	reserve = int(d.get("reserve", 96)); shards = int(d.get("shards", 0)); decoys = int(d.get("decoys", 3))
	for k in upgrades:
		upgrades[k] = int(d.get("upgrades", {}).get(k, 0))
	var c = d.get("cp", [0, 0, 0])
	checkpoint = Vector3(c[0], c[1], c[2]); has_checkpoint = bool(d.get("has_cp", false))
	killed = d.get("killed", []); quality = int(d.get("quality", 1))
	return true

func _key(action: String, keys: Array):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e = InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)

func _setup_input():
	_key("move_left", [KEY_A, KEY_LEFT]); _key("move_right", [KEY_D, KEY_RIGHT])
	_key("move_forward", [KEY_W, KEY_UP]); _key("move_back", [KEY_S, KEY_DOWN])
	_key("fire", [KEY_F, KEY_J]); _key("aim", [KEY_Q, KEY_K]); _key("reload", [KEY_R])
	_key("dodge", [KEY_SPACE]); _key("interact", [KEY_E]); _key("decoy", [KEY_G])
	_key("crouch", [KEY_C]); _key("sprint", [KEY_SHIFT]); _key("pause", [KEY_ESCAPE])
