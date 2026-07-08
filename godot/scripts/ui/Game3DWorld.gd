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
var _last_current := -1

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
			board.flash_production(d.x + d.y)
	else:
		_last_dice = Vector2i(-1, -1)

	# On a turn change, drift the camera toward the active player's cluster.
	if Game.state.current != _last_current:
		_last_current = Game.state.current
		_focus_active_player()

func _focus_active_player() -> void:
	var s := Game.state
	var seat := s.current
	var sum := Vector3.ZERO
	var n := 0
	for v in s.buildings:
		if s.buildings[v]["owner"] == seat:
			sum += board._vertex_world[v]
			n += 1
	if n > 0:
		rig.focus_on(sum / float(n))

# ===========================================================================
#  Environment & lighting (bright, plastic, toy-like)
# ===========================================================================
func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	# Deep, vibrant ocean-blue background (no bright sky) — a shade darker than
	# the colonist-blue water plane so the sea fades out at the horizon.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.22, 0.38)

	# Generous ambient fill: shaded faces stay readable, and because the key
	# light is dimmer overall the scene reads soft rather than harsh.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.68, 0.80)
	env.ambient_light_energy = 0.34

	# Rich-but-calm grading: pull exposure DOWN and saturation UP so colors
	# read deep and vivid instead of bright and washed out.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72
	env.tonemap_white = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.02
	env.adjustment_brightness = 0.97

	# SSAO + glow need Forward+/Mobile (a RenderingDevice); guarded so the GL
	# fallback never errors. SSAO is pushed hard so the seams between the chunky
	# hex tiles get deep, rich contact shadows (the key "physical board" look).
	if RenderingServer.get_rendering_device() != null:
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 3.0
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_horizon = 0.06
		# Subtle bloom so emissive holograms / rim highlights bleed nicely.
		env.glow_enabled = true
		env.glow_intensity = 0.16
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.0

	we.environment = env
	add_child(we)

func _setup_light() -> void:
	# Key light — LOW-angle warm sun (Pummel Party look) for long, dramatic
	# shadows raked across the tiles. Warm cream, bright but not overexposed.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -55, 0)   # low-ish sun -> long shadows
	sun.light_energy = 0.95                       # strong key = readable shadows
	sun.light_color = Color(1.0, 0.95, 0.84)      # warm cream / soft gold
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 1.0   # soft but clearly present shadow edges
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_opacity = 1.0           # full shadows — props must ground visibly
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	# Gentle cool fill (no shadows) keeps shaded faces readable without
	# flattening the sun shadows.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 120, 0)
	fill.light_energy = 0.22
	fill.light_color = Color(0.82, 0.89, 1.0)
	fill.shadow_enabled = false
	add_child(fill)
