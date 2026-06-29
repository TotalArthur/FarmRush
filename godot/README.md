# FarmRush 🌾

A cozy, **Catan-style** hex board game built in **Godot 4** — designed to ship
to **Steam** (Windows / macOS / Linux). Same core logic and gameplay as
*The Settlers of Catan* / *colonist.io*, with soft, bubbly board-game-on-PC
visuals.

![board](docs/preview.png)

## Game modes

- **Single Player** — play against 1–5 heuristic AI opponents.
- **Local Hotseat** — 2–6 humans, pass-and-play on one screen.
- **Online Multiplayer** — host/join over the network (Godot high-level
  multiplayer / ENet). The host is authoritative and syncs game state to all
  clients.

## How to play

Classic Catan rules:

1. **Setup** — in snake order, each player places 2 settlements + 2 roads.
   Your second settlement grants starting resources.
2. **Roll** the dice each turn. Tiles matching the roll produce resources to
   adjacent settlements (×1) and cities (×2). Rolling a **7** triggers the
   robber: anyone holding 8+ cards discards half, then the roller moves the
   robber and steals a card.
3. **Build & trade** — spend resources to build:
   - Road: 🌲 + 🧱
   - Settlement: 🌲 + 🧱 + 🐑 + 🌾 (1 VP)
   - City (upgrade): 3 ⛰️ + 2 🌾 (2 VP)
   - Development card: ⛰️ + 🐑 + 🌾
   Trade with the bank at 4:1, or 3:1 / 2:1 if you sit on a port.
4. **Win** at **10 victory points** (settlements, cities, hidden VP cards,
   +2 for Longest Road ≥5, +2 for Largest Army ≥3 knights).

Development cards: Knight, Victory Point, Road Building, Year of Plenty,
Monopoly.

## Running it

1. Install [Godot 4.2+](https://godotengine.org/download) (standard, GDScript).
2. Open this `godot/` folder as a project and press **▶ Play**.

### Export for Steam

`Project → Export…` and add Windows / macOS / Linux presets. For Steam
achievements / friends, add the [GodotSteam](https://godotsteam.com/) addon and
wire it into a thin layer over `NetworkManager`. The game already uses Godot's
built-in multiplayer for online play, so no extra backend is required for
peer-hosted matches.

## Project layout

```
godot/
├── project.godot              # autoloads: Net (networking), Game (match manager)
├── scenes/Main.tscn           # root; swaps Menu / Lobby / Game screens
├── scripts/
│   ├── core/
│   │   ├── Consts.gd          # rules constants, resources, costs, colors
│   │   ├── HexBoard.gd        # board geometry: hexes, vertices, edges, ports
│   │   ├── Player.gd          # per-player state (serializable)
│   │   ├── GameState.gd       # authoritative headless rules engine
│   │   └── GameManager.gd     # autoload "Game": modes, action routing, AI/sync
│   ├── ai/AIBot.gd            # heuristic opponent
│   ├── net/NetworkManager.gd  # autoload "Net": host/join + lobby
│   └── ui/
│       ├── Main.gd            # screen router
│       ├── MainMenu.gd, Lobby.gd
│       ├── GameScreen.gd      # HUD, dialogs, interaction
│       └── BoardView.gd       # bubbly board rendering + click picking
└── tests/
    ├── sim.gd                 # headless AI-vs-AI full-game self-test
    └── screenshot.gd          # render a frame to PNG
```

The rules engine (`GameState`) is fully **headless and deterministic-friendly**,
so the same code drives local play, the AI, and the networked host.

## Testing

```bash
# Full AI-vs-AI games + JSON state round-trip (no display needed)
godot --headless --script res://tests/sim.gd
```

Dev hooks (env vars): `FARMRUSH_AUTOSTART=1` boots straight into a vs-AI game;
`FARMRUSH_SCREENSHOT=1` saves `tests/board_preview.png` and quits.
