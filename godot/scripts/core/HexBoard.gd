class_name HexBoard
extends RefCounted

## Geometry + topology for the classic 19-hex Catan board.
##
## Builds, purely from geometry:
##   - 19 hex tiles (axial coords, radius 2)
##   - the shared vertices (settlement/city spots)
##   - the edges (road spots)
##   - hex -> vertex membership (for resource production)
##   - vertex/edge adjacency (for placement rules + longest road)
##   - coastal ports
##
## Pixel positions are computed for pointy-top hexes so the board renders as
## the familiar rows of 3 / 4 / 5 / 4 / 3.

const HEX_SIZE := 64.0          # center-to-corner radius
const MERGE_EPSILON := 6.0      # corners closer than this are the same vertex

# Hex tiles -----------------------------------------------------------------
var hex_axial: Array[Vector2i] = []     # axial (q, r) per hex index
var hex_center: Array[Vector2] = []     # pixel center per hex index
var hex_corners: Array = []             # Array[PackedVector2Array] 6 corners/hex
var hex_vertices: Array = []            # Array[Array[int]] 6 vertex ids per hex

# Vertices ------------------------------------------------------------------
var vertex_pos: Array[Vector2] = []     # pixel position per vertex id
var vertex_neighbors: Array = []        # Array[Array[int]] adjacent vertex ids
var vertex_hexes: Array = []            # Array[Array[int]] hexes touching vertex
var vertex_port: Dictionary = {}        # vertex id -> port type (Res or null)

# Edges ---------------------------------------------------------------------
var edges: Array[Vector2i] = []         # each edge = (vertexA, vertexB), a<b
var edge_lookup: Dictionary = {}        # "a_b" -> edge id

func _init() -> void:
	_build_hexes()
	_build_vertices_and_edges()
	_build_ports()

# --- Hex generation --------------------------------------------------------
func _build_hexes() -> void:
	for q in range(-2, 3):
		for r in range(-2, 3):
			var s := -q - r
			if abs(q) <= 2 and abs(r) <= 2 and abs(s) <= 2:
				hex_axial.append(Vector2i(q, r))
	# Sort top-to-bottom, left-to-right for stable, readable indices.
	hex_axial.sort_custom(func(a, b):
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)

	for axial in hex_axial:
		var center := _axial_to_pixel(axial)
		hex_center.append(center)
		var corners := PackedVector2Array()
		for i in range(6):
			corners.append(_corner(center, i))
		hex_corners.append(corners)

func _axial_to_pixel(axial: Vector2i) -> Vector2:
	var q := float(axial.x)
	var r := float(axial.y)
	var x := HEX_SIZE * (sqrt(3.0) * q + sqrt(3.0) / 2.0 * r)
	var y := HEX_SIZE * (1.5 * r)
	return Vector2(x, y)

func _corner(center: Vector2, i: int) -> Vector2:
	# Pointy-top: corners at 60*i - 30 degrees.
	var angle := deg_to_rad(60.0 * i - 30.0)
	return center + Vector2(cos(angle), sin(angle)) * HEX_SIZE

# --- Vertex + edge generation ---------------------------------------------
func _build_vertices_and_edges() -> void:
	# Merge nearly-identical corner positions into shared vertices.
	var keys: Array = []          # parallel to vertex_pos: rounded key per vertex
	for h in range(hex_corners.size()):
		var corner_ids: Array[int] = []
		for c in hex_corners[h]:
			var vid := _get_or_add_vertex(c, keys)
			corner_ids.append(vid)
		hex_vertices.append(corner_ids)

	# Initialize per-vertex adjacency containers.
	vertex_neighbors.resize(vertex_pos.size())
	vertex_hexes.resize(vertex_pos.size())
	for i in range(vertex_pos.size()):
		vertex_neighbors[i] = []
		vertex_hexes[i] = []

	# Build edges + adjacency from each hex's corner ring.
	for h in range(hex_vertices.size()):
		var ring: Array = hex_vertices[h]
		for i in range(6):
			var a: int = ring[i]
			var b: int = ring[(i + 1) % 6]
			_add_edge(a, b)
			if not vertex_hexes[a].has(h):
				vertex_hexes[a].append(h)

func _get_or_add_vertex(p: Vector2, keys: Array) -> int:
	for i in range(vertex_pos.size()):
		if vertex_pos[i].distance_to(p) <= MERGE_EPSILON:
			return i
	vertex_pos.append(p)
	keys.append(p)
	return vertex_pos.size() - 1

func _add_edge(a: int, b: int) -> void:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var key := "%d_%d" % [lo, hi]
	if edge_lookup.has(key):
		return
	edge_lookup[key] = edges.size()
	edges.append(Vector2i(lo, hi))
	if not vertex_neighbors[a].has(b):
		vertex_neighbors[a].append(b)
	if not vertex_neighbors[b].has(a):
		vertex_neighbors[b].append(a)

func edge_id(a: int, b: int) -> int:
	return edge_lookup.get("%d_%d" % [mini(a, b), maxi(a, b)], -1)

# --- Ports -----------------------------------------------------------------
func _build_ports() -> void:
	# Coastal edges touch exactly one hex. Spread ports evenly around the coast.
	var coastal: Array[int] = []
	for e in range(edges.size()):
		var edge := edges[e]
		var hexes := _hexes_for_edge(edge.x, edge.y)
		if hexes.size() == 1:
			coastal.append(e)
	# Order coastal edges by angle around the board center for even spacing.
	var board_center := _board_center()
	coastal.sort_custom(func(ea, eb):
		var pa := (vertex_pos[edges[ea].x] + vertex_pos[edges[ea].y]) * 0.5
		var pb := (vertex_pos[edges[eb].x] + vertex_pos[edges[eb].y]) * 0.5
		return (pa - board_center).angle() < (pb - board_center).angle())

	if coastal.is_empty():
		return
	var ports := Consts.PORT_BAG.duplicate()
	ports.shuffle()
	var count: int = min(ports.size(), coastal.size())
	# Place ports every ~Nth coastal edge so they don't bunch up.
	var step: int = max(1, int(floor(float(coastal.size()) / float(count))))
	for i in range(count):
		var e: int = coastal[(i * step) % coastal.size()]
		var edge := edges[e]
		vertex_port[edge.x] = ports[i]
		vertex_port[edge.y] = ports[i]

func _hexes_for_edge(a: int, b: int) -> Array:
	var result: Array = []
	for h in range(vertex_hexes[a].size()):
		var hx: int = vertex_hexes[a][h]
		if vertex_hexes[b].has(hx):
			result.append(hx)
	return result

func _board_center() -> Vector2:
	var sum := Vector2.ZERO
	for c in hex_center:
		sum += c
	return sum / float(hex_center.size())

# --- Helpers used by rendering + rules -------------------------------------
func bounds() -> Rect2:
	var r := Rect2(vertex_pos[0], Vector2.ZERO)
	for p in vertex_pos:
		r = r.expand(p)
	return r.grow(HEX_SIZE * 0.6)

func vertex_count() -> int:
	return vertex_pos.size()

func edge_count() -> int:
	return edges.size()

func hex_count() -> int:
	return hex_center.size()
