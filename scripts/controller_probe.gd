extends RefCounted
class_name DiverControllerProbe

# Read-only device snapshots. No InputMap edits, deadzones, saves or network I/O.
const AXIS_LABELS = ["Left X", "Left Y", "Right X", "Right Y", "Left trigger", "Right trigger"]

static func clean_browser(value: Variant) -> Array:
	var result = []
	if not value is Array: return result
	for pad in value.slice(0, 8):
		if not pad is Dictionary or not pad.get("axes") is Array or not pad.get("buttons") is Array: continue
		var index = pad.get("index", 0)
		if not (index is int or index is float) or not is_finite(float(index)): continue
		var axes = []
		for axis in pad.axes.slice(0, 32):
			axes.append(clampf(float(axis), -1, 1) if (axis is int or axis is float) and is_finite(float(axis)) else 0.0)
		var buttons = []
		for button in pad.buttons.slice(0, 64):
			buttons.append(clampf(float(button), 0, 1) if (button is int or button is float) and is_finite(float(button)) else 0.0)
		result.append({"index": clampi(int(index), 0, 63), "name": str(pad.get("id", "Unknown")).left(512), "mapping": str(pad.get("mapping", "")).left(32), "axes": axes, "buttons": buttons})
	return result

static func browser_snapshot() -> Array:
	if not OS.has_feature("web"): return []
	var raw = JavaScriptBridge.eval("(() => { try { return JSON.stringify(Array.from(navigator.getGamepads?.() || []).filter(p => p && p.connected).map(p => ({index:p.index,id:p.id,mapping:p.mapping,axes:Array.from(p.axes).slice(0,32),buttons:Array.from(p.buttons).slice(0,64).map(b=>b.value)}))); } catch(e) { return '[]'; } })()", true)
	if not raw is String or raw.length() > 32768: return []
	return clean_browser(JSON.parse_string(raw))

static func sample(device: int) -> Dictionary:
	var devices = Input.get_connected_joypads()
	var connected = device in devices
	var result = {"devices": Array(devices), "device": device, "connected": connected, "name": "No controller detected", "guid": "Unavailable", "known": false, "axes": [], "buttons": [], "browser": browser_snapshot()}
	if not connected: return result
	result.name = Input.get_joy_name(device)
	result.guid = Input.get_joy_guid(device)
	if result.guid == "": result.guid = "Unavailable on this platform"
	result.known = Input.is_joy_known(device)
	for axis in 6: result.axes.append(Input.get_joy_axis(device, axis))
	for button in JOY_BUTTON_MAX: result.buttons.append(1.0 if Input.is_joy_button_pressed(device, button) else 0.0)
	return result
