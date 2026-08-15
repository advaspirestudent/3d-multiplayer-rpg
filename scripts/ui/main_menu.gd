## Title screen: pick a name, then host a world or join one.
extends Control

signal play_requested(mode: String, address: String, port: int)
signal quit_requested

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var port_spin: SpinBox = %PortSpin
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	name_edit.text = GameState.player_name
	port_spin.value = NetworkManager.DEFAULT_PORT
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%QuitButton.pressed.connect(func() -> void: quit_requested.emit())


func set_status(message: String) -> void:
	status_label.text = message


func _commit_name() -> bool:
	var chosen := name_edit.text.strip_edges()
	if chosen.is_empty():
		set_status("Enter a player name first.")
		return false
	GameState.player_name = chosen.left(20)
	return true


func _on_host_pressed() -> void:
	if not _commit_name():
		return
	set_status("")
	play_requested.emit("host", "", int(port_spin.value))


func _on_join_pressed() -> void:
	if not _commit_name():
		return
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		set_status("Enter the server address to join.")
		return
	set_status("")
	play_requested.emit("join", address, int(port_spin.value))
