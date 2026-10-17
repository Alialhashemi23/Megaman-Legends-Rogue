extends Node
class_name DiverRunLog

# Device-only playtest notes; never part of a build, account request or relay packet.
# Life lost is sampled after physics, not a hit/damage meter. Healing within the
# same physics tick can hide a loss; reconnect snapshots reset the baseline.
const LIMIT = 20
const EVENT_LIMIT = 512
var game: Node3D
var path = ""
var runs: Array = []
var current: Dictionary = {}
var loaded = false
var dirty = false
var save_clock = 0.0
var last_player = 0
var last_depth = 0
var last_hp = 0.0
var baseline = false
var storage_ok = true

func _ready() -> void:
	process_physics_priority = 10000

func _physics_process(dt: float) -> void:
	if not is_instance_valid(game): return
	if game.in_run() and not game.run_recorded and game.run_id != "":
		observe(dt)
		save_clock += dt
		if dirty and save_clock >= 5.0: persist()
	else: baseline = false

static func number(value: Variant, maximum: float = 100000000.0) -> float:
	return clampf(float(value), 0, maximum) if (value is float or value is int) and is_finite(float(value)) else 0.0

static func clean_build(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var result = {}
	for key in ["character", "weapon", "level", "base_damage", "fire_multiplier", "base_health", "power_picks", "haste_picks"]:
		if value.has(key): result[key] = number(value[key])
	result.spec = str(value.get("spec", "")).left(64)
	for key in ["skills", "milestones"]:
		result[key] = []
		if value.get(key) is Array:
			for id in value[key].slice(0, 32):
				if id is String: result[key].append(id.left(64))
	result.items = {}
	if value.get("items") is Dictionary:
		for id in value.items.keys().slice(0, 64):
			if id is String and number(value.items[id]) > 0: result.items[id.left(64)] = int(number(value.items[id]))
	return result

static func clean_record(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("id") is String or value.id == "": return {}
	var record = {"id":value.id.left(128),"seed":int(number(value.get("seed"))),"character":int(number(value.get("character"),3)),"party":maxi(1,int(number(value.get("party"),4))),"started":number(value.get("started"),4000000000),"seconds":number(value.get("seconds")),"depth":maxi(1,int(number(value.get("depth"),3))),"life_lost":number(value.get("life_lost")),"pick_count":int(number(value.get("pick_count"))),"reroll_count":int(number(value.get("reroll_count"))),"won":bool(value.get("won",false)),"finished":bool(value.get("finished",false)),"interrupted":bool(value.get("interrupted",false)),"guardians":[],"events":[]}
	if value.get("guardians") is Array:
		for row in value.guardians.slice(0,3):
			if not row is Dictionary: continue
			record.guardians.append({"depth":maxi(1,int(number(row.get("depth"),3))),"seconds":number(row.get("seconds")),"life_lost":number(row.get("life_lost")),"defeated":bool(row.get("defeated",false)),"partial":bool(row.get("partial",false)),"build":clean_build(row.get("build"))})
	if value.get("events") is Array:
		for event in value.events.slice(-EVENT_LIMIT):
			if not event is Dictionary or str(event.get("kind","")) not in ["pick","reroll"]: continue
			var row = {"kind":str(event.kind),"offer":str(event.get("offer","")).left(128),"depth":maxi(1,int(number(event.get("depth"),3))),"seconds":number(event.get("seconds")),"choice_kind":str(event.get("choice_kind","")).left(24),"item":str(event.get("item","")).left(64),"cards":[]}
			if event.get("cards") is Array:
				for id in event.cards.slice(0,3):
					if id is String: row.cards.append(id.left(64))
			record.events.append(row)
	return record

func load_notes() -> void:
	if loaded: return
	loaded = true
	if path == "" or not FileAccess.file_exists(path): return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8388608: return
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK: return
	var data = parser.data
	if not data is Dictionary or int(number(data.get("version"))) != 1: return
	if data.get("runs") is Array:
		for entry in data.runs.slice(-LIMIT):
			var record = clean_record(entry)
			if not record.is_empty() and record.finished: runs.append(record)
	current = clean_record(data.get("active"))
	reset_baseline()

func ensure_run() -> void:
	load_notes()
	if current.get("id", "") == game.run_id: return
	if not current.is_empty() and not current.get("finished",false):
		current.finished = true
		current.interrupted = true
		remember_current()
	current = {"id":game.run_id,"seed":game.run_seed,"character":game.selected_character,"party":game.party_size,"started":Time.get_unix_time_from_system(),"seconds":0.0,"depth":game.depth,"life_lost":0.0,"pick_count":0,"reroll_count":0,"won":false,"finished":false,"interrupted":false,"guardians":[],"events":[]}
	baseline = false
	dirty = true

func reset_baseline() -> void:
	baseline = false
	# Time spent offline/away is excluded. Mark an interrupted fight honestly.
	if not current.is_empty():
		for row in current.guardians:
			if not row.defeated: row.partial = true

func guardian_row() -> Dictionary:
	for row in current.get("guardians", []):
		if int(row.depth) == game.depth: return row
	return {}

func observe(dt: float) -> void:
	if not is_instance_valid(game.player) or game.run_id == "": return
	ensure_run()
	if current.finished: return
	var player = game.player
	var running = game.world_running()
	var synced = not game.net.awaiting_run_sync and (not game.net.active() or game.net.connected())
	if not synced:
		reset_baseline()
		return
	var loss = 0.0
	var identity = player.get_instance_id()
	if baseline and identity == last_player and last_depth == game.depth: loss = maxf(0, last_hp - player.hp)
	last_player = identity
	last_depth = game.depth
	last_hp = player.hp
	baseline = true
	current.life_lost += loss
	current.seconds = game.run_time
	current.depth = game.depth
	var row = guardian_row()
	if row.is_empty() and not game.guardian_dead:
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.kind == 3 and not enemy.dead and (enemy.active or enemy.state != "approach" or enemy.health < enemy.max_health):
				row = {"depth":game.depth,"seconds":0.0,"life_lost":0.0,"defeated":false,"partial":enemy.health < enemy.max_health,"build":clean_build(game.build_state())}
				current.guardians.append(row)
				break
	if not row.is_empty() and not row.defeated:
		if running: row.seconds += maxf(0,dt)
		row.life_lost += loss
		if game.guardian_dead: row.defeated = true
	if loss > 0 or (not row.is_empty() and running): dirty = true

func event(kind: String, entry: Dictionary, selected: String = "") -> void:
	if game.run_id == "": return
	observe(0)
	if current.finished: return
	current.events.append({"kind":kind,"offer":str(entry.get("id","")),"depth":int(entry.get("depth",game.depth)),"seconds":game.run_time,"choice_kind":str(entry.get("kind",game.choice_kind)),"item":selected,"cards":(entry.get("items",[]) as Array).duplicate()})
	if current.events.size() > EVENT_LIMIT: current.events.pop_front()
	if kind == "pick": current.pick_count += 1
	else: current.reroll_count += 1
	dirty = true
	persist()

func finish(won: bool) -> void:
	if game.run_id == "": return
	observe(0)
	current.won = won
	current.finished = true
	current.seconds = game.run_time
	current.depth = game.depth
	remember_current()
	dirty = true
	persist()

func remember_current() -> void:
	# Finish/account retry can call this twice. Replace by dig id, never duplicate.
	for i in range(runs.size()-1,-1,-1):
		if runs[i].id == current.id: runs.remove_at(i)
	runs.append(current.duplicate(true))
	if runs.size() > LIMIT: runs = runs.slice(-LIMIT)

func persist() -> void:
	if path == "": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file = FileAccess.open(path + ".tmp",FileAccess.WRITE)
	if file == null:
		storage_ok = false
		return
	file.store_string(JSON.stringify({"version":1,"runs":runs,"active":current if not current.get("finished",false) else {}}))
	file.flush()
	var error = file.get_error()
	file.close()
	storage_ok = error == OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path)) == OK
	if storage_ok:
		dirty = false
		save_clock = 0
		if OS.has_feature("web"): JavaScriptBridge.force_fs_sync()
