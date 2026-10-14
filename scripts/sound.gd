extends Node
class_name DiverSound

const MUSIC_NAMES = ["title", "tidal", "garden", "core", "guardian", "clear", "lost"]
const EFFECT_NAMES = ["shot_0", "shot_1", "shot_2", "hit_0", "hit_1", "hit_2", "step_0", "step_1", "step_2", "needle", "siege", "loot", "scrap", "health", "hurt", "dash", "jump", "land", "level", "enemy", "door", "win", "warning", "slam", "destroy", "guardian_down", "menu_move", "menu_confirm", "lock"]
const LEVELS = {"shot": -5.0, "needle": -6.0, "siege": -3.5, "hit": -7.0, "step": -9.0, "scrap": -10.0, "loot": -5.0, "health": -6.0, "hurt": -4.0, "warning": -2.0, "slam": -3.0, "enemy": -7.0, "destroy": -7.0, "guardian_down": -2.0, "menu_move": -7.0, "menu_confirm": -6.0, "lock": -6.0}
const SETTINGS_PATH = "res://save/audio.json"
var streams: Dictionary = {}
var tracks: Dictionary = {}
var volumes = {"Master": 0.85, "Music": 0.65, "Effects": 0.85, "Ambience": 0.6}
var muted = false:
	set(value):
		muted = value
		if initialized:
			apply_volumes()
			save_settings()
var initialized = false
var ambience: AudioStreamPlayer
var music_players: Array[AudioStreamPlayer] = []
var music_gains = [0.0, 0.0]
var active_music = 0
var current_cue = ""
var retained_cue = "tidal"
var live_voices: Array[Node] = []
var last_played: Dictionary = {}
var clock = 0.0
var rng = RandomNumberGenerator.new()
var settings_path = SETTINGS_PATH

func _ready() -> void:
	rng.seed = 90317
	settings_path = DiverPaths.pick(SETTINGS_PATH, "user://audio.json")
	setup_buses()
	load_settings()
	for kind in EFFECT_NAMES:
		streams[kind] = load("res://assets/audio/sfx/%s.wav" % kind)
	for cue in MUSIC_NAMES:
		var stream: AudioStreamOggVorbis = load("res://assets/audio/music/%s.ogg" % cue)
		stream.loop = cue not in ["clear", "lost"]
		tracks[cue] = stream
	for i in 2:
		var player = AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -60
		add_child(player)
		music_players.append(player)
	ambience = AudioStreamPlayer.new()
	ambience.bus = "Ambience"
	ambience.volume_db = -60
	var air: AudioStreamOggVorbis = load("res://assets/audio/ambience/ruin_air.ogg")
	air.loop = true
	ambience.stream = air
	add_child(ambience)
	initialized = true
	apply_volumes()

func setup_buses() -> void:
	for bus in ["Music", "Effects", "Ambience", "Menu"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	if not AudioServer.get_bus_effect_count(0):
		var limiter = AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(0, limiter)
	var effects_index = AudioServer.get_bus_index("Effects")
	if not AudioServer.get_bus_effect_count(effects_index):
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.5
		reverb.wet = 0.12
		reverb.dry = 0.93
		AudioServer.add_bus_effect(effects_index, reverb)

func apply_volumes() -> void:
	for bus in volumes:
		var level = float(volumes[bus])
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(0.00001, level)))
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), level <= 0 or (bus == "Master" and muted))
	var menu_index = AudioServer.get_bus_index("Menu")
	AudioServer.set_bus_volume_db(menu_index, linear_to_db(maxf(0.00001, volumes.Effects)))
	AudioServer.set_bus_mute(menu_index, volumes.Effects <= 0)

func adjust_volume(bus: String, amount: float) -> void:
	if not volumes.has(bus): return
	volumes[bus] = clampf(snappedf(float(volumes[bus]) + amount, 0.05), 0, 1)
	apply_volumes()
	save_settings()

func load_settings() -> void:
	if not FileAccess.file_exists(settings_path): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if not parsed is Dictionary: return
	var levels = parsed.get("volumes", {})
	if levels is Dictionary:
		for bus in volumes:
			if levels.get(bus) is float or levels.get(bus) is int:
				volumes[bus] = clampf(float(levels[bus]), 0, 1)
	muted = parsed.get("muted", false) == true

func save_settings() -> void:
	if DisplayServer.get_name() == "headless" or get_parent().smoke_test: return
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	var file = FileAccess.open(settings_path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"volumes": volumes, "muted": muted}, "\t"))

func desired_cue() -> String:
	var game = get_parent()
	if game.mode in ["title", "archive", "online", "lobby"]: return "title"
	if game.mode == "end": return "clear" if game.outcome else "lost"
	if game.mode in ["pause", "options", "controls", "inventory", "choice"]: return retained_cue
	if not game.guardian_dead:
		for enemy in game.enemies:
			if is_instance_valid(enemy) and not enemy.dead and enemy.kind == 3 and enemy.active and enemy.room_id == game.current_room:
				return "guardian"
	return ["tidal", "garden", "core"][clampi(game.depth - 1, 0, 2)]

func change_music(cue: String) -> void:
	if cue == current_cue or not tracks.has(cue): return
	current_cue = cue
	if cue not in ["title", "clear", "lost"]: retained_cue = cue
	active_music = 1 - active_music
	var player = music_players[active_music]
	player.stop()
	player.stream = tracks[cue]
	music_gains[active_music] = 0.0
	player.volume_db = -60
	player.play()

func _process(dt: float) -> void:
	clock += dt
	if DisplayServer.get_name() == "headless" or get_parent().smoke_test: return
	change_music(desired_cue())
	var duck = get_parent().mode in ["pause", "options", "controls", "inventory", "choice"]
	for i in 2:
		music_gains[i] = move_toward(music_gains[i], (0.42 if duck else 1.0) if i == active_music else 0.0, dt * 0.85)
		music_players[i].volume_db = linear_to_db(maxf(0.0001, music_gains[i])) - 6
		if i != active_music and music_gains[i] <= 0: music_players[i].stop()
	var ambient_target = -27.0 if get_parent().mode in ["title", "archive", "end", "online", "lobby"] else -16.0 if duck else -9.0
	ambience.volume_db = move_toward(ambience.volume_db, ambient_target, dt * 14)
	if not ambience.playing: ambience.play()

func play(kind: String, pitch: float = 1.0, at = null) -> void:
	if muted or get_parent().smoke_test or DisplayServer.get_name() == "headless": return
	var interval = {"shot": 0.025, "needle": 0.025, "hit": 0.035, "scrap": 0.07, "step": 0.10, "slam": 0.06}.get(kind, 0.015)
	if clock - float(last_played.get(kind, -99.0)) < interval: return
	last_played[kind] = clock
	var variant = kind + "_%d" % rng.randi_range(0, 2) if kind in ["shot", "hit", "step"] else kind
	if not streams.has(variant): return
	for i in range(live_voices.size() - 1, -1, -1):
		if not is_instance_valid(live_voices[i]): live_voices.remove_at(i)
	# Reserve four additional voices for menus and readable attack warnings.
	var important = kind in ["warning", "guardian_down", "menu_move", "menu_confirm"]
	if live_voices.size() >= (28 if important else 24): return
	var p: Node
	if at is Vector3:
		p = AudioStreamPlayer3D.new()
		add_child(p)
		p.global_position = at
		p.unit_size = 9.0
		p.max_distance = 40.0
		p.attenuation_filter_cutoff_hz = 10000
	else:
		p = AudioStreamPlayer.new()
		add_child(p)
	p.bus = "Menu" if kind in ["menu_move", "menu_confirm"] else "Effects"
	p.stream = streams[variant]
	p.pitch_scale = pitch * (rng.randf_range(0.965, 1.035) if kind in ["shot", "hit", "step", "destroy"] else 1.0)
	p.volume_db = LEVELS.get(kind, -6.0)
	p.finished.connect(p.queue_free)
	live_voices.append(p)
	p.play()

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	streams.clear()
	tracks.clear()
