class_name CameraRig3D
extends Node3D

## Tabletop camera rig for the 3D board.
##
## Gimbal layout (built in code):
##   CameraRig3D (this, holds focus point + yaw)
##     └─ Arm (Node3D, pitched down ~55°)
##          └─ Camera3D (pulled back by `distance`)
##
## Controls:
##   - WASD / arrows  : pan the focus point (relative to current yaw)
##   - Mouse at screen edge : edge-scroll panning
##   - Scroll wheel   : zoom (clamps distance)
##   - Middle-drag    : orbit (yaw)
## Panning is clamped to the board's footprint so you can't lose the table.

@export var pitch_degrees := 47.0   # tight, dramatic isometric tilt
@export var fov := 40.0             # low FOV -> telephoto "miniature diorama"
@export var distance := 20.0
@export var min_distance := 10.0
@export var max_distance := 48.0
@export var pan_speed := 9.0
@export var zoom_step := 1.6
@export var edge_scroll := true
@export var edge_margin := 24.0
@export var orbit_speed := 0.008

@export var idle_delay := 2.0       # seconds of no input before drift kicks in
@export var idle_drift := 0.35      # how far the idle drift offsets the view

var arm: Node3D
var camera: Camera3D
var _bounds := Rect2(Vector2(-12, -12), Vector2(24, 24))  # focus clamp (XZ)
var _orbiting := false
var _time := 0.0
var _idle := 0.0                    # 0..1 ramp once the player stops interacting
var _focus_target := Vector3.ZERO
var _has_focus := false

func _ready() -> void:
	arm = Node3D.new()
	arm.rotation_degrees = Vector3(-pitch_degrees, 0, 0)
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = fov
	camera.position = Vector3(0, 0, distance)
	# Depth of field disabled: the whole tabletop should read crisp and sharp
	# at any camera distance/FOV. Leaving this off avoids the board-wide blur
	# some Forward+/Vulkan setups produced with a far-blur radius tuned for an
	# older, closer camera position.
	arm.add_child(camera)
	camera.current = true

## Fit the camera framing + pan limits to the live board.
func frame_board(board: BoardView3D) -> void:
	var span := 6.0
	for c in board._hex_world:
		span = max(span, Vector2(c.x, c.z).length())
	_bounds = Rect2(Vector2(-span, -span), Vector2(span * 2.0, span * 2.0))
	# Low FOV needs more pull-back to frame the same board (telephoto look).
	distance = clampf(span * 4.6, min_distance, max_distance)
	camera.position.z = distance

## Smoothly drift the camera focus toward a world point (active player's
## settlement cluster). Manual panning cancels it.
func focus_on(world_pos: Vector3) -> void:
	_focus_target = Vector3(
		clampf(world_pos.x, _bounds.position.x, _bounds.position.x + _bounds.size.x),
		0.0,
		clampf(world_pos.z, _bounds.position.y, _bounds.position.y + _bounds.size.y))
	_has_focus = true

func _process(delta: float) -> void:
	_time += delta
	var move := Vector2.ZERO
	move.x += Input.get_axis("ui_left", "ui_right")
	move.y += Input.get_axis("ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if Input.is_key_pressed(KEY_W): move.y -= 1.0
	if Input.is_key_pressed(KEY_S): move.y += 1.0

	if edge_scroll:
		var vp := get_viewport().get_visible_rect().size
		var mp := get_viewport().get_mouse_position()
		if mp.x < edge_margin: move.x -= 1.0
		elif mp.x > vp.x - edge_margin: move.x += 1.0
		if mp.y < edge_margin: move.y -= 1.0
		elif mp.y > vp.y - edge_margin: move.y += 1.0

	var interacting := move != Vector2.ZERO or _orbiting
	if interacting:
		_idle = 0.0
		_has_focus = false   # taking manual control cancels auto-focus
		move = move.limit_length(1.0)
		# Pan relative to yaw so "up" is always away from the camera.
		var yaw := rotation.y
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var delta_pos := (right * move.x + fwd * (-move.y)) * pan_speed * delta
		_apply_focus(position + delta_pos)
	else:
		# Auto-focus toward the active player's cluster.
		if _has_focus:
			_apply_focus(position.lerp(_focus_target, 1.0 - exp(-2.5 * delta)))
		# Ramp up the idle drift after a pause.
		_idle = min(1.0, _idle + delta / idle_delay)

	# Subtle ambient drift via the camera's view offset (doesn't move the rig,
	# so it never fights focus or clamping).
	var d := _idle * idle_drift
	camera.h_offset = sin(_time * 0.27) * d
	camera.v_offset = sin(_time * 0.21 + 1.3) * d * 0.6

func _apply_focus(focus: Vector3) -> void:
	focus.x = clampf(focus.x, _bounds.position.x, _bounds.position.x + _bounds.size.x)
	focus.z = clampf(focus.z, _bounds.position.y, _bounds.position.y + _bounds.size.y)
	position = Vector3(focus.x, position.y, focus.z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(-zoom_step); _idle = 0.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(zoom_step); _idle = 0.0
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = event.pressed
	elif event is InputEventMouseMotion and _orbiting:
		rotation.y -= event.relative.x * orbit_speed
		_idle = 0.0

func _zoom(amount: float) -> void:
	distance = clampf(distance + amount, min_distance, max_distance)
	camera.position.z = distance
