class_name DiceManager
extends Node3D

## Throws two physical dice onto the board and reports the total once they
## settle. Includes an invisible floor so the dice land on the tabletop.
##
## INTEGRATION NOTE — the core engine (GameState._do_roll) is authoritative and
## generates the dice values via RNG; it must stay untouched. So there are two
## ways to use this:
##   1) COSMETIC (default, recommended): call throw() for flair after the engine
##      rolls; the HUD still shows the engine's number. Simple and desync-proof.
##   2) AUTHORITATIVE: read `dice_rolled` and feed the faces into a NEW action
##      added in GameManager (NOT GameState), e.g. a "roll_with" that sets the
##      dice — only do this in local single-player to avoid network divergence.

signal dice_rolled(total, faces)

@export var floor_y := 0.45        # match BoardView3D.TILE_HEIGHT
@export var spawn_height := 6.0

var _dice: Array[Dice3D] = []
var _rolling := false
var _settle_time := 0.0

func _ready() -> void:
	_add_floor()
	for i in range(2):
		var d := Dice3D.new()
		add_child(d)
		d.global_position = Vector3(-100, -100, -100)  # park off-board until thrown
		_dice.append(d)

func _add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, floor_y)
	shape.shape = plane
	body.add_child(shape)
	add_child(body)

## Toss both dice from above the board center (or a given point).
func throw(center: Vector3 = Vector3.ZERO) -> void:
	_rolling = true
	_settle_time = 0.0
	for i in range(_dice.size()):
		var off := Vector3(-0.6 + 1.2 * i, spawn_height, randf_range(-0.4, 0.4))
		_dice[i].throw_from(center + off)

func _physics_process(delta: float) -> void:
	if not _rolling:
		return
	for d in _dice:
		if not d.is_at_rest():
			_settle_time = 0.0
			return
	# All dice still for a short moment -> lock in the result.
	_settle_time += delta
	if _settle_time >= 0.3:
		_rolling = false
		var faces: Array[int] = []
		var total := 0
		for d in _dice:
			var v := d.top_value()
			faces.append(v)
			total += v
		dice_rolled.emit(total, faces)
