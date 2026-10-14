extends Node
class_name DiverAndroidUpdates

var game: Node
var http: HTTPRequest
var metadata: Dictionary = {}
var origin = ""
var installed_code = 0
var dismissed = false
var checked = false
var opener: Callable

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 5.0
	http.body_size_limit = 16384
	add_child(http)
	http.request_completed.connect(completed)
	if OS.has_feature("android"):
		var runtime = Engine.get_singleton("AndroidRuntime")
		if runtime != null:
			var context = runtime.getApplicationContext()
			var info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0)
			if info != null: installed_code = int(info.getLongVersionCode())
		check.call_deferred()

static func integer(value: Variant, minimum: int = 1) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= 2147483647

static func valid(data: Variant, base: String) -> bool:
	if not data is Dictionary or not base.begins_with("https://"): return false
	for field in ["versionCode", "gameProtocol", "minimumOnlineVersionCode", "bytes"]:
		if not integer(data.get(field)): return false
	if data.minimumOnlineVersionCode > data.versionCode: return false
	for field in ["versionName", "downloadUrl", "sha256", "signingFingerprint", "notes"]:
		if not data.get(field) is String: return false
	if data.versionName.is_empty() or data.versionName.length() > 64 or data.notes.length() > 4000: return false
	for field in ["sha256", "signingFingerprint"]:
		var hex: String = data[field].to_lower()
		if hex.length() != 64 or not hex.is_valid_hex_number(false): return false
	var url: String = data.downloadUrl
	return url.begins_with(base + "/downloads/android/") and not url.contains("..") and not url.contains("\\") and not url.contains("?") and not url.contains("#") and not url.contains("%")

func check() -> void:
	http.cancel_request()
	metadata = {}
	checked = false
	origin = game.account.base_url()
	if not origin.begins_with("https://"): checked = true; return
	if http.request(origin + "/updates/android/stable.json") != OK: checked = true

func completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	checked = true
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("downloadUrl") == "/downloads/android/": data.downloadUrl = origin + data.downloadUrl
	if valid(data, origin): metadata = data

func available() -> bool:
	return not metadata.is_empty() and int(metadata.versionCode) > installed_code

func blocks_online() -> bool:
	return not metadata.is_empty() and (installed_code < int(metadata.minimumOnlineVersionCode) or int(metadata.gameProtocol) != DiverNet.NET_VERSION)

func later() -> void:
	dismissed = true
	game.show_title()

func download() -> void:
	if not available() or not game.account.switch_allowed(): return
	if not game.account.persist_pending(): return
	dismissed = true
	if opener.is_valid(): opener.call(metadata.downloadUrl)
	else: OS.shell_open(metadata.downloadUrl)
	game.show_title()

func _process(_dt: float) -> void:
	if OS.has_feature("android") and game != null and origin != "" and origin != game.account.base_url():
		dismissed = false
		check()
	if game != null and game.mode == "title" and not dismissed and available() and game.account.switch_allowed():
		game.mode = "android_update"
