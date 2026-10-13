extends Node3D
class_name DiverCharacter

const SCENES = [preload("res://assets/characters/volnutt.glb"), preload("res://assets/characters/roll.glb")]
const DISPLAY_NAMES = ["Mega Man Volnutt", "Roll Caskett"]
const SHORT_NAMES = ["MEGA", "ROLL"]
const LOCOMOTION = ["run", "backpedal", "strafe_left", "strafe_right"]
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

func _ready() -> void:
	model = SCENES[clampi(character, 0, 1)].instantiate()
	add_child(model)
	for node in model.find_children("*", "Skeleton3D", true, false): skeleton = node
	for node in model.find_children("*", "AnimationPlayer", true, false): animator = node
	assert(skeleton != null and animator != null, "Character requires its imported skin and animation player")
	for i in skeleton.get_bone_count(): joints[skeleton.get_bone_name(i)] = i
	animator.callback_mode_process = 2 # Manual: advance, then layer buster aiming.
	for clip in ["idle", "run", "backpedal", "strafe_left", "strafe_right", "fall", "dash"]:
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
	var blue = Color("235acb") if character == 0 else Color("c73350")
	var cuff = DiverArt.cylinder(weapon_mount, Vector3(0, -0.14, 0), 0.132, 0.21, blue)
	cuff.material_override = DiverArt.painted("blue_armor", Color.WHITE if character == 0 else Color("ffb1ab"))
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

func select_clip(clip: String, immediate: bool = false) -> void:
	if current_clip == clip: return
	var preserve_step = not immediate and current_clip in LOCOMOTION and clip in LOCOMOTION
	var phase = 0.0
	if preserve_step:
		phase = fposmod(animator.current_animation_position / animator.current_animation_length, 1.0)
	current_clip = clip
	animator.play(clip, 0.0 if immediate else 0.12)
	if preserve_step:
		animator.seek(phase * animator.get_animation(clip).length)

func animate(dt: float, move: Vector2, grounded: bool, rising: float, dash: bool, aiming: bool, aim_pitch: float, recoil: float, speed_ratio: float = 1.0) -> void:
	foot_contact = false
	hurt_time = maxf(0, hurt_time - dt)
	shot_time = maxf(0, shot_time - dt)
	if grounded: jump_elapsed = 0
	else: jump_elapsed += dt
	var clip = "idle"
	if dash: clip = "dash"
	elif not grounded: clip = "jump" if rising > 0 and jump_elapsed < 0.35 else "fall"
	elif hurt_time > 0: clip = "hurt"
	elif move.length() > 0.1:
		clip = "strafe_left" if move.x < -0.4 and absf(move.x) > absf(move.y) else "strafe_right" if move.x > 0.4 and absf(move.x) > absf(move.y) else "backpedal" if move.y > 0.1 else "run"
	elif shot_time > 0: clip = "fire"
	select_clip(clip)
	animation_speed = speed_ratio if clip in LOCOMOTION else 1.0
	var before = animator.current_animation_position
	animator.advance(dt * animation_speed)
	if clip in LOCOMOTION:
		var length = animator.current_animation_length
		var after = animator.current_animation_position
		foot_contact = after < before or (before < length * .5 and after >= length * .5)
	layer_aim(dt, aiming, aim_pitch, recoil)

func layer_aim(dt: float, aiming: bool, aim_pitch: float, recoil: float) -> void:
	arm_weight = move_toward(arm_weight, 1.0 if aiming or shot_time > 0 else 0.0, dt * 8)
	# Keep locomotion in the legs, layer aim and recoil in the buster arm.
	var upper = joints.LeftUpperArm
	var forearm = joints.LeftForeArm
	var torso = skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper)).basis.get_rotation_quaternion()
	var upper_target = torso.inverse() * Quaternion.from_euler(Vector3(PI / 2 + aim_pitch - 0.36 - recoil * .13, 0, -.035))
	var forearm_target = Quaternion(Vector3.RIGHT, .36 + recoil * .04)
	skeleton.set_bone_pose_rotation(upper, skeleton.get_bone_pose_rotation(upper).slerp(upper_target, arm_weight))
	skeleton.set_bone_pose_rotation(forearm, skeleton.get_bone_pose_rotation(forearm).slerp(forearm_target, arm_weight))
	update_mount()

func update_mount() -> void:
	weapon_mount.transform = skeleton.get_bone_global_pose(joints.LeftForeArm)

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
