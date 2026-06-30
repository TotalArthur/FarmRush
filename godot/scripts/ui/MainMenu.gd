class_name MainMenu
extends Control

## Modern start screen (colonist.io-style): left nav sidebar, mode tabs
## (Bots / Casual / Ranked), a styled mode card, and a big Start button.

signal play_single(ai_count)
signal play_hotseat(player_count)
signal play_online()

enum Tab { BOTS, CASUAL, RANKED }

var _tab := Tab.BOTS
var _bots := 3
var _players := 2
var _difficulty := "Easy"

var content_panel: PanelContainer
var content_box: VBoxContainer
var tab_buttons := {}
var start_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UITheme.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_sidebar())

	# Main column.
	var main_margin := MarginContainer.new()
	main_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		main_margin.add_theme_constant_override(m, 28)
	root.add_child(main_margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	main_margin.add_child(col)

	var title := UITheme.heading("Play", 34, Color.WHITE)
	col.add_child(title)

	col.add_child(_build_tabs())

	content_panel = UITheme.make_panel(UITheme.PANEL, 16)
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(content_panel)
	content_box = VBoxContainer.new()
	content_box.add_theme_constant_override("separation", 14)
	content_panel.add_child(content_box)

	start_btn = UITheme.make_button("Start Game", UITheme.ACCENT)
	start_btn.custom_minimum_size = Vector2(0, 64)
	start_btn.add_theme_font_size_override("font_size", 26)
	start_btn.pressed.connect(_on_start)
	col.add_child(start_btn)

	_select_tab(Tab.BOTS)

# --- Sidebar ---------------------------------------------------------------
func _build_sidebar() -> PanelContainer:
	var side := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_SIDEBAR
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	side.add_theme_stylebox_override("panel", sb)
	side.custom_minimum_size = Vector2(128, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	side.add_child(v)
	var logo := UITheme.heading("🌾", 40, Color("ffd34d"))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	var name := UITheme.heading("HEXBOUND", 16, Color.WHITE)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	v.add_child(_spacer(20))
	v.add_child(_nav_button("Play", true))
	v.add_child(_nav_button("Leaderboards", false))
	v.add_child(_nav_button("Rooms", false))
	v.add_child(_nav_button("Store", false))
	v.add_child(_nav_button("More", false))
	return side

func _nav_button(text: String, active: bool) -> Button:
	var b := UITheme.make_button(text, UITheme.BLUE if active else UITheme.BG_SIDEBAR.lightened(0.08))
	b.custom_minimum_size = Vector2(108, 44)
	b.disabled = not active   # only Play is wired up
	if not active:
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.65))
	return b

# --- Tabs ------------------------------------------------------------------
func _build_tabs() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for entry in [[Tab.BOTS, "🤖  Bots"], [Tab.CASUAL, "👥  Casual"], [Tab.RANKED, "🌐  Ranked"]]:
		var t: int = entry[0]
		var b := UITheme.make_button(entry[1], UITheme.SLATE)
		b.custom_minimum_size = Vector2(180, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _select_tab(t))
		tab_buttons[t] = b
		row.add_child(b)
	return row

func _select_tab(tab: int) -> void:
	_tab = tab
	for t in tab_buttons:
		UITheme.style_button(tab_buttons[t], UITheme.BLUE if t == tab else UITheme.SLATE)
	_rebuild_content()

func _rebuild_content() -> void:
	for c in content_box.get_children():
		c.queue_free()
	match _tab:
		Tab.BOTS:
			_build_bots_content()
		Tab.CASUAL:
			_build_casual_content()
		Tab.RANKED:
			_build_ranked_content()

func _build_bots_content() -> void:
	content_box.add_child(UITheme.heading("Play vs. Bots", 24))
	content_box.add_child(_subtext("Take on AI opponents on a classic random board."))
	# Difficulty toggle (cosmetic for now — one AI profile).
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	diff_row.add_child(_field_label("Difficulty:"))
	for d in ["Easy", "Medium", "Hard"]:
		var b := UITheme.make_button(d, UITheme.BLUE if d == _difficulty else UITheme.PANEL_SOFT,
			UITheme.INK if d != _difficulty else Color.WHITE)
		b.pressed.connect(func(): _difficulty = d; _rebuild_content())
		diff_row.add_child(b)
	content_box.add_child(diff_row)
	content_box.add_child(_counter_row("Opponents:", _bots, 1, 5, func(v): _bots = v))

func _build_casual_content() -> void:
	content_box.add_child(UITheme.heading("Local Hotseat", 24))
	content_box.add_child(_subtext("Pass-and-play with friends on this device."))
	content_box.add_child(_counter_row("Players:", _players, 2, 6, func(v): _players = v))

func _build_ranked_content() -> void:
	content_box.add_child(UITheme.heading("Online Multiplayer", 24))
	content_box.add_child(_subtext("Host a game or join a friend over the network."))

func _on_start() -> void:
	match _tab:
		Tab.BOTS: play_single.emit(_bots)
		Tab.CASUAL: play_hotseat.emit(_players)
		Tab.RANKED: play_online.emit()

# --- Small helpers ---------------------------------------------------------
func _counter_row(label: String, value: int, lo: int, hi: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_field_label(label))
	var val := { "v": value }
	var num := UITheme.heading(str(value), 22)
	var minus := UITheme.make_button("−", UITheme.SLATE)
	var plus := UITheme.make_button("+", UITheme.BLUE)
	minus.pressed.connect(func():
		val["v"] = max(lo, val["v"] - 1); num.text = str(val["v"]); on_change.call(val["v"]))
	plus.pressed.connect(func():
		val["v"] = min(hi, val["v"] + 1); num.text = str(val["v"]); on_change.call(val["v"]))
	row.add_child(minus); row.add_child(num); row.add_child(plus)
	return row

func _field_label(text: String) -> Label:
	return UITheme.heading(text, 16, UITheme.INK)

func _subtext(text: String) -> Label:
	var l := UITheme.heading(text, 14, UITheme.INK_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
