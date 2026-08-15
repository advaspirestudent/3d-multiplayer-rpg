## Character picker. One card per CharacterData resource found by GameState,
## each showing a live 3D preview of the model that character will use.
extends Control

signal confirmed(character_id: String)
signal cancelled

const CARD_SIZE := Vector2(230, 320)
const PREVIEW_SIZE := Vector2i(230, 230)

var _cards: Array[Dictionary] = []
var _selected_id := ""

@onready var card_row: HBoxContainer = %CardRow
@onready var description_label: Label = %DescriptionLabel
@onready var stats_label: Label = %StatsLabel
@onready var confirm_button: Button = %ConfirmButton


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void: cancelled.emit())
	confirm_button.pressed.connect(_on_confirm)


## Rebuilds the roster of cards. Call this every time the screen is shown so
## newly imported characters appear without restarting the game.
func refresh() -> void:
	GameState.reload_characters()
	for child in card_row.get_children():
		child.queue_free()
	_cards.clear()

	if GameState.characters.is_empty():
		description_label.text = "No characters found in res://resources/characters/."
		confirm_button.disabled = true
		return

	confirm_button.disabled = false
	for data in GameState.characters:
		_cards.append(_build_card(data))

	var wanted := GameState.selected_character_id
	if GameState.get_character(wanted) == null:
		wanted = GameState.characters[0].id
	_select(wanted)


func _build_card(data: CharacterData) -> Dictionary:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_select.bind(data.id))
	card_row.add_child(button)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	button.add_child(column)

	var preview := _build_preview(data)
	column.add_child(preview)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", data.accent_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var tag := Label.new()
	tag.text = "%d HP  ·  %.1f spd" % [data.max_health, data.run_speed]
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tag)

	return {"id": data.id, "data": data, "button": button, "pivot": preview.get_meta("pivot")}


## A SubViewport with its own little world, so each card renders its model
## independently of the game world.
func _build_preview(data: CharacterData) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(PREVIEW_SIZE)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	container.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)

	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.72)
	environment.ambient_light_energy = 1.4
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(35.0), 0.0)
	light.light_energy = 1.4
	world.add_child(light)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.15, 2.7)
	camera.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)
	camera.fov = 45.0
	camera.current = true
	world.add_child(camera)

	var pivot := Node3D.new()
	world.add_child(pivot)
	pivot.add_child(_instantiate_model(data))

	container.set_meta("pivot", pivot)
	return container


func _instantiate_model(data: CharacterData) -> Node3D:
	var model: Node3D
	if data.model_scene != null:
		model = data.model_scene.instantiate() as Node3D
	if model == null:
		model = _placeholder_model(data.accent_color)
	model.scale = Vector3.ONE * data.model_scale
	model.position = data.model_offset
	model.rotation.y = deg_to_rad(data.model_yaw_offset_deg)
	return model


## Mirrors the placeholder in player.gd so the preview matches what you spawn as.
func _placeholder_model(color: Color) -> Node3D:
	var root := Node3D.new()
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

	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.22)
	nose.mesh = box
	nose.material_override = material
	nose.position = Vector3(0.0, 1.72, -0.24)
	root.add_child(nose)
	return root


func _process(delta: float) -> void:
	if not visible:
		return
	for card in _cards:
		var pivot: Node3D = card["pivot"]
		if is_instance_valid(pivot):
			# The selected character turns faster so the eye lands on it.
			var speed := 0.9 if card["id"] == _selected_id else 0.25
			pivot.rotate_y(speed * delta)


func _select(character_id: String) -> void:
	_selected_id = character_id
	for card in _cards:
		card["button"].button_pressed = card["id"] == character_id
	var data := GameState.get_character(character_id)
	if data == null:
		return
	description_label.text = data.description
	stats_label.text = "Health %d    Walk %.1f    Sprint %.1f    Damage %d" % [
		data.max_health, data.walk_speed, data.run_speed, data.attack_damage
	]


func _on_confirm() -> void:
	if _selected_id.is_empty():
		return
	confirmed.emit(_selected_id)
