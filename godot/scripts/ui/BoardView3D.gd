class_name BoardView3D
extends Node3D

## 3D "digital tabletop" board.
##
## Renders the SAME board the engine produces (GameState.board / HexBoard) as
## solid, chunky hex tiles sitting in a calm water plane, with floating number
## tokens, hover lift, and bouncy piece placement. Reads state from the Game
## autoload; never mutates it.
##
## Drop-in API match with the 2D BoardView so the HUD (GameScreen) is unchanged:
## same PickMode enum, set_mode(), pick_mode/acting_seat, and the
## vertex_picked / edge_picked / hex_picked signals.

signal vertex_picked(vertex_id)
signal edge_picked(edge_id)
signal hex_picked(hex_id)

enum PickMode { NONE, SETTLEMENT, CITY, ROAD, ROBBER }

# --- Tunables (world units) ------------------------------------------------
const WORLD_SCALE := 0.02
const TILE_HEIGHT := 0.5         # chunky vertical extrusion; also the rim/top
const WATER_Y := 0.12            # water sits partway up the tile sides
const TOKEN_LIFT := 0.1          # token height above the solid hex top
const TILE_HOVER_LIFT := 0.12
const PLACE_TIME := 0.5

var pick_mode: int = PickMode.NONE
var acting_seat: int = -1

# Precomputed world positions (aligned to engine vertex/edge/hex ids).
var _hex_world: Array[Vector3] = []
var _vertex_world: Array[Vector3] = []
var _edge_mid_world: Array[Vector3] = []
var _board_ref
var _board_center := Vector2.ZERO
var _r := 1.0

var _tile_nodes: Array[MeshInstance3D] = []
var _settle_nodes := {}
var _road_nodes := {}
var _robber_node: Node3D
var _highlights: Node3D
var _hologram: Node3D

var _hover_hex := -1
var _hover_vertex := -1
var _hover_edge := -1
var _time := 0.0
var _ready_for_fx := false       # suppress placement bursts during initial build

var _mat_cache := {}
var _terrain_shader: Shader
var _water_shader: Shader
var _hex_mesh: ArrayMesh

func _ready() -> void:
	_terrain_shader = load("res://shaders/terrain.gdshader")
	_water_shader = load("res://shaders/water.gdshader")
	_highlights = Node3D.new()
	add_child(_highlights)
	if Game.state != null:
		_build_board()
	Game.state_changed.connect(_on_state_changed)
	set_process(true)

func queue_redraw() -> void:
	pass  # drop-in no-op for the HUD's board.queue_redraw()

# ===========================================================================
#  Public API used by the HUD
# ===========================================================================
func set_mode(mode: int, seat: int) -> void:
	pick_mode = mode
	acting_seat = seat
	_rebuild_hologram()
	_rebuild_highlights()

# ===========================================================================
#  Board construction
# ===========================================================================
func _on_state_changed() -> void:
	if Game.state == null:
		return
	if Game.state.board != _board_ref:
		_build_board()
	else:
		_sync_pieces()
		_rebuild_highlights()

func _build_board() -> void:
	var s := Game.state
	_board_ref = s.board
	_clear_children_except_highlights()
	_precompute_world(s)
	_spawn_water()

	# One shared solid hex prism mesh for every tile.
	_hex_mesh = _make_hex_prism(_r, TILE_HEIGHT)
	_tile_nodes.clear()
	for h in range(s.board.hex_count()):
		var tile := MeshInstance3D.new()
		tile.mesh = _hex_mesh
		tile.material_override = _terrain_material(s.hex_res[h])
		tile.position = Vector3(_hex_world[h].x, 0.0, _hex_world[h].z)
		add_child(tile)
		_tile_nodes.append(tile)
		# Number token parented to the tile so it stays 0.1 above the top face
		# (and rides along on hover).
		if s.hex_token[h] > 0:
			var tok := _make_token(s.hex_token[h])
			tok.position = Vector3(0, TILE_HEIGHT + TOKEN_LIFT, 0)
			tile.add_child(tok)

	_settle_nodes.clear()
	_road_nodes.clear()
	_robber_node = _make_robber()
	add_child(_robber_node)
	_ready_for_fx = false
	_sync_pieces()            # no confetti for pieces that already existed
	_ready_for_fx = true
	_rebuild_highlights()

func _precompute_world(s: GameState) -> void:
	_board_center = Vector2.ZERO
	for c in s.board.hex_center:
		_board_center += c
	_board_center /= float(s.board.hex_count())
	_r = HexBoard.HEX_SIZE * WORLD_SCALE
	_hex_world.clear()
	for c in s.board.hex_center:
		_hex_world.append(_to_world(c, TILE_HEIGHT))
	_vertex_world.clear()
	for v in s.board.vertex_pos:
		_vertex_world.append(_to_world(v, TILE_HEIGHT))
	_edge_mid_world.clear()
	for e in s.board.edges:
		var mid := (s.board.vertex_pos[e.x] + s.board.vertex_pos[e.y]) * 0.5
		_edge_mid_world.append(_to_world(mid, TILE_HEIGHT))

func _to_world(p: Vector2, y: float) -> Vector3:
	return Vector3((p.x - _board_center.x) * WORLD_SCALE, y, (p.y - _board_center.y) * WORLD_SCALE)

func _clear_children_except_highlights() -> void:
	for c in get_children():
		if c != _highlights:
			c.queue_free()

# ===========================================================================
#  Solid hex prism geometry
# ===========================================================================
func _make_hex_prism(radius: float, height: float) -> ArrayMesh:
	# Pointy-top hexagon matching HexBoard's corner angles (60*i - 30 deg).
	# Explicit normals + a filled top/bottom fan + solid side walls. Visibility
	# is guaranteed by the material's cull_disabled, so winding can't hollow it.
	var corners: Array[Vector2] = []
	for i in range(6):
		var a := deg_to_rad(60.0 * i - 30.0)
		corners.append(Vector2(cos(a), sin(a)) * radius)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_c := Vector3(0, height, 0)
	var bot_c := Vector3(0, 0, 0)
	for i in range(6):
		var j := (i + 1) % 6
		var t0 := Vector3(corners[i].x, height, corners[i].y)
		var t1 := Vector3(corners[j].x, height, corners[j].y)
		var b0 := Vector3(corners[i].x, 0, corners[i].y)
		var b1 := Vector3(corners[j].x, 0, corners[j].y)
		_tri(st, top_c, t0, t1, Vector3.UP)         # solid top face
		_tri(st, bot_c, b1, b0, Vector3.DOWN)       # solid bottom face
		var radial := Vector3(corners[i].x + corners[j].x, 0, corners[i].y + corners[j].y).normalized()
		_tri(st, b0, t0, t1, radial)                # side wall
		_tri(st, b0, t1, b1, radial)
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n); st.add_vertex(a)
	st.set_normal(n); st.add_vertex(b)
	st.set_normal(n); st.add_vertex(c)

# ===========================================================================
#  Materials
# ===========================================================================
func _plastic(color: Color) -> StandardMaterial3D:
	var key := "p_" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mat_cache[key] = m
	return m

func _terrain_material(res: int) -> ShaderMaterial:
	var key := "t_%d" % res
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _terrain_shader
	var ca: Color
	var cb: Color
	var pattern := 0
	var scale := 6.0
	# Polished cartoon finish: smooth satin sheen (roughness ~0.4–0.5) with
	# bright, saturated colors. Ore is a touch glossier/metallic.
	var rough_a := 0.5
	var rough_b := 0.4
	var metallic := 0.0
	match res:
		Consts.Res.WOOD:        # lush forest green
			ca = Color("2f8f3b"); cb = Color("5cc24f"); pattern = 0; scale = 7.0
		Consts.Res.SHEEP:       # bright pasture
			ca = Color("7ec64a"); cb = Color("aee06a"); pattern = 0; scale = 6.0
		Consts.Res.WHEAT:       # golden wheat
			ca = Color("e6b52e"); cb = Color("ffd84a"); pattern = 0; scale = 8.0
		Consts.Res.BRICK:       # bright terracotta
			ca = Color("d2632f"); cb = Color("ef8c52"); pattern = 1; scale = 6.0
		Consts.Res.ORE:         # clean stone with a gleam
			ca = Color("7d8893"); cb = Color("b6bfc9"); pattern = 1; scale = 6.0
			rough_a = 0.42; rough_b = 0.30; metallic = 0.30
		_:                      # desert sand
			ca = Color("e6cd86"); cb = Color("f6e6b0"); pattern = 2; scale = 5.0
	m.set_shader_parameter("color_a", ca)
	m.set_shader_parameter("color_b", cb)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("pattern_type", pattern)
	m.set_shader_parameter("rough_a", rough_a)
	m.set_shader_parameter("rough_b", rough_b)
	m.set_shader_parameter("metallic_amt", metallic)
	m.set_shader_parameter("hex_radius", _r)
	# SSAO now does the deep crevice shadows, so ease off the in-shader darken.
	m.set_shader_parameter("edge_darken", 0.16)
	m.set_shader_parameter("rim_strength", 0.14)
	_mat_cache[key] = m
	return m

# ===========================================================================
#  Water (no island base — tiles sit directly in the water)
# ===========================================================================
func _spawn_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	water.mesh = plane
	var wm := ShaderMaterial.new()
	wm.shader = _water_shader
	water.material_override = wm
	water.position = Vector3(0, WATER_Y, 0)
	add_child(water)

# ===========================================================================
#  Piece sync (bouncy pop-in)
# ===========================================================================
func _sync_pieces() -> void:
	var s := Game.state
	for v in s.buildings:
		var b: Dictionary = s.buildings[v]
		var col: Color = s.players[b["owner"]].color
		if not _settle_nodes.has(v):
			var node := _make_city(col) if b["city"] else _make_settlement(col)
			node.position = _vertex_world[v]
			add_child(node)
			_settle_nodes[v] = { "node": node, "city": b["city"] }
			_pop_in(node)
			if _ready_for_fx:
				_burst(node.position + Vector3(0, _r * 0.4, 0), col)
		elif _settle_nodes[v]["city"] != b["city"]:
			_settle_nodes[v]["node"].queue_free()
			var node2 := _make_city(col)
			node2.position = _vertex_world[v]
			add_child(node2)
			_settle_nodes[v] = { "node": node2, "city": true }
			_pop_in(node2)
			if _ready_for_fx:
				_burst(node2.position + Vector3(0, _r * 0.4, 0), col)
	for e in s.roads:
		if not _road_nodes.has(e):
			var edge := s.board.edges[e]
			var col2: Color = s.players[s.roads[e]].color
			var rnode := _make_road(col2, _vertex_world[edge.x], _vertex_world[edge.y])
			add_child(rnode)
			_road_nodes[e] = rnode
			_pop_in(rnode)
			if _ready_for_fx:
				_burst(rnode.position + Vector3(0, _r * 0.25, 0), col2)
	if _robber_node != null:
		var target := _hex_world[s.robber_hex] + Vector3(_r * 0.3, 0.02, _r * 0.1)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_robber_node, "position", target, 0.4)

func _pop_in(node: Node3D) -> void:
	node.scale = Vector3.ZERO
	var tw := create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ONE, PLACE_TIME)

# ===========================================================================
#  Confetti burst on placement (player-colored, scales down to 0)
# ===========================================================================
func _burst(pos: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 26
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = _r * 0.12
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 1.4
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -6.5, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	# Tiny confetti chip that fades from full size to nothing.
	var chip := BoxMesh.new()
	chip.size = Vector3(0.05, 0.05, 0.01)
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.albedo_color = Color.WHITE
	cmat.emission_enabled = true
	cmat.emission = color
	cmat.emission_energy_multiplier = 0.6
	cmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	chip.material = cmat
	p.mesh = chip
	p.color = color
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.9))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.6
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(p, p.lifetime + 0.4)

func _free_later(node: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(node):
		node.queue_free()

# ===========================================================================
#  Per-frame: hover detection + highlight pulse
# ===========================================================================
func _process(delta: float) -> void:
	_time += delta
	_update_hover()
	_pulse_highlights()

func _update_hover() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or Game.state == null:
		return
	var mpos := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mpos)
	var dir := cam.project_ray_normal(mpos)
	var plane := Plane(Vector3.UP, TILE_HEIGHT)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		_set_hover_hex(-1)
		_hover_vertex = -1
		_hover_edge = -1
		if _hologram != null:
			_hologram.visible = false
		return
	var p: Vector3 = hit
	_set_hover_hex(_nearest(_hex_world, p, _r * 1.2))
	match pick_mode:
		PickMode.SETTLEMENT, PickMode.CITY:
			_hover_vertex = _nearest_in(_vertex_world, p, _r * 0.5, _valid_vertex_set())
			_place_hologram_at_vertex(_hover_vertex)
		PickMode.ROAD:
			_hover_edge = _nearest_in(_edge_mid_world, p, _r * 0.45, _valid_edge_set())
			_place_hologram_at_edge(_hover_edge)
		_:
			_hover_vertex = -1
			_hover_edge = -1
			if _hologram != null:
				_hologram.visible = false

func _set_hover_hex(h: int) -> void:
	if h == _hover_hex:
		return
	if _hover_hex != -1 and _hover_hex < _tile_nodes.size():
		_lift_tile(_hover_hex, 0.0)
	_hover_hex = h
	if h != -1:
		_lift_tile(h, TILE_HOVER_LIFT)

func _lift_tile(h: int, target_y: float) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_tile_nodes[h], "position:y", target_y, 0.18)

# ===========================================================================
#  Input -> picks
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if Game.state == null:
		return
	match pick_mode:
		PickMode.SETTLEMENT, PickMode.CITY:
			if _hover_vertex != -1:
				vertex_picked.emit(_hover_vertex)
		PickMode.ROAD:
			if _hover_edge != -1:
				edge_picked.emit(_hover_edge)
		PickMode.ROBBER:
			if _hover_hex != -1 and _hover_hex != Game.state.robber_hex:
				hex_picked.emit(_hover_hex)

# ===========================================================================
#  Highlights + hologram
# ===========================================================================
func _rebuild_highlights() -> void:
	for c in _highlights.get_children():
		_highlights.remove_child(c)
		c.queue_free()
	if Game.state == null:
		return
	match pick_mode:
		PickMode.SETTLEMENT, PickMode.CITY:
			for v in _valid_vertex_set():
				_highlights.add_child(_make_marker(_vertex_world[v]))
		PickMode.ROAD:
			for e in _valid_edge_set():
				var edge := Game.state.board.edges[e]
				_highlights.add_child(_make_edge_marker(_vertex_world[edge.x], _vertex_world[edge.y]))
		PickMode.ROBBER:
			for h in range(Game.state.board.hex_count()):
				if h != Game.state.robber_hex:
					_highlights.add_child(_make_marker(_hex_world[h], Color(1, 0.4, 0.3)))

func _pulse_highlights() -> void:
	if _highlights.get_child_count() == 0:
		return
	var e := 1.5 + 1.5 * (0.5 + 0.5 * sin(_time * 4.0))
	for c in _highlights.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			c.material_override.emission_energy_multiplier = e

func _rebuild_hologram() -> void:
	if _hologram != null:
		_hologram.queue_free()
		_hologram = null
	if Game.state == null or acting_seat < 0:
		return
	var col: Color = Game.state.players[acting_seat].color
	match pick_mode:
		PickMode.SETTLEMENT:
			_hologram = _make_settlement(col)
		PickMode.CITY:
			_hologram = _make_city(col)
		PickMode.ROAD:
			_hologram = _make_road(col, Vector3.ZERO, Vector3(0, 0, _r))
		_:
			return
	_make_ghost(_hologram)
	_hologram.visible = false
	add_child(_hologram)

func _place_hologram_at_vertex(v: int) -> void:
	if _hologram == null:
		return
	if v == -1:
		_hologram.visible = false
		return
	_hologram.visible = true
	_hologram.position = _vertex_world[v]

func _place_hologram_at_edge(e: int) -> void:
	if _hologram == null:
		return
	if e == -1:
		_hologram.visible = false
		return
	var edge := Game.state.board.edges[e]
	var a := _vertex_world[edge.x]
	var b := _vertex_world[edge.y]
	_hologram.visible = true
	_hologram.position = (a + b) * 0.5
	_hologram.rotation.y = atan2(b.x - a.x, b.z - a.z)

# ===========================================================================
#  Validity (mirrors GameState rules — engine untouched)
# ===========================================================================
func _valid_vertex_set() -> Array:
	var s := Game.state
	var out: Array = []
	if pick_mode == PickMode.CITY:
		for v in s.buildings:
			if s.buildings[v]["owner"] == acting_seat and not s.buildings[v]["city"]:
				out.append(v)
		return out
	var setup := s.phase == Consts.Phase.SETUP
	for v in range(s.board.vertex_count()):
		if not s._vertex_open_for_settlement(v, setup):
			continue
		if setup or s._vertex_touches_own_road(v, acting_seat):
			out.append(v)
	return out

func _valid_edge_set() -> Array:
	var s := Game.state
	var out: Array = []
	for e in range(s.board.edge_count()):
		if s.roads.has(e):
			continue
		if s.phase == Consts.Phase.SETUP:
			var edge := s.board.edges[e]
			if edge.x == s.setup_last_vertex or edge.y == s.setup_last_vertex:
				out.append(e)
		elif s._road_connects(e, acting_seat):
			out.append(e)
	return out

# ===========================================================================
#  Piece + marker meshes
# ===========================================================================
func _nearest(arr: Array, p: Vector3, max_d: float) -> int:
	var best := -1
	var best_d := max_d
	for i in range(arr.size()):
		var d := Vector2(arr[i].x, arr[i].z).distance_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d; best = i
	return best

func _nearest_in(arr: Array, p: Vector3, max_d: float, allowed: Array) -> int:
	var best := -1
	var best_d := max_d
	for i in allowed:
		var d := Vector2(arr[i].x, arr[i].z).distance_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d; best = i
	return best

func _make_token(number: int) -> Node3D:
	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _r * 0.34
	cyl.bottom_radius = _r * 0.34
	cyl.height = _r * 0.12
	cyl.radial_segments = 24
	disc.mesh = cyl
	disc.material_override = _plastic(Color("f7f3e6"))
	root.add_child(disc)
	var lbl := Label3D.new()
	lbl.text = str(number)
	lbl.font_size = 110
	lbl.pixel_size = _r * 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color("c0392b") if (number == 6 or number == 8) else Color("2c3e50")
	lbl.position = Vector3(0, _r * 0.12, 0)
	root.add_child(lbl)
	return root

func _make_marker(pos: Vector3, color: Color = Color(1, 1, 1)) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _r * 0.22
	cyl.bottom_radius = _r * 0.22
	cyl.height = 0.04
	cyl.radial_segments = 20
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	m.material_override = mat
	m.position = pos + Vector3(0, 0.06, 0)
	return m

func _make_edge_marker(a: Vector3, b: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(_r * 0.12, 0.04, a.distance_to(b) * 0.7)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	m.material_override = mat
	m.position = (a + b) * 0.5 + Vector3(0, 0.06, 0)
	m.rotation.y = atan2(b.x - a.x, b.z - a.z)
	return m

func _make_settlement(color: Color) -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(_r * 0.4, _r * 0.4, _r * 0.4)
	base.mesh = box
	base.material_override = _plastic(color)
	base.position = Vector3(0, _r * 0.2, 0)
	root.add_child(base)
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(_r * 0.46, _r * 0.28, _r * 0.46)
	roof.mesh = prism
	roof.material_override = _plastic(color.lightened(0.15))
	roof.position = Vector3(0, _r * 0.54, 0)
	root.add_child(roof)
	return root

func _make_city(color: Color) -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(_r * 0.6, _r * 0.4, _r * 0.45)
	base.mesh = box
	base.material_override = _plastic(color)
	base.position = Vector3(0, _r * 0.2, 0)
	root.add_child(base)
	var tower := MeshInstance3D.new()
	var box2 := BoxMesh.new()
	box2.size = Vector3(_r * 0.32, _r * 0.55, _r * 0.32)
	tower.mesh = box2
	tower.material_override = _plastic(color.lightened(0.1))
	tower.position = Vector3(_r * 0.18, _r * 0.5, 0)
	root.add_child(tower)
	return root

func _make_road(color: Color, a: Vector3, b: Vector3) -> Node3D:
	var root := Node3D.new()
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(_r * 0.16, _r * 0.16, max(a.distance_to(b) * 0.8, 0.1))
	m.mesh = box
	m.material_override = _plastic(color)
	m.position = Vector3(0, _r * 0.08, 0)
	root.add_child(m)
	root.position = (a + b) * 0.5
	root.rotation.y = atan2(b.x - a.x, b.z - a.z)
	return root

func _make_robber() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = _r * 0.18
	cap.height = _r * 0.7
	body.mesh = cap
	body.material_override = _plastic(Color("1b1b22"))
	body.position = Vector3(0, _r * 0.35, 0)
	root.add_child(body)
	return root

func _make_ghost(node: Node3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var src = child.material_override
			var base_col: Color = src.albedo_color if src is StandardMaterial3D else Color.WHITE
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.4)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = base_col.lightened(0.3)
			mat.emission_energy_multiplier = 1.6
			child.material_override = mat
