## In-game overlay: connection info, control hints, crosshair, pause panel.
extends Control

signal leave_requested

var _player: Player


func _ready() -> void:
	%ResumeButton.pressed.connect(_close_pause)
	%LeaveButton.pressed.connect(func() -> void: leave_requested.emit())
	%PausePanel.hide()
	NetworkManager.roster_changed.connect(_refresh_roster)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		%PausePanel.hide()
		_refresh_roster()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if %PausePanel.visible:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		# Clicking back into the world re-captures the mouse.
		if not %PausePanel.visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_pause() -> void:
	%PausePanel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_pause() -> void:
	%PausePanel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("local_player") as Player
	if _player == null:
		%ViewLabel.text = "Spawning..."
		%Crosshair.hide()
		return

	var first_person := _player.view_mode == Player.ViewMode.FIRST_PERSON
	%ViewLabel.text = "View: %s   (V to switch)" % (
		"First person" if first_person else "Third person"
	)
	%Crosshair.visible = first_person and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _refresh_roster() -> void:
	var id := NetworkManager.local_id()
	var role := "Host" if multiplayer.multiplayer_peer != null and multiplayer.is_server() else "Client"
	%StatusLabel.text = "%s  ·  %s  ·  %d player(s) online" % [
		GameState.player_name, role, NetworkManager.player_count()
	]
	var lines: Array[String] = []
	for peer_id in NetworkManager.roster:
		var marker := "> " if peer_id == id else "  "
		lines.append("%s%s" % [marker, NetworkManager.get_display_name(peer_id)])
	%RosterLabel.text = "\n".join(lines)
