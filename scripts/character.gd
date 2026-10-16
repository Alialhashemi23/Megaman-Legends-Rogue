extends Node3D
class_name DiverCharacter

const SCENES = [preload("res://assets/characters/volnutt.glb"), preload("res://assets/characters/roll.glb"), preload("res://assets/characters/tron.glb"), preload("res://assets/characters/servbot.glb")]
const DISPLAY_NAMES = ["Mega Man Volnutt", "Roll Caskett", "Tron Bonne", "Servbot"]
const SHORT_NAMES = ["MEGA", "ROLL", "TRON", "SERVBOT"]
const IDS = ["volnutt", "roll", "tron", "servbot"]
const COUNT = 4
# Buster casing colour, armour tint and size for each digger's arm.
const BUSTER_COLORS = [Color("235acb"), Color("c73350"), Color("b02a86"), Color("2c3fa8")]
const BUSTER_TINTS = [Color.WHITE, Color("ffb1ab"), Color("ffa3e0"), Color("c9d2ff")]
const BUSTER_SCALES = [1.0, 1.0, 1.0, 0.62]
const LOCOMOTION = ["run", "backpedal", "strafe_left", "strafe_right"]
# One-shot dash clips: onset crouch, travel lean, then a plant and settle that
# play out after the 0.19 s dash unless the digger runs, jumps or is hit.
const DASH_CLIPS = ["dash", "dash_back", "dash_left", "dash_right"]
const DASH_TRAVEL = 0.19
const DASH_PLANT = 0.24
# A landing after a real fall squashes into the knees unless the digger moves on.
const LAND_AIR_TIME = 0.3
var character = 0
var model: Node3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var weapon_mount: Node3D
var muzzle: Marker3D
var current_clip = ""
var jump_elapsed = 0.0
var hurt_time = 0.0
var shot_time = 0.0
var arm_weight = 0.0
var animation_speed = 1.0
var preview_time = 0.0
var joints: Dictionary = {}
var barrel_material: StandardMaterial3D
var equipped_weapon = -1
var foot_contact = false
var dash_clip = "dash"
var dash_elapsed = -1.0
var was_dashing = false
var dash_started = false
var air_time = 0.0
var land_time = 0.0

func _ready() -> void:
	character = clampi(character, 0, COUNT - 1)
	model = SCENES[character].instantiate()
	add_child(model)
	for node in model.find_children("*", "Skeleton3D", true, false): skeleton = node
	for node in model.find_children("*", "AnimationPlayer", true, false): animator = node
	assert(skeleton != null and animator != null, "Character requires its imported skin and animation player")
	for i in skeleton.get_bone_count(): joints[skeleton.get_bone_name(i)] = i
	animator.callback_mode_process = 2 # Manual: advance, then layer buster aiming.
	for clip in ["idle", "run", "backpedal", "strafe_left", "strafe_right", "fall"]:
		animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source = mesh.mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				var material = source.duplicate() as StandardMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				material.roughness = 1.0
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh.set_surface_override_material(surface, material)
	build_buster()
	select_clip("idle", true)
	animator.advance(0)
	update_mount()

func build_buster() -> void:
	weapon_mount = Node3D.new()
	weapon_mount.name = "BusterMount"
	skeleton.add_child(weapon_mount)
	var blue: Color = BUSTER_COLORS[character]
	var cuff = DiverArt.cylinder(weapon_mount, Vector3(0, -0.14, 0), 0.132, 0.21, blue)
	cuff.material_override = DiverArt.painted("blue_armor", BUSTER_TINTS[character])
	DiverArt.cylinder(weapon_mount, Vector3(0, -0.29, 0), 0.12, 0.22, blue)
	DiverArt.cylinder(weapon_mount, Vector3(0, -0.408, 0), 0.125, 0.033, Color("183059"))
	var aperture = DiverArt.cylinder(weapon_mount, Vector3(0, -0.429, 0), 0.081, 0.012, Color("55def2"))
	barrel_material = DiverArt.material(Color("55def2"), 0.8).duplicate()
	aperture.material_override = barrel_material
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, -0.448, 0)
	weapon_mount.add_child(muzzle)

func equip(index: int) -> void:
	if equipped_weapon == index: return
	equipped_weapon = index
	barrel_material.albedo_color = [Color("ffdd65"), Color("b5f3ad"), Color("ffbb65")][clampi(index, 0, 2)]
	barrel_material.emission = barrel_material.albedo_color

func select_clip(clip: String, immediate: bool = false, blend: float = 0.12) -> void:
	if current_clip == clip: return
	var preserve_step = not immediate and current_clip in LOCOMOTION and clip in LOCOMOTION
	var phase = 0.0
	if preserve_step:
		phase = fposmod(animator.current_animation_position / animator.current_animation_length, 1.0)
	current_clip = clip
	animator.play(clip, 0.0 if immediate else blend)
	if preserve_step:
		animator.seek(phase * animator.get_animation(clip).length)

# dash_direction is the dash's travel direction relative to facing (x right, y back).
func animate(dt: float, move: Vector2, grounded: bool, rising: float, dash: bool, aiming: bool, aim_pitch: float, recoil: float, speed_ratio: float = 1.0, dash_direction: Vector2 = Vector2(0, -1)) -> void:
	foot_contact = false
	hurt_time = maxf(0, hurt_time - dt)
	shot_time = maxf(0, shot_time - dt)
	if grounded: jump_elapsed = 0
	else: jump_elapsed += dt
	var landed = false
	if grounded:
		landed = air_time > LAND_AIR_TIME and not dash
		air_time = 0.0
	else: air_time += dt
	land_time = animator.get_animation("land").length if landed else maxf(0, land_time - dt)
	if move.length() > 0.1: land_time = 0.0
	dash_started = dash and not was_dashing
	was_dashing = dash
	var dash_before = dash_elapsed
	if dash_started:
		dash_elapsed = 0.0
		dash_clip = dash_clip_for(dash_direction)
		# Restart from the onset with a near-instant blend, even when repeating a clip.
		current_clip = dash_clip
		animator.play(dash_clip, 0.04)
		animator.seek(0.0)
	elif dash_elapsed >= 0: dash_elapsed += dt
	# The recovery plays on the ground; running on cuts it after the foot plants.
	var recovering = not dash and dash_elapsed >= 0 and dash_elapsed < animator.get_animation(dash_clip).length 		and grounded and hurt_time <= 0 and not (move.length() > 0.1 and dash_elapsed > DASH_TRAVEL + 0.07)
	if not dash and not recovering: dash_elapsed = -1.0
	elif grounded and dash_before < DASH_PLANT and dash_elapsed >= DASH_PLANT: foot_contact = true
	var clip = "idle"
	if dash or recovering: clip = dash_clip
	elif not grounded: clip = "jump" if rising > 0 and jump_elapsed < 0.35 else "fall"
	elif hurt_time > 0: clip = "hurt"
	elif land_time > 0 and move.length() <= 0.1:
		clip = "land"
		if landed: current_clip = ""
	elif move.length() > 0.1:
		clip = "strafe_left" if move.x < -0.4 and absf(move.x) > absf(move.y) else "strafe_right" if move.x > 0.4 and absf(move.x) > absf(move.y) else "backpedal" if move.y > 0.1 else "run"
	elif shot_time > 0: clip = "fire"
	select_clip(clip, false, 0.05 if landed else 0.14 if current_clip in DASH_CLIPS else 0.12)
	# A light stick tilt walks slower, so the cadence eases down with it.
	animation_speed = speed_ratio * clampf(move.length(), 0.55, 1.0) if clip in LOCOMOTION else 1.0
	var before = animator.current_animation_position
	animator.advance(dt * animation_speed)
	if clip in LOCOMOTION:
		var length = animator.current_animation_length
		var after = animator.current_animation_position
		foot_contact = after < before or (before < length * .5 and after >= length * .5)
	layer_aim(dt, aiming, aim_pitch, recoil)

func dash_clip_for(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y): return "dash_right" if direction.x > 0 else "dash_left"
	return "dash_back" if direction.y > 0 else "dash"

func layer_aim(dt: float, aiming: bool, aim_pitch: float, recoil: float) -> void:
	arm_weight = move_toward(arm_weight, 1.0 if aiming or shot_time > 0 else 0.0, dt * 8)
	# Keep locomotion in the legs, layer aim and recoil in the buster arm.
	var upper = joints.LeftUpperArm
	var torso = skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper)).basis.get_rotation_quaternion()
	# A Servbot's arm is a single joint, so the whole arm points down the aim line.
	var elbow = .36 if joints.has("LeftForeArm") else 0.0
	var upper_target = torso.inverse() * Quaternion.from_euler(Vector3(PI / 2 + aim_pitch - elbow - recoil * .13, 0, -.035))
	skeleton.set_bone_pose_rotation(upper, skeleton.get_bone_pose_rotation(upper).slerp(upper_target, arm_weight))
	if joints.has("LeftForeArm"):
		var forearm = joints.LeftForeArm
		var forearm_target = Quaternion(Vector3.RIGHT, elbow + recoil * .04)
		skeleton.set_bone_pose_rotation(forearm, skeleton.get_bone_pose_rotation(forearm).slerp(forearm_target, arm_weight))
	update_mount()

func update_mount() -> void:
	weapon_mount.transform = skeleton.get_bone_global_pose(joints.get("LeftForeArm", joints.LeftUpperArm)).scaled_local(Vector3.ONE * BUSTER_SCALES[character])

func fire() -> void:
	shot_time = 0.30

func hurt() -> void:
	hurt_time = .30
	current_clip = ""

func preview(dt: float, ending: bool = false, won: bool = false) -> void:
	preview_time += dt
	select_clip("victory" if ending and won else "defeat" if ending else "idle")
	animator.advance(dt)
	arm_weight = 0
	update_mount()
