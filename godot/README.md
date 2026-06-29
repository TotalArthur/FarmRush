# FarmRush 🌾

A cozy, **Catan-style** hex board game built in **Godot 4** — designed to ship
to **Steam** (Windows / macOS / Linux). Same core logic and gameplay as
*The Settlers of Catan* / *colonist.io*, rendered as a vibrant, chunky **3D
digital tabletop** (Pummel Party / Mario Party vibe).

![board](docs/preview.png)

## 3D tabletop view

The board is a 3D scene (`Game3DWorld`) and is the **default** in-game view:

- **Chunky hex prisms** generated from the engine's axial coordinates, with the
  ocean sitting lower than the land tops.
- **Juicy feedback**: hexes lift on hover (Tween), settlements/roads/cities
  *pop in* with an elastic overshoot, and a translucent glowing **hologram**
  previews your placement under the cursor.
- **Floating number tokens** that bob and slowly spin above each tile.
- **3D physics dice** (`scripts/dice/`) that can be physically thrown and read
  by their resting top face.

Camera (`CameraRig3D`): isometric ~55° tabletop view, **WASD / arrows** or
**edge-scroll** to pan (clamped to the board), **scroll wheel** to zoom, and
**middle-mouse drag** to orbit.

> The 2D board is still available — launch with `FARMRUSH_2D=1` to use it.

### Renderer note (for the full toy look)

The project ships on **gl_compatibility** so it runs everywhere. For the premium
look — **SSAO**, **glow/bloom**, and **depth of field** — switch
`Project → Project Settings → Rendering → Renderer → Rendering Method` to
**Forward+**. Those effects are enabled automatically when a Vulkan
`RenderingDevice` is present (see `Game3DWorld._setup_environment` /
`CameraRig3D`); soft directional shadows and the bright sky/ambient work on both
renderers.

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
├── scenes/
│   ├── Main.tscn              # root; swaps Menu / Lobby / Game screens
│   └── Game3D.tscn            # 3D tabletop world (Game3DWorld)
├── scripts/
│   ├── core/
│   │   ├── Consts.gd          # rules constants, resources, costs, colors
│   │   ├── HexBoard.gd        # board geometry: hexes, vertices, edges, ports
│   │   ├── Player.gd          # per-player state (serializable)
│   │   ├── GameState.gd       # authoritative headless rules engine
│   │   └── GameManager.gd     # autoload "Game": modes, action routing, AI/sync
│   ├── ai/AIBot.gd            # heuristic opponent
│   ├── net/NetworkManager.gd  # autoload "Net": host/join + lobby
│   ├── dice/                  # Dice3D + DiceManager (3D physics dice)
│   └── ui/
│       ├── Main.gd            # screen router (3D by default)
│       ├── MainMenu.gd, Lobby.gd
│       ├── GameScreen.gd      # HUD, dialogs, interaction (2D + 3D)
│       ├── BoardView.gd       # 2D board rendering + click picking
│       ├── BoardView3D.gd     # 3D board: prisms, hover/pop animation, tokens
│       ├── CameraRig3D.gd     # isometric pan/zoom/orbit camera
│       └── Game3DWorld.gd     # assembles env + light + camera + board + HUD
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
