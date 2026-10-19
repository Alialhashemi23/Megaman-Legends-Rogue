extends Node3D
class_name DiverFire

# Painted polygon flames and one ember batch. A small pool reuses all meshes,
# materials and lights; no particle-node churn, textures or shadow passes.
const SECONDS = 2.0
var tongues: Array[MeshInstance3D] = []
var flame_material: StandardMaterial3D
var scorch_material: StandardMaterial3D
var embers: MultiMeshInstance3D
var glow: OmniLight3D
var age = SECONDS
var radius = 1.8

func _ready() -> void:
	flame_material = material(true)
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for i in 5:
		var tongue = MeshInstance3D.new()
		tongue.mesh = flame_mesh()
		tongue.material_override = flame_material
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tongue)
		tongues.append(tongue)
	scorch_material = material(false)
	var scorch = MeshInstance3D.new()
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		for point in [Vector3.ZERO, Vector3(cos(i * TAU / 12), 0, sin(i * TAU / 12)), Vector3(cos((i + 1) * TAU / 12), 0, sin((i + 1) * TAU / 12))]:
			surface.set_color(Color(0.13, 0.08, 0.06, 0.25 if point == Vector3.ZERO else 0.0))
			surface.add_vertex(point)
	scorch.mesh = surface.commit()
	scorch.material_override = scorch_material
	scorch.position.y = 0.015
	add_child(scorch)
	embers = MultiMeshInstance3D.new()
	embers.multimesh = MultiMesh.new()
	embers.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var spark = SphereMesh.new()
	spark.radius = 0.035
	spark.height = 0.09
	spark.radial_segments = 4
	spark.rings = 1
	embers.multimesh.mesh = spark
	embers.multimesh.instance_count = 12
	var ember_mat = material(true)
	ember_mat.albedo_color = Color("ffca68")
	ember_mat.vertex_color_use_as_albedo = false
	embers.material_override = ember_mat
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(embers)
	glow = OmniLight3D.new()
	glow.light_color = Color("ff9e50")
	glow.omni_range = 4.0
	glow.shadow_enabled = false
	glow.position.y = 0.65
	add_child(glow)
	visible = false

func material(lit: bool) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	if lit:
		mat.emission_enabled = true
		mat.emission = Color("ff8c36")
		mat.emission_energy_multiplier = 0.5
	return mat

func flame_mesh() -> ArrayMesh:
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each lobe has an irregular pointed silhouette with a pale inner flame.
	for inner in [false, true]:
		var outline = [Vector2(-0.34, 0.04), Vector2(-0.42, 0.42), Vector2(-0.17, 0.75), Vector2(-0.08, 1.25), Vector2(0.20, 0.84), Vector2(0.12, 0.55), Vector2(0.34, 0.29), Vector2(0.26, 0.04)]
		var center = Vector2(0, 0.37)
		for i in outline.size():
			for point in [center, outline[i], outline[(i + 1) % outline.size()]]:
				var color = Color("fff0a0").lerp(Color("ffbd42"), point.y) if inner else Color("ff9e32").lerp(Color("db5427"), point.y / 1.25)
				surface.set_color(color)
				var size = Vector2(0.5, 0.6) if inner else Vector2.ONE
				surface.add_vertex(Vector3(point.x * size.x, point.y * size.y, 0.008 if inner else 0.0))
	return surface.commit()

func ignite(at: Vector3, footprint: float, light: bool) -> void:
	position = at
	radius = footprint
	age = 0
	visible = true
	glow.visible = light
	animate(0)

func animate(seconds: float) -> void:
	age = seconds
	var fade = clampf((SECONDS - age) / 0.4, 0, 1) * minf(1, age / 0.08 + 0.2)
	flame_material.albedo_color.a = fade
	scorch_material.albedo_color.a = clampf((SECONDS - age) / 0.7, 0, 1)
	embers.visible = fade > 0.05
	for i in tongues.size():
		var angle = i * TAU / tongues.size()
		var flicker = sin(age * 19 + i * 3.7)
		tongues[i].position = Vector3(cos(angle), 0, sin(angle)) * (0.32 if i > 0 else 0.0) * minf(radius, 2.4)
		tongues[i].scale = Vector3(0.85 + 0.14 * flicker, (0.75 + 0.21 * sin(age * 23 + i * 1.7)) * fade, 1)
	for i in 12:
		var t = fposmod(age * 0.7 + i / 12.0, 1.0)
		var angle = i * 2.4 + age
		var at = Vector3(cos(angle) * (0.25 + t * 0.45), 0.2 + t * 1.8, sin(angle) * (0.25 + t * 0.45))
		embers.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (1.0 - t) * fade), at))
	glow.light_energy = fade * (0.65 + 0.12 * sin(age * 21))
	visible = age < SECONDS
