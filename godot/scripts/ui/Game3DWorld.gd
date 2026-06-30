class_name Game3DWorld
extends Node3D

## Assembles the 3D tabletop: environment, lighting, camera rig, the 3D board,
## the physics dice, and the existing 2D HUD as a transparent overlay.
##
## The HUD (GameScreen) is reused verbatim — we just hand it the 3D board via
## `external_board`, so all build/trade/dialog logic is shared with the 2D path.

var board: BoardView3D
var rig: CameraRig3D
var dice: DiceManager
var hud: GameScreen

var _last_dice := Vector2i(-1, -1)

func _ready() -> void:
	_setup_environment()
	_setup_light()

	board = BoardView3D.new()
	add_child(board)

	rig = CameraRig3D.new()
	add_child(rig)
	rig.frame_board(board)

	dice = DiceManager.new()
	dice.floor_y = BoardView3D.TILE_HEIGHT
	add_child(dice)

	# HUD overlay on its own CanvasLayer so it draws over the 3D world.
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = GameScreen.new()
	hud.external_board = board
	layer.add_child(hud)

	Game.state_changed.connect(_on_state_changed)
	if Game.state != null and Game.state.has_rolled:
		_last_dice = Vector2i(Game.state.dice[0], Game.state.dice[1])

func _on_state_changed() -> void:
	# Cosmetic dice toss whenever the engine produces a new roll.
	if Game.state == null:
		return
	if Game.state.has_rolled:
		var d := Vector2i(Game.state.dice[0], Game.state.dice[1])
		if d != _last_dice:
			_last_dice = d
			dice.throw(Vector3.ZERO)
	else:
		_last_dice = Vector2i(-1, -1)

# ===========================================================================
#  Environment & lighting (bright, plastic, toy-like)
# ===========================================================================
func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	# Deep, vibrant ocean-blue background (no bright sky).
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.20, 0.38)

	# Controlled ambient fill: lifts shadows so they aren't pitch black,
	# without washing out the highlights.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.70, 0.84)
	env.ambient_light_energy = 0.45

	# ACES tonemapping with a slightly reduced exposure for a rich, matte look.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85
	env.tonemap_white = 1.0

	# Slight saturation boost for that vibrant "toy box" feel.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.03

	# SSAO + glow need Forward+/Mobile (a RenderingDevice); guard for GL.
	if RenderingServer.get_rendering_device() != null:
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 2.2
		env.ssao_detail = 1.0
		# Bloom so emissive holograms / highlights bleed beautifully.
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_bloom = 0.15
		env.glow_hdr_threshold = 0.9

	we.environment = env
	add_child(we)

func _setup_light() -> void:
	# Key light — soft, warm, not too strong.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -50, 0)
	sun.light_energy = 0.8
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 2.5   # soft shadow edges
	sun.shadow_blur = 2.0
	add_child(sun)

	# Cool fill light from the opposite side (no shadows) to open up the
	# shaded faces — keeps the plastic-toy look from going muddy.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 130, 0)
	fill.light_energy = 0.28
	fill.light_color = Color(0.78, 0.86, 1.0)
	fill.shadow_enabled = false
	add_child(fill)
