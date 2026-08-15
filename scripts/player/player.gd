## Networked player character.
##
## The owning peer simulates movement locally and publishes `sync_*` state
## through the MultiplayerSynchronizer; every other peer smooths towards it.
class_name Player
extends CharacterBody3D

enum AnimState { IDLE, WALK, RUN, JUMP, FALL }
enum ViewMode { THIRD_PERSON, FIRST_PERSON }

const MOUSE_SENSITIVITY := 0.0022
const PITCH_MIN := -1.35
const PITCH_MAX := 1.30
const TP_MIN_ZOOM := 1.5
const TP_MAX_ZOOM := 8.0
const TP_SHOULDER_OFFSET := 0.5
const FP_FORWARD_OFFSET := 0.15
const TURN_SPEED := 12.0
const GROUND_ACCEL := 60.0
const AIR_ACCEL := 18.0
const REMOTE_SMOOTHING := 15.0

signal view_mode_changed(mode: ViewMode)

## Set by the spawner before the node enters the tree.
var player_name := "Player"
var character_id := ""

# --- Replicated state (see the MultiplayerSynchronizer in player.tscn) ---
var sync_position := Vector3.ZERO
var sync_yaw := 0.0
var sync_anim := AnimState.IDLE

var view_mode := ViewMode.THIRD_PERSON
var yaw := 0.0
var pitch := -0.15
var tp_zoom := 4.5

var _data: CharacterData
var _model: Node3D
var _anim_player: AnimationPlayer
var _gravity := 20.0
var _is_local := false
var _head_height := 1.55

@onready var model_root: Node3D = $ModelRoot
@onready var name_tag: Label3D = $NameTag
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 20.0))
	_is_local = is_multiplayer_authority()
	_apply_character()

	name_tag.text = player_name
	yaw = rotation.y
	sync_yaw = yaw
	sync_position = global_position

	if _is_local:
		add_to_group("local_player")
		name_tag.visible = false
		# Detaching the pivot from the body keeps the camera stable while the
		# character turns underneath it.
		camera_pivot.top_level = true
		camera.current = true
		set_view_mode(ViewMode.THIRD_PERSON)
		_update_camera(1.0)
	else:
		# Remote players do not need a camera rig at all.
		camera_pivot.queue_free()


## Rebuilds the visual model from the CharacterData resource.
func _apply_character() -> void:
	_data = GameState.get_character_or_default(character_id)
	for child in model_root.get_children():
		child.queue_free()

	var instance: Node3D
	if _data != null and _data.model_scene != null:
		instance = _data.model_scene.instantiate() as Node3D
	if instance == null:
		instance = _build_placeholder_model()

	model_root.add_child(instance)
	_model = instance

	if _data != null:
		instance.scale = Vector3.ONE * _data.model_scale
		instance.position = _data.model_offset
		instance.rotation.y = deg_to_rad(_data.model_yaw_offset_deg)
		_head_height = _data.head_height
	_anim_player = _find_animation_player(instance)


func _build_placeholder_model() -> Node3D:
	var root := Node3D.new()
	var color := _data.accent_color if _data != null else Color(0.7, 0.7, 0.8)

	var material := StandardMaterial3D.new()
	material.albedo_color = color

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	body.mesh = capsule
	body.material_override = material
	body.position = Vector3(0.0, 0.85, 0.0)
	root.add_child(body)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	head.mesh = sphere
	head.material_override = material
	head.position = Vector3(0.0, 1.75, 0.0)
	root.add_child(head)

	# A small nose so you can tell which way the placeholder is facing.
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.22)
	nose.mesh = box
	nose.material_override = material
	nose.position = Vector3(0.0, 1.72, -0.24)
	root.add_child(nose)
	return root


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_view"):
		toggle_view_mode()
		get_viewport().set_input_as_handled()
	elif view_mode == ViewMode.THIRD_PERSON and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("zoom_in"):
			tp_zoom = clampf(tp_zoom - 0.5, TP_MIN_ZOOM, TP_MAX_ZOOM)
		elif event.is_action_pressed("zoom_out"):
			tp_zoom = clampf(tp_zoom + 0.5, TP_MIN_ZOOM, TP_MAX_ZOOM)


func toggle_view_mode() -> void:
	set_view_mode(
		ViewMode.FIRST_PERSON if view_mode == ViewMode.THIRD_PERSON else ViewMode.THIRD_PERSON
	)


func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	if not _is_local or not is_instance_valid(spring_arm):
		return
	if mode == ViewMode.FIRST_PERSON:
		spring_arm.spring_length = 0.0
		spring_arm.position = Vector3.ZERO
		camera.position = Vector3(0.0, 0.0, -FP_FORWARD_OFFSET)
		_set_model_visible(false)
	else:
		spring_arm.spring_length = tp_zoom
		spring_arm.position = Vector3(TP_SHOULDER_OFFSET, 0.0, 0.0)
		camera.position = Vector3.ZERO
		_set_model_visible(true)
	view_mode_changed.emit(mode)


## In first person we keep the model in the world for its shadow, but stop it
## from being drawn over the camera.
func _set_model_visible(visible_to_owner: bool) -> void:
	if _model == null:
		return
	var mode := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if visible_to_owner
		else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	)
	_apply_shadow_mode(_model, mode)


func _apply_shadow_mode(node: Node, mode: int) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = mode
	for child in node.get_children():
		_apply_shadow_mode(child, mode)


# --- Simulation ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _is_local:
		_simulate_local(delta)
	else:
		_follow_remote(delta)
	_update_animation()


func _simulate_local(delta: float) -> void:
	var walk_speed := _data.walk_speed if _data != null else 4.5
	var run_speed := _data.run_speed if _data != null else 8.0
	var jump_velocity := _data.jump_velocity if _data != null else 7.0

	var input_locked := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	var input_dir := Vector2.ZERO
	if not input_locked:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Movement is relative to where the camera is looking.
	var cam_basis := Basis(Vector3.UP, yaw)
	var direction := (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var sprinting := not input_locked and Input.is_action_pressed("sprint")
	var target_speed := run_speed if sprinting else walk_speed
	var target_velocity := direction * target_speed

	var accel: float = GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	if is_on_floor():
		if not input_locked and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta

	move_and_slide()

	# Facing: locked to the camera in first person, otherwise it follows motion.
	if view_mode == ViewMode.FIRST_PERSON:
		rotation.y = yaw
	elif direction.length_squared() > 0.01:
		# A node with yaw t points its -Z forward at (-sin t, 0, -cos t), so the
		# yaw that faces `direction` is atan2(-x, -z).
		var facing := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, facing, TURN_SPEED * delta)

	sync_position = global_position
	sync_yaw = rotation.y
	sync_anim = _resolve_anim_state(sprinting)


func _follow_remote(delta: float) -> void:
	var weight := clampf(REMOTE_SMOOTHING * delta, 0.0, 1.0)
	# Snap instead of sliding across the map after a teleport or a long stall.
	if global_position.distance_squared_to(sync_position) > 100.0:
		global_position = sync_position
	else:
		global_position = global_position.lerp(sync_position, weight)
	rotation.y = lerp_angle(rotation.y, sync_yaw, weight)


func _resolve_anim_state(sprinting: bool) -> AnimState:
	if not is_on_floor():
		return AnimState.JUMP if velocity.y > 0.0 else AnimState.FALL
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar < 0.15:
		return AnimState.IDLE
	return AnimState.RUN if sprinting else AnimState.WALK


func _update_animation() -> void:
	if _anim_player == null or _data == null:
		return
	var wanted := ""
	match sync_anim:
		AnimState.IDLE: wanted = _data.anim_idle
		AnimState.WALK: wanted = _data.anim_walk
		AnimState.RUN: wanted = _data.anim_run
		AnimState.JUMP: wanted = _data.anim_jump
		AnimState.FALL: wanted = _data.anim_fall
	if wanted.is_empty() or not _anim_player.has_animation(wanted):
		return
	if _anim_player.current_animation != wanted:
		_anim_player.play(wanted)


# --- Camera ----------------------------------------------------------------

func _process(delta: float) -> void:
	if _is_local:
		_update_camera(delta)


func _update_camera(_delta: float) -> void:
	if not is_instance_valid(camera_pivot):
		return
	camera_pivot.global_position = global_position + Vector3.UP * _head_height
	camera_pivot.global_rotation = Vector3(pitch, yaw, 0.0)
	if view_mode == ViewMode.THIRD_PERSON:
		spring_arm.spring_length = tp_zoom
