## Test map. The layout is generated from a fixed seed so every peer builds an
## identical world without any of it needing to travel over the network.
##
## Replace this scene with your own map later; `main.gd` only needs the map root
## to expose `get_spawn_point(index)`.
extends Node3D

const ARENA_HALF_SIZE := 45.0
const WALL_HEIGHT := 6.0
const BLOCK_SEED := 20250815

var _spawn_points: Array[Vector3] = []


func _ready() -> void:
	_build_ground()
	_build_walls()
	_build_obstacles()
	_build_spawn_points()


## Spawn positions are handed out round-robin by the server.
func get_spawn_point(index: int) -> Vector3:
	if _spawn_points.is_empty():
		return Vector3(0.0, 1.0, 0.0)
	return _spawn_points[index % _spawn_points.size()]


func _build_spawn_points() -> void:
	var ring_radius := 6.0
	for i in 8:
		var angle := TAU * float(i) / 8.0
		_spawn_points.append(Vector3(cos(angle) * ring_radius, 1.2, sin(angle) * ring_radius))


func _make_material(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


## Creates a matching BoxMesh + BoxShape3D static body.
func _add_box(box_position: Vector3, size: Vector3, material: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = box_position
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)
	return body


func _build_ground() -> void:
	var size := ARENA_HALF_SIZE * 2.0
	_add_box(
		Vector3(0.0, -0.5, 0.0),
		Vector3(size, 1.0, size),
		_make_material(Color(0.24, 0.30, 0.22))
	)
	# A lighter plaza in the middle so movement reads clearly.
	_add_box(
		Vector3(0.0, 0.05, 0.0),
		Vector3(24.0, 0.2, 24.0),
		_make_material(Color(0.42, 0.40, 0.36))
	)


func _build_walls() -> void:
	var mat := _make_material(Color(0.30, 0.29, 0.32))
	var span := ARENA_HALF_SIZE * 2.0
	var offsets := [
		Vector3(0.0, WALL_HEIGHT * 0.5, -ARENA_HALF_SIZE),
		Vector3(0.0, WALL_HEIGHT * 0.5, ARENA_HALF_SIZE),
		Vector3(-ARENA_HALF_SIZE, WALL_HEIGHT * 0.5, 0.0),
		Vector3(ARENA_HALF_SIZE, WALL_HEIGHT * 0.5, 0.0),
	]
	var sizes := [
		Vector3(span, WALL_HEIGHT, 2.0),
		Vector3(span, WALL_HEIGHT, 2.0),
		Vector3(2.0, WALL_HEIGHT, span),
		Vector3(2.0, WALL_HEIGHT, span),
	]
	for i in offsets.size():
		_add_box(offsets[i], sizes[i], mat)


func _build_obstacles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = BLOCK_SEED
	var rock_mat := _make_material(Color(0.35, 0.33, 0.30))
	var wood_mat := _make_material(Color(0.42, 0.28, 0.16))

	# Scattered cover, kept out of the central plaza.
	for i in 26:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(15.0, ARENA_HALF_SIZE - 6.0)
		var height := rng.randf_range(1.0, 4.0)
		var width := rng.randf_range(1.5, 4.0)
		var depth := rng.randf_range(1.5, 4.0)
		var block := _add_box(
			Vector3(cos(angle) * distance, height * 0.5, sin(angle) * distance),
			Vector3(width, height, depth),
			rock_mat if i % 3 else wood_mat
		)
		block.rotation.y = rng.randf() * TAU

	# A stair of 0.5 m steps leading to a platform, for testing jumps and the
	# way the third-person spring arm handles geometry behind the player.
	for step in 6:
		var top := 0.5 * float(step + 1)
		_add_box(
			Vector3(-16.0 + float(step) * 2.2, top * 0.5, 14.0),
			Vector3(2.2, top, 4.0),
			rock_mat
		)
	_add_box(Vector3(-1.0, 2.9, 14.0), Vector3(8.0, 0.4, 6.0), wood_mat)
