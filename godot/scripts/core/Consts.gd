class_name Consts
extends RefCounted

## Central place for game rules constants, resource definitions and colors.
## Pure data — no node dependencies — so it can be used by the engine and the AI.

# --- Resources -------------------------------------------------------------
enum Res { WOOD, BRICK, SHEEP, WHEAT, ORE }

const RES_ALL := [Res.WOOD, Res.BRICK, Res.SHEEP, Res.WHEAT, Res.ORE]

const RES_NAME := {
	Res.WOOD: "Wood",
	Res.BRICK: "Brick",
	Res.SHEEP: "Sheep",
	Res.WHEAT: "Wheat",
	Res.ORE: "Ore",
}

# Warm, "bubbly board game" palette for each resource tile.
const RES_COLOR := {
	Res.WOOD: Color("4e9b54"),   # forest green
	Res.BRICK: Color("d8693b"),  # terracotta
	Res.SHEEP: Color("9bd16b"),  # pasture lime
	Res.WHEAT: Color("f1c44b"),  # golden field
	Res.ORE: Color("9aa4ad"),    # stone grey
}

# Emoji glyphs used for quick, friendly tile / card art (no external assets).
const RES_GLYPH := {
	Res.WOOD: "🌲",
	Res.BRICK: "🧱",
	Res.SHEEP: "🐑",
	Res.WHEAT: "🌾",
	Res.ORE: "⛰️",
}

const DESERT_COLOR := Color("e4d9a8")

# --- Standard Catan tile + token distribution (19 hexes) -------------------
# 4 wood, 3 brick, 4 sheep, 4 wheat, 3 ore, 1 desert.
const TILE_BAG := [
	Res.WOOD, Res.WOOD, Res.WOOD, Res.WOOD,
	Res.BRICK, Res.BRICK, Res.BRICK,
	Res.SHEEP, Res.SHEEP, Res.SHEEP, Res.SHEEP,
	Res.WHEAT, Res.WHEAT, Res.WHEAT, Res.WHEAT,
	Res.ORE, Res.ORE, Res.ORE,
]
# 18 number tokens for the 18 producing tiles (no 7).
const TOKEN_BAG := [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]

# Pips (dots) under each number — higher = more likely.
const TOKEN_PIPS := {
	2: 1, 3: 2, 4: 3, 5: 4, 6: 5,
	8: 5, 9: 4, 10: 3, 11: 2, 12: 1,
}

# --- Build costs -----------------------------------------------------------
const COST_ROAD := { Res.WOOD: 1, Res.BRICK: 1 }
const COST_SETTLEMENT := { Res.WOOD: 1, Res.BRICK: 1, Res.SHEEP: 1, Res.WHEAT: 1 }
const COST_CITY := { Res.ORE: 3, Res.WHEAT: 2 }
const COST_DEV := { Res.ORE: 1, Res.SHEEP: 1, Res.WHEAT: 1 }

# --- Piece limits per player ----------------------------------------------
const MAX_ROADS := 15
const MAX_SETTLEMENTS := 5
const MAX_CITIES := 4

# --- Victory / bonuses -----------------------------------------------------
const WIN_POINTS := 10
const LONGEST_ROAD_MIN := 5      # need this many road segments to earn the bonus
const LARGEST_ARMY_MIN := 3      # knights played to earn the bonus

# --- Development cards -----------------------------------------------------
enum Dev { KNIGHT, VICTORY_POINT, ROAD_BUILDING, YEAR_OF_PLENTY, MONOPOLY }

const DEV_NAME := {
	Dev.KNIGHT: "Knight",
	Dev.VICTORY_POINT: "Victory Point",
	Dev.ROAD_BUILDING: "Road Building",
	Dev.YEAR_OF_PLENTY: "Year of Plenty",
	Dev.MONOPOLY: "Monopoly",
}

# Standard 25-card development deck.
const DEV_BAG := [
	Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT,
	Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT,
	Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT, Dev.KNIGHT,
	Dev.VICTORY_POINT, Dev.VICTORY_POINT, Dev.VICTORY_POINT,
	Dev.VICTORY_POINT, Dev.VICTORY_POINT,
	Dev.ROAD_BUILDING, Dev.ROAD_BUILDING,
	Dev.YEAR_OF_PLENTY, Dev.YEAR_OF_PLENTY,
	Dev.MONOPOLY, Dev.MONOPOLY,
]

# --- Ports -----------------------------------------------------------------
# null == generic 3:1 port; a Res value == 2:1 port for that resource.
const PORT_BAG := [
	null, null, null, null,
	Res.WOOD, Res.BRICK, Res.SHEEP, Res.WHEAT, Res.ORE,
]

# --- Player colors (bubbly, distinct) -------------------------------------
const PLAYER_COLORS := [
	Color("e6443b"), # red
	Color("3a7bd5"), # blue
	Color("f29f1f"), # orange
	Color("ffffff"), # white
	Color("7b4ea3"), # purple (for up to 6 players)
	Color("2fb38a"), # teal
]

# --- Turn / game phases ----------------------------------------------------
enum Phase {
	LOBBY,            # not started
	SETUP,            # initial placement (snake order)
	ROLL,             # current player must roll the dice
	DISCARD,          # players over 7 cards must discard after a 7
	MOVE_ROBBER,      # current player moves the robber + steals
	MAIN,             # build / trade / play cards freely
	GAME_OVER,
}

static func dict_empty_res() -> Dictionary:
	return { Res.WOOD: 0, Res.BRICK: 0, Res.SHEEP: 0, Res.WHEAT: 0, Res.ORE: 0 }
