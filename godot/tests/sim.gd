extends SceneTree

## Headless self-test: plays a full AI-vs-AI game using the pure engine
## (GameState + AIBot), with no UI or networking. Run with:
##   godot --headless --script res://tests/sim.gd

func _init() -> void:
	seed(12345)
	var failures := 0
	for trial in range(5):
		var result := _play_one(trial)
		if not result:
			failures += 1
	if failures == 0:
		print("\nALL SIM TRIALS PASSED")
		quit(0)
	else:
		print("\n%d TRIAL(S) FAILED" % failures)
		quit(1)

func _play_one(trial: int) -> bool:
	var s := GameState.new()
	s.start_new([
		{ "name": "Bot A", "is_ai": true },
		{ "name": "Bot B", "is_ai": true },
		{ "name": "Bot C", "is_ai": true },
		{ "name": "Bot D", "is_ai": true },
	])

	# Sanity-check the generated board topology.
	if s.board.hex_count() != 19:
		print("Trial %d FAIL: expected 19 hexes, got %d" % [trial, s.board.hex_count()])
		return false
	if s.board.vertex_count() != 54:
		print("Trial %d FAIL: expected 54 vertices, got %d" % [trial, s.board.vertex_count()])
		return false
	if s.board.edge_count() != 72:
		print("Trial %d FAIL: expected 72 edges, got %d" % [trial, s.board.edge_count()])
		return false

	var steps := 0
	var max_steps := 8000
	while s.phase != Consts.Phase.GAME_OVER and steps < max_steps:
		steps += 1
		var action := AIBot.choose_action(s)
		if action.is_empty():
			print("Trial %d FAIL: AI returned no action in phase %d" % [trial, s.phase])
			return false
		var res := s.apply(action)
		if not res["ok"]:
			# An illegal AI choice is a logic bug worth surfacing.
			print("Trial %d FAIL: action %s rejected: %s" % [trial, action, res["error"]])
			return false

	if s.phase != Consts.Phase.GAME_OVER:
		print("Trial %d FAIL: no winner after %d steps" % [trial, steps])
		return false

	var vp := s.victory_points(s.winner)
	print("Trial %d OK: %s won with %d VP in %d steps." % [trial, s.players[s.winner].name, vp, steps])
	# Round-trip the serialization to catch sync bugs.
	var d := s.to_dict()
	var json := JSON.stringify(d)
	var back = JSON.parse_string(json)
	if typeof(back) != TYPE_DICTIONARY:
		print("Trial %d FAIL: state did not round-trip through JSON" % trial)
		return false
	var s2 := GameState.new()
	s2.apply_dict(back)
	if s2.winner != s.winner or s2.players.size() != s.players.size():
		print("Trial %d FAIL: deserialized state mismatch" % trial)
		return false
	return true
