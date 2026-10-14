extends RefCounted
class_name DiverProgression

# One tuning table for every permanent purchase. Keys are scoped per digger.
const VERSION = 2
const BONUS = {"frame": 1.08, "mobility": 1.04, "mastery": 1.05, "pulse_interval": 5, "pulse_power": 1.6, "repair_life": 8.0, "repair_delay": 8.0, "splash_radius": 4.5}
const NODES = [
	{"id": "frame", "name": "Reinforced Frame", "cost": 100, "requires": "", "desc": "+8% base Life. Parts still reset each dig."},
	{"id": "mobility", "name": "Lightweight Joints", "cost": 140, "requires": "frame", "desc": "+4% running speed."},
	{"id": "salvage", "name": "Salvage Research", "cost": 180, "requires": "frame", "desc": "Add a signature part to this digger's drop pool early."},
	{"id": "ability", "name": "Signature Circuit", "cost": 260, "requires": "salvage", "desc": "Develop this digger's signature ability."},
	{"id": "mastery", "name": "Master Mechanic", "cost": 400, "requires": "mobility", "desc": "+5% attack speed. Requires Signature Circuit too."}
]
const RESEARCH = ["echo", "coil", "ember", "split"]
const ABILITIES = ["Every fifth Pulse shot deals 60% more damage.", "Dashing repairs 8 Life, once every 8 seconds.", "Siege splash radius expands from 3.5 m to 4.5 m.", "Bomb blast radius expands from 3.5 m to 4.5 m."]
const OLD_GATES = {"ember": 10, "coil": 10, "prism": 25, "echo": 25, "split": 50, "frost": 50, "clover": 50}

static func fresh() -> Dictionary:
	return {"version": VERSION, "revision": 0, "kills": 0, "runs": 0, "wins": 0, "deepest": 0, "discovered": {}, "best_time": 0.0, "zenny": 0, "trees": {}, "legacy_unlocks": []}

static func node(id: String) -> Dictionary:
	for entry in NODES:
		if entry.id == id: return entry
	return {}

static func owned(meta: Dictionary, character: int) -> Array:
	return meta.get("trees", {}).get(str(character), []).duplicate()

static func can_buy(meta: Dictionary, character: int, id: String) -> bool:
	var entry = node(id)
	if character < 0 or character >= 4 or entry.is_empty(): return false
	var skills = owned(meta, character)
	return id not in skills and int(meta.get("zenny", 0)) >= entry.cost and (entry.requires == "" or entry.requires in skills) and (id != "mastery" or "ability" in skills)

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
		for id in seen:
			var entry = node(id)
			if entry.requires != "" and entry.requires not in seen: return {}
			if id == "mastery" and "ability" not in seen: return {}
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
