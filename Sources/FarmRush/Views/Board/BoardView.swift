import SwiftUI

struct BoardView: View {
    @ObservedObject var state: GameState
    @Binding var buildMode: GameView.BuildMode
    @Binding var scarecrowTarget: TileCoord?

    let onVertexTap: (VertexCoord) -> Void
    let onEdgeTap: (EdgeCoord) -> Void
    let onTileTap: (TileCoord) -> Void

    let tileSize: CGFloat = 66

    var boardPixelWidth:  CGFloat { tileSize * CGFloat(state.boardCols) + tileSize }
    var boardPixelHeight: CGFloat { tileSize * CGFloat(state.boardRows) + tileSize }

    // Valid placement sets (recomputed when needed)
    var validVertices: Set<VertexCoord> {
        switch buildMode {
        case .farmstead:
            let isSetup = state.isInSetup
            return Set(state.board.validFarmsteadPlacements(for: state.currentPlayerIndex,
                                                            setupPhase: isSetup))
        case .barn:
            return Set(state.board.validBarnUpgrades(for: state.currentPlayerIndex))
        default:
            return []
        }
    }

    var validEdges: Set<EdgeCoord> {
        switch buildMode {
        case .fence:
            let isSetup: Bool
            if case .setup(_, let sub) = state.phase, sub == .placingFence { isSetup = true }
            else { isSetup = false }
            if isSetup {
                return Set(state.setupFenceOptions())
            }
            return Set(state.board.validFencePlacements(for: state.currentPlayerIndex,
                                                        setupPhase: false))
        case .landGrab:
            return Set(state.board.validFencePlacements(for: state.currentPlayerIndex,
                                                        setupPhase: false))
        default:
            return []
        }
    }

    var isTileSelectable: Bool {
        state.phase == .blightMove || state.phase == .playingScarecrow
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // 1. Tile layer
                ForEach(Array(state.board.tiles.values)) { tile in
                    TileView(tile: tile,
                             isBlighted: tile.coord == state.board.blightTile,
                             isSelectable: isTileSelectable,
                             tileSize: tileSize)
                    .position(tileCenter(tile.coord))
                    .onTapGesture { onTileTap(tile.coord) }
                }

                // 2. Market posts
                ForEach(state.board.marketPosts) { market in
                    MarketPostView(market: market)
                        .position(vertexPosition(market.vertex))
                }

                // 3. Placed fences
                ForEach(state.board.fences) { fence in
                    FenceView(edge: fence.edge,
                              color: state.players[fence.playerIndex].colorScheme.primary,
                              tileSize: tileSize)
                }

                // 4. Valid fence highlights
                ForEach(Array(validEdges), id: \.self) { edge in
                    EdgeHighlight(edge: edge, tileSize: tileSize)
                        .onTapGesture { onEdgeTap(edge) }
                }

                // 5. Placed buildings
                ForEach(state.board.buildings) { building in
                    BuildingView(building: building,
                                 color: state.players[building.playerIndex].colorScheme.primary)
                    .position(vertexPosition(building.vertex))
                }

                // 6. Valid vertex highlights
                ForEach(Array(validVertices), id: \.self) { vertex in
                    Circle()
                        .fill(Color.yellow.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
                        .position(vertexPosition(vertex))
                        .onTapGesture { onVertexTap(vertex) }
                }

                // 7. Blight marker (if not on a tile since TileView handles it)

                // 8. Setup prompt: show fence options during setup fence phase
                if case .setup(_, let sub) = state.phase, sub == .placingFence {
                    ForEach(state.setupFenceOptions(), id: \.self) { edge in
                        EdgeHighlight(edge: edge, tileSize: tileSize)
                            .onTapGesture { onEdgeTap(edge) }
                    }
                }

                // 9. Setup farmstead placement hints
                if case .setup(_, let sub) = state.phase, sub == .placingFarmstead {
                    let options = state.board.validFarmsteadPlacements(for: state.currentPlayerIndex,
                                                                       setupPhase: true)
                    ForEach(options, id: \.self) { vertex in
                        Circle()
                            .fill(state.currentPlayer.colorScheme.primary.opacity(0.4))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(state.currentPlayer.colorScheme.primary, lineWidth: 2))
                            .position(vertexPosition(vertex))
                            .onTapGesture { onVertexTap(vertex) }
                    }
                }
            }
            .frame(width: boardPixelWidth, height: boardPixelHeight)
            .padding(tileSize / 2)
        }
        .background(Color(red: 0.55, green: 0.72, blue: 0.40).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(8)
    }

    func tileCenter(_ coord: TileCoord) -> CGPoint {
        CGPoint(
            x: CGFloat(coord.col) * tileSize + tileSize / 2 + tileSize / 2,
            y: CGFloat(coord.row) * tileSize + tileSize / 2 + tileSize / 2
        )
    }

    func vertexPosition(_ coord: VertexCoord) -> CGPoint {
        CGPoint(
            x: CGFloat(coord.col) * tileSize + tileSize / 2,
            y: CGFloat(coord.row) * tileSize + tileSize / 2
        )
    }
}

// MARK: - Fence View

struct FenceView: View {
    let edge: EdgeCoord
    let color: Color
    let tileSize: CGFloat

    var body: some View {
        let mid = edgeMidpoint(edge, tileSize: tileSize)
        let isH = edge.isHorizontal

        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: isH ? tileSize * 0.85 : 6,
                   height: isH ? 6 : tileSize * 0.85)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
            }
            .position(mid)
    }
}

struct EdgeHighlight: View {
    let edge: EdgeCoord
    let tileSize: CGFloat

    var body: some View {
        let mid = edgeMidpoint(edge, tileSize: tileSize)
        let isH = edge.isHorizontal

        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow.opacity(0.35))
            .frame(width: isH ? tileSize * 0.8 : 12,
                   height: isH ? 12 : tileSize * 0.8)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.yellow, lineWidth: 1.5)
            }
            .position(mid)
    }
}

private func edgeMidpoint(_ edge: EdgeCoord, tileSize: CGFloat) -> CGPoint {
    let x = (CGFloat(edge.v1.col) + CGFloat(edge.v2.col)) / 2.0 * tileSize + tileSize / 2
    let y = (CGFloat(edge.v1.row) + CGFloat(edge.v2.row)) / 2.0 * tileSize + tileSize / 2
    return CGPoint(x: x, y: y)
}

// MARK: - Building View

struct BuildingView: View {
    let building: Building
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            Image(systemName: building.type == .farmstead ? "house.fill" : "building.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Market Post View

struct MarketPostView: View {
    let market: MarketPost

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.85, green: 0.70, blue: 0.20))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .shadow(radius: 2)

            Text(market.specialResource?.emoji ?? "🏪")
                .font(.system(size: 10))
        }
    }
}
