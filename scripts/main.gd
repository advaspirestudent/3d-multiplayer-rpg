## Root controller. Owns the screen flow (menu -> character select -> world)
## and, on the server, decides when players are spawned and despawned.
extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MAP_SCENE := preload("res://scenes/maps/arena.tscn")

var _map: Node3D
var _spawn_index := 0

@onready var map_root: Node3D = $World/MapRoot
@onready var players_root: Node3D = $World/Players
@onready var spawner: MultiplayerSpawner = $World/PlayerSpawner
@onready var main_menu: Control = $UI/MainMenu
@onready var character_select: Control = $UI/CharacterSelect
@onready var hud: Control = $UI/HUD


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.player_removed.connect(_on_player_removed)

	main_menu.play_requested.connect(_on_play_requested)
	main_menu.quit_requested.connect(func() -> void: get_tree().quit())
	character_select.confirmed.connect(_on_character_confirmed)
	character_select.cancelled.connect(_show_main_menu)
	hud.leave_requested.connect(_leave_to_menu)

	_show_main_menu()
	_apply_command_line()


## Quick-connect flags, handy for launching a second window while testing:
##   godot --path . -- --host
##   godot --path . -- --join 127.0.0.1 --name Bob --character rogue
func _apply_command_line() -> void:
	var user_args := OS.get_cmdline_user_args()
	var mode := ""
	var address := "127.0.0.1"
	var port := NetworkManager.DEFAULT_PORT
	var character_given := false
	for i in user_args.size():
		match user_args[i]:
			"--host":
				mode = "host"
			"--join":
				mode = "join"
				if i + 1 < user_args.size():
					address = user_args[i + 1]
			"--port":
				if i + 1 < user_args.size():
					port = int(user_args[i + 1])
			"--name":
				if i + 1 < user_args.size():
					GameState.player_name = user_args[i + 1]
			"--character":
				if i + 1 < user_args.size():
					GameState.selected_character_id = user_args[i + 1]
					character_given = true
	if mode.is_empty():
		return
	if character_given:
		# Fully specified: skip both menus and go straight into the world.
		_pending_mode = mode
		_pending_address = address
		_pending_port = port
		main_menu.hide()
		_on_character_confirmed(GameState.selected_character_id)
	else:
		_on_play_requested(mode, address, port)


# --- Screen flow -----------------------------------------------------------

func _show_main_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_menu.show()
	character_select.hide()
	hud.hide()


## `mode` is "host" or "join"; the connection details are cached until the
## player has picked a character.
var _pending_mode := ""
var _pending_address := ""
var _pending_port := NetworkManager.DEFAULT_PORT


func _on_play_requested(mode: String, address: String, port: int) -> void:
	_pending_mode = mode
	_pending_address = address
	_pending_port = port
	main_menu.hide()
	character_select.show()
	character_select.refresh()


func _on_character_confirmed(character_id: String) -> void:
	GameState.selected_character_id = character_id
	character_select.hide()
	var err := OK
	if _pending_mode == "host":
		err = NetworkManager.host_game(_pending_port)
	else:
		main_menu.set_status("Connecting to %s..." % _pending_address)
		err = NetworkManager.join_game(_pending_address, _pending_port)
	if err != OK:
		_show_main_menu()


func _enter_world() -> void:
	if _map == null:
		_map = MAP_SCENE.instantiate()
		map_root.add_child(_map)
	hud.show()
	main_menu.hide()
	character_select.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave_to_menu() -> void:
	NetworkManager.leave_game()
	for child in players_root.get_children():
		child.queue_free()
	if _map != null:
		_map.queue_free()
		_map = null
	_spawn_index = 0
	main_menu.set_status("")
	_show_main_menu()


# --- Network reactions -----------------------------------------------------

func _on_server_started() -> void:
	print("[net] hosting on port %d" % _pending_port)
	_enter_world()


func _on_connection_succeeded() -> void:
	print("[net] connected to %s as peer %d" % [_pending_address, NetworkManager.local_id()])
	_enter_world()
	# Only introduce ourselves once the world exists, so incoming spawns have
	# somewhere to land.
	NetworkManager.send_registration()


func _on_connection_failed(reason: String) -> void:
	NetworkManager.leave_game()
	_show_main_menu()
	main_menu.set_status(reason)


func _on_server_disconnected() -> void:
	_leave_to_menu()
	main_menu.set_status("Disconnected from the server.")


func _on_player_registered(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var spawn_position := Vector3(0.0, 1.5, 0.0)
	if _map != null and _map.has_method("get_spawn_point"):
		spawn_position = _map.get_spawn_point(_spawn_index)
	_spawn_index += 1
	print("[net] spawning %s (peer %d) as '%s' at %v" % [
		NetworkManager.get_display_name(peer_id),
		peer_id,
		NetworkManager.get_character_id(peer_id),
		spawn_position,
	])
	spawner.spawn({
		"peer": peer_id,
		"name": NetworkManager.get_display_name(peer_id),
		"character": NetworkManager.get_character_id(peer_id),
		"position": spawn_position,
	})


func _on_player_removed(peer_id: int) -> void:
	print("[net] peer %d left" % peer_id)
	var node := players_root.get_node_or_null(_player_node_name(peer_id))
	if node != null:
		node.queue_free()


# --- Spawning --------------------------------------------------------------

func _player_node_name(peer_id: int) -> String:
	return "P%d" % peer_id


## Runs on every peer: the server calls it through MultiplayerSpawner.spawn()
## and clients replay it with the same data.
func _spawn_player(data: Dictionary) -> Node:
	var peer_id := int(data.get("peer", 1))
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = _player_node_name(peer_id)
	player.player_name = String(data.get("name", "Player"))
	player.character_id = String(data.get("character", ""))
	player.position = data.get("position", Vector3.UP)
	player.set_multiplayer_authority(peer_id)
	return player


func local_player() -> Player:
	var id := NetworkManager.local_id()
	if id == 0:
		return null
	return players_root.get_node_or_null(_player_node_name(id)) as Player
