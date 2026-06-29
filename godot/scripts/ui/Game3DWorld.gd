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

	# Soft bright sky.
	var sky := Sky.new()
	var skymat := ProceduralSkyMaterial.new()
	skymat.sky_top_color = Color(0.30, 0.55, 0.85)
	skymat.sky_horizon_color = Color(0.62, 0.78, 0.92)
	skymat.ground_bottom_color = Color(0.45, 0.55, 0.65)
	skymat.ground_horizon_color = Color(0.62, 0.78, 0.92)
	skymat.energy_multiplier = 0.8
	sky.sky_material = skymat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.30

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 2.0

	# These three need Forward+/Mobile (a RenderingDevice). Enabling them on
	# gl_compatibility does nothing harmful but isn't rendered, so guard them.
	if RenderingServer.get_rendering_device() != null:
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 2.0
		env.ssao_detail = 1.0
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_bloom = 0.1

	we.environment = env
	add_child(we)

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -45, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 1.5   # softer shadow edges
	sun.shadow_blur = 1.5
	add_child(sun)
