class_name Player
extends RefCounted

## Per-player state. Plain data so it serializes easily for networking/AI.

var id: int = 0                 # 0-based seat index
var name: String = "Player"
var color: Color = Color.WHITE
var is_ai: bool = false
var net_peer_id: int = 0        # multiplayer peer id (0 = local/AI)

var resources: Dictionary = Consts.dict_empty_res()
var dev_cards: Dictionary = {}          # Dev -> count (in hand, usable next turn)
var dev_bought_this_turn: Dictionary = {}  # Dev -> count bought this turn
var played_knights: int = 0

# Pieces remaining in the supply.
var roads_left: int = Consts.MAX_ROADS
var settlements_left: int = Consts.MAX_SETTLEMENTS
var cities_left: int = Consts.MAX_CITIES

# Bonus flags (maintained by GameState).
var has_longest_road: bool = false
var has_largest_army: bool = false

func total_resources() -> int:
	var n := 0
	for k in resources:
		n += resources[k]
	return n

func add_res(res: int, amount: int = 1) -> void:
	resources[res] = resources.get(res, 0) + amount

func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if resources.get(res, 0) < cost[res]:
			return false
	return true

func pay(cost: Dictionary) -> void:
	for res in cost:
		resources[res] -= cost[res]

func dev_card_count() -> int:
	var n := 0
	for k in dev_cards:
		n += dev_cards[k]
	return n

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"color": color.to_html(),
		"is_ai": is_ai,
		"net_peer_id": net_peer_id,
		"resources": resources.duplicate(),
		"dev_cards": dev_cards.duplicate(),
		"dev_bought_this_turn": dev_bought_this_turn.duplicate(),
		"played_knights": played_knights,
		"roads_left": roads_left,
		"settlements_left": settlements_left,
		"cities_left": cities_left,
		"has_longest_road": has_longest_road,
		"has_largest_army": has_largest_army,
	}

static func from_dict(d: Dictionary) -> Player:
	var p := Player.new()
	p.id = int(d["id"])
	p.name = str(d["name"])
	p.color = Color(d["color"])
	p.is_ai = bool(d["is_ai"])
	p.net_peer_id = int(d["net_peer_id"])
	p.resources = _int_pairs(d["resources"])
	p.dev_cards = _int_pairs(d["dev_cards"])
	p.dev_bought_this_turn = _int_pairs(d["dev_bought_this_turn"])
	p.played_knights = int(d["played_knights"])
	p.roads_left = int(d["roads_left"])
	p.settlements_left = int(d["settlements_left"])
	p.cities_left = int(d["cities_left"])
	p.has_longest_road = bool(d["has_longest_road"])
	p.has_largest_army = bool(d["has_largest_army"])
	return p

# JSON turns int dict keys into strings and counts into floats; restore ints.
static func _int_pairs(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = int(d[k])
	return out
