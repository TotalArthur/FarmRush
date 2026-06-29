class_name Lobby
extends Control

signal back()

var name_edit: LineEdit
var addr_edit: LineEdit
var ai_spin: SpinBox
var roster_box: VBoxContainer
var status_label: Label
var start_btn: Button
var host_btn: Button
var join_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.50, 0.70)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -220
	box.offset_right = 220
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = "Online Multiplayer"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_row("Name:", func(r):
		name_edit = LineEdit.new()
		name_edit.text = "Player"
		name_edit.custom_minimum_size = Vector2(220, 0)
		r.add_child(name_edit)))

	box.add_child(_row("Host port 24816 — Start hosting:", func(r):
		host_btn = Button.new()
		host_btn.text = "Host Game"
		host_btn.pressed.connect(_on_host)
		r.add_child(host_btn)))

	box.add_child(_row("Address:", func(r):
		addr_edit = LineEdit.new()
		addr_edit.text = "127.0.0.1"
		addr_edit.custom_minimum_size = Vector2(160, 0)
		r.add_child(addr_edit)
		join_btn = Button.new()
		join_btn.text = "Join"
		join_btn.pressed.connect(_on_join)
		r.add_child(join_btn)))

	box.add_child(_row("Fill with bots (host):", func(r):
		ai_spin = SpinBox.new()
		ai_spin.min_value = 0
		ai_spin.max_value = 4
		ai_spin.value = 0
		r.add_child(ai_spin)))

	var roster_title := Label.new()
	roster_title.text = "Players in lobby:"
	box.add_child(roster_title)
	roster_box = VBoxContainer.new()
	box.add_child(roster_box)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	box.add_child(status_label)

	var btns := HBoxContainer.new()
	start_btn = Button.new()
	start_btn.text = "Start Game"
	start_btn.disabled = true
	start_btn.pressed.connect(_on_start)
	btns.add_child(start_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func(): Net.leave(); back.emit())
	btns.add_child(back_btn)
	box.add_child(btns)

	Net.lobby_changed.connect(_refresh_roster)
	Net.connection_failed.connect(func(): status_label.text = "Connection failed.")
	Net.connection_succeeded.connect(func(): status_label.text = "Connected! Waiting for host…")
	Net.server_disconnected.connect(func(): status_label.text = "Host disconnected.")
	_refresh_roster()

func _row(label_text: String, build: Callable) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(120, 0)
	r.add_child(l)
	build.call(r)
	return r

func _on_host() -> void:
	if Net.host_game(name_edit.text):
		status_label.text = "Hosting on port %d. Waiting for players…" % Net.DEFAULT_PORT
		host_btn.disabled = true
		join_btn.disabled = true
	else:
		status_label.text = "Could not host (port in use?)."

func _on_join() -> void:
	if Net.join_game(name_edit.text, addr_edit.text):
		status_label.text = "Connecting…"
		host_btn.disabled = true
		join_btn.disabled = true
	else:
		status_label.text = "Could not start client."

func _on_start() -> void:
	if not Net.is_host:
		return
	var total: int = Net.lobby.size() + int(ai_spin.value)
	if total < 2:
		status_label.text = "Need at least 2 players."
		return
	Game.start_online_host(int(ai_spin.value))
	Net.start_match()

func _refresh_roster() -> void:
	for c in roster_box.get_children():
		c.queue_free()
	for peer in Net.lobby:
		var l := Label.new()
		var tag := " (host)" if peer == 1 else ""
		l.text = "• %s%s" % [Net.lobby[peer].get("name", "Player"), tag]
		roster_box.add_child(l)
	start_btn.disabled = not (Net.is_host and Net.lobby.size() >= 1)
