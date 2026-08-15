## Describes one playable character.
##
## Drop a new `.tres` of this type into `res://resources/characters/` and it
## automatically shows up in the character-select screen. To use your own model,
## set `model_scene` to your imported `.glb`/`.gltf`/`.tscn` file and tune
## `model_scale` / `model_offset` / `model_yaw_offset_deg` until the character
## stands correctly on the ground and faces -Z.
class_name CharacterData
extends Resource

@export_group("Identity")
## Stable id used over the network. Must be unique and must not change.
@export var id: String = ""
@export var display_name: String = "Character"
@export_multiline var description: String = ""
## Used for the UI card accent and the fallback placeholder model.
@export var accent_color: Color = Color(0.6, 0.7, 1.0)

@export_group("Model")
## Your imported character scene. Leave empty to use a placeholder capsule.
@export var model_scene: PackedScene
@export var model_scale: float = 1.0
## Shifts the model inside the collision capsule (feet should land on y = 0).
@export var model_offset: Vector3 = Vector3.ZERO
## Rotate the model if it was authored facing +Z instead of Godot's -Z forward.
@export var model_yaw_offset_deg: float = 0.0
## Eye height, used by the first-person camera.
@export var head_height: float = 1.55

@export_group("Animation Names")
## Names as they appear in the model's AnimationPlayer. Blank = skip.
@export var anim_idle: String = "idle"
@export var anim_walk: String = "walk"
@export var anim_run: String = "run"
@export var anim_jump: String = "jump"
@export var anim_fall: String = "fall"

@export_group("Stats")
@export var max_health: int = 100
@export var walk_speed: float = 4.5
@export var run_speed: float = 8.0
@export var jump_velocity: float = 7.0
@export var attack_damage: int = 12
