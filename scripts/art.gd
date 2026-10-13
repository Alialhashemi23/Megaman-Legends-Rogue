extends RefCounted
class_name DiverArt

const INK = Color("172a3a")
const TEAL = Color("21b6b6")
const GOLD = Color("ffca68")
const STONE = Color("446b78")
static var materials: Dictionary = {}
static var texture_materials: Dictionary = {}

static func painted(kind: String, tint: Color = Color.WHITE, world_scale: float = 0.0) -> StandardMaterial3D:
	var key = kind + str(tint) + str(world_scale)
	if texture_materials.has(key): return texture_materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load("res://assets/textures/%s.svg" % kind)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	if world_scale > 0:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * world_scale
	texture_materials[key] = m
	return m

static func stone_material(color: Color) -> StandardMaterial3D:
	return painted("ruin_floor", color)

static func wall(parent: Node3D, pos: Vector3, size: Vector3, tint: Color, solid: bool = true) -> MeshInstance3D:
	var mesh = box(parent, pos, size, tint, solid)
	mesh.material_override = painted("ruin_wall", tint, 0.5)
	return mesh

static func metal(parent: Node3D, pos: Vector3, size: Vector3, tint: Color = Color.WHITE) -> MeshInstance3D:
	var mesh = box(parent, pos, size, tint)
	mesh.material_override = painted("ruin_metal", tint, 0.35)
	return mesh

static func ring(parent: Node3D, pos: Vector3, radius: float, color: Color, width: float = 0.09, arc: float = TAU) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		var a = -arc * 0.5 + arc * i / 48.0
		var b = -arc * 0.5 + arc * (i + 1) / 48.0
		var inside = maxf(0.01, radius - width)
		var p0 = Vector3(sin(a) * inside, 0, -cos(a) * inside)
		var p1 = Vector3(sin(b) * inside, 0, -cos(b) * inside)
		var p2 = Vector3(sin(b) * radius, 0, -cos(b) * radius)
		var p3 = Vector3(sin(a) * radius, 0, -cos(a) * radius)
		for p in [p0, p1, p2, p0, p2, p3]: st.set_normal(Vector3.UP); st.add_vertex(p)
	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat = material(color, 0.5).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func profile(parent: Node3D, pos: Vector3, rings: Array, color: Color, textured: bool = false, segments: int = 10) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo: float = rings[0][0]
	var hi: float = rings[-1][0]
	for j in rings.size() - 1:
		var a = rings[j]
		var b = rings[j + 1]
		for i in segments:
			var aa = TAU * i / segments
			var ab = TAU * (i + 1) / segments
			var p0 = Vector3(cos(aa) * a[1], a[0], sin(aa) * a[2] + a[3])
			var p1 = Vector3(cos(ab) * a[1], a[0], sin(ab) * a[2] + a[3])
			var p2 = Vector3(cos(ab) * b[1], b[0], sin(ab) * b[2] + b[3])
			var p3 = Vector3(cos(aa) * b[1], b[0], sin(aa) * b[2] + b[3])
			var u0 = float(i) / segments
			var u1 = float(i + 1) / segments
			var va = 1.0 - (a[0] - lo) / (hi - lo)
			var vb = 1.0 - (b[0] - lo) / (hi - lo)
			var vertices = [p0, p1, p2, p0, p2, p3]
			var uvs = [Vector2(u0, va), Vector2(u1, va), Vector2(u1, vb), Vector2(u0, va), Vector2(u1, vb), Vector2(u0, vb)]
			var normal = (p2 - p0).cross(p1 - p0).normalized()
			for n in 6:
				st.set_normal(normal)
				st.set_uv(uvs[n])
				st.add_vertex(vertices[n])
	for cap in [0, rings.size() - 1]:
		var r = rings[cap]
		for i in segments:
			var points = [Vector3(0, r[0], r[3]), Vector3(cos(TAU * i / segments) * r[1], r[0], sin(TAU * i / segments) * r[2] + r[3]), Vector3(cos(TAU * (i + 1) / segments) * r[1], r[0], sin(TAU * (i + 1) / segments) * r[2] + r[3])]
			if cap == 0: points.reverse()
			for p in points:
				st.set_normal(Vector3.UP if cap != 0 else Vector3.DOWN)
				st.set_uv(Vector2(p.x / (r[1] * 2) + 0.5, p.z / (r[2] * 2) + 0.5))
				st.add_vertex(p)
	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = painted("blue_armor", color) if textured else material(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func tuft(parent: Node3D, base: Vector3, tip: Vector3, width: float, depth: float, color: Color) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners = [base + Vector3(-width, 0, -depth), base + Vector3(width, 0, -depth), base + Vector3(width, 0, depth), base + Vector3(-width, 0, depth)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var normal = (tip - a).cross(b - a).normalized()
		for p in [a, b, tip]: st.set_normal(normal); st.add_vertex(p)
	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat = material(color).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	parent.add_child(mesh)

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key = str(color) + str(glow)
	if materials.has(key):
		return materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	materials[key] = m
	return m

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false, glow: float = 0.0) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color, glow)
	parent.add_child(mesh)
	mesh.position = pos
	if solid:
		var body = StaticBody3D.new()
		var collision = CollisionShape3D.new()
		var s = BoxShape3D.new()
		s.size = size
		collision.shape = s
		body.add_child(collision)
		parent.add_child(body)
		body.position = pos
	return mesh

static func orb(parent: Node3D, pos: Vector3, radius: float, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2
	shape.radial_segments = 10
	shape.rings = 5
	mesh.mesh = shape
	mesh.material_override = material(color, glow)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func armor(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	# Eight-sided armor has clipped corners rather than a voxel silhouette.
	var cut = minf(size.x, size.z) * 0.19
	var x = size.x * 0.5
	var z = size.z * 0.5
	var outline = [Vector2(-x + cut, -z), Vector2(x - cut, -z), Vector2(x, -z + cut), Vector2(x, z - cut), Vector2(x - cut, z), Vector2(-x + cut, z), Vector2(-x, z - cut), Vector2(-x, -z + cut)]
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var a = outline[i]
		var b = outline[(i + 1) % 8]
		var normal = Vector3(b.y - a.y, 0, a.x - b.x).normalized()
		var a0 = Vector3(a.x, -size.y * 0.5, a.y)
		var a1 = Vector3(a.x, size.y * 0.5, a.y)
		var b0 = Vector3(b.x, -size.y * 0.5, b.y)
		var b1 = Vector3(b.x, size.y * 0.5, b.y)
		for v in [a0, b0, b1, a0, b1, a1]: surface.set_normal(normal); surface.add_vertex(v)
		for v in [Vector3(0, size.y * 0.5, 0), a1, b1]: surface.set_normal(Vector3.UP); surface.add_vertex(v)
		for v in [Vector3(0, -size.y * 0.5, 0), b0, a0]: surface.set_normal(Vector3.DOWN); surface.add_vertex(v)
	var m = MeshInstance3D.new()
	m.mesh = surface.commit()
	m.material_override = material(color)
	parent.add_child(m)
	m.position = pos
	return m

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 8
	mesh.mesh = shape
	mesh.material_override = material(color, glow)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func label(parent: Node3D, pos: Vector3, text: String, color: Color = GOLD, size: int = 34) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.font = preload("res://assets/fonts/RussoOne-Regular.ttf")
	l.font_size = size
	l.modulate = color
	l.outline_size = 6
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	parent.add_child(l)
	l.position = pos
	return l

static func diver(parent: Node3D) -> Dictionary:
	# A locally authored fan interpretation of helmet-off Mega Man Volnutt.
	var blue = Color("c5e1ff")
	var navy = Color("163253")
	var trim = Color("649ecd")
	var skin = Color("efbf91")
	var root = Node3D.new()
	root.name = "Volnutt"
	parent.add_child(root)
	profile(root, Vector3.ZERO, [[0.83, 0.25, 0.17, 0], [0.95, 0.29, 0.19, 0], [1.28, 0.38, 0.23, 0], [1.48, 0.33, 0.19, 0]], blue, true)
	profile(root, Vector3.ZERO, [[0.76, 0.27, 0.18, 0], [0.86, 0.28, 0.19, 0]], navy)
	# Raised chest sections, dark collar and the small amber power indicator.
	profile(root, Vector3.ZERO, [[1.44, 0.23, 0.15, 0], [1.53, 0.20, 0.13, 0]], navy)
	armor(root, Vector3(0, 1.23, -0.225), Vector3(0.51, 0.32, 0.065), trim)
	box(root, Vector3(0, 1.23, -0.268), Vector3(0.14, 0.12, 0.035), Color("e6c34e"))
	for x in [-0.20, 0.20]:
		box(root, Vector3(x, 1.38, -0.20), Vector3(0.14, 0.06, 0.04), Color("acd7eb"))
	# Rear armor: central spine and recessed side vents are visible during play.
	armor(root, Vector3(0, 1.16, 0.23), Vector3(0.42, 0.45, 0.15), Color("2e6395"))
	box(root, Vector3(0, 1.31, 0.317), Vector3(0.19, 0.10, 0.025), Color("9cd4eb"))
	for x in [-0.12, 0.12]:
		for y in [1.08, 1.14, 1.20]: box(root, Vector3(x, y, 0.315), Vector3(0.08, 0.025, 0.02), navy)
	var legs = []
	for x in [-0.205, 0.205]:
		var pivot = Node3D.new()
		root.add_child(pivot)
		pivot.position = Vector3(x, 0.81, 0)
		profile(pivot, Vector3.ZERO, [[-0.43, 0.125, 0.13, 0], [-0.08, 0.13, 0.13, 0], [0.03, 0.15, 0.14, 0]], navy)
		profile(pivot, Vector3.ZERO, [[-0.75, 0.22, 0.32, -0.075], [-0.62, 0.24, 0.32, -0.075], [-0.43, 0.205, 0.22, 0], [-0.20, 0.18, 0.18, 0]], blue, true)
		profile(pivot, Vector3.ZERO, [[-0.80, 0.225, 0.32, -0.075], [-0.75, 0.225, 0.32, -0.075]], navy)
		armor(pivot, Vector3(0, -0.28, -0.17), Vector3(0.26, 0.21, 0.08), trim)
		legs.append(pivot)
	# Left buster and a separate right shoulder let the idle and run poses breathe.
	var buster = Node3D.new()
	root.add_child(buster)
	buster.position = Vector3(-0.49, 1.35, 0)
	orb(buster, Vector3(0, -0.015, 0), 0.225, trim)
	profile(buster, Vector3(0, -0.15, 0), [[-0.18, 0.13, 0.13, 0], [0, 0.15, 0.15, 0]], navy)
	var cannon = Node3D.new()
	buster.add_child(cannon)
	cannon.position = Vector3(0, -0.19, -0.12)
	cannon.rotation.x = -PI / 2
	profile(cannon, Vector3.ZERO, [[0, 0.16, 0.16, 0], [0.12, 0.23, 0.23, 0], [0.48, 0.23, 0.23, 0], [0.56, 0.19, 0.19, 0]], blue, true)
	var rim = cylinder(buster, Vector3(0, -0.19, -0.70), 0.19, 0.08, trim)
	rim.rotation.x = PI / 2
	var hole = cylinder(buster, Vector3(0, -0.19, -0.75), 0.145, 0.025, navy)
	hole.rotation.x = PI / 2
	var glow = cylinder(buster, Vector3(0, -0.19, -0.767), 0.07, 0.015, Color("f8cb5a"), 0.5)
	glow.rotation.x = PI / 2
	var free_arm = Node3D.new()
	root.add_child(free_arm)
	free_arm.position = Vector3(0.48, 1.35, 0)
	orb(free_arm, Vector3.ZERO, 0.22, trim)
	profile(free_arm, Vector3.ZERO, [[-0.40, 0.12, 0.12, 0], [-0.1, 0.14, 0.14, 0]], navy)
	profile(free_arm, Vector3.ZERO, [[-0.64, 0.17, 0.16, 0], [-0.36, 0.19, 0.18, 0], [-0.28, 0.15, 0.15, 0]], blue, true)
	orb(free_arm, Vector3(0, -0.70, -0.01), 0.145, navy)
	var head = Node3D.new()
	root.add_child(head)
	profile(head, Vector3.ZERO, [[1.58, 0.18, 0.17, -0.01], [1.71, 0.28, 0.225, 0], [1.98, 0.30, 0.25, 0], [2.12, 0.23, 0.21, 0]], skin, false, 12)
	for x in [-0.30, 0.30]: orb(head, Vector3(x, 1.84, 0), 0.085, skin).scale = Vector3(0.5, 1, 0.8)
	var face = MeshInstance3D.new()
	var face_quad = QuadMesh.new()
	face_quad.size = Vector2(0.49, 0.48)
	face.mesh = face_quad
	face.material_override = painted("volnutt_face")
	head.add_child(face)
	face.position = Vector3(0, 1.84, -0.239)
	face.rotation.y = PI
	# A faceted brown hair cap plus individual locks, rather than a block helmet.
	orb(head, Vector3(0, 1.95, 0.09), 0.31, Color("67412c")).scale = Vector3(1.02, 0.86, 0.79)
	profile(head, Vector3.ZERO, [[1.92, 0.31, 0.27, 0.03], [2.10, 0.32, 0.27, 0.025], [2.22, 0.21, 0.18, 0.02]], Color("67412c"), false, 10)
	for i in 9:
		var angle = TAU * i / 9.0
		var base = Vector3(cos(angle) * 0.23, 2.06, sin(angle) * 0.20 + 0.03)
		var tip = Vector3(cos(angle) * 0.39, 2.12 + (i % 3) * 0.035, sin(angle) * 0.32 + 0.04)
		tuft(head, base, tip, 0.095, 0.09, Color("785036") if i % 2 == 0 else Color("533325"))
	for i in 4:
		var x = -0.23 + i * 0.145
		tuft(head, Vector3(x, 2.10, -0.19), Vector3(x - 0.06, 1.94 + (i % 2) * 0.035, -0.28), 0.09, 0.07, Color("67412c"))
	tuft(head, Vector3(-0.05, 2.16, -0.02), Vector3(-0.15, 2.35, -0.04), 0.10, 0.11, Color("80573b"))
	return {"root": root, "legs": legs, "arm": buster, "free_arm": free_arm, "head": head}

static func robot(parent: Node3D, kind: int, tier: int = 1) -> Dictionary:
	var root = Node3D.new()
	parent.add_child(root)
	var color = [Color("e78a59"), Color("9b9de3"), Color("8bbf82"), GOLD][kind]
	if kind == 3: color = [GOLD, Color("82bfa0"), Color("b5a3df")][tier - 1]
	var limbs = []
	if kind == 1:
		orb(root, Vector3(0, 1.5, 0), 0.6, Color("506d6a"))
		var eye_rim = cylinder(root, Vector3(0, 1.5, -0.53), 0.32, 0.12, Color("c4ac75"))
		eye_rim.rotation.x = PI / 2
		var eye = cylinder(root, Vector3(0, 1.5, -0.60), 0.24, 0.035, Color("ed6a4d"), 0.15)
		eye.rotation.x = PI / 2
		var pupil = cylinder(root, Vector3(0, 1.5, -0.626), 0.09, 0.02, INK)
		pupil.rotation.x = PI / 2
		for x in [-0.86, 0.86]:
			armor(root, Vector3(x, 1.4, 0), Vector3(0.55, 0.18, 0.60), color)
			cylinder(root, Vector3(x, 1.5, 0), 0.12, 0.6, INK)
		cylinder(root, Vector3(0, 1.1, 0), 0.27, 0.20, TEAL, 1)
	else:
		profile(root, Vector3.ZERO, [[0.52, 0.36, 0.24, 0], [0.7, 0.49, 0.31, 0], [1.13, 0.46, 0.30, 0], [1.3, 0.32, 0.25, 0]], color)
		profile(root, Vector3.ZERO, [[1.28, 0.31, 0.27, 0], [1.58, 0.38, 0.30, 0], [1.73, 0.24, 0.21, 0]], Color("48615e"))
		var eye_rim = cylinder(root, Vector3(0, 1.49, -0.29), 0.23, 0.1, Color("d9c798"))
		eye_rim.rotation.x = PI / 2
		var eye = cylinder(root, Vector3(0, 1.49, -0.35), 0.175, 0.035, Color("e56748"), 0.15)
		eye.rotation.x = PI / 2
		var pupil = cylinder(root, Vector3(0, 1.49, -0.375), 0.065, 0.02, INK)
		pupil.rotation.x = PI / 2
		for y in [0.78, 0.88, 0.98]: box(root, Vector3(0, y, -0.315), Vector3(0.38, 0.04, 0.04), INK)
		for x in [-0.35, 0.35]:
			var pivot = Node3D.new()
			root.add_child(pivot)
			pivot.position = Vector3(x, 0.61, 0)
			cylinder(pivot, Vector3(0, -0.17, 0), 0.12, 0.35, INK)
			armor(pivot, Vector3(0, -0.40, -0.05), Vector3(0.32, 0.20, 0.45), color)
			limbs.append(pivot)
		for x in [-0.68, 0.68]:
			orb(root, Vector3(x * 0.8, 1.17, 0), 0.19, INK)
			profile(root, Vector3(x, 0, 0), [[0.62, 0.17, 0.18, 0], [0.8, 0.2, 0.21, 0], [1.21, 0.16, 0.18, 0]], color)
		if kind == 2:
			armor(root, Vector3(0, 0.93, -0.44), Vector3(1.0, 0.58, 0.15), Color("608f81"))
		if kind == 3:
			root.scale = Vector3.ONE * 2.35
			for x in [-0.55, 0.55]:
				box(root, Vector3(x, 1.75, 0), Vector3(0.22, 0.60, 0.3), color)
	return {"root": root, "limbs": limbs}
