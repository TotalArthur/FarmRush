class_name AIBot
extends RefCounted

## A lightweight heuristic opponent. Returns ONE action for the given state;
## GameManager calls it repeatedly so the bot can chain builds within a turn.

static func choose_action(s: GameState) -> Dictionary:
	match s.phase:
		Consts.Phase.SETUP:
			return _setup(s)
		Consts.Phase.ROLL:
			return { "type": "roll" }
		Consts.Phase.DISCARD:
			return _discard(s)
		Consts.Phase.MOVE_ROBBER:
			return _move_robber(s)
		Consts.Phase.MAIN:
			return _main(s)
	return {}

# --- Setup -----------------------------------------------------------------
static func _setup(s: GameState) -> Dictionary:
	var pid := s.current
	if s.setup_need_road:
		# Place a road off the just-built settlement toward good expansion.
		var v := s.setup_last_vertex
		var best_e := -1
		var best_score := -1.0
		for n in s.board.vertex_neighbors[v]:
			var e := s.board.edge_id(v, n)
			if s.roads.has(e):
				continue
			var score := _vertex_value(s, n)
			if score > best_score:
				best_score = score; best_e = e
		if best_e == -1:
			# Fallback: any free neighbor edge.
			for n in s.board.vertex_neighbors[v]:
				var e := s.board.edge_id(v, n)
				if not s.roads.has(e):
					best_e = e; break
		return { "type": "setup_road", "edge": best_e }
	# Place a settlement on the best open vertex.
	var best_v := -1
	var best_val := -1.0
	for v in range(s.board.vertex_count()):
		if not s._vertex_open_for_settlement(v, true):
			continue
		var val := _vertex_value(s, v)
		if val > best_val:
			best_val = val; best_v = v
	return { "type": "setup_settlement", "vertex": best_v }

# Sum of production "pips" across the hexes a vertex touches (with variety bonus).
static func _vertex_value(s: GameState, v: int) -> float:
	var score := 0.0
	var seen := {}
	for h in s.board.vertex_hexes[v]:
		if s.hex_res[h] == -1:
			continue
		score += Consts.TOKEN_PIPS.get(s.hex_token[h], 0)
		if not seen.has(s.hex_res[h]):
			seen[s.hex_res[h]] = true
			score += 0.5  # reward resource diversity
	if s.board.vertex_port.has(v):
		score += 0.4
	return score

# --- Discard ---------------------------------------------------------------
static func _discard(s: GameState) -> Dictionary:
	var pid := s.current
	# Find an AI that still owes a discard (current first).
	if not s.pending_discards.has(pid) or not s.players[pid].is_ai:
		for k in s.pending_discards:
			if s.players[k].is_ai:
				pid = k; break
	var need: int = s.pending_discards[pid]
	var have := s.players[pid].resources.duplicate()
	var drop := {}
	for i in range(need):
		# Drop from whichever pile is largest.
		var best_res := -1
		var best_amt := -1
		for r in have:
			if have[r] > best_amt:
				best_amt = have[r]; best_res = r
		have[best_res] -= 1
		drop[best_res] = drop.get(best_res, 0) + 1
	return { "type": "discard", "player": pid, "resources": drop }

# --- Robber ----------------------------------------------------------------
static func _move_robber(s: GameState) -> Dictionary:
	var pid := s.current
	var best_h := -1
	var best_score := -1
	for h in range(s.board.hex_count()):
		if h == s.robber_hex:
			continue
		var score := 0
		var hits_self := false
		for v in s.board.vertex_hexes[h]:
			if s.buildings.has(v):
				var owner: int = s.buildings[v]["owner"]
				if owner == pid:
					hits_self = true
				else:
					score += (2 if s.buildings[v]["city"] else 1) + s.players[owner].total_resources()
		if hits_self:
			score -= 100
		if score > best_score:
			best_score = score; best_h = h
	if best_h == -1:
		best_h = (s.robber_hex + 1) % s.board.hex_count()
	# Steal from the richest victim on that tile.
	var victims := s._robber_victims(best_h, pid)
	var target := -1
	var richest := -1
	for vic in victims:
		var tr := s.players[vic].total_resources()
		if tr > richest:
			richest = tr; target = vic
	return { "type": "move_robber", "hex": best_h, "steal_from": target }

# --- Main phase ------------------------------------------------------------
static func _main(s: GameState) -> Dictionary:
	var pid := s.current
	var p := s.players[pid]

	# 1) Upgrade the most productive settlement to a city.
	if p.can_afford(Consts.COST_CITY) and p.cities_left > 0:
		var best_v := -1
		var best_val := -1.0
		for v in s.buildings:
			if s.buildings[v]["owner"] == pid and not s.buildings[v]["city"]:
				var val := _vertex_value(s, v)
				if val > best_val:
					best_val = val; best_v = v
		if best_v != -1:
			return { "type": "build_city", "vertex": best_v }

	# 2) Build a settlement on the best connected, legal spot.
	if p.can_afford(Consts.COST_SETTLEMENT) and p.settlements_left > 0:
		var spot := _best_settlement_spot(s, pid)
		if spot != -1:
			return { "type": "build_settlement", "vertex": spot }

	# 3) If no spot is reachable, build a road toward a good open vertex.
	if p.can_afford(Consts.COST_ROAD) and p.roads_left > 0:
		var e := _expansion_road(s, pid)
		if e != -1:
			return { "type": "build_road", "edge": e }

	# 4) Bank-trade toward a city if we're close (surplus of something).
	var trade := _trade_toward_city(s, pid)
	if not trade.is_empty():
		return trade

	# 5) Buy a development card with spare resources.
	if p.can_afford(Consts.COST_DEV) and not s.dev_deck.is_empty() and p.total_resources() >= 4:
		return { "type": "buy_dev" }

	# 6) Otherwise end the turn.
	return { "type": "end_turn" }

static func _best_settlement_spot(s: GameState, pid: int) -> int:
	var best_v := -1
	var best_val := -1.0
	for v in range(s.board.vertex_count()):
		if not s._vertex_open_for_settlement(v, false):
			continue
		if not s._vertex_touches_own_road(v, pid):
			continue
		var val := _vertex_value(s, v)
		if val > best_val:
			best_val = val; best_v = v
	return best_v

static func _expansion_road(s: GameState, pid: int) -> int:
	# Choose a free, connectable road that brings us closest to a new spot.
	var best_e := -1
	var best_val := -1.0
	for e in range(s.board.edge_count()):
		if s.roads.has(e):
			continue
		if not s._road_connects(e, pid):
			continue
		var edge := s.board.edges[e]
		var val := maxf(_vertex_value(s, edge.x), _vertex_value(s, edge.y))
		if val > best_val:
			best_val = val; best_e = e
	return best_e

static func _trade_toward_city(s: GameState, pid: int) -> Dictionary:
	var p := s.players[pid]
	# Only trade if we have a settlement to upgrade.
	var has_settlement := false
	for v in s.buildings:
		if s.buildings[v]["owner"] == pid and not s.buildings[v]["city"]:
			has_settlement = true; break
	if not has_settlement:
		return {}
	var need := { Consts.Res.ORE: 3, Consts.Res.WHEAT: 2 }
	for want in need:
		var deficit: int = need[want] - p.resources.get(want, 0)
		if deficit <= 0:
			continue
		# Find a resource we have plenty of (beyond its own need) to trade away.
		for give in Consts.RES_ALL:
			if give == want:
				continue
			var ratio := s._best_ratio(pid, give)
			var reserve: int = need.get(give, 0)
			if p.resources.get(give, 0) >= ratio + reserve:
				return { "type": "bank_trade", "give": give, "get": want }
	return {}
