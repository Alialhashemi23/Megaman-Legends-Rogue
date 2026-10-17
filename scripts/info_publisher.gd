extends Node
class_name DiverInfoPublisher

# M_INFO carries a recovery build, not a shot event. Durable changes publish
# immediately; rapidly changing counters share at most four full builds/sec.
signal published(build: Dictionary)
const INTERVAL = 0.25
const TRANSIENT = ["shot_count", "repair_cooldown", "hp", "xp"]
var game: Node3D
var clock = func(): return Time.get_ticks_msec() / 1000.0
var sent: Dictionary = {}
var sent_shape: Dictionary = {}
var latest: Dictionary = {}
var pending_context: Array = []
var sent_context: Array = []
var last_sent = -INF

func context() -> Array:
	return [game.net.context(), game.net.slot, game.net.host_slot, game.run_id, game.depth, game.in_run()]

static func shape(build: Dictionary) -> Dictionary:
	var result = build.duplicate(true)
	for key in TRANSIENT: result.erase(key)
	return result

func clear() -> void:
	latest = {}
	sent = {}
	sent_shape = {}
	pending_context = []
	sent_context = []
	last_sent = -INF

func submit(build: Dictionary, force: bool = false) -> bool:
	if not game.net.active() or not game.net.connected():
		clear()
		return false
	var revision = shape(build)
	var current = context()
	latest = build.duplicate(true)
	pending_context = current
	if force or sent_context != current or sent_shape != revision or float(clock.call()) - last_sent >= INTERVAL:
		return publish_latest(force)
	if sent == latest: latest = {}
	return false

func publish_latest(force: bool = false) -> bool:
	if latest.is_empty(): return false
	if not game.net.active() or not game.net.connected() or pending_context != context():
		clear()
		return false
	if not force and sent == latest and sent_context == pending_context:
		latest = {}
		return false
	sent = latest.duplicate(true)
	sent_shape = shape(sent)
	sent_context = pending_context.duplicate(true)
	last_sent = float(clock.call())
	latest = {}
	published.emit(sent.duplicate(true))
	return true

func flush_pending() -> bool:
	if not latest.is_empty() and float(clock.call()) - last_sent >= INTERVAL: return publish_latest()
	return false

func _process(_dt: float) -> void:
	if not is_instance_valid(game): return
	if not game.net.active() or not game.net.connected(): clear()
	else: flush_pending()
