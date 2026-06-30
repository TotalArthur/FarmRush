extends Control

## Root controller — swaps between the menu, lobby and game screens.
## Registered in the "main" group so other screens can call show_menu().

var current: Node

func _ready() -> void:
	add_to_group("main")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.game_should_start.connect(show_game)
	Net.server_disconnected.connect(_on_server_disconnected)
	# Dev/test hooks.
	if OS.has_environment("HEXBOUND_MAINSHOT"):
		Game.start_single("You", 3)
		# Auto-play the setup phase so the main-phase action buttons are visible.
		var guard := 0
		while Game.state.phase != Consts.Phase.MAIN and guard < 400:
			guard += 1
			Game.apply_action(AIBot.choose_action(Game.state))
		show_game()
		_grab_screenshot.call_deferred()
	elif OS.has_environment("HEXBOUND_MENUSHOT"):
		show_menu()
		_grab_screenshot.call_deferred()
	elif OS.has_environment("HEXBOUND_AUTOSTART") or OS.has_environment("HEXBOUND_SCREENSHOT"):
		Game.start_single("You", 3)
		show_game()
		if OS.has_environment("HEXBOUND_SCREENSHOT"):
			_grab_screenshot.call_deferred()
	else:
		show_menu()

func _grab_screenshot() -> void:
	# Let a few frames render, then save the viewport and quit.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/board_preview.png")
	print("HEXBOUND: screenshot saved")
	get_tree().quit(0)

func _swap(node: Node) -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = node
	add_child(node)

func show_menu() -> void:
	var m := MainMenu.new()
	m.play_single.connect(_on_play_single)
	m.play_hotseat.connect(_on_play_hotseat)
	m.play_online.connect(show_lobby)
	_swap(m)

func show_lobby() -> void:
	var l := Lobby.new()
	l.back.connect(show_menu)
	_swap(l)

func show_game() -> void:
	# 3D tabletop is the default. Set HEXBOUND_2D=1 to use the flat 2D board.
	if OS.has_environment("HEXBOUND_2D"):
		_swap(GameScreen.new())
	else:
		_swap(Game3DWorld.new())

func _on_play_single(ai_count: int) -> void:
	Game.start_single("You", ai_count)
	show_game()

func _on_play_hotseat(player_count: int) -> void:
	var names: Array = []
	for i in range(player_count):
		names.append("Player %d" % (i + 1))
	Game.start_hotseat(names)
	show_game()

func _on_server_disconnected() -> void:
	show_menu()
