class_name Token3D
extends Node3D

## Number-token root that keeps itself readable from anywhere on the table.
##
## Two per-frame corrections:
##
## 1. Distance equalization — projected size on screen is proportional to
##    1/distance, so multiplying our scale by (distance / reference) cancels
##    the shrink exactly: a back-row token reads the same size as a front-row
##    one. The reference is the camera's distance to the table center, so the
##    average token keeps its authored size.
##
## 2. Soft facing — the disc's normal tilts PARTWAY from straight-up toward
##    the camera (tilt_factor). Full billboarding makes tokens "swim" against
##    the static board during pans; a partial tilt keeps them anchored to the
##    table while still killing the worst of the ellipse distortion.

@export var tilt_factor := 0.55   # 0 = lie flat on the tile, 1 = face camera
@export var max_boost := 1.35     # cap on distance up-scaling
@export var min_boost := 0.90     # cap on distance down-scaling

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	var dist := to_cam.length()
	if dist < 0.001:
		return
	var ref := maxf(cam.global_position.length(), 0.001)
	scale = Vector3.ONE * clampf(dist / ref, min_boost, max_boost)
	# Yaw to the camera's compass direction, then pitch the disc normal
	# tilt_factor of the way from vertical toward the camera (YXZ order:
	# the X pitch happens inside the yawed frame, i.e. toward the camera).
	var yaw := atan2(to_cam.x, to_cam.z)
	var from_up := acos(clampf(to_cam.y / dist, -1.0, 1.0))
	rotation = Vector3(from_up * tilt_factor, yaw, 0.0)
