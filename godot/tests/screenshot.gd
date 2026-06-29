extends SceneTree

## Boots a vs-AI game, waits a few frames, and saves a screenshot.
## Run (needs a display, e.g. xvfb-run):
##   godot --script res://tests/screenshot.gd

var _frames := 0
var _root_scene

func _initialize() -> void:
	# Load the main scene into the tree so autoloads + UI are live.
	_root_scene = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(_root_scene)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# Start a game once everything is ready.
		Engine.get_singleton("Game").start_single("You", 3)
		_root_scene.show_game()
	if _frames >= 30:
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("res://tests/board_preview.png")
		print("Saved screenshot.")
		quit(0)
	return false
