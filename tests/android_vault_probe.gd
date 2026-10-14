extends Node

# Export only into a disposable dev.galosengen.relicdiver.checks app. These
# strings are test fixtures, never real sessions. No tokens are printed.
var checks = 0
var failures = 0

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("VAULT_PROBE_FAILED: " + label)

func _ready() -> void:
	var vault = preload("res://android_vault.gd").new()
	vault.directory = "user://vault-probe"
	var origin = "https://disposable.example"
	if FileAccess.file_exists("user://probe-ready"):
		verify(vault.load_token(origin) == "disposable-persisted-token", "Session survives process death or APK upgrade")
	verify(vault.save_token(origin, "disposable-test-token"), "Keystore encrypts session")
	verify(vault.load_token(origin) == "disposable-test-token", "Keystore decrypts session")
	var raw = FileAccess.get_file_as_string(vault.file_for(origin))
	verify(not raw.contains("disposable-test-token"), "Disk contains no plaintext bearer")
	verify(vault.load_token("https://other.example") == "", "Origins stay separate")
	var data = JSON.parse_string(raw)
	if data is Dictionary:
		var sealed = Marshalls.base64_to_raw(data.sealed)
		sealed[sealed.size() - 1] = sealed[sealed.size() - 1] ^ 1
		data.sealed = Marshalls.raw_to_base64(sealed)
		var output = FileAccess.open(vault.file_for(origin), FileAccess.WRITE)
		output.store_string(JSON.stringify(data))
		output.close()
		verify(vault.load_token(origin) == "", "Tampered ciphertext rejected")
	verify(vault.erase(origin), "Local sign-out deletes ciphertext")
	verify(vault.load_token(origin) == "", "Deleted session cannot restore")
	verify(vault.save_token(origin, "disposable-persisted-token"), "Session saved for restart/upgrade rehearsal")
	var marker = FileAccess.open("user://probe-ready", FileAccess.WRITE)
	marker.store_string("ready")
	marker.close()
	print("VAULT_PROBE: %d checks, %d failures" % [checks, failures])
