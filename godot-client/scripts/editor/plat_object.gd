class_name PlatObject
extends RefCounted
## Модель одного объекта уровня — аналог "Part" в Roblox.
## Хранит геометрию, трансформ и прикреплённые правила (визуальный скриптинг).
## Не является Node — это чистые данные, которые редактор и рантайм
## превращают в реальные Node3D через spawn_into().

enum Shape { CUBE, CYLINDER, SPHERE, WEDGE, NPC }

var id: String                      # уникальный ID внутри уровня (для ссылок из правил)
var shape: int = Shape.CUBE
var position: Vector3 = Vector3.ZERO
var rotation: Vector3 = Vector3.ZERO   # градусы, для читаемости в JSON
var scale: Vector3 = Vector3(1, 1, 1)
var color: Color = Color(0.6, 0.6, 0.65)
var anchored: bool = true           # true = StaticBody3D (неподвижный), false = RigidBody3D
var rules: Array[PlatRule] = []      # визуальные правила "Когда X -> Сделай Y"
var name: String = "Part"

func _init(p_id: String = "") -> void:
	id = p_id if p_id != "" else _generate_id()

static func _generate_id() -> String:
	return "obj_%d_%d" % [Time.get_ticks_msec(), randi() % 10000]

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"shape": shape,
		"position": [position.x, position.y, position.z],
		"rotation": [rotation.x, rotation.y, rotation.z],
		"scale": [scale.x, scale.y, scale.z],
		"color": color.to_html(false),
		"anchored": anchored,
		"rules": rules.map(func(r: PlatRule): return r.to_dict()),
	}

static func from_dict(data: Dictionary) -> PlatObject:
	var obj := PlatObject.new(data.get("id", ""))
	obj.name = data.get("name", "Part")
	obj.shape = data.get("shape", Shape.CUBE)
	var pos = data.get("position", [0, 0, 0])
	obj.position = Vector3(pos[0], pos[1], pos[2])
	var rot = data.get("rotation", [0, 0, 0])
	obj.rotation = Vector3(rot[0], rot[1], rot[2])
	var scl = data.get("scale", [1, 1, 1])
	obj.scale = Vector3(scl[0], scl[1], scl[2])
	obj.color = Color.html(data.get("color", "999999"))
	obj.anchored = data.get("anchored", true)
	var rules_data = data.get("rules", [])
	for rule_dict in rules_data:
		obj.rules.append(PlatRule.from_dict(rule_dict))
	return obj

## Создаёт реальный игровой Node3D из этих данных. Используется и редактором
## (для предпросмотра), и рантаймом (для реальной игры).
func spawn_into(parent: Node3D) -> StaticBody3D:
	var body: StaticBody3D
	if anchored:
		body = StaticBody3D.new()
	else:
		# RigidBody3D нужен для физически подвижных объектов; пока анкорим всё
		# по умолчанию, движущиеся part — задел на будущее.
		body = StaticBody3D.new()

	body.name = name
	body.position = position
	body.rotation_degrees = rotation
	body.set_meta("plat_object_id", id)

	var mesh_instance := MeshInstance3D.new()
	var collision := CollisionShape3D.new()

	match shape:
		Shape.CUBE:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			mesh_instance.mesh = box
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3.ONE
			collision.shape = box_shape
		Shape.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 1.0
			mesh_instance.mesh = cyl
			var cyl_shape := CylinderShape3D.new()
			cyl_shape.radius = 0.5
			cyl_shape.height = 1.0
			collision.shape = cyl_shape
		Shape.SPHERE:
			var sph := SphereMesh.new()
			sph.radius = 0.5
			sph.height = 1.0
			mesh_instance.mesh = sph
			var sph_shape := SphereShape3D.new()
			sph_shape.radius = 0.5
			collision.shape = sph_shape
		Shape.WEDGE:
			# Клин: Godot не имеет встроенного WedgeMesh, строим вручную из ArrayMesh.
			mesh_instance.mesh = _build_wedge_mesh()
			var wedge_shape := ConvexPolygonShape3D.new()
			wedge_shape.points = _wedge_points()
			collision.shape = wedge_shape
		Shape.NPC:
			# NPC пока — визуальная капсула-заглушка (как у игрока), без ИИ/поведения.
			# Задел на будущее: диалоги, патрулирование, торговля и т.д.
			var npc_capsule := CapsuleMesh.new()
			npc_capsule.radius = 0.4
			npc_capsule.height = 1.6
			mesh_instance.mesh = npc_capsule
			var npc_shape := CapsuleShape3D.new()
			npc_shape.radius = 0.4
			npc_shape.height = 1.6
			collision.shape = npc_shape
			body.set_meta("is_npc", true)

	mesh_instance.scale = scale
	collision.scale = scale

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat

	body.add_child(mesh_instance)
	body.add_child(collision)
	parent.add_child(body)

	# Если есть правила с триггером "касание" — вешаем Area3D-детектор.
	var has_touch_rule := rules.any(func(r): return r.trigger == PlatRule.Trigger.TOUCH)
	if has_touch_rule:
		_attach_touch_detector(body)

	return body

func _wedge_points() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
		Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
	])

func _build_wedge_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := _wedge_points()
	# Полностью замкнутая призма-клин: 2 треугольных торца + 3 прямоугольные
	# грани (низ, задняя вертикальная стенка, наклонный скос) = 8 треугольников.
	# Порядок вершин в каждой грани подобран так, чтобы нормаль смотрела наружу.
	var faces := [
		[0, 2, 4],              # левый торец
		[1, 5, 3],              # правый торец
		[0, 1, 3], [0, 3, 2],   # низ
		[0, 5, 1], [0, 4, 5],   # задняя вертикальная грань
		[4, 3, 5], [4, 2, 3],   # наклонная грань (скос)
	]
	for face in faces:
		for idx in face:
			st.add_vertex(pts[idx])
	st.generate_normals()
	return st.commit()

func _attach_touch_detector(body: StaticBody3D) -> void:
	var area := Area3D.new()
	area.name = "TouchDetector"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(scale.x + 0.1, scale.y + 0.1, scale.z + 0.1)
	shape.shape = box
	area.add_child(shape)
	body.add_child(area)
	area.body_entered.connect(func(other_body):
		if other_body.is_in_group("player"):
			for rule in rules:
				if rule.trigger == PlatRule.Trigger.TOUCH:
					rule.execute(other_body)
	)
