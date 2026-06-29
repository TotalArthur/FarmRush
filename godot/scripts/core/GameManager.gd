extends Node

## Autoload "Game" — owns the live match and is the single entry point for
## every player/AI action. Handles the three modes:
##   SINGLE  : 1 human + AI opponents, all local.
##   HOTSEAT : several humans sharing one screen.
##   ONLINE  : host is authoritative; clients send action requests and receive
##             synced state.

signal state_changed
signal action_rejected(message)
signal game_over(winner_seat)

enum Mode { SINGLE, HOTSEAT, ONLINE }

var mode: int = Mode.SINGLE
var state: GameState
var local_seat: int = 0          # seat this machine "is" (online); 0 otherwise
var peer_to_seat: Dictionary = {}  # online only
var _ai_busy: bool = false

# ---------------------------------------------------------------------------
#  Starting a match
# ---------------------------------------------------------------------------
func start_game(new_mode: int, player_defs: Array) -> void:
	mode = new_mode
	state = GameState.new()
	state.start_new(player_defs)
	peer_to_seat.clear()
	local_seat = 0
	for i in range(player_defs.size()):
		var pd: Dictionary = player_defs[i]
		var peer: int = pd.get("net_peer_id", 0)
		if peer != 0:
			peer_to_seat[peer] = i
		if peer == Net.local_id():
			local_seat = i
	if mode != Mode.ONLINE:
		local_seat = -1  # all local seats controllable
	state_changed.emit()
	if mode == Mode.ONLINE and Net.is_host:
		_broadcast_state()
	_post_apply()

## Convenience for the menu: single-player vs N AI opponents.
func start_single(human_name: String, ai_count: int) -> void:
	var defs: Array = [{ "name": human_name, "is_ai": false }]
	for i in range(ai_count):
		defs.append({ "name": "Bot %d" % (i + 1), "is_ai": true })
	start_game(Mode.SINGLE, defs)

## Convenience for the menu: local hotseat with given human names.
func start_hotseat(names: Array) -> void:
	var defs: Array = []
	for n in names:
		defs.append({ "name": n, "is_ai": false })
	start_game(Mode.HOTSEAT, defs)

## Host builds the online match from the lobby roster (+ optional AI fill).
func start_online_host(ai_fill: int = 0) -> void:
	var defs: Array = []
	for peer in Net.lobby:
		defs.append({
			"name": Net.lobby[peer].get("name", "Player"),
			"is_ai": false,
			"net_peer_id": peer,
		})
	for i in range(ai_fill):
		defs.append({ "name": "Bot %d" % (i + 1), "is_ai": true })
	start_game(Mode.ONLINE, defs)

# ---------------------------------------------------------------------------
#  Action entry point
# ---------------------------------------------------------------------------
func apply_action(action: Dictionary) -> void:
	if state == null:
		return
	if mode == Mode.ONLINE and not Net.is_host:
		_req_action.rpc_id(1, JSON.stringify(action))
		return
	var actor := _local_actor_for(action)
	_authoritative_apply(action, actor)

func _local_actor_for(action: Dictionary) -> int:
	# Discards can come from any owing player; everything else is the current one.
	if action.get("type", "") == "discard":
		return action.get("player", state.current)
	return state.current

@rpc("any_peer", "call_remote", "reliable")
func _req_action(json: String) -> void:
	if not Net.is_host:
		return
	var parsed = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var action: Dictionary = parsed
	var sender := multiplayer.get_remote_sender_id()
	var actor: int = peer_to_seat.get(sender, -1)
	if actor == -1:
		return
	_authoritative_apply(action, actor)

func _authoritative_apply(action: Dictionary, actor: int) -> void:
	if not _actor_allowed(action, actor):
		action_rejected.emit("It's not your turn.")
		return
	# Stamp the acting seat for actions that need it.
	if action.get("type", "") == "discard":
		action["player"] = actor
	var result := state.apply(action)
	if not result["ok"]:
		action_rejected.emit(result["error"])
		# Still sync so clients/AI stay consistent on rejected no-ops? No-op.
		return
	if mode == Mode.ONLINE and Net.is_host:
		_broadcast_state()
	state_changed.emit()
	if state.phase == Consts.Phase.GAME_OVER:
		game_over.emit(state.winner)
	_post_apply()

func _actor_allowed(action: Dictionary, actor: int) -> bool:
	var t: String = action.get("type", "")
	# Discards may be submitted by any player who owes one.
	if t == "discard":
		return state.pending_discards.has(actor)
	# Accepted player-trade transfers are validated inside GameState.
	if t == "give_resources":
		return true
	# Everything else must come from the current player.
	return actor == state.current

# ---------------------------------------------------------------------------
#  State sync (host -> clients)
# ---------------------------------------------------------------------------
func _broadcast_state() -> void:
	_recv_state.rpc(JSON.stringify(state.to_dict()))

@rpc("authority", "call_remote", "reliable")
func _recv_state(json: String) -> void:
	var parsed = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	mode = Mode.ONLINE  # clients learn the mode from the first sync
	if state == null:
		state = GameState.new()
	state.apply_dict(parsed)
	# Re-resolve which seat is "us".
	for i in range(state.players.size()):
		if state.players[i].net_peer_id == Net.local_id():
			local_seat = i
	state_changed.emit()
	if state.phase == Consts.Phase.GAME_OVER:
		game_over.emit(state.winner)

# ---------------------------------------------------------------------------
#  Driving AI + auto-discards (authority side only)
# ---------------------------------------------------------------------------
func _post_apply() -> void:
	if mode == Mode.ONLINE and not Net.is_host:
		return
	if state == null or state.phase == Consts.Phase.GAME_OVER:
		return
	if _ai_busy:
		return
	# Auto-discard for AI players first.
	if state.phase == Consts.Phase.DISCARD:
		for pid in state.pending_discards.keys():
			if state.players[pid].is_ai:
				_ai_busy = true
				_run_ai_step.call_deferred()
				return
		return
	# AI takes its turn.
	if state.players[state.current].is_ai:
		_ai_busy = true
		_run_ai_step.call_deferred()

func _run_ai_step() -> void:
	await get_tree().create_timer(0.6).timeout
	_ai_busy = false
	if state == null or state.phase == Consts.Phase.GAME_OVER:
		return
	var action := AIBot.choose_action(state)
	if action.is_empty():
		return
	var actor: int = action.get("player", state.current)
	_authoritative_apply(action, actor)

# ---------------------------------------------------------------------------
#  Helpers for the UI
# ---------------------------------------------------------------------------
## Which seat the local human is currently allowed to drive.
func active_human_seat() -> int:
	if state == null:
		return -1
	if state.phase == Consts.Phase.DISCARD:
		# The owing human (in online, only ourselves).
		for pid in state.pending_discards:
			if not state.players[pid].is_ai:
				if mode != Mode.ONLINE or pid == local_seat:
					return pid
		return -1
	var cur := state.current
	if state.players[cur].is_ai:
		return -1
	if mode == Mode.ONLINE:
		return cur if cur == local_seat else -1
	return cur  # SINGLE / HOTSEAT: the local machine drives the current human

func is_my_control() -> bool:
	return active_human_seat() != -1
