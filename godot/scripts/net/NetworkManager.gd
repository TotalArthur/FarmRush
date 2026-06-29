extends Node

## Autoload "Net" — thin wrapper over Godot's high-level multiplayer.
##
## Handles hosting / joining over ENet and keeps a synced lobby roster. The
## actual game-state sync lives in GameManager; this just owns the connection
## and the lobby.

signal lobby_changed
signal connection_failed
signal connection_succeeded
signal server_disconnected
signal game_should_start  # host pressed start; clients switch to the game scene

const DEFAULT_PORT := 24816
const MAX_PLAYERS := 6

var is_online: bool = false
var is_host: bool = false
# peer_id -> { "name": String }
var lobby: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(player_name: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = true
	lobby.clear()
	lobby[1] = { "name": player_name }
	lobby_changed.emit()
	return true

func join_game(player_name: String, address: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = false
	_pending_name = player_name
	return true

var _pending_name: String = ""

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_online = false
	is_host = false
	lobby.clear()
	lobby_changed.emit()

func local_id() -> int:
	if not is_online:
		return 1
	return multiplayer.get_unique_id()

# --- Connection callbacks --------------------------------------------------
func _on_peer_connected(id: int) -> void:
	# Server tells the newcomer the full roster after they register.
	pass

func _on_peer_disconnected(id: int) -> void:
	if is_host:
		lobby.erase(id)
		_broadcast_lobby()
		lobby_changed.emit()

func _on_connected_to_server() -> void:
	# Register our name with the host.
	_register.rpc_id(1, _pending_name)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	is_online = false
	connection_failed.emit()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	is_online = false
	lobby.clear()
	server_disconnected.emit()

# --- Lobby sync ------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	lobby[id] = { "name": player_name }
	_broadcast_lobby()
	lobby_changed.emit()

func _broadcast_lobby() -> void:
	_receive_lobby.rpc(lobby)

@rpc("authority", "call_remote", "reliable")
func _receive_lobby(new_lobby: Dictionary) -> void:
	lobby = new_lobby
	lobby_changed.emit()

func start_match() -> void:
	# Host only. Tell everyone to enter the game scene.
	if not is_host:
		return
	_start.rpc()
	game_should_start.emit()

@rpc("authority", "call_remote", "reliable")
func _start() -> void:
	game_should_start.emit()
