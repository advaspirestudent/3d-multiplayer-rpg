## Autoload. Owns the ENet peer and the authoritative roster of connected
## players. It does not touch the world; `main.gd` reacts to the signals here
## and does the spawning.
extends Node

signal server_started
signal connection_succeeded
signal connection_failed(reason: String)
signal server_disconnected
signal player_registered(peer_id: int)
signal player_removed(peer_id: int)
signal roster_changed

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 16

## peer_id -> { "name": String, "character": String }
var roster: Dictionary = {}
var is_online := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Session control -------------------------------------------------------

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("Could not open port %d (error %d)." % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	roster.clear()
	roster[1] = {
		"name": GameState.player_name,
		"character": GameState.selected_character_id,
	}
	server_started.emit()
	roster_changed.emit()
	player_registered.emit(1)
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Could not reach %s:%d (error %d)." % [address, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	return OK


func leave_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_online = false
	roster.clear()
	roster_changed.emit()


func local_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func player_count() -> int:
	return roster.size()


func get_display_name(peer_id: int) -> String:
	var entry: Dictionary = roster.get(peer_id, {})
	return entry.get("name", "Player %d" % peer_id)


func get_character_id(peer_id: int) -> String:
	var entry: Dictionary = roster.get(peer_id, {})
	return entry.get("character", "")


# --- Handshake -------------------------------------------------------------

## Called by main.gd once the client has its world loaded and can safely
## receive spawns.
func send_registration() -> void:
	_register.rpc_id(1, GameState.player_name, GameState.selected_character_id)


@rpc("any_peer", "call_remote", "reliable")
func _register(display_name: String, character_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	# Validate: never trust a client-supplied character id.
	var character := GameState.get_character_or_default(character_id)
	roster[peer_id] = {
		"name": display_name.strip_edges().left(20),
		"character": character.id if character != null else "",
	}
	_sync_roster.rpc(roster)
	roster_changed.emit()
	player_registered.emit(peer_id)


@rpc("authority", "call_remote", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	roster_changed.emit()


# --- Peer signals ----------------------------------------------------------

func _on_peer_connected(_peer_id: int) -> void:
	# The client introduces itself via _register once its world is ready.
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	roster.erase(peer_id)
	if multiplayer.is_server():
		_sync_roster.rpc(roster)
	player_removed.emit(peer_id)
	roster_changed.emit()


func _on_connected_to_server() -> void:
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	is_online = false
	multiplayer.multiplayer_peer = null
	connection_failed.emit("The server refused the connection.")


func _on_server_disconnected() -> void:
	is_online = false
	multiplayer.multiplayer_peer = null
	roster.clear()
	server_disconnected.emit()
