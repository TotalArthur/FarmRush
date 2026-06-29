class_name GameScreen
extends Control

## In-match HUD: the board plus all panels, buttons and dialogs. Reads state
## from the Game autoload and sends actions back through Game.apply_action().

var board                       # BoardView (2D) or BoardView3D — set via duck typing
var external_board = null        # if set, use this 3D board instead of a 2D one
var players_bar: HBoxContainer
var prompt_label: Label
var hand_bar: HBoxContainer
var actions_bar: HBoxContainer
var dice_label: Label
var log_label: RichTextLabel
var toast_label: Label

var roll_btn: Button
var road_btn: Button
var settle_btn: Button
var city_btn: Button
var dev_btn: Button
var play_dev_btn: Button
var trade_btn: Button
var end_btn: Button

var _overlay: Control          # active modal overlay, if any
var _free_road_mode: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Let clicks on empty areas fall through to the 3D board behind the HUD.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	Game.state_changed.connect(refresh)
	Game.action_rejected.connect(_toast)
	Game.game_over.connect(_on_game_over)
	board.vertex_picked.connect(_on_vertex_picked)
	board.edge_picked.connect(_on_edge_picked)
	board.hex_picked.connect(_on_hex_picked)
	refresh()

# ===========================================================================
#  Static layout
# ===========================================================================
func _build_ui() -> void:
	if external_board != null:
		# 3D board lives in the world tree; the HUD is a transparent overlay.
		board = external_board
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.34, 0.62, 0.86)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

		board = BoardView.new()
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.offset_top = 64
		board.offset_bottom = -96
		board.offset_right = -230
		add_child(board)

	# Top players bar.
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 60
	add_child(top)
	players_bar = HBoxContainer.new()
	players_bar.add_theme_constant_override("separation", 14)
	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 12)
	top_margin.add_theme_constant_override("margin_top", 6)
	top_margin.add_theme_constant_override("margin_bottom", 6)
	top_margin.add_child(players_bar)
	top.add_child(top_margin)

	# Prompt banner.
	prompt_label = Label.new()
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	prompt_label.offset_top = 70
	prompt_label.offset_left = -300
	prompt_label.offset_right = 300
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.add_theme_color_override("font_color", Color.WHITE)
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	prompt_label.add_theme_constant_override("outline_size", 4)
	add_child(prompt_label)

	# Log panel (right edge).
	var log_panel := PanelContainer.new()
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	log_panel.offset_left = -220
	log_panel.offset_top = 64
	log_panel.offset_bottom = -96
	add_child(log_panel)
	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_label.fit_content = false
	log_panel.add_child(log_label)

	# Bottom bar (hand + actions + dice).
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -90
	add_child(bottom)
	var bottom_box := VBoxContainer.new()
	bottom.add_child(bottom_box)

	hand_bar = HBoxContainer.new()
	hand_bar.add_theme_constant_override("separation", 10)
	hand_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_box.add_child(hand_bar)

	actions_bar = HBoxContainer.new()
	actions_bar.add_theme_constant_override("separation", 8)
	actions_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_box.add_child(actions_bar)

	dice_label = Label.new()
	roll_btn = _mk_button("🎲 Roll", _on_roll)
	settle_btn = _mk_button("Settlement", func(): _start_pick("settlement"))
	city_btn = _mk_button("City", func(): _start_pick("city"))
	road_btn = _mk_button("Road", func(): _start_pick("road"))
	dev_btn = _mk_button("Buy Dev", _on_buy_dev)
	play_dev_btn = _mk_button("Play Dev", _on_play_dev)
	trade_btn = _mk_button("Trade", _on_trade)
	end_btn = _mk_button("End Turn", _on_end_turn)
	for b in [dice_label, roll_btn, settle_btn, city_btn, road_btn, dev_btn, play_dev_btn, trade_btn, end_btn]:
		actions_bar.add_child(b)

	# Toast.
	toast_label = Label.new()
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.add_theme_font_size_override("font_size", 22)
	toast_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	toast_label.add_theme_constant_override("outline_size", 5)
	toast_label.visible = false
	add_child(toast_label)

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b

# ===========================================================================
#  Refresh
# ===========================================================================
func refresh() -> void:
	var s := Game.state
	if s == null:
		prompt_label.text = "Waiting for game to start…"
		return
	_refresh_players(s)
	_refresh_hand(s)
	_refresh_actions(s)
	_refresh_prompt(s)
	_refresh_log(s)
	_auto_board_mode(s)
	board.queue_redraw()

func _view_seat(s: GameState) -> int:
	if Game.mode == Game.Mode.ONLINE:
		return Game.local_seat
	var a := Game.active_human_seat()
	return a if a != -1 else s.current

func _refresh_players(s: GameState) -> void:
	for c in players_bar.get_children():
		c.queue_free()
	for p in s.players:
		var chip := PanelContainer.new()
		var box := VBoxContainer.new()
		chip.add_child(box)
		var name_row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = p.color
		sw.custom_minimum_size = Vector2(16, 16)
		name_row.add_child(sw)
		var nm := Label.new()
		var marker := "➤ " if p.id == s.current else ""
		nm.text = "%s%s" % [marker, p.name]
		name_row.add_child(nm)
		box.add_child(name_row)
		var info := Label.new()
		var badges := ""
		if p.has_longest_road: badges += " 🛣"
		if p.has_largest_army: badges += " ⚔"
		info.text = "★%d  🃏%d  cards:%d%s" % [
			s.victory_points(p.id, p.id == _view_seat(s)),
			p.dev_card_count() + _bought_count(p),
			p.total_resources(), badges]
		info.add_theme_font_size_override("font_size", 12)
		box.add_child(info)
		players_bar.add_child(chip)

func _bought_count(p: Player) -> int:
	var n := 0
	for k in p.dev_bought_this_turn:
		n += p.dev_bought_this_turn[k]
	return n

func _refresh_hand(s: GameState) -> void:
	for c in hand_bar.get_children():
		c.queue_free()
	var seat := _view_seat(s)
	if seat < 0 or seat >= s.players.size():
		return
	var p := s.players[seat]
	var title := Label.new()
	title.text = "%s's hand:" % p.name
	hand_bar.add_child(title)
	for r in Consts.RES_ALL:
		var card := PanelContainer.new()
		var lbl := Label.new()
		lbl.text = "%s %d" % [Consts.RES_NAME[r], p.resources.get(r, 0)]
		lbl.add_theme_color_override("font_color", Consts.RES_COLOR[r].darkened(0.3))
		card.add_child(lbl)
		hand_bar.add_child(card)

func _refresh_actions(s: GameState) -> void:
	var my := Game.is_my_control()
	var seat := Game.active_human_seat()
	var is_main := s.phase == Consts.Phase.MAIN and my
	dice_label.text = "🎲 %d + %d" % [s.dice[0], s.dice[1]] if s.has_rolled else "🎲 —"
	roll_btn.visible = s.phase == Consts.Phase.ROLL and my
	for b in [settle_btn, city_btn, road_btn, dev_btn, trade_btn, end_btn]:
		b.visible = is_main
	play_dev_btn.visible = (is_main or (s.phase == Consts.Phase.ROLL and my)) and _has_playable_dev(s, seat)
	if not is_main:
		return
	var p := s.players[seat]
	settle_btn.disabled = not (p.can_afford(Consts.COST_SETTLEMENT) and p.settlements_left > 0)
	city_btn.disabled = not (p.can_afford(Consts.COST_CITY) and p.cities_left > 0)
	road_btn.disabled = not (p.can_afford(Consts.COST_ROAD) and p.roads_left > 0)
	dev_btn.disabled = not (p.can_afford(Consts.COST_DEV) and not s.dev_deck.is_empty())

func _has_playable_dev(s: GameState, seat: int) -> bool:
	if seat < 0:
		return false
	if s.dev_played_this_turn:
		return false
	var p := s.players[seat]
	for c in p.dev_cards:
		if c != Consts.Dev.VICTORY_POINT and p.dev_cards[c] > 0:
			return true
	return false

func _refresh_prompt(s: GameState) -> void:
	var cur := s.players[s.current]
	match s.phase:
		Consts.Phase.SETUP:
			if Game.is_my_control():
				prompt_label.text = "Place your %s." % ("road" if s.setup_need_road else "settlement")
			else:
				prompt_label.text = "%s is placing…" % cur.name
		Consts.Phase.ROLL:
			prompt_label.text = "Your roll!" if Game.is_my_control() else "%s is about to roll…" % cur.name
		Consts.Phase.DISCARD:
			prompt_label.text = "Discard down to 7 cards."
		Consts.Phase.MOVE_ROBBER:
			prompt_label.text = "Move the robber." if Game.is_my_control() else "%s moves the robber…" % cur.name
		Consts.Phase.MAIN:
			prompt_label.text = "Your turn — build, trade or play." if Game.is_my_control() else "%s is taking their turn…" % cur.name
		Consts.Phase.GAME_OVER:
			prompt_label.text = "%s wins! 🏆" % s.players[s.winner].name

func _refresh_log(s: GameState) -> void:
	var lines := s.log.slice(max(0, s.log.size() - 14))
	log_label.text = "\n".join(lines)

# ===========================================================================
#  Auto board interaction modes
# ===========================================================================
func _auto_board_mode(s: GameState) -> void:
	var seat := Game.active_human_seat()
	if seat == -1:
		board.set_mode(BoardView.PickMode.NONE, -1)
		_close_overlay()
		return
	match s.phase:
		Consts.Phase.SETUP:
			board.set_mode(BoardView.PickMode.ROAD if s.setup_need_road else BoardView.PickMode.SETTLEMENT, seat)
		Consts.Phase.MOVE_ROBBER:
			board.set_mode(BoardView.PickMode.ROBBER, seat)
		Consts.Phase.DISCARD:
			board.set_mode(BoardView.PickMode.NONE, seat)
			_open_discard_dialog(s, seat)
		Consts.Phase.MAIN:
			if _free_road_mode and s.free_roads > 0:
				board.set_mode(BoardView.PickMode.ROAD, seat)
			else:
				_free_road_mode = false
				if board.pick_mode == BoardView.PickMode.ROBBER:
					board.set_mode(BoardView.PickMode.NONE, seat)
		_:
			board.set_mode(BoardView.PickMode.NONE, seat)

func _start_pick(kind: String) -> void:
	var seat := Game.active_human_seat()
	if seat == -1:
		return
	match kind:
		"settlement": board.set_mode(BoardView.PickMode.SETTLEMENT, seat)
		"city": board.set_mode(BoardView.PickMode.CITY, seat)
		"road": board.set_mode(BoardView.PickMode.ROAD, seat)

# ===========================================================================
#  Board pick handlers
# ===========================================================================
func _on_vertex_picked(v: int) -> void:
	var s := Game.state
	if s.phase == Consts.Phase.SETUP:
		Game.apply_action({ "type": "setup_settlement", "vertex": v })
	elif board.pick_mode == BoardView.PickMode.CITY:
		Game.apply_action({ "type": "build_city", "vertex": v })
		board.set_mode(BoardView.PickMode.NONE, board.acting_seat)
	else:
		Game.apply_action({ "type": "build_settlement", "vertex": v })
		board.set_mode(BoardView.PickMode.NONE, board.acting_seat)

func _on_edge_picked(e: int) -> void:
	var s := Game.state
	if s.phase == Consts.Phase.SETUP:
		Game.apply_action({ "type": "setup_road", "edge": e })
	else:
		Game.apply_action({ "type": "build_road", "edge": e })
		if not (_free_road_mode and s.free_roads > 1):
			_free_road_mode = false
			board.set_mode(BoardView.PickMode.NONE, board.acting_seat)

func _on_hex_picked(h: int) -> void:
	var s := Game.state
	if s.phase != Consts.Phase.MOVE_ROBBER:
		return
	var victims := s._robber_victims(h, s.current)
	if victims.size() <= 1:
		var target: int = victims[0] if victims.size() == 1 else -1
		Game.apply_action({ "type": "move_robber", "hex": h, "steal_from": target })
	else:
		_open_steal_dialog(s, h, victims)

# ===========================================================================
#  Action buttons
# ===========================================================================
func _on_roll() -> void:
	Game.apply_action({ "type": "roll" })

func _on_buy_dev() -> void:
	Game.apply_action({ "type": "buy_dev" })

func _on_end_turn() -> void:
	board.set_mode(BoardView.PickMode.NONE, -1)
	Game.apply_action({ "type": "end_turn" })

# ===========================================================================
#  Overlays: discard / steal / trade / dev / game over
# ===========================================================================
func _open_overlay(title: String) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	margin.add_child(box)
	panel.add_child(margin)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 20)
	box.add_child(t)
	add_child(_overlay)
	return box

func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null

func _open_discard_dialog(s: GameState, seat: int) -> void:
	if _overlay != null:
		return
	var need: int = s.pending_discards[seat]
	var box := _open_overlay("Discard %d cards" % need)
	var chosen := Consts.dict_empty_res()
	var summary := Label.new()
	box.add_child(summary)
	var update_summary := func():
		var n := 0
		for r in chosen: n += chosen[r]
		summary.text = "Selected %d / %d" % [n, need]
	update_summary.call()
	for r in Consts.RES_ALL:
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.custom_minimum_size = Vector2(120, 0)
		var amount_lbl := Label.new()
		var refresh_row := func():
			name_lbl.text = "%s (have %d)" % [Consts.RES_NAME[r], s.players[seat].resources.get(r, 0)]
			amount_lbl.text = "drop %d" % chosen[r]
		refresh_row.call()
		var minus := Button.new(); minus.text = "−"
		var plus := Button.new(); plus.text = "+"
		minus.pressed.connect(func():
			if chosen[r] > 0: chosen[r] -= 1
			refresh_row.call(); update_summary.call())
		plus.pressed.connect(func():
			var total := 0
			for x in chosen: total += chosen[x]
			if chosen[r] < s.players[seat].resources.get(r, 0) and total < need:
				chosen[r] += 1
			refresh_row.call(); update_summary.call())
		row.add_child(name_lbl); row.add_child(minus); row.add_child(amount_lbl); row.add_child(plus)
		box.add_child(row)
	var confirm := Button.new()
	confirm.text = "Discard"
	confirm.pressed.connect(func():
		var total := 0
		for r in chosen: total += chosen[r]
		if total != need:
			_toast("Select exactly %d cards." % need)
			return
		_close_overlay()
		Game.apply_action({ "type": "discard", "player": seat, "resources": chosen }))
	box.add_child(confirm)

func _open_steal_dialog(s: GameState, h: int, victims: Array) -> void:
	var box := _open_overlay("Steal from whom?")
	for vic in victims:
		var b := Button.new()
		b.text = "%s (%d cards)" % [s.players[vic].name, s.players[vic].total_resources()]
		b.pressed.connect(func():
			_close_overlay()
			Game.apply_action({ "type": "move_robber", "hex": h, "steal_from": vic }))
		box.add_child(b)

func _on_trade() -> void:
	var s := Game.state
	var seat := Game.active_human_seat()
	if seat == -1:
		return
	var box := _open_overlay("Bank / Port Trade")
	var give_res := { "v": Consts.Res.WOOD }
	var get_res := { "v": Consts.Res.BRICK }
	var info := Label.new()
	box.add_child(info)
	var update := func():
		var ratio := s._best_ratio(seat, give_res["v"])
		info.text = "Give %d %s  →  get 1 %s" % [ratio, Consts.RES_NAME[give_res["v"]], Consts.RES_NAME[get_res["v"]]]
	update.call()
	var give_row := HBoxContainer.new()
	give_row.add_child(_label("Give:"))
	for r in Consts.RES_ALL:
		var b := Button.new(); b.text = Consts.RES_NAME[r]
		b.pressed.connect(func(): give_res["v"] = r; update.call())
		give_row.add_child(b)
	box.add_child(give_row)
	var get_row := HBoxContainer.new()
	get_row.add_child(_label("Get:"))
	for r in Consts.RES_ALL:
		var b := Button.new(); b.text = Consts.RES_NAME[r]
		b.pressed.connect(func(): get_res["v"] = r; update.call())
		get_row.add_child(b)
	box.add_child(get_row)
	var confirm := Button.new(); confirm.text = "Trade"
	confirm.pressed.connect(func():
		_close_overlay()
		Game.apply_action({ "type": "bank_trade", "give": give_res["v"], "get": get_res["v"] }))
	var cancel := Button.new(); cancel.text = "Cancel"
	cancel.pressed.connect(_close_overlay)
	var btns := HBoxContainer.new(); btns.add_child(confirm); btns.add_child(cancel)
	box.add_child(btns)

func _on_play_dev() -> void:
	var s := Game.state
	var seat := Game.active_human_seat()
	if seat == -1:
		return
	var box := _open_overlay("Play a Development Card")
	var p := s.players[seat]
	var any := false
	for card in [Consts.Dev.KNIGHT, Consts.Dev.ROAD_BUILDING, Consts.Dev.YEAR_OF_PLENTY, Consts.Dev.MONOPOLY]:
		if p.dev_cards.get(card, 0) <= 0:
			continue
		any = true
		var b := Button.new()
		b.text = "%s (x%d)" % [Consts.DEV_NAME[card], p.dev_cards[card]]
		b.pressed.connect(func(): _play_dev_card(card))
		box.add_child(b)
	if not any:
		box.add_child(_label("No playable cards."))
	var cancel := Button.new(); cancel.text = "Close"
	cancel.pressed.connect(_close_overlay)
	box.add_child(cancel)

func _play_dev_card(card: int) -> void:
	match card:
		Consts.Dev.KNIGHT:
			_close_overlay()
			Game.apply_action({ "type": "play_dev", "card": card })
		Consts.Dev.ROAD_BUILDING:
			_close_overlay()
			_free_road_mode = true
			Game.apply_action({ "type": "play_dev", "card": card })
		Consts.Dev.MONOPOLY:
			_open_pick_resource("Monopolize which resource?", func(r):
				Game.apply_action({ "type": "play_dev", "card": card, "res": r }))
		Consts.Dev.YEAR_OF_PLENTY:
			_open_pick_two_resources(func(r1, r2):
				Game.apply_action({ "type": "play_dev", "card": card, "res1": r1, "res2": r2 }))

func _open_pick_resource(title: String, cb: Callable) -> void:
	var box := _open_overlay(title)
	for r in Consts.RES_ALL:
		var b := Button.new(); b.text = Consts.RES_NAME[r]
		b.pressed.connect(func(): _close_overlay(); cb.call(r))
		box.add_child(b)

func _open_pick_two_resources(cb: Callable) -> void:
	var box := _open_overlay("Year of Plenty — pick 2")
	var first := { "v": -1 }
	var status := Label.new()
	status.text = "Pick the first resource."
	box.add_child(status)
	for r in Consts.RES_ALL:
		var b := Button.new(); b.text = Consts.RES_NAME[r]
		b.pressed.connect(func():
			if first["v"] == -1:
				first["v"] = r
				status.text = "First: %s. Pick the second." % Consts.RES_NAME[r]
			else:
				_close_overlay()
				cb.call(first["v"], r))
		box.add_child(b)

# ===========================================================================
#  Misc UI helpers
# ===========================================================================
func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _toast(message: String) -> void:
	toast_label.text = message
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): toast_label.visible = false)

func _on_game_over(winner_seat: int) -> void:
	var s := Game.state
	var box := _open_overlay("🏆 %s wins!" % s.players[winner_seat].name)
	for p in s.players:
		box.add_child(_label("%s — %d points" % [p.name, s.victory_points(p.id)]))
	var menu := Button.new()
	menu.text = "Back to Menu"
	menu.pressed.connect(func():
		_close_overlay()
		if Net.is_online:
			Net.leave()
		get_tree().call_group("main", "show_menu"))
	box.add_child(menu)
