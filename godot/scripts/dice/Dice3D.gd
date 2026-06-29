class_name Dice3D
extends RigidBody3D

## A single physical d6. Builds its own cube mesh + collider, can be thrown,
## and reports the value on its top face once it comes to rest.

# Local face normal -> pip value (opposite faces sum to 7).
const FACE_VALUES := [
	[Vector3.UP, 1],
	[Vector3.DOWN, 6],
	[Vector3.RIGHT, 2],
	[Vector3.LEFT, 5],
	[Vector3(0, 0, 1), 3],
	[Vector3(0, 0, -1), 4],
]

@export var size := 0.5
var _rest_timer := 0.0

func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("fbfbf2")
	mat.roughness = 0.4
	mesh.material_override = mat
	add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * size
	shape.shape = box_shape
	add_child(shape)

	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	mass = 0.6

## Throw the die from a position with random spin.
func throw_from(pos: Vector3) -> void:
	global_position = pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var impulse := Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 0.5), randf_range(-1.5, 1.5))
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)))

## True once the die has settled.
func is_at_rest() -> bool:
	return linear_velocity.length() < 0.05 and angular_velocity.length() < 0.05

## Read the value of the face currently pointing up.
func top_value() -> int:
	var best_dot := -2.0
	var best_val := 1
	for entry in FACE_VALUES:
		var world_normal: Vector3 = global_transform.basis * entry[0]
		var d := world_normal.dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best_val = entry[1]
	return best_val
