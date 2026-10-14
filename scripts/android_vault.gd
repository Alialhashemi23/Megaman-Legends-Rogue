extends RefCounted
class_name DiverAndroidVault

# Only ciphertext and a random IV leave Android Keystore. Never serialize a
# bearer token elsewhere, even when the bridge or Keystore is unavailable.
var directory = "user://credentials"
var bridge: Object

func _init() -> void:
	if OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper"):
		bridge = Engine.get_singleton("JavaClassWrapper")

func failed() -> bool:
	return bridge == null or bridge.get_exception() != null

func file_for(origin: String) -> String:
	return directory.path_join(origin.sha256_text() + ".json")

func key_for(origin: String, create: bool) -> Variant:
	if bridge == null: return null
	var store = bridge.wrap("java.security.KeyStore").getInstance("AndroidKeyStore")
	if failed() or store == null: return null
	store.load(null)
	if failed(): return null
	var alias = "relic.session." + origin.sha256_text()
	var present = store.containsAlias(alias)
	if failed(): return null
	if not present:
		if not create: return null
		var builder = bridge.wrap("android.security.keystore.KeyGenParameterSpec$Builder").call("KeyGenParameterSpec$Builder", alias, 3)
		if failed() or builder == null: return null
		builder.setBlockModes(PackedStringArray(["GCM"]))
		if failed(): return null
		builder.setEncryptionPaddings(PackedStringArray(["NoPadding"]))
		if failed(): return null
		builder.setKeySize(256)
		if failed(): return null
		var spec = builder.build()
		if failed() or spec == null: return null
		var generator = bridge.wrap("javax.crypto.KeyGenerator").getInstance("AES", "AndroidKeyStore")
		if failed() or generator == null: return null
		generator.init(spec)
		if failed(): return null
		generator.generateKey()
		if failed(): return null
	var key = store.getKey(alias, PackedByteArray())
	return null if failed() else key

func save_token(origin: String, token: String) -> bool:
	if token == "": return erase(origin)
	var key = key_for(origin, true)
	if key == null: return false
	var cipher = bridge.wrap("javax.crypto.Cipher").getInstance("AES/GCM/NoPadding")
	if failed() or cipher == null: return false
	cipher.init(1, key)
	if failed(): return false
	cipher.updateAAD(origin.to_utf8_buffer())
	if failed(): return false
	var encrypted = cipher.doFinal(token.to_utf8_buffer())
	if failed() or not encrypted is PackedByteArray: return false
	var iv = cipher.getIV()
	if failed() or not iv is PackedByteArray: return false
	var file = file_for(origin)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var output = FileAccess.open(file + ".tmp", FileAccess.WRITE)
	if output == null: return false
	output.store_string(JSON.stringify({"v": 1, "iv": Marshalls.raw_to_base64(iv), "sealed": Marshalls.raw_to_base64(encrypted)}))
	output.flush()
	var error = output.get_error()
	output.close()
	return error == OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(file + ".tmp"), ProjectSettings.globalize_path(file)) == OK

func load_token(origin: String) -> String:
	if bridge == null or not FileAccess.file_exists(file_for(origin)): return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(file_for(origin)))
	if not data is Dictionary or data.get("v") != 1: return ""
	var iv = Marshalls.base64_to_raw(str(data.get("iv", "")))
	var sealed = Marshalls.base64_to_raw(str(data.get("sealed", "")))
	if iv.size() != 12 or sealed.size() < 16 or sealed.size() > 16384: return ""
	var key = key_for(origin, false)
	if key == null: return ""
	var cipher = bridge.wrap("javax.crypto.Cipher").getInstance("AES/GCM/NoPadding")
	if failed() or cipher == null: return ""
	var spec = bridge.wrap("javax.crypto.spec.GCMParameterSpec").GCMParameterSpec(128, iv)
	if failed() or spec == null: return ""
	cipher.init(2, key, spec)
	if failed(): return ""
	cipher.updateAAD(origin.to_utf8_buffer())
	if failed(): return ""
	var plain = cipher.doFinal(sealed)
	if failed() or not plain is PackedByteArray: return ""
	return plain.get_string_from_utf8()

func erase(origin: String) -> bool:
	var success = true
	for suffix in ["", ".tmp"]:
		var file = ProjectSettings.globalize_path(file_for(origin) + suffix)
		if FileAccess.file_exists(file) and DirAccess.remove_absolute(file) != OK: success = false
	return success
