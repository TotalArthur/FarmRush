class_name GameState
extends RefCounted

## Authoritative, headless game logic for the whole match.
##
## Everything the rules need lives here. It validates and applies "actions"
## (plain dictionaries) and is fully serializable so the host can sync it to
## clients over the network. UI and AI never mutate this directly — they go
## through GameManager.apply_action().

var board: HexBoard

# Board contents (parallel to board.hex_center).
var hex_res: Array[int] = []        # Consts.Res value, or -1 for desert
var hex_token: Array[int] = []      # dice number, or 0 for desert
var robber_hex: int = 0

# Placements.
var buildings: Dictionary = {}      # vertex id -> { "owner": int, "city": bool }
var roads: Dictionary = {}          # edge id -> owner id

# Players + turn tracking.
var players: Array[Player] = []
var current: int = 0
var phase: int = Consts.Phase.LOBBY
var dice: Array[int] = [0, 0]
var has_rolled: bool = false
var dev_played_this_turn: bool = false
var free_roads: int = 0             # from Road Building / setup
var winner: int = -1

# Development deck.
var dev_deck: Array[int] = []

# Setup (initial placement) tracking.
var setup_order: Array[int] = []
var setup_index: int = 0
var setup_need_road: bool = false
var setup_last_vertex: int = -1

# Robber / discard flow.
var pending_discards: Dictionary = {}   # player id -> number of cards to discard
var return_phase: int = Consts.Phase.MAIN

# Bonus holders.
var longest_road_owner: int = -1
var largest_army_owner: int = -1

var log: Array[String] = []

# ===========================================================================
#  Setup
# ===========================================================================
func start_new(player_defs: Array) -> void:
	board = HexBoard.new()
	_layout_board()
	players.clear()
	for i in range(player_defs.size()):
		var d: Dictionary = player_defs[i]
		var p := Player.new()
		p.id = i
		p.name = d.get("name", "Player %d" % (i + 1))
		p.color = Consts.PLAYER_COLORS[i % Consts.PLAYER_COLORS.size()]
		p.is_ai = d.get("is_ai", false)
		p.net_peer_id = d.get("net_peer_id", 0)
		players.append(p)

	dev_deck.assign(Consts.DEV_BAG)
	dev_deck.shuffle()

	# Snake setup order: 0..n-1 then n-1..0
	setup_order.clear()
	for i in range(players.size()):
		setup_order.append(i)
	for i in range(players.size() - 1, -1, -1):
		setup_order.append(i)
	setup_index = 0
	setup_need_road = false
	setup_last_vertex = -1

	current = setup_order[0]
	phase = Consts.Phase.SETUP
	_log("Game started — place your first settlement.")

func _layout_board() -> void:
	var tiles := Consts.TILE_BAG.duplicate()
	tiles.shuffle()
	var tokens := Consts.TOKEN_BAG.duplicate()
	tokens.shuffle()
	hex_res.clear()
	hex_token.clear()
	# Pick a random hex to be the desert.
	var desert_index := randi() % board.hex_count()
	var ti := 0
	var ki := 0
	for h in range(board.hex_count()):
		if h == desert_index:
			hex_res.append(-1)
			hex_token.append(0)
			robber_hex = h
		else:
			hex_res.append(tiles[ti]); ti += 1
			hex_token.append(tokens[ki]); ki += 1

# ===========================================================================
#  Action dispatch
# ===========================================================================
func apply(action: Dictionary) -> Dictionary:
	var t: String = action.get("type", "")
	match t:
		"setup_settlement": return _do_setup_settlement(action)
		"setup_road": return _do_setup_road(action)
		"roll": return _do_roll(action)
		"discard": return _do_discard(action)
		"move_robber": return _do_move_robber(action)
		"build_road": return _do_build_road(action)
		"build_settlement": return _do_build_settlement(action)
		"build_city": return _do_build_city(action)
		"buy_dev": return _do_buy_dev(action)
		"play_dev": return _do_play_dev(action)
		"bank_trade": return _do_bank_trade(action)
		"give_resources": return _do_give_resources(action)  # accepted player trade
		"end_turn": return _do_end_turn(action)
	return _err("Unknown action: %s" % t)

func _ok(msg: String = "") -> Dictionary:
	if msg != "":
		_log(msg)
	return { "ok": true, "error": "" }

func _err(msg: String) -> Dictionary:
	return { "ok": false, "error": msg }

func _log(msg: String) -> void:
	log.append(msg)
	if log.size() > 100:
		log.remove_at(0)

# ===========================================================================
#  Setup phase
# ===========================================================================
func _do_setup_settlement(a: Dictionary) -> Dictionary:
	if phase != Consts.Phase.SETUP or setup_need_road:
		return _err("Not time to place a settlement.")
	var v: int = a["vertex"]
	if not _vertex_open_for_settlement(v, true):
		return _err("Can't build there.")
	var pid := current
	buildings[v] = { "owner": pid, "city": false }
	players[pid].settlements_left -= 1
	setup_need_road = true
	setup_last_vertex = v
	# Second-round settlement yields starting resources.
	if setup_index >= players.size():
		for h in board.vertex_hexes[v]:
			if hex_res[h] != -1:
				players[pid].add_res(hex_res[h], 1)
	_update_bonuses()
	return _ok("%s placed a settlement." % players[pid].name)

func _do_setup_road(a: Dictionary) -> Dictionary:
	if phase != Consts.Phase.SETUP or not setup_need_road:
		return _err("Place a settlement first.")
	var e: int = a["edge"]
	var edge := board.edges[e]
	if roads.has(e):
		return _err("Road already there.")
	if edge.x != setup_last_vertex and edge.y != setup_last_vertex:
		return _err("Road must touch your new settlement.")
	var pid := current
	roads[e] = pid
	players[pid].roads_left -= 1
	setup_need_road = false
	_update_bonuses()
	# Advance snake order.
	setup_index += 1
	if setup_index >= setup_order.size():
		# Setup complete — first player begins.
		current = setup_order[0]
		phase = Consts.Phase.ROLL
		has_rolled = false
		_begin_turn_reset()
		_log("Setup complete! %s rolls to begin." % players[current].name)
	else:
		current = setup_order[setup_index]
		var which := "second" if setup_index >= players.size() else "first"
		_log("%s — place your %s settlement." % [players[current].name, which])
	return _ok()

# ===========================================================================
#  Rolling + production
# ===========================================================================
func _do_roll(a: Dictionary) -> Dictionary:
	if phase != Consts.Phase.ROLL:
		return _err("Not time to roll.")
	dice[0] = (randi() % 6) + 1
	dice[1] = (randi() % 6) + 1
	var total: int = dice[0] + dice[1]
	has_rolled = true
	_log("%s rolled %d (%d + %d)." % [players[current].name, total, dice[0], dice[1]])
	if total == 7:
		_begin_robber(Consts.Phase.MAIN, true)
	else:
		_produce(total)
		phase = Consts.Phase.MAIN
	return _ok()

func _produce(total: int) -> void:
	for h in range(board.hex_count()):
		if hex_token[h] != total or h == robber_hex or hex_res[h] == -1:
			continue
		var res: int = hex_res[h]
		for v in board.hex_vertices[h]:
			if buildings.has(v):
				var b: Dictionary = buildings[v]
				var amount := 2 if b["city"] else 1
				players[b["owner"]].add_res(res, amount)

func _begin_robber(after: int, with_discard: bool) -> void:
	return_phase = after
	pending_discards.clear()
	if with_discard:
		for p in players:
			if p.total_resources() > 7:
				pending_discards[p.id] = p.total_resources() / 2  # floor (7 cards or fewer kept)
	if pending_discards.is_empty():
		phase = Consts.Phase.MOVE_ROBBER
		_log("%s must move the robber." % players[current].name)
	else:
		phase = Consts.Phase.DISCARD
		_log("A 7! Players with more than 7 cards must discard.")

func _do_discard(a: Dictionary) -> Dictionary:
	if phase != Consts.Phase.DISCARD:
		return _err("Nothing to discard.")
	var pid: int = a["player"]
	if not pending_discards.has(pid):
		return _err("You don't need to discard.")
	var to_drop: Dictionary = a["resources"]
	var need: int = pending_discards[pid]
	var total := 0
	for r in to_drop:
		total += to_drop[r]
	if total != need:
		return _err("Must discard exactly %d cards." % need)
	var p := players[pid]
	for r in to_drop:
		if p.resources.get(int(r), 0) < to_drop[r]:
			return _err("You don't have those cards.")
	for r in to_drop:
		p.resources[int(r)] -= to_drop[r]
	pending_discards.erase(pid)
	_log("%s discarded %d cards." % [p.name, need])
	if pending_discards.is_empty():
		phase = Consts.Phase.MOVE_ROBBER
		_log("%s must move the robber." % players[current].name)
	return _ok()

func _do_move_robber(a: Dictionary) -> Dictionary:
	if phase != Consts.Phase.MOVE_ROBBER:
		return _err("Not time to move the robber.")
	var h: int = a["hex"]
	if h == robber_hex:
		return _err("Move the robber to a different tile.")
	robber_hex = h
	# Steal one random card from a chosen adjacent victim.
	var victims := _robber_victims(h, current)
	var steal_from: int = a.get("steal_from", -1)
	if steal_from in victims:
		var target := players[steal_from]
		var pool: Array[int] = []
		for r in target.resources:
			for i in range(target.resources[r]):
				pool.append(r)
		if pool.size() > 0:
			var r: int = pool[randi() % pool.size()]
			target.resources[r] -= 1
			players[current].add_res(r, 1)
			_log("%s stole a card from %s." % [players[current].name, target.name])
	phase = return_phase
	return _ok("%s moved the robber." % players[current].name)

func _robber_victims(h: int, exclude: int) -> Array:
	var ids: Array = []
	for v in board.hex_vertices[h]:
		if buildings.has(v):
			var owner: int = buildings[v]["owner"]
			if owner != exclude and players[owner].total_resources() > 0 and not ids.has(owner):
				ids.append(owner)
	return ids

# ===========================================================================
#  Building
# ===========================================================================
func _do_build_road(a: Dictionary) -> Dictionary:
	if not _is_active_main():
		return _err("Not your build phase.")
	var e: int = a["edge"]
	var pid := current
	if roads.has(e):
		return _err("There's already a road here.")
	if players[pid].roads_left <= 0:
		return _err("No roads left.")
	if not _road_connects(e, pid):
		return _err("Roads must connect to your network.")
	var paying := free_roads <= 0
	if paying and not players[pid].can_afford(Consts.COST_ROAD):
		return _err("Not enough resources for a road.")
	if paying:
		players[pid].pay(Consts.COST_ROAD)
	else:
		free_roads -= 1
	roads[e] = pid
	players[pid].roads_left -= 1
	_update_bonuses()
	_check_winner()
	return _ok("%s built a road." % players[pid].name)

func _do_build_settlement(a: Dictionary) -> Dictionary:
	if not _is_active_main():
		return _err("Not your build phase.")
	var v: int = a["vertex"]
	var pid := current
	if players[pid].settlements_left <= 0:
		return _err("No settlements left.")
	if not _vertex_open_for_settlement(v, false):
		return _err("Can't build a settlement there.")
	if not _vertex_touches_own_road(v, pid):
		return _err("Settlements must touch your road.")
	if not players[pid].can_afford(Consts.COST_SETTLEMENT):
		return _err("Not enough resources.")
	players[pid].pay(Consts.COST_SETTLEMENT)
	buildings[v] = { "owner": pid, "city": false }
	players[pid].settlements_left -= 1
	_update_bonuses()
	_check_winner()
	return _ok("%s built a settlement." % players[pid].name)

func _do_build_city(a: Dictionary) -> Dictionary:
	if not _is_active_main():
		return _err("Not your build phase.")
	var v: int = a["vertex"]
	var pid := current
	if not buildings.has(v) or buildings[v]["owner"] != pid or buildings[v]["city"]:
		return _err("Upgrade your own settlement.")
	if players[pid].cities_left <= 0:
		return _err("No cities left.")
	if not players[pid].can_afford(Consts.COST_CITY):
		return _err("Not enough resources.")
	players[pid].pay(Consts.COST_CITY)
	buildings[v]["city"] = true
	players[pid].cities_left -= 1
	players[pid].settlements_left += 1
	_check_winner()
	return _ok("%s upgraded to a city." % players[pid].name)

# ===========================================================================
#  Development cards
# ===========================================================================
func _do_buy_dev(a: Dictionary) -> Dictionary:
	if not _is_active_main():
		return _err("Not your turn.")
	if dev_deck.is_empty():
		return _err("No development cards left.")
	var pid := current
	if not players[pid].can_afford(Consts.COST_DEV):
		return _err("Not enough resources.")
	players[pid].pay(Consts.COST_DEV)
	var card: int = dev_deck.pop_back()
	# Bought this turn — can't be played until next turn (except hidden VP).
	players[pid].dev_bought_this_turn[card] = players[pid].dev_bought_this_turn.get(card, 0) + 1
	_check_winner()
	return _ok("%s bought a development card." % players[pid].name)

func _do_play_dev(a: Dictionary) -> Dictionary:
	if not _is_active_main() and not (phase == Consts.Phase.ROLL and current == a.get("player", current)):
		return _err("Can't play a card now.")
	if dev_played_this_turn:
		return _err("Only one development card per turn.")
	var pid := current
	var card: int = a["card"]
	if players[pid].dev_cards.get(card, 0) <= 0:
		return _err("You don't have that card.")
	match card:
		Consts.Dev.KNIGHT:
			players[pid].dev_cards[card] -= 1
			players[pid].played_knights += 1
			dev_played_this_turn = true
			_update_bonuses()
			_begin_robber(phase, false)  # knight: move robber, no discards
			_check_winner()
			return _ok("%s played a Knight." % players[pid].name)
		Consts.Dev.ROAD_BUILDING:
			players[pid].dev_cards[card] -= 1
			dev_played_this_turn = true
			free_roads += 2
			return _ok("%s played Road Building — place 2 roads." % players[pid].name)
		Consts.Dev.YEAR_OF_PLENTY:
			var r1: int = a["res1"]
			var r2: int = a["res2"]
			players[pid].dev_cards[card] -= 1
			dev_played_this_turn = true
			players[pid].add_res(r1, 1)
			players[pid].add_res(r2, 1)
			return _ok("%s played Year of Plenty." % players[pid].name)
		Consts.Dev.MONOPOLY:
			var res: int = a["res"]
			players[pid].dev_cards[card] -= 1
			dev_played_this_turn = true
			var taken := 0
			for p in players:
				if p.id == pid:
					continue
				taken += p.resources.get(res, 0)
				p.resources[res] = 0
			players[pid].add_res(res, taken)
			return _ok("%s monopolized %s (+%d)." % [players[pid].name, Consts.RES_NAME[res], taken])
		Consts.Dev.VICTORY_POINT:
			return _err("Victory Point cards are revealed automatically when you win.")
	return _err("Unknown card.")

# ===========================================================================
#  Trading
# ===========================================================================
func _do_bank_trade(a: Dictionary) -> Dictionary:
	if not _is_active_main():
		return _err("Not your turn.")
	var give: int = a["give"]
	var get_res: int = a["get"]
	var pid := current
	var ratio := _best_ratio(pid, give)
	if players[pid].resources.get(give, 0) < ratio:
		return _err("Need %d %s to trade." % [ratio, Consts.RES_NAME[give]])
	players[pid].resources[give] -= ratio
	players[pid].add_res(get_res, 1)
	return _ok("%s traded %d %s for 1 %s." % [players[pid].name, ratio, Consts.RES_NAME[give], Consts.RES_NAME[get_res]])

func _best_ratio(pid: int, give: int) -> int:
	var ratio := 4
	for v in board.vertex_port:
		if buildings.has(v) and buildings[v]["owner"] == pid:
			var port = board.vertex_port[v]
			if port == null:
				ratio = min(ratio, 3)
			elif int(port) == give:
				ratio = min(ratio, 2)
	return ratio

# Direct resource transfer for an accepted player-to-player trade.
func _do_give_resources(a: Dictionary) -> Dictionary:
	var from_id: int = a["from"]
	var to_id: int = a["to"]
	var pack: Dictionary = a["resources"]
	var giver := players[from_id]
	for r in pack:
		if giver.resources.get(int(r), 0) < pack[r]:
			return _err("Trade failed — missing resources.")
	for r in pack:
		giver.resources[int(r)] -= pack[r]
		players[to_id].add_res(int(r), pack[r])
	return _ok()

# ===========================================================================
#  Turn flow
# ===========================================================================
func _do_end_turn(a: Dictionary) -> Dictionary:
	if not _is_active_main():
		return _err("Can't end turn now.")
	# Move cards bought this turn into the playable hand.
	var p := players[current]
	for card in p.dev_bought_this_turn:
		p.dev_cards[card] = p.dev_cards.get(card, 0) + p.dev_bought_this_turn[card]
	p.dev_bought_this_turn.clear()
	current = (current + 1) % players.size()
	phase = Consts.Phase.ROLL
	_begin_turn_reset()
	_log("%s's turn." % players[current].name)
	return _ok()

func _begin_turn_reset() -> void:
	has_rolled = false
	dev_played_this_turn = false
	free_roads = 0

func _is_active_main() -> bool:
	return phase == Consts.Phase.MAIN

# ===========================================================================
#  Placement validity
# ===========================================================================
func _vertex_open_for_settlement(v: int, _setup: bool) -> bool:
	if buildings.has(v):
		return false
	# Distance rule: no adjacent vertex may have a building.
	for n in board.vertex_neighbors[v]:
		if buildings.has(n):
			return false
	return true

func _vertex_touches_own_road(v: int, pid: int) -> bool:
	for n in board.vertex_neighbors[v]:
		var e := board.edge_id(v, n)
		if roads.get(e, -1) == pid:
			return true
	return false

func _road_connects(e: int, pid: int) -> bool:
	var edge := board.edges[e]
	for v in [edge.x, edge.y]:
		# Connects via own building...
		if buildings.has(v) and buildings[v]["owner"] == pid:
			return true
		# ...or via own adjacent road, as long as an opponent building
		# doesn't block the junction.
		if buildings.has(v) and buildings[v]["owner"] != pid:
			continue
		for n in board.vertex_neighbors[v]:
			var ne := board.edge_id(v, n)
			if ne != e and roads.get(ne, -1) == pid:
				return true
	return false

# ===========================================================================
#  Bonuses, victory points, winner
# ===========================================================================
func _update_bonuses() -> void:
	_update_longest_road()
	_update_largest_army()

func _update_longest_road() -> void:
	var best_len := 0
	var best_pid := -1
	var tie := false
	for p in players:
		var l := _longest_road_for(p.id)
		if l > best_len:
			best_len = l; best_pid = p.id; tie = false
		elif l == best_len and l > 0:
			tie = true
	for p in players:
		p.has_longest_road = false
	if best_len < Consts.LONGEST_ROAD_MIN:
		longest_road_owner = -1
		return
	# Keep current holder on ties; otherwise the unique leader takes it.
	if longest_road_owner != -1 and _longest_road_for(longest_road_owner) == best_len:
		players[longest_road_owner].has_longest_road = true
		return
	if not tie and best_pid != -1:
		longest_road_owner = best_pid
		players[best_pid].has_longest_road = true
	elif longest_road_owner != -1 and _longest_road_for(longest_road_owner) >= Consts.LONGEST_ROAD_MIN:
		players[longest_road_owner].has_longest_road = true
	else:
		longest_road_owner = -1

func _longest_road_for(pid: int) -> int:
	var best := 0
	for v in range(board.vertex_count()):
		# Only start from a vertex that has one of the player's roads.
		var has_road := false
		for n in board.vertex_neighbors[v]:
			if roads.get(board.edge_id(v, n), -1) == pid:
				has_road = true
				break
		if has_road:
			best = max(best, _road_dfs(pid, v, {}, true))
	return best

func _road_dfs(pid: int, v: int, used: Dictionary, is_start: bool) -> int:
	# Can't route through an opponent's building (except as the start vertex).
	if not is_start and buildings.has(v) and buildings[v]["owner"] != pid:
		return 0
	var best := 0
	for n in board.vertex_neighbors[v]:
		var e := board.edge_id(v, n)
		if roads.get(e, -1) == pid and not used.has(e):
			used[e] = true
			best = max(best, 1 + _road_dfs(pid, n, used, false))
			used.erase(e)
	return best

func _update_largest_army() -> void:
	var best := 0
	var best_pid := -1
	var tie := false
	for p in players:
		p.has_largest_army = false
		if p.played_knights > best:
			best = p.played_knights; best_pid = p.id; tie = false
		elif p.played_knights == best and best > 0:
			tie = true
	if best < Consts.LARGEST_ARMY_MIN:
		largest_army_owner = -1
		return
	if largest_army_owner != -1 and players[largest_army_owner].played_knights == best:
		players[largest_army_owner].has_largest_army = true
		return
	if not tie and best_pid != -1:
		largest_army_owner = best_pid
		players[best_pid].has_largest_army = true

func victory_points(pid: int, include_hidden: bool = true) -> int:
	var p := players[pid]
	var vp := 0
	for v in buildings:
		if buildings[v]["owner"] == pid:
			vp += 2 if buildings[v]["city"] else 1
	if p.has_longest_road:
		vp += 2
	if p.has_largest_army:
		vp += 2
	if include_hidden:
		vp += p.dev_cards.get(Consts.Dev.VICTORY_POINT, 0)
		vp += p.dev_bought_this_turn.get(Consts.Dev.VICTORY_POINT, 0)
	return vp

func _check_winner() -> void:
	if victory_points(current) >= Consts.WIN_POINTS:
		winner = current
		phase = Consts.Phase.GAME_OVER
		_log("🏆 %s wins the game!" % players[current].name)

# ===========================================================================
#  Serialization (for network sync)
# ===========================================================================
func to_dict() -> Dictionary:
	var ports := {}
	for v in board.vertex_port:
		var pt = board.vertex_port[v]
		ports[v] = -99 if pt == null else int(pt)
	var pdata := []
	for p in players:
		pdata.append(p.to_dict())
	# Buildings/roads with int keys → string keys for JSON safety on the wire.
	var bd := {}
	for v in buildings:
		bd[str(v)] = buildings[v]
	var rd := {}
	for e in roads:
		rd[str(e)] = roads[e]
	return {
		"hex_res": hex_res.duplicate(),
		"hex_token": hex_token.duplicate(),
		"robber_hex": robber_hex,
		"ports": ports,
		"buildings": bd,
		"roads": rd,
		"players": pdata,
		"current": current,
		"phase": phase,
		"dice": dice.duplicate(),
		"has_rolled": has_rolled,
		"dev_played_this_turn": dev_played_this_turn,
		"free_roads": free_roads,
		"winner": winner,
		"setup_order": setup_order.duplicate(),
		"setup_index": setup_index,
		"setup_need_road": setup_need_road,
		"setup_last_vertex": setup_last_vertex,
		"pending_discards": pending_discards.duplicate(),
		"return_phase": return_phase,
		"longest_road_owner": longest_road_owner,
		"largest_army_owner": largest_army_owner,
		"log": log.duplicate(),
	}

func apply_dict(d: Dictionary) -> void:
	# Note: JSON decodes every number as a float, so we coerce ints carefully
	# wherever a value is used as an array index, enum or count.
	if board == null:
		board = HexBoard.new()
	hex_res = _to_int_array(d["hex_res"])
	hex_token = _to_int_array(d["hex_token"])
	robber_hex = int(d["robber_hex"])
	for v in d["ports"]:
		var pt: int = int(d["ports"][v])
		board.vertex_port[int(v)] = null if pt == -99 else pt
	buildings.clear()
	for v in d["buildings"]:
		var b: Dictionary = d["buildings"][v]
		buildings[int(v)] = { "owner": int(b["owner"]), "city": bool(b["city"]) }
	roads.clear()
	for e in d["roads"]:
		roads[int(e)] = int(d["roads"][e])
	players.clear()
	for pd in d["players"]:
		players.append(Player.from_dict(pd))
	current = int(d["current"])
	phase = int(d["phase"])
	dice = _to_int_array(d["dice"])
	has_rolled = bool(d["has_rolled"])
	dev_played_this_turn = bool(d["dev_played_this_turn"])
	free_roads = int(d["free_roads"])
	winner = int(d["winner"])
	setup_order = _to_int_array(d["setup_order"])
	setup_index = int(d["setup_index"])
	setup_need_road = bool(d["setup_need_road"])
	setup_last_vertex = int(d["setup_last_vertex"])
	pending_discards.clear()
	for k in d["pending_discards"]:
		pending_discards[int(k)] = int(d["pending_discards"][k])
	return_phase = int(d["return_phase"])
	longest_road_owner = int(d["longest_road_owner"])
	largest_army_owner = int(d["largest_army_owner"])
	log.clear()
	for line in d["log"]:
		log.append(str(line))

static func _to_int_array(arr) -> Array[int]:
	var out: Array[int] = []
	for x in arr:
		out.append(int(x))
	return out
