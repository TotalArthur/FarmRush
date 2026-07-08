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
const BEACH_HEIGHT := 0.3        # sand frame ring sits lower than the land tiles
const WATER_Y := 0.12            # water sits partway up the tile sides
const TOKEN_LIFT := 0.14         # token float height above the hex top
const TILE_HOVER_LIFT := 0.12
const PLACE_TIME := 0.5

# Click/hover detection radii, as a fraction of the hex radius (_r). Generous
# on purpose: the picker always resolves to whichever valid candidate is
# *nearest* the ray hit, so a wide catch radius only makes targets easier to
# hit — it never makes the wrong one win over a closer correct one.
const HEX_PICK_FRAC := 1.5
const VERTEX_PICK_FRAC := 0.62
const EDGE_PICK_FRAC := 0.55

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
var _roof_shader: Shader
var _hex_mesh: ArrayMesh

func _ready() -> void:
	_terrain_shader = load("res://shaders/terrain.gdshader")
	_water_shader = load("res://shaders/water.gdshader")
	_roof_shader = load("res://shaders/roof.gdshader")
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
	_spawn_beach()

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
		_scatter_props(tile, s.hex_res[h], h)

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
# Neutral building palette. Player colour is NEVER a full-mesh tint — it
# lives only in the accent elements (banner flag / road stripe), so the
# buildings keep their material identity and ownership reads as a deliberate
# team-colour mark instead of a toy recolour.
const WALL_COL := Color("e8dcc2")     # warm plaster
const TIMBER_COL := Color("7a5b40")   # dark wood (doors, poles, planks)
const STONE_COL := Color("b7b1a4")    # stone base / chimneys
const WINDOW_COL := Color("f7f0dd")   # bright shutter/window inset

## Player-accent material: proper PBR (satin roughness, hint of metal) plus
## an emission boost when a RenderingDevice exists, so Forward+ bloom makes
## the team colour pop at camera distance. On GL it stays a clean satin tint.
func _accent(color: Color) -> StandardMaterial3D:
	var key := "a_" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35
	m.metallic = 0.05
	if RenderingServer.get_rendering_device() != null:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.55
	_mat_cache[key] = m
	return m

## Player-coloured roof: THE primary ownership signal (roofs are the most
## visible surface at distance). shaders/roof.gdshader adds shingle courses
## and roughness breakup so it reads as a tiled surface, not a flat tint;
## the emission uniform carries the Forward+ bloom boost and stays 0 on GL.
func _roof_mat(color: Color) -> ShaderMaterial:
	var key := "r_" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _roof_shader
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("emission_strength",
		0.40 if RenderingServer.get_rendering_device() != null else 0.0)
	_mat_cache[key] = m
	return m

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
	# GWYF-style palette: deep saturated colors with the a/b pair kept CLOSE
	# together, so surfaces read as clean smooth color with soft variation
	# instead of busy noise.
	match res:
		Consts.Res.WOOD:        # deep forest green
			ca = Color("1d7a37"); cb = Color("339a47"); pattern = 0; scale = 5.0
		Consts.Res.SHEEP:       # fresh lime pasture
			ca = Color("84bd3a"); cb = Color("9dcf52"); pattern = 0; scale = 4.5
		Consts.Res.WHEAT:       # rich golden field with crop furrows
			ca = Color("e1a513"); cb = Color("f2c02c"); pattern = 4; scale = 8.0
		Consts.Res.BRICK:       # warm clay with brick-course texture
			ca = Color("a8481e"); cb = Color("e08348"); pattern = 3; scale = 6.0
		Consts.Res.ORE:         # cool slate with a gleam
			ca = Color("707d8a"); cb = Color("96a2ad"); pattern = 1; scale = 6.0
			rough_a = 0.42; rough_b = 0.30; metallic = 0.30
		_:                      # desert sand
			ca = Color("d6bf7e"); cb = Color("e4d194"); pattern = 2; scale = 5.0
	m.set_shader_parameter("color_a", ca)
	m.set_shader_parameter("color_b", cb)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("pattern_type", pattern)
	m.set_shader_parameter("rough_a", rough_a)
	m.set_shader_parameter("rough_b", rough_b)
	m.set_shader_parameter("metallic_amt", metallic)
	m.set_shader_parameter("hex_radius", _r)
	# SSAO now does the deep crevice shadows, so ease off the in-shader darken;
	# rim kept low so the board doesn't read overly bright/contrasty.
	m.set_shader_parameter("edge_darken", 0.14)
	m.set_shader_parameter("rim_strength", 0.03)
	m.set_shader_parameter("bump_strength", 0.3)
	_mat_cache[key] = m
	return m

# ===========================================================================
#  Water + sand frame (no island base — tiles sit directly in the water)
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
	# colonist.io ocean: friendly mid-blue, deep enough to never look washed.
	wm.set_shader_parameter("deep_color", Color("0f5589"))
	wm.set_shader_parameter("shallow_color", Color("358dc4"))
	water.material_override = wm
	water.position = Vector3(0, WATER_Y, 0)
	add_child(water)

## Ring of low sand hexes hugging the island — the 3D take on colonist.io's
## tan board frame. Shorter than the land tiles so the island reads raised,
## taller than the water so it forms a visible beach shoreline.
func _spawn_beach() -> void:
	var beach_mesh := _make_hex_prism(_r, BEACH_HEIGHT)
	var mat := ShaderMaterial.new()
	mat.shader = _terrain_shader
	mat.set_shader_parameter("color_a", Color("ab8f50"))
	mat.set_shader_parameter("color_b", Color("cdb578"))
	mat.set_shader_parameter("noise_scale", 4.0)
	mat.set_shader_parameter("pattern_type", 2)
	mat.set_shader_parameter("rough_a", 0.95)
	mat.set_shader_parameter("rough_b", 0.85)
	mat.set_shader_parameter("metallic_amt", 0.0)
	mat.set_shader_parameter("hex_radius", _r)
	mat.set_shader_parameter("edge_darken", 0.18)
	mat.set_shader_parameter("rim_strength", 0.02)
	# Pointy-top hexes: neighbors sit across the 6 edges at 60° steps,
	# center-to-center distance sqrt(3) * radius.
	var step := _r * sqrt(3.0)
	var occupied := {}
	for c in _hex_world:
		occupied[_grid_key(Vector2(c.x, c.z))] = true
	for c in _hex_world:
		for k in range(6):
			var ang := deg_to_rad(60.0 * k)
			var p := Vector2(c.x, c.z) + Vector2(cos(ang), sin(ang)) * step
			var key := _grid_key(p)
			if occupied.has(key):
				continue
			occupied[key] = true
			var m := MeshInstance3D.new()
			m.mesh = beach_mesh
			m.material_override = mat
			m.position = Vector3(p.x, 0, p.y)
			add_child(m)

func _grid_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 10.0), roundi(p.y * 10.0))

# ===========================================================================
#  Production feedback: bounce + golden burst on every tile whose number was
#  just rolled, so the player's eye snaps to what produced.
# ===========================================================================
func flash_production(total: int) -> void:
	var s := Game.state
	if s == null:
		return
	for h in range(s.board.hex_count()):
		if s.hex_token[h] != total or h == s.robber_hex:
			continue
		var tile := _tile_nodes[h]
		var tw := create_tween()
		tw.tween_property(tile, "position:y", 0.22, 0.16) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(tile, "position:y", 0.0, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		_burst(_hex_world[h] + Vector3(0, 0.4, 0), Color(1.0, 0.84, 0.30))

# ===========================================================================
#  Piece sync (bouncy pop-in)
# ===========================================================================
func _sync_pieces() -> void:
	var s := Game.state
	for v in s.buildings:
		var b: Dictionary = s.buildings[v]
		var col: Color = s.players[b["owner"]].color
		if not _settle_nodes.has(v):
			# Vertex id seeds the roof variant, so the set varies but every
			# client renders the identical board.
			var node := _make_city(col, v) if b["city"] else _make_settlement(col, v)
			node.position = _vertex_world[v]
			add_child(node)
			_settle_nodes[v] = { "node": node, "city": b["city"] }
			var fpos := node.position
			_place_juice(node,
				func(): if _ready_for_fx: _burst(fpos + Vector3(0, _r * 0.4, 0), col))
		elif _settle_nodes[v]["city"] != b["city"]:
			_settle_nodes[v]["node"].queue_free()
			var node2 := _make_city(col, v)
			node2.position = _vertex_world[v]
			add_child(node2)
			_settle_nodes[v] = { "node": node2, "city": true }
			var fpos2 := node2.position
			_place_juice(node2,
				func(): if _ready_for_fx: _burst(fpos2 + Vector3(0, _r * 0.4, 0), col))
	for e in s.roads:
		if not _road_nodes.has(e):
			var edge := s.board.edges[e]
			var col2: Color = s.players[s.roads[e]].color
			var rnode := _make_road(col2, _vertex_world[edge.x], _vertex_world[edge.y])
			add_child(rnode)
			_road_nodes[e] = rnode
			var fpos3 := rnode.position
			_place_juice(rnode,
				func(): if _ready_for_fx: _burst(fpos3 + Vector3(0, _r * 0.25, 0), col2))
	if _robber_node != null:
		var target := _hex_world[s.robber_hex] + Vector3(_r * 0.3, 0.02, _r * 0.1)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_robber_node, "position", target, 0.4)

## Placement juice: the piece falls from above (gravity-style ease-in),
## squashes on impact, and springs back — squash & stretch sells the weight.
const DROP_HEIGHT := 0.9

func _place_juice(node: Node3D, on_impact: Callable = Callable()) -> void:
	var final_pos := node.position
	node.position = final_pos + Vector3(0, DROP_HEIGHT, 0)
	node.scale = Vector3(0.72, 1.28, 0.72)          # stretched during the fall
	var tw := create_tween()
	tw.tween_property(node, "position", final_pos, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if on_impact.is_valid():
		tw.tween_callback(on_impact)
	tw.tween_property(node, "scale", Vector3(1.22, 0.72, 1.22), 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # impact squash
	tw.tween_property(node, "scale", Vector3(0.94, 1.06, 0.94), 0.09)
	tw.tween_property(node, "scale", Vector3.ONE, 0.11) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # settle

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
	_set_hover_hex(_nearest(_hex_world, p, _r * HEX_PICK_FRAC))
	match pick_mode:
		PickMode.SETTLEMENT, PickMode.CITY:
			_hover_vertex = _nearest_in(_vertex_world, p, _r * VERTEX_PICK_FRAC, _valid_vertex_set())
			_place_hologram_at_vertex(_hover_vertex)
		PickMode.ROAD:
			_hover_edge = _nearest_in(_edge_mid_world, p, _r * EDGE_PICK_FRAC, _valid_edge_set())
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
	# Token3D self-corrects every frame: equal on-screen size at any distance
	# plus a soft tilt toward the camera (see scripts/ui/Token3D.gd).
	var root := Token3D.new()
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _r * 0.38
	cyl.bottom_radius = _r * 0.38
	cyl.height = _r * 0.12
	cyl.radial_segments = 24
	disc.mesh = cyl
	disc.material_override = _plastic(Color("f7f3e6"))
	root.add_child(disc)
	var hot := number == 6 or number == 8
	var ink := Color("c0392b") if hot else Color("2c3e50")
	var lbl := Label3D.new()
	lbl.text = str(number)
	lbl.font_size = 76
	lbl.pixel_size = _r * 0.006
	# Stamped flat onto the disc, not billboarded — lay the glyph plane down
	# into the X-Z plane (normal facing +Y) so it never rotates to face the
	# camera and instead reads like it's printed on the token.
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.modulate = ink
	lbl.position = Vector3(0, cyl.height * 0.5 + 0.006, -_r * 0.06)
	root.add_child(lbl)
	# Catan-style probability pips under the number (more pips = more likely),
	# kept clear of the digits so wide numbers like 10/11/12 stay readable.
	var pips := Label3D.new()
	pips.text = "•".repeat(6 - abs(7 - number))
	pips.font_size = 40
	pips.pixel_size = _r * 0.0035
	pips.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pips.rotation_degrees = Vector3(-90, 0, 0)
	pips.modulate = ink
	pips.position = Vector3(0, cyl.height * 0.5 + 0.005, _r * 0.22)
	root.add_child(pips)
	return root

## ===========================================================================
##  Tile props — Kenney Nature Kit models (CC0, assets/models/) for the "Golf
##  With Your Friends" cartoony low-poly look, plus procedural sheep/bricks.
##  Arranged in a RING around the number token so the digits at the tile
##  center stay clearly readable, and capped well inside the vertex circle
##  (settlement markers sit out at radius _r).
## ===========================================================================
const MODEL_DIR := "res://assets/models/"

var _model_cache := {}

func _model(name_: String) -> PackedScene:
	if not _model_cache.has(name_):
		_model_cache[name_] = load(MODEL_DIR + name_ + ".glb")
	return _model_cache[name_]

func _spawn_model(tile: Node3D, name_: String, pos: Vector3, scale_f: float, yaw: float) -> void:
	var scene := _model(name_)
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	inst.position = pos
	inst.scale = Vector3.ONE * scale_f
	inst.rotation.y = yaw
	tile.add_child(inst)

func _scatter_props(tile: MeshInstance3D, res: int, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	match res:
		Consts.Res.WOOD:
			var kinds := ["tree_default", "tree_pineRoundA", "tree_detailed", "tree_pineRoundA", "tree_default"]
			var i := 0
			for pos in _prop_ring(rng, 5):
				_spawn_model(tile, kinds[i % kinds.size()], pos,
					_r * rng.randf_range(0.40, 0.50), rng.randf_range(0.0, TAU))
				i += 1
		Consts.Res.BRICK:
			for pos in _prop_ring(rng, 2, 0.42, 0.5):
				_make_brick_pile(tile, pos, rng)
		Consts.Res.SHEEP:
			for pos in _prop_ring(rng, 2, 0.42, 0.52):
				tile.add_child(_make_sheep(pos, rng))
			for pos in _prop_ring(rng, 3, 0.55, 0.62):
				_spawn_model(tile, "grass_large", pos,
					_r * rng.randf_range(0.30, 0.40), rng.randf_range(0.0, TAU))
		Consts.Res.WHEAT:
			for pos in _prop_ring(rng, 6, 0.44, 0.58):
				_spawn_model(tile, "crops_wheatStageB", pos,
					_r * rng.randf_range(0.34, 0.42), rng.randf_range(0.0, TAU))
		Consts.Res.ORE:
			var rocks := ["rock_largeA", "rock_largeB", "rock_smallA"]
			var j := 0
			for pos in _prop_ring(rng, 3):
				_spawn_model(tile, rocks[j % rocks.size()], pos,
					_r * rng.randf_range(0.42, 0.55), rng.randf_range(0.0, TAU))
				j += 1
		_:
			# Desert: a lone cactus and a flat stone so it reads arid, not empty.
			var ring := _prop_ring(rng, 2, 0.45, 0.55)
			_spawn_model(tile, "cactus_short", ring[0], _r * 0.42, rng.randf_range(0.0, TAU))
			_spawn_model(tile, "rock_smallFlatA", ring[1], _r * 0.45, rng.randf_range(0.0, TAU))

## Evenly spaced ring positions (with jitter) between r_min.._r*r_max — outside
## the token disc (0.38 _r), inside the settlement corners (1.0 _r).
func _prop_ring(rng: RandomNumberGenerator, count: int, r_min := 0.46, r_max := 0.56) -> Array:
	var out: Array = []
	var base := rng.randf_range(0.0, TAU)
	for i in range(count):
		var ang := base + TAU * float(i) / float(count) + rng.randf_range(-0.22, 0.22)
		var dist := rng.randf_range(r_min, r_max) * _r
		out.append(Vector3(cos(ang) * dist, TILE_HEIGHT, sin(ang) * dist))
	return out

func _make_brick_pile(tile: MeshInstance3D, base: Vector3, rng: RandomNumberGenerator) -> void:
	var mat := _plastic(Color("a83226"))
	var brick := Vector3(_r * 0.17, _r * 0.08, _r * 0.10)
	# 3 bricks on the ground, 2 stacked across them.
	var layout := [
		Vector3(-brick.x * 0.55, brick.y * 0.5, 0),
		Vector3(brick.x * 0.55, brick.y * 0.5, 0),
		Vector3(0, brick.y * 0.5, brick.z * 1.05),
		Vector3(-brick.x * 0.3, brick.y * 1.5, brick.z * 0.3),
		Vector3(brick.x * 0.35, brick.y * 1.5, brick.z * 0.35),
	]
	for off in layout:
		var b := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = brick
		b.mesh = box
		b.material_override = mat
		b.position = base + off
		b.rotation.y = rng.randf_range(-0.18, 0.18)
		tile.add_child(b)

func _make_sheep(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	root.scale = Vector3.ONE * 1.3
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = _r * 0.12
	cap.height = _r * 0.30
	body.mesh = cap
	body.material_override = _plastic(Color("f5f5f0"))
	body.rotation.z = deg_to_rad(90)
	body.position = Vector3(0, _r * 0.13, 0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = _r * 0.065
	sph.height = _r * 0.13
	head.mesh = sph
	head.material_override = _plastic(Color("2c2c2c"))
	head.position = Vector3(_r * 0.17, _r * 0.15, 0)
	root.add_child(head)
	# Four stubby legs so it reads as an animal, not a blob.
	for lx in [-0.07, 0.07]:
		for lz in [-0.05, 0.05]:
			var leg := MeshInstance3D.new()
			var lcyl := CylinderMesh.new()
			lcyl.top_radius = _r * 0.018
			lcyl.bottom_radius = _r * 0.018
			lcyl.height = _r * 0.07
			leg.mesh = lcyl
			leg.material_override = _plastic(Color("2c2c2c"))
			leg.position = Vector3(_r * lx, _r * 0.035, _r * lz)
			root.add_child(leg)
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

## Small axis-aligned box part (all building details are box parts so the
## ghost-hologram pass can restyle every direct MeshInstance3D child).
func _box_part(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	return m

## Player banner: dark pole + team-colour pennant planted at a roof peak.
## This is THE ownership marker on buildings.
func _add_banner(root: Node3D, color: Color, base_y: float) -> void:
	var s := _r
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.013 * s
	pc.bottom_radius = 0.013 * s
	pc.height = 0.24 * s
	pc.radial_segments = 8
	pole.mesh = pc
	pole.material_override = _plastic(TIMBER_COL)
	pole.position = Vector3(0, base_y + 0.12 * s, 0)
	root.add_child(pole)
	root.add_child(_box_part(Vector3(0.15, 0.09, 0.016) * s, _accent(color),
		Vector3(0.085 * s, base_y + 0.185 * s, 0)))

## Settlement: a small cottage with a real silhouette — plaster walls, timber
## door, window, chimney, and a roof that varies (shape + colour) by variant
## so the board never reads as repeated identical props.
func _make_settlement(color: Color, variant: int = 0) -> Node3D:
	var root := Node3D.new()
	var s := _r
	# Walls + timber door (slightly proud of the face) + window shutter.
	root.add_child(_box_part(Vector3(0.42, 0.30, 0.36) * s, _plastic(WALL_COL), Vector3(0, 0.15, 0) * s))
	root.add_child(_box_part(Vector3(0.10, 0.17, 0.02) * s, _plastic(TIMBER_COL), Vector3(0.07, 0.085, 0.185) * s))
	root.add_child(_box_part(Vector3(0.09, 0.09, 0.02) * s, _plastic(WINDOW_COL), Vector3(-0.10, 0.19, 0.185) * s))
	# Roof: three silhouettes — steep gable, turned gable, long low saltbox.
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	var rh: float
	match variant % 3:
		0:
			prism.size = Vector3(0.50, 0.22, 0.44) * s
			rh = 0.22
		1:
			prism.size = Vector3(0.44, 0.27, 0.50) * s
			roof.rotation.y = PI * 0.5
			rh = 0.27
		_:
			prism.size = Vector3(0.54, 0.16, 0.46) * s
			rh = 0.16
	roof.mesh = prism
	roof.material_override = _roof_mat(color)   # roof = primary ownership signal
	roof.position = Vector3(0, (0.30 + rh * 0.5) * s, 0)
	root.add_child(roof)
	# Stone chimney poking through one roof slope.
	root.add_child(_box_part(Vector3(0.07, 0.18, 0.07) * s, _plastic(STONE_COL),
		Vector3(-0.13, 0.30 + rh * 0.55, -0.08) * s))
	_add_banner(root, color, (0.30 + rh) * s)
	return root

## City: reads as "upgraded" at a glance — wider two-mass footprint on a
## stone plinth, a second story, a tall tower with a pyramid cap, and more
## window detail. Same part vocabulary as the settlement, bigger volume.
func _make_city(color: Color, variant: int = 0) -> Node3D:
	var root := Node3D.new()
	var s := _r
	# Main hall: stone plinth + plaster upper story.
	root.add_child(_box_part(Vector3(0.62, 0.16, 0.42) * s, _plastic(STONE_COL), Vector3(0, 0.08, 0) * s))
	root.add_child(_box_part(Vector3(0.58, 0.24, 0.38) * s, _plastic(WALL_COL), Vector3(0, 0.28, 0) * s))
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.64, 0.20, 0.44) * s
	roof.mesh = prism
	roof.material_override = _roof_mat(color)   # roof = primary ownership signal
	roof.position = Vector3(-0.04, 0.50, 0) * s
	root.add_child(roof)
	# Door + two hall windows.
	root.add_child(_box_part(Vector3(0.11, 0.18, 0.02) * s, _plastic(TIMBER_COL), Vector3(-0.12, 0.09, 0.215) * s))
	root.add_child(_box_part(Vector3(0.09, 0.09, 0.02) * s, _plastic(WINDOW_COL), Vector3(-0.20, 0.30, 0.20) * s))
	root.add_child(_box_part(Vector3(0.09, 0.09, 0.02) * s, _plastic(WINDOW_COL), Vector3(0.00, 0.30, 0.20) * s))
	# Watchtower mass with a 4-sided pyramid cap.
	root.add_child(_box_part(Vector3(0.24, 0.56, 0.24) * s, _plastic(WALL_COL), Vector3(0.23, 0.28, -0.04) * s))
	var cap := MeshInstance3D.new()
	var pyr := CylinderMesh.new()
	pyr.top_radius = 0.0
	pyr.bottom_radius = 0.19 * s
	pyr.height = 0.18 * s
	pyr.radial_segments = 4
	cap.mesh = pyr
	cap.material_override = _roof_mat(color)
	cap.position = Vector3(0.23, 0.65, -0.04) * s
	cap.rotation.y = PI * 0.25
	root.add_child(cap)
	# Tower window + stone chimney on the hall roof.
	root.add_child(_box_part(Vector3(0.08, 0.10, 0.02) * s, _plastic(WINDOW_COL), Vector3(0.23, 0.44, 0.09) * s))
	root.add_child(_box_part(Vector3(0.07, 0.18, 0.07) * s, _plastic(STONE_COL), Vector3(-0.22, 0.56, -0.09) * s))
	# Banner on the tower peak — highest point, unmistakable from distance.
	var banner_root := Node3D.new()
	banner_root.position = Vector3(0.23 * s, 0, -0.04 * s)
	root.add_child(banner_root)
	_add_banner(banner_root, color, 0.74 * s)
	return root

## Road: neutral timber plank; ownership is an inset team-colour stripe along
## the top (same accent material as the banners, so the language matches).
func _make_road(color: Color, a: Vector3, b: Vector3) -> Node3D:
	var root := Node3D.new()
	var length := maxf(a.distance_to(b) * 0.8, 0.1)
	root.add_child(_box_part(Vector3(_r * 0.16, _r * 0.11, length),
		_plastic(TIMBER_COL), Vector3(0, _r * 0.055, 0)))
	root.add_child(_box_part(Vector3(_r * 0.075, _r * 0.025, length * 0.92),
		_accent(color), Vector3(0, _r * 0.115, 0)))
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
	# Recurse: buildings nest parts (e.g. the city banner) below sub-nodes.
	for child in node.get_children():
		if child is MeshInstance3D:
			var src = child.material_override
			var base_col := Color.WHITE
			if src is StandardMaterial3D:
				base_col = src.albedo_color
			elif src is ShaderMaterial:
				var p = src.get_shader_parameter("base_color")
				if p is Color:
					base_col = p
				elif p is Vector3:
					base_col = Color(p.x, p.y, p.z)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.4)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = base_col.lightened(0.3)
			mat.emission_energy_multiplier = 1.6
			child.material_override = mat
		if child is Node3D:
			_make_ghost(child)
