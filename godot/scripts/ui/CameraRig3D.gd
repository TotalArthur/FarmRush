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

@export var pitch_degrees := 55.0
@export var distance := 14.0
@export var min_distance := 6.0
@export var max_distance := 26.0
@export var pan_speed := 9.0
@export var zoom_step := 1.6
@export var edge_scroll := true
@export var edge_margin := 24.0
@export var orbit_speed := 0.008

var arm: Node3D
var camera: Camera3D
var _bounds := Rect2(Vector2(-12, -12), Vector2(24, 24))  # focus clamp (XZ)
var _orbiting := false

func _ready() -> void:
	arm = Node3D.new()
	arm.rotation_degrees = Vector3(-pitch_degrees, 0, 0)
	add_child(arm)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, distance)
	# Depth of field needs the Forward+/Mobile renderer (a RenderingDevice).
	# On gl_compatibility it's unsupported, so only enable it when available.
	if RenderingServer.get_rendering_device() != null:
		var attribs := CameraAttributesPractical.new()
		attribs.dof_blur_far_enabled = true
		attribs.dof_blur_far_distance = 22.0
		attribs.dof_blur_far_transition = 8.0
		attribs.dof_blur_amount = 0.06
		camera.attributes = attribs
	arm.add_child(camera)
	camera.current = true

## Fit the camera framing + pan limits to the live board.
func frame_board(board: BoardView3D) -> void:
	var span := 6.0
	for c in board._hex_world:
		span = max(span, Vector2(c.x, c.z).length())
	_bounds = Rect2(Vector2(-span, -span), Vector2(span * 2.0, span * 2.0))
	distance = clampf(span * 2.4, min_distance, max_distance)
	camera.position.z = distance

func _process(delta: float) -> void:
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

	if move != Vector2.ZERO:
		move = move.limit_length(1.0)
		# Pan relative to yaw so "up" is always away from the camera.
		var yaw := rotation.y
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var delta_pos := (right * move.x + fwd * (-move.y)) * pan_speed * delta
		var focus := position + delta_pos
		focus.x = clampf(focus.x, _bounds.position.x, _bounds.position.x + _bounds.size.x)
		focus.z = clampf(focus.z, _bounds.position.y, _bounds.position.y + _bounds.size.y)
		position = focus

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = event.pressed
	elif event is InputEventMouseMotion and _orbiting:
		rotation.y -= event.relative.x * orbit_speed

func _zoom(amount: float) -> void:
	distance = clampf(distance + amount, min_distance, max_distance)
	camera.position.z = distance
