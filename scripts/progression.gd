extends RefCounted
class_name DiverProgression

# One tuning table for every permanent purchase. Keys are scoped per digger.
# Profile 3: the Workshop is a connected grid (polish P4). The five original
# nodes keep their ids and effects; their links keep every v2 tree valid.
# Profile 4 adds the two specialization nodes at the ends of the grid (P5).
const VERSION = 4
const BONUS = {"frame": 1.08, "cell": 1.06, "mobility": 1.04, "mastery": 1.05, "loader": 1.05, "barrel": 1.06, "servos": 0.12, "plating": 0.2, "magnet": 1.4, "pulse_interval": 5, "pulse_interval_2": 4, "pulse_power": 1.6, "repair_life": 8.0, "repair_life_2": 12.0, "repair_delay": 8.0, "splash_radius": 4.5, "splash_radius_2": 5.2}
# Every digger has their own grid with this layout. `pos` is in grid cells
# (x right, y down). A node can be bought once any linked node is owned;
# START is always buyable. Order lists a valid purchase sequence.
const START = "frame"
const NODES = [
	{"id": "frame", "name": "Reinforced Frame", "cost": 100, "pos": [0, 0], "icon": "heart", "desc": "+8% base Life. Parts still reset each dig."},
	{"id": "mobility", "name": "Lightweight Joints", "cost": 140, "pos": [-2, 0], "icon": "boots", "desc": "+4% running speed."},
	{"id": "salvage", "name": "Salvage Research", "cost": 180, "pos": [2, 0], "icon": "research", "desc": "Add a signature part to this digger's drop pool early."},
	{"id": "plating", "name": "Shock Plating", "cost": 160, "pos": [0, -2], "icon": "shell", "desc": "Stay protected 0.2 s longer after taking a hit."},
	{"id": "servos", "name": "Dash Servos", "cost": 200, "pos": [-2, -2], "icon": "dash", "desc": "Dash recharges 0.12 s sooner."},
	{"id": "barrel", "name": "Tuned Barrel", "cost": 220, "pos": [2, -2], "icon": "lens", "desc": "+6% buster damage."},
	{"id": "ability", "name": "Signature Circuit", "cost": 260, "pos": [2, 2], "icon": "weapon", "desc": "Develop this digger's signature ability."},
	{"id": "magnet", "name": "Scrap Magnet", "cost": 220, "pos": [-2, 2], "icon": "cache", "desc": "Scrap and pickups drift to you from 40% farther away."},
	{"id": "mastery", "name": "Master Mechanic", "cost": 400, "pos": [0, 2], "icon": "wrench", "desc": "+5% attack speed."},
	{"id": "loader", "name": "Quick Loader", "cost": 340, "pos": [-2, 4], "icon": "spring", "desc": "+5% attack speed."},
	{"id": "ability2", "name": "Signature Circuit II", "cost": 480, "pos": [2, 4], "icon": "weapon", "desc": "Strengthen this digger's signature ability."},
	{"id": "cell", "name": "Reserve Cell", "cost": 420, "pos": [0, 4], "icon": "life", "desc": "+6% base Life."},
	{"id": "spec_a", "name": "Specialization", "cost": 600, "pos": [-2, 6], "icon": "spec", "desc": "Unlock a specialization."},
	{"id": "spec_b", "name": "Specialization", "cost": 600, "pos": [2, 6], "icon": "spec", "desc": "Unlock a specialization."}
]
const LINKS = [["frame", "mobility"], ["frame", "salvage"], ["frame", "plating"], ["plating", "servos"], ["plating", "barrel"], ["servos", "mobility"], ["barrel", "salvage"], ["mobility", "magnet"], ["salvage", "ability"], ["magnet", "mastery"], ["ability", "mastery"], ["magnet", "loader"], ["mastery", "cell"], ["ability", "ability2"], ["loader", "cell"], ["ability2", "cell"], ["loader", "spec_a"], ["ability2", "spec_b"]]
const RESEARCH = ["echo", "coil", "ember", "split"]
# Owning a specialization node unlocks it; one is equipped per dig (or none,
# the default loadout). Only the equipped one's effect applies. `key` is what
# combat code checks via DiverPlayer.specialization().
const SPEC_NODES = ["spec_a", "spec_b"]
const SPECS = [
	[{"key": "focus", "name": "Focus Lens", "icon": "lens", "desc": "Each consecutive Pulse hit on the same machine deals +8% more, up to +40%. Switching targets resets it."},
	 {"key": "ricochet", "name": "Ricochet Coil", "icon": "coil", "desc": "Pulse shots that hit a machine bounce once to the nearest other machine within 9 m for 60% damage."}],
	[{"key": "medic", "name": "Field Medic", "icon": "moss", "desc": "After 2 s without taking damage, Roll and teammates within 6 m of her repair 2 Life per second."},
	 {"key": "storm", "name": "Needle Storm", "icon": "needle", "desc": "Holding fire ramps attack speed up to +30%. Every 6th needle on a machine exposes it: +20% damage from everyone for 3 s."}],
	[{"key": "breaker", "name": "Siege Breaker", "icon": "siege", "desc": "Direct hits deal +40% damage and stagger nearby machines for 0.5 s."},
	 {"key": "barrage", "name": "Wide Barrage", "icon": "ember", "desc": "Blasts reach 1.5 m farther, splash for 65% instead of 50% and slow machines for 1.5 s."}],
	[{"key": "demolition", "name": "Demolition Charge", "icon": "split", "desc": "Bombs deal +45% damage, and a further +25% to guardians."},
	 {"key": "runner", "name": "Scrap Runner", "icon": "dash", "desc": "Each dash drops a bomb where you stood. Machines Servbot finishes drop 2 extra scrap."}]
]
const ABILITIES = ["Every fifth Pulse shot deals 60% more damage.", "Dashing repairs 8 Life, once every 8 seconds.", "Siege splash radius expands from 3.5 m to 4.5 m.", "Bomb blast radius expands from 3.5 m to 4.5 m."]
const ABILITIES_2 = ["Every fourth Pulse shot is charged instead of every fifth.", "Dash repairs grow from 8 to 12 Life.", "Siege splash radius grows from 4.5 m to 5.2 m.", "Bomb blast radius grows from 4.5 m to 5.2 m."]
const OLD_GATES = {"ember": 10, "coil": 10, "prism": 25, "echo": 25, "split": 50, "frost": 50, "clover": 50}

static func fresh() -> Dictionary:
	return {"version": VERSION, "revision": 0, "kills": 0, "runs": 0, "wins": 0, "deepest": 0, "discovered": {}, "best_time": 0.0, "zenny": 0, "trees": {}, "legacy_unlocks": []}

static func node(id: String) -> Dictionary:
	for entry in NODES:
		if entry.id == id: return entry
	return {}

static func owned(meta: Dictionary, character: int) -> Array:
	return meta.get("trees", {}).get(str(character), []).duplicate()

static func neighbors(id: String) -> Array:
	var result = []
	for link in LINKS:
		if link[0] == id: result.append(link[1])
		elif link[1] == id: result.append(link[0])
	return result

# Reachable: the start node, or linked to something already owned.
static func reachable(skills: Array, id: String) -> bool:
	if id == START: return true
	for other in neighbors(id):
		if other in skills: return true
	return false

# A valid tree is empty, or a connected set of nodes containing the start.
static func connected(skills: Array) -> bool:
	if skills.is_empty(): return true
	if START not in skills: return false
	var seen = [START]
	var queue = [START]
	while not queue.is_empty():
		for other in neighbors(queue.pop_front()):
			if other in skills and other not in seen:
				seen.append(other)
				queue.append(other)
	return seen.size() == skills.size()

static func can_buy(meta: Dictionary, character: int, id: String) -> bool:
	var entry = node(id)
	if character < 0 or character >= 4 or entry.is_empty(): return false
	var skills = owned(meta, character)
	return id not in skills and int(meta.get("zenny", 0)) >= entry.cost and reachable(skills, id)

static func spec(character: int, id: String) -> Dictionary:
	var index = SPEC_NODES.find(id)
	return SPECS[character][index] if index >= 0 and character >= 0 and character < SPECS.size() else {}

# The specialization a digger may bring into a dig: owned, or none.
static func usable_spec(meta: Dictionary, character: int, id: String) -> String:
	return id if id in SPEC_NODES and id in owned(meta, character) else ""

static func completion(meta: Dictionary, character: int) -> float:
	return float(owned(meta, character).size()) / NODES.size()

static func reward(depth: int, guardians: int, scrap: int) -> int:
	return clampi(depth, 1, 3) * 25 + clampi(guardians, 0, 3) * 60 + clampi(scrap, 0, 1000000) / 5

# Validate before migrating; malformed records must never overwrite a profile.
static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary: return {}
	var result = fresh()
	var version = data.get("version", 1)
	if not number(version) or version < 1 or version > VERSION: return {}
	for key in ["revision", "kills", "runs", "wins", "deepest", "zenny"]:
		var value = data.get(key, 0)
		if not number(value) or value < 0 or value > 100000000 or value != floor(value): return {}
		result[key] = int(value)
	if result.deepest > 3 or result.wins > result.runs: return {}
	var best = data.get("best_time", 0.0)
	if not number(best) or best < 0 or best > 100000000: return {}
	result.best_time = float(best)
	var discoveries = data.get("discovered", {})
	if not discoveries is Dictionary or discoveries.size() > 64: return {}
	for id in discoveries:
		if not id is String or not discoveries[id] is bool: return {}
	result.discovered = discoveries.duplicate()
	var trees = data.get("trees", {})
	if not trees is Dictionary or trees.size() > 4: return {}
	for character in trees:
		if character not in ["0", "1", "2", "3"] or not trees[character] is Array: return {}
		var seen = []
		for id in trees[character]:
			if not id is String or node(id).is_empty() or id in seen: return {}
			seen.append(id)
		if not connected(seen): return {}
		result.trees[character] = seen
	var legacy = data.get("legacy_unlocks", [])
	if not legacy is Array or legacy.size() > OLD_GATES.size(): return {}
	for id in legacy:
		if not id is String or not OLD_GATES.has(id) or id in result.legacy_unlocks: return {}
		result.legacy_unlocks.append(id)
	if int(version) == 1:
		for id in OLD_GATES:
			if result.kills >= OLD_GATES[id] and id not in result.legacy_unlocks: result.legacy_unlocks.append(id)
	return result

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func encode(meta: Dictionary) -> String:
	var body = JSON.stringify(meta)
	return "RD2." + Marshalls.utf8_to_base64(body) + "." + body.sha256_text()

static func decode(code: String) -> Dictionary:
	if code.length() > 32768: return {}
	var chunks = code.strip_edges().split(".")
	if chunks.size() != 3 or chunks[0] != "RD2" or chunks[1].length() % 4 != 0: return {}
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
	if pattern.search(chunks[1]) == null: return {}
	var body = Marshalls.base64_to_utf8(chunks[1])
	if body.sha256_text() != chunks[2] or Marshalls.utf8_to_base64(body) != chunks[1]: return {}
	var parser = JSON.new()
	if parser.parse(body) != OK: return {}
	return validate(parser.data)
