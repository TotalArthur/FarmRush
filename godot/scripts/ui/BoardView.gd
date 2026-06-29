class_name BoardView
extends Control

## Draws the hex board and turns clicks into vertex / edge / hex picks.
## Reads the live GameState from the Game autoload; never mutates it.

signal vertex_picked(vertex_id)
signal edge_picked(edge_id)
signal hex_picked(hex_id)

enum PickMode { NONE, SETTLEMENT, CITY, ROAD, ROBBER }

var pick_mode: int = PickMode.NONE
var acting_seat: int = -1        # whose legality we highlight

var _b2s_scale: float = 1.0
var _b2s_offset: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	_time += delta
	if pick_mode != PickMode.NONE:
		queue_redraw()  # animate highlight pulse

func set_mode(mode: int, seat: int) -> void:
	pick_mode = mode
	acting_seat = seat
	queue_redraw()

# --- Coordinate transform --------------------------------------------------
func _recompute_transform() -> void:
	var s := _state()
	if s == null:
		return
	var b := s.board.bounds()
	var avail := size - Vector2(40, 40)
	var sx := avail.x / b.size.x
	var sy := avail.y / b.size.y
	_b2s_scale = min(sx, sy)
	var drawn := b.size * _b2s_scale
	_b2s_offset = (size - drawn) * 0.5 - b.position * _b2s_scale

func _b2s(p: Vector2) -> Vector2:
	return p * _b2s_scale + _b2s_offset

func _s2b(p: Vector2) -> Vector2:
	return (p - _b2s_offset) / _b2s_scale

func _state() -> GameState:
	return Game.state

# --- Drawing ---------------------------------------------------------------
func _draw() -> void:
	var s := _state()
	if s == null or s.board == null:
		return
	_recompute_transform()
	_draw_water_backing(s)
	for h in range(s.board.hex_count()):
		_draw_hex(s, h)
	_draw_ports(s)
	_draw_roads(s)
	_draw_buildings(s)
	_draw_robber(s)
	_draw_highlights(s)

func _draw_water_backing(s: GameState) -> void:
	# Soft rounded "island" behind the hexes for the bubbly board-game look.
	var b := s.board.bounds()
	var rect := Rect2(_b2s(b.position), b.size * _b2s_scale)
	draw_rect(rect.grow(10), Color(0.18, 0.45, 0.68), true)  # deep water rim
	draw_rect(rect.grow(2), Color(0.86, 0.78, 0.55), true)   # sandy shore

func _draw_hex(s: GameState, h: int) -> void:
	var pts := PackedVector2Array()
	for c in s.board.hex_corners[h]:
		pts.append(_b2s(c))
	var res: int = s.hex_res[h]
	var col: Color = Consts.DESERT_COLOR if res == -1 else Consts.RES_COLOR[res]
	# Base fill + a lighter inner glow for a soft, "bubbly" surface.
	draw_colored_polygon(pts, col)
	var inner := _shrink(pts, _b2s(s.board.hex_center[h]), 0.82)
	draw_colored_polygon(inner, col.lightened(0.12))
	# Outline.
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, col.darkened(0.35), 3.0, true)

	# Resource initial, faint, in the tile.
	if res != -1:
		var initial: String = Consts.RES_NAME[res].substr(0, 1)
		var cpix := _b2s(s.board.hex_center[h])
		draw_string(_font, cpix + Vector2(-8, -22), initial,
			HORIZONTAL_ALIGNMENT_CENTER, 16, 16, col.darkened(0.4))

	# Number token.
	if s.hex_token[h] > 0:
		_draw_token(_b2s(s.board.hex_center[h]), s.hex_token[h])

func _draw_token(center: Vector2, number: int) -> void:
	var r := clampf(18.0 * _b2s_scale, 14.0, 22.0)
	draw_circle(center, r + 2.0, Color(0, 0, 0, 0.15))
	draw_circle(center, r, Color(0.97, 0.95, 0.88))
	var hot := number == 6 or number == 8
	var text_col := Color("c0392b") if hot else Color("2c3e50")
	draw_string(_font, center + Vector2(-r, 4), str(number),
		HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.2), text_col)
	# Probability pips.
	var pips: int = Consts.TOKEN_PIPS.get(number, 0)
	var pip_w := 4.0
	var start_x := center.x - (pips - 1) * pip_w * 0.5
	for i in range(pips):
		draw_circle(Vector2(start_x + i * pip_w, center.y + r * 0.7), 1.4, text_col)

func _draw_ports(s: GameState) -> void:
	var drawn := {}
	for v in s.board.vertex_port:
		var key := str(v)
		if drawn.has(key):
			continue
		drawn[key] = true
		var port = s.board.vertex_port[v]
		var pos := _b2s(s.board.vertex_pos[v])
		draw_circle(pos, 9, Color(0.30, 0.55, 0.78))
		draw_circle(pos, 7, Color(0.92, 0.96, 1.0))
		var label: String = "3:1" if port == null else ("2:1 " + Consts.RES_NAME[int(port)].substr(0, 1))
		draw_string(_font, pos + Vector2(-10, -12), label,
			HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color("1b4f72"))

func _draw_roads(s: GameState) -> void:
	for e in s.roads:
		var edge := s.board.edges[e]
		var a := _b2s(s.board.vertex_pos[edge.x])
		var b := _b2s(s.board.vertex_pos[edge.y])
		var col: Color = s.players[s.roads[e]].color
		draw_line(a, b, Color(0, 0, 0, 0.25), 9, true)
		draw_line(a, b, col, 6, true)

func _draw_buildings(s: GameState) -> void:
	for v in s.buildings:
		var b: Dictionary = s.buildings[v]
		var pos := _b2s(s.board.vertex_pos[v])
		var col: Color = s.players[b["owner"]].color
		if b["city"]:
			_draw_city(pos, col)
		else:
			_draw_settlement(pos, col)

func _draw_settlement(pos: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(-8, 8), pos + Vector2(-8, -2),
		pos + Vector2(0, -10), pos + Vector2(8, -2),
		pos + Vector2(8, 8),
	])
	draw_colored_polygon(pts, col)
	var ol := pts.duplicate(); ol.append(pts[0])
	draw_polyline(ol, Color(0, 0, 0, 0.5), 2.0, true)

func _draw_city(pos: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(-11, 10), pos + Vector2(-11, -2),
		pos + Vector2(-3, -2), pos + Vector2(-3, -8),
		pos + Vector2(4, -14), pos + Vector2(11, -8),
		pos + Vector2(11, 10),
	])
	draw_colored_polygon(pts, col)
	var ol := pts.duplicate(); ol.append(pts[0])
	draw_polyline(ol, Color(0, 0, 0, 0.5), 2.0, true)

func _draw_robber(s: GameState) -> void:
	var pos := _b2s(s.board.hex_center[s.robber_hex]) + Vector2(20, -6)
	draw_circle(pos, 13, Color(0.12, 0.12, 0.14))
	draw_circle(pos + Vector2(0, -9), 7, Color(0.12, 0.12, 0.14))

# --- Highlights ------------------------------------------------------------
func _draw_highlights(s: GameState) -> void:
	if pick_mode == PickMode.NONE:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var col := Color(1, 1, 1, 0.35 + 0.35 * pulse)
	match pick_mode:
		PickMode.SETTLEMENT, PickMode.CITY:
			for v in _valid_vertices(s):
				draw_circle(_b2s(s.board.vertex_pos[v]), 11 + 3 * pulse, col)
		PickMode.ROAD:
			for e in _valid_edges(s):
				var edge := s.board.edges[e]
				var a := _b2s(s.board.vertex_pos[edge.x])
				var b := _b2s(s.board.vertex_pos[edge.y])
				draw_line(a, b, col, 8, true)
		PickMode.ROBBER:
			for h in range(s.board.hex_count()):
				if h != s.robber_hex:
					draw_circle(_b2s(s.board.hex_center[h]), 14 + 3 * pulse, Color(1, 0.3, 0.3, 0.3))

func _valid_vertices(s: GameState) -> Array:
	var out: Array = []
	if pick_mode == PickMode.CITY:
		for v in s.buildings:
			if s.buildings[v]["owner"] == acting_seat and not s.buildings[v]["city"]:
				out.append(v)
		return out
	# settlement
	var setup := s.phase == Consts.Phase.SETUP
	for v in range(s.board.vertex_count()):
		if not s._vertex_open_for_settlement(v, setup):
			continue
		if setup or s._vertex_touches_own_road(v, acting_seat):
			out.append(v)
	return out

func _valid_edges(s: GameState) -> Array:
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

# --- Input -----------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var s := _state()
	if s == null or pick_mode == PickMode.NONE:
		return
	var bp := _s2b(event.position)
	match pick_mode:
		PickMode.SETTLEMENT, PickMode.CITY:
			var v := _nearest_vertex(s, bp, 22.0)
			if v != -1 and _valid_vertices(s).has(v):
				vertex_picked.emit(v)
		PickMode.ROAD:
			var e := _nearest_edge(s, bp, 18.0)
			if e != -1 and _valid_edges(s).has(e):
				edge_picked.emit(e)
		PickMode.ROBBER:
			var h := _nearest_hex(s, bp)
			if h != -1 and h != s.robber_hex:
				hex_picked.emit(h)

func _nearest_vertex(s: GameState, bp: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for v in range(s.board.vertex_count()):
		var d := s.board.vertex_pos[v].distance_to(bp)
		if d < best_d:
			best_d = d; best = v
	return best

func _nearest_edge(s: GameState, bp: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for e in range(s.board.edge_count()):
		var edge := s.board.edges[e]
		var mid := (s.board.vertex_pos[edge.x] + s.board.vertex_pos[edge.y]) * 0.5
		var d := mid.distance_to(bp)
		if d < best_d:
			best_d = d; best = e
	return best

func _nearest_hex(s: GameState, bp: Vector2) -> int:
	var best := -1
	var best_d := INF
	for h in range(s.board.hex_count()):
		var d := s.board.hex_center[h].distance_to(bp)
		if d < best_d:
			best_d = d; best = h
	if best_d <= HexBoard.HEX_SIZE:
		return best
	return -1

# --- Geometry helper -------------------------------------------------------
func _shrink(pts: PackedVector2Array, center: Vector2, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(center + (p - center) * factor)
	return out
