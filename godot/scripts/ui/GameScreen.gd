class_name GameScreen
extends Control

## Modern, docked in-game HUD (colonist.io-style) layered over the 3D board.
##
## Layout (all built in code; equivalent editor node tree is in the README):
##   GameScreen (Control, full rect, mouse IGNORE so clicks reach the board)
##   ├─ TopBanner (PanelContainer, top-center)         -> prompt / whose turn
##   ├─ RightHub (PanelContainer, right dock)
##   │    └─ VBox
##   │         ├─ "Game Log" + RichTextLabel (scrolls)
##   │         └─ "Players" + ScrollContainer -> player rows
##   ├─ ActionHub (PanelContainer, bottom dock)
##   │    └─ VBox
##   │         ├─ Hand row (resource chips)
##   │         └─ Buttons row (Roll / End / Road / Settlement / City / Card / Trade)
##   └─ Toast + modal overlays (discard / steal / trade / dev / game over)

var board                        # BoardView (2D) or BoardView3D (duck-typed)
var external_board = null        # if set, HUD overlays this 3D board

var prompt_label: Label
var turn_swatch: ColorRect
var players_bar: VBoxContainer
var log_label: RichTextLabel
var hand_bar: HBoxContainer
var actions_bar: HBoxContainer
var dice_label: Label
var toast_label: Label

var roll_btn: Button
var road_btn: Button
var settle_btn: Button
var city_btn: Button
var dev_btn: Button
var play_dev_btn: Button
var trade_btn: Button
var end_btn: Button

var _overlay: Control
var _free_road_mode := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # empty areas -> board behind
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
		board = external_board
	else:
		var bg := ColorRect.new()
		bg.color = UITheme.BG_DEEP
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		board = BoardView.new()
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.offset_top = 64
		board.offset_bottom = -160
		board.offset_right = -348
		add_child(board)

	_build_top_banner()
	_build_right_hub()
	_build_action_hub()

	toast_label = Label.new()
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.add_theme_font_size_override("font_size", 22)
	toast_label.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast_label.add_theme_constant_override("outline_size", 5)
	toast_label.visible = false
	add_child(toast_label)

func _build_top_banner() -> void:
	var panel := UITheme.make_panel(UITheme.PANEL, 14)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = 12
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	turn_swatch = ColorRect.new()
	turn_swatch.custom_minimum_size = Vector2(20, 20)
	turn_swatch.color = Color.WHITE
	row.add_child(turn_swatch)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 19)
	prompt_label.add_theme_color_override("font_color", UITheme.INK)
	row.add_child(prompt_label)

func _build_right_hub() -> void:
	var panel := UITheme.make_panel(UITheme.PANEL, 14)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -336
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = -12
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	vb.add_child(UITheme.heading("Game Log", 18))
	var log_panel := UITheme.make_panel(UITheme.PANEL_SOFT, 10)
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(log_panel)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.fit_content = false
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_color_override("default_color", UITheme.INK)
	log_panel.add_child(log_label)

	vb.add_child(UITheme.heading("Players", 18))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	players_bar = VBoxContainer.new()
	players_bar.add_theme_constant_override("separation", 6)
	players_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(players_bar)

func _build_action_hub() -> void:
	var panel := UITheme.make_panel(UITheme.PANEL, 14)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 12
	panel.offset_right = -348
	panel.offset_top = -148
	panel.offset_bottom = -12
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	hand_bar = HBoxContainer.new()
	hand_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_bar.add_theme_constant_override("separation", 8)
	vb.add_child(hand_bar)

	actions_bar = HBoxContainer.new()
	actions_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	actions_bar.add_theme_constant_override("separation", 8)
	vb.add_child(actions_bar)

	dice_label = Label.new()
	dice_label.add_theme_font_size_override("font_size", 18)
	dice_label.add_theme_color_override("font_color", UITheme.INK)
	dice_label.custom_minimum_size = Vector2(96, 0)
	dice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	roll_btn = _btn("Roll Dice", UITheme.GREEN, _on_roll)
	settle_btn = _btn("Settlement", UITheme.BLUE, func(): _start_pick("settlement"))
	city_btn = _btn("City", UITheme.BLUE, func(): _start_pick("city"))
	road_btn = _btn("Road", UITheme.BLUE, func(): _start_pick("road"))
	dev_btn = _btn("Buy Card", UITheme.BLUE, _on_buy_dev)
	play_dev_btn = _btn("Play Card", UITheme.SLATE, _on_play_dev)
	trade_btn = _btn("Trade", UITheme.SLATE, _on_trade)
	end_btn = _btn("End Turn", UITheme.ACCENT, _on_end_turn)

	actions_bar.add_child(dice_label)
	for b in [roll_btn, road_btn, settle_btn, city_btn, dev_btn, play_dev_btn, trade_btn, end_btn]:
		actions_bar.add_child(b)

func _btn(text: String, color: Color, cb: Callable) -> Button:
	var b := UITheme.make_button(text, color)
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
	if board.has_method("queue_redraw"):
		board.queue_redraw()

func _view_seat(s: GameState) -> int:
	if Game.mode == Game.Mode.ONLINE:
		return Game.local_seat
	var a := Game.active_human_seat()
	return a if a != -1 else s.current

func _refresh_players(s: GameState) -> void:
	for c in players_bar.get_children():
		c.queue_free()
	var view := _view_seat(s)
	for p in s.players:
		players_bar.add_child(_player_row(s, p, p.id == s.current, p.id == view))

func _player_row(s: GameState, p: Player, is_current: bool, is_view: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var bg := UITheme.ACCENT.lightened(0.55) if is_current else UITheme.PANEL_SOFT
	row.add_theme_stylebox_override("panel", UITheme.flat(bg, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	var sw := ColorRect.new()
	sw.color = p.color
	sw.custom_minimum_size = Vector2(20, 20)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sw)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var name := Label.new()
	name.text = ("➤ " if is_current else "") + p.name
	name.add_theme_color_override("font_color", UITheme.INK)
	name.add_theme_font_size_override("font_size", 15)
	col.add_child(name)
	var stats := Label.new()
	var dev := p.dev_card_count() + _bought_count(p)
	stats.text = "VP %d   Cards %d   Dev %d   Kn %d" % [
		s.victory_points(p.id, is_view), p.total_resources(), dev, p.played_knights]
	stats.add_theme_color_override("font_color", UITheme.INK_SOFT)
	stats.add_theme_font_size_override("font_size", 12)
	col.add_child(stats)
	# Bonus badges.
	if p.has_longest_road or p.has_largest_army:
		var badge := Label.new()
		var b := ""
		if p.has_longest_road: b += "ROAD "
		if p.has_largest_army: b += "ARMY"
		badge.text = b
		badge.add_theme_color_override("font_color", UITheme.ACCENT.darkened(0.1))
		badge.add_theme_font_size_override("font_size", 11)
		h.add_child(badge)
	return row

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
	title.text = "Hand:"
	title.add_theme_color_override("font_color", UITheme.INK)
	title.add_theme_font_size_override("font_size", 16)
	hand_bar.add_child(title)
	for r in Consts.RES_ALL:
		hand_bar.add_child(UITheme.resource_chip(r, p.resources.get(r, 0), true))

func _refresh_actions(s: GameState) -> void:
	var seat := Game.active_human_seat()
	var my := seat != -1
	var is_main := s.phase == Consts.Phase.MAIN and my
	dice_label.text = ("Dice %d + %d" % [s.dice[0], s.dice[1]]) if s.has_rolled else "Dice —"
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
	if seat < 0 or s.dev_played_this_turn:
		return false
	var p := s.players[seat]
	for c in p.dev_cards:
		if c != Consts.Dev.VICTORY_POINT and p.dev_cards[c] > 0:
			return true
	return false

func _refresh_prompt(s: GameState) -> void:
	var cur := s.players[s.current]
	turn_swatch.color = cur.color
	match s.phase:
		Consts.Phase.SETUP:
			prompt_label.text = "Place your %s." % ("road" if s.setup_need_road else "settlement") if Game.is_my_control() else "%s is placing…" % cur.name
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
	var lines := s.log.slice(max(0, s.log.size() - 30))
	log_label.text = "\n".join(lines)

# ===========================================================================
#  Board interaction modes (unchanged logic)
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
#  Modal overlays (restyled with UITheme)
# ===========================================================================
func _open_overlay(title: String) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var panel := UITheme.make_panel(UITheme.PANEL, 16)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(440, 0)
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", UITheme.INK)
	box.add_child(t)
	add_child(_overlay)
	return box

func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null

func _dlg_button(text: String, color: Color, cb: Callable) -> Button:
	var b := UITheme.make_button(text, color)
	b.pressed.connect(cb)
	return b

func _open_discard_dialog(s: GameState, seat: int) -> void:
	if _overlay != null:
		return
	var need: int = s.pending_discards[seat]
	var box := _open_overlay("Discard %d cards" % need)
	var chosen := Consts.dict_empty_res()
	var summary := UITheme.heading("Selected 0 / %d" % need, 14, UITheme.INK_SOFT)
	box.add_child(summary)
	var update_summary := func():
		var n := 0
		for r in chosen: n += chosen[r]
		summary.text = "Selected %d / %d" % [n, need]
	for r in Consts.RES_ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.custom_minimum_size = Vector2(150, 0)
		name_lbl.add_theme_color_override("font_color", UITheme.INK)
		var amount_lbl := Label.new()
		amount_lbl.add_theme_color_override("font_color", UITheme.INK)
		amount_lbl.custom_minimum_size = Vector2(70, 0)
		var refresh_row := func():
			name_lbl.text = "%s (have %d)" % [Consts.RES_NAME[r], s.players[seat].resources.get(r, 0)]
			amount_lbl.text = "drop %d" % chosen[r]
		refresh_row.call()
		var minus := _dlg_button("−", UITheme.SLATE, func():
			if chosen[r] > 0: chosen[r] -= 1
			refresh_row.call(); update_summary.call())
		var plus := _dlg_button("+", UITheme.BLUE, func():
			var total := 0
			for x in chosen: total += chosen[x]
			if chosen[r] < s.players[seat].resources.get(r, 0) and total < need:
				chosen[r] += 1
			refresh_row.call(); update_summary.call())
		row.add_child(name_lbl); row.add_child(minus); row.add_child(amount_lbl); row.add_child(plus)
		box.add_child(row)
	box.add_child(_dlg_button("Discard", UITheme.ACCENT, func():
		var total := 0
		for r in chosen: total += chosen[r]
		if total != need:
			_toast("Select exactly %d cards." % need); return
		_close_overlay()
		Game.apply_action({ "type": "discard", "player": seat, "resources": chosen })))

func _open_steal_dialog(s: GameState, h: int, victims: Array) -> void:
	var box := _open_overlay("Steal from whom?")
	for vic in victims:
		box.add_child(_dlg_button("%s (%d cards)" % [s.players[vic].name, s.players[vic].total_resources()],
			UITheme.BLUE, func():
				_close_overlay()
				Game.apply_action({ "type": "move_robber", "hex": h, "steal_from": vic })))

func _on_trade() -> void:
	var s := Game.state
	var seat := Game.active_human_seat()
	if seat == -1:
		return
	var box := _open_overlay("Bank / Port Trade")
	var give_res := { "v": Consts.Res.WOOD }
	var get_res := { "v": Consts.Res.BRICK }
	var info := UITheme.heading("", 15, UITheme.INK)
	box.add_child(info)
	var update := func():
		var ratio := s._best_ratio(seat, give_res["v"])
		info.text = "Give %d %s  →  get 1 %s" % [ratio, Consts.RES_NAME[give_res["v"]], Consts.RES_NAME[get_res["v"]]]
	update.call()
	var give_row := HBoxContainer.new()
	give_row.add_theme_constant_override("separation", 6)
	give_row.add_child(UITheme.heading("Give:", 14, UITheme.INK_SOFT))
	for r in Consts.RES_ALL:
		give_row.add_child(_dlg_button(Consts.RES_NAME[r], Consts.RES_COLOR[r].darkened(0.1),
			func(): give_res["v"] = r; update.call()))
	box.add_child(give_row)
	var get_row := HBoxContainer.new()
	get_row.add_theme_constant_override("separation", 6)
	get_row.add_child(UITheme.heading("Get:", 14, UITheme.INK_SOFT))
	for r in Consts.RES_ALL:
		get_row.add_child(_dlg_button(Consts.RES_NAME[r], Consts.RES_COLOR[r].darkened(0.1),
			func(): get_res["v"] = r; update.call()))
	box.add_child(get_row)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.add_child(_dlg_button("Trade", UITheme.ACCENT, func():
		_close_overlay()
		Game.apply_action({ "type": "bank_trade", "give": give_res["v"], "get": get_res["v"] })))
	btns.add_child(_dlg_button("Cancel", UITheme.SLATE, _close_overlay))
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
		box.add_child(_dlg_button("%s (x%d)" % [Consts.DEV_NAME[card], p.dev_cards[card]],
			UITheme.BLUE, func(): _play_dev_card(card)))
	if not any:
		box.add_child(UITheme.heading("No playable cards.", 14, UITheme.INK_SOFT))
	box.add_child(_dlg_button("Close", UITheme.SLATE, _close_overlay))

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
		box.add_child(_dlg_button(Consts.RES_NAME[r], Consts.RES_COLOR[r].darkened(0.1),
			func(): _close_overlay(); cb.call(r)))

func _open_pick_two_resources(cb: Callable) -> void:
	var box := _open_overlay("Year of Plenty — pick 2")
	var first := { "v": -1 }
	var status := UITheme.heading("Pick the first resource.", 14, UITheme.INK_SOFT)
	box.add_child(status)
	for r in Consts.RES_ALL:
		box.add_child(_dlg_button(Consts.RES_NAME[r], Consts.RES_COLOR[r].darkened(0.1), func():
			if first["v"] == -1:
				first["v"] = r
				status.text = "First: %s. Pick the second." % Consts.RES_NAME[r]
			else:
				_close_overlay()
				cb.call(first["v"], r)))

# ===========================================================================
#  Toast + game over
# ===========================================================================
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
		box.add_child(UITheme.heading("%s — %d points" % [p.name, s.victory_points(p.id)], 15, UITheme.INK))
	box.add_child(_dlg_button("Back to Menu", UITheme.ACCENT, func():
		_close_overlay()
		if Net.is_online:
			Net.leave()
		get_tree().call_group("main", "show_menu")))
