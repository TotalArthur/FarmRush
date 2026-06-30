import Foundation

/// Heuristic AI that makes reasonable decisions each turn.
class AIPlayer {

    static func takeTurn(state: GameState, playerIndex: Int) async {
        // Small delay for realism
        try? await Task.sleep(nanoseconds: 600_000_000)

        await MainActor.run {
            // 1. Roll dice
            if case .preRoll = state.phase, state.currentPlayerIndex == playerIndex {
                state.rollDice()
            }
        }

        try? await Task.sleep(nanoseconds: 400_000_000)

        await MainActor.run {
            // 2. Handle blight move if needed
            if case .blightMove = state.phase, state.currentPlayerIndex == playerIndex {
                pickBlightMove(state: state, playerIndex: playerIndex)
            }
        }

        try? await Task.sleep(nanoseconds: 400_000_000)

        await MainActor.run {
            guard case .postRoll = state.phase, state.currentPlayerIndex == playerIndex else { return }

            // 3. Play any playable card (prize crops first)
            playBestCard(state: state, playerIndex: playerIndex)

            // 4. Trade if needed
            performTrading(state: state, playerIndex: playerIndex)

            // 5. Build
            performBuilding(state: state, playerIndex: playerIndex)

            // 6. Buy harvest card if can afford
            if state.currentPlayer.canAfford(Player.harvestCardCost) &&
               !state.harvestDeck.isEmpty && state.phase == .postRoll {
                state.buyHarvestCard()
            }

            // 7. End turn
            if case .postRoll = state.phase {
                state.endTurn()
            }
        }
    }

    // MARK: - Blight

    private static func pickBlightMove(state: GameState, playerIndex: Int) {
        let player = state.players[playerIndex]
        let playerVertices = Set(state.board.buildings
            .filter { $0.playerIndex == playerIndex }
            .map { $0.vertex })

        // Pick a tile that doesn't touch my buildings, but touches an opponent's
        var best: TileCoord? = nil
        var bestScore = -1
        var bestVictim: Int? = nil

        for tile in state.board.tiles.values where tile.coord != state.board.blightTile {
            let adjacentBuildings = state.board.buildingsAdjacentTo(tile: tile.coord)
            let myBuildings = adjacentBuildings.filter { $0.playerIndex == playerIndex }.count
            let opponentBuildings = adjacentBuildings.filter { $0.playerIndex != playerIndex }
            let score = opponentBuildings.count - myBuildings * 3
            if score > bestScore {
                bestScore = score
                best = tile.coord
                bestVictim = opponentBuildings.first.map { $0.playerIndex }
            }
        }

        let target = best ?? state.board.tiles.keys.first!
        state.moveBlight(to: target, stealFrom: bestVictim)

        _ = player // suppress unused warning
    }

    // MARK: - Card Play

    private static func playBestCard(state: GameState, playerIndex: Int) {
        let player = state.players[playerIndex]
        let playable = player.harvestCards.filter { state.canPlayCard($0) }
        guard let card = playable.first else { return }

        switch card.type {
        case .prizeCrop:
            return // Prize Crops are VP cards, not actively played

        case .bumperCrop:
            state.playCard(card)
            // Pick most-needed resources
            let needed = mostNeededResources(state: state, playerIndex: playerIndex)
            state.collectBumperCrop(resources: needed)

        case .landGrab:
            state.playCard(card)
            // Will be handled in building phase

        case .scarecrow:
            state.executeScarecrow(target: pickBlightTargetTile(state: state, playerIndex: playerIndex),
                                   stealFrom: pickVictimNearBlight(state: state))

        case .marketCorner:
            let res = mostNeededResources(state: state, playerIndex: playerIndex).first ?? .grain
            state.executeMarketCorner(resource: res)
        }
    }

    private static func pickBlightTargetTile(state: GameState, playerIndex: Int) -> TileCoord {
        let playerVerts = Set(state.board.buildings.filter { $0.playerIndex == playerIndex }.map { $0.vertex })
        return state.board.tiles.values
            .filter { tile in
                state.board.verticesOf(tile: tile.coord).allSatisfy { !playerVerts.contains($0) }
            }
            .max { a, b in
                state.board.buildingsAdjacentTo(tile: a.coord).count <
                state.board.buildingsAdjacentTo(tile: b.coord).count
            }?.coord ?? state.board.tiles.keys.first!
    }

    private static func pickVictimNearBlight(state: GameState) -> Int? {
        state.board.buildingsAdjacentTo(tile: state.board.blightTile).first.map { $0.playerIndex }
    }

    // MARK: - Trading

    private static func mostNeededResources(state: GameState, playerIndex: Int) -> [ResourceType] {
        let player = state.players[playerIndex]
        // Score each resource by how much we need it for building
        return ResourceType.allCases.sorted { a, b in
            player.resource(a) < player.resource(b)
        }
    }

    private static func performTrading(state: GameState, playerIndex: Int) {
        let player = state.players[playerIndex]
        guard state.phase == .postRoll else { return }

        // Determine what we want to build next
        let target = nextBuildTarget(state: state, playerIndex: playerIndex)
        guard let cost = target else { return }

        // Check what we're missing
        for (needed, amount) in cost {
            let have = player.resource(needed)
            if have >= amount { continue }
            let deficit = amount - have

            // Find a resource we have excess of
            for excess in ResourceType.allCases where excess != needed {
                let rate = state.tradeRate(for: playerIndex, resource: excess)
                let excessAmount = player.resource(excess)
                let canTrade = excessAmount / rate
                if canTrade > 0 {
                    let trades = min(canTrade, deficit)
                    for _ in 0..<trades {
                        state.tradeWithSupply(giving: excess, giveCount: rate, receiving: needed)
                    }
                    break
                }
            }
        }
    }

    private static func nextBuildTarget(state: GameState, playerIndex: Int) -> [ResourceType: Int]? {
        let player = state.players[playerIndex]
        let board = state.board

        // Prefer barn if we have a farmstead
        let hasFarmstead = board.buildings.contains { $0.playerIndex == playerIndex && $0.type == .farmstead }
        let barnCount = board.buildings.filter { $0.playerIndex == playerIndex && $0.type == .barn }.count
        let farmsteadCount = board.buildings.filter { $0.playerIndex == playerIndex && $0.type == .farmstead }.count
        let fenceCount = board.fences.filter { $0.playerIndex == playerIndex }.count

        if hasFarmstead && barnCount < Player.maxBarns {
            return Player.barnCost
        }
        if farmsteadCount < Player.maxFarmsteads {
            return Player.farmsteadCost
        }
        if fenceCount < Player.maxFences {
            return Player.fenceCost
        }
        return nil
    }

    // MARK: - Building

    private static func performBuilding(state: GameState, playerIndex: Int) {
        guard state.phase == .postRoll else { return }
        let player = state.players[playerIndex]
        let board = state.board

        // Land Grab fence placement
        if case .playingLandGrab(let remaining) = state.phase, remaining > 0 {
            placeFreeFences(state: state, playerIndex: playerIndex, count: remaining)
            return
        }

        // Try upgrade to barn
        if player.canAfford(Player.barnCost) {
            let upgradeable = board.validBarnUpgrades(for: playerIndex)
            if let vertex = upgradeable.first {
                state.upgradeToBarn(at: vertex)
            }
        }

        guard state.phase == .postRoll else { return }

        // Try build farmstead
        if player.canAfford(Player.farmsteadCost) {
            let options = board.validFarmsteadPlacements(for: playerIndex, setupPhase: false)
            if let best = bestFarmsteadVertex(options: options, board: board) {
                state.buildFarmstead(at: best)
            }
        }

        guard state.phase == .postRoll else { return }

        // Try build fence
        if player.canAfford(Player.fenceCost) {
            let options = board.validFencePlacements(for: playerIndex, setupPhase: false)
            if let edge = bestFenceEdge(options: options, board: board, playerIndex: playerIndex) {
                state.buildFence(on: edge)
            }
        }
    }

    private static func placeFreeFences(state: GameState, playerIndex: Int, count: Int) {
        let board = state.board
        for _ in 0..<count {
            guard case .playingLandGrab(let rem) = state.phase, rem > 0 else { return }
            let options = board.validFencePlacements(for: playerIndex, setupPhase: false)
            if let edge = bestFenceEdge(options: options, board: board, playerIndex: playerIndex) {
                state.placeLandGrabFence(on: edge)
            }
        }
    }

    private static func bestFarmsteadVertex(options: [VertexCoord], board: GameBoard) -> VertexCoord? {
        // Score by number of adjacent producing tiles and value of numbers
        options.max { a, b in
            score(vertex: a, board: board) < score(vertex: b, board: board)
        }
    }

    private static func score(vertex: VertexCoord, board: GameBoard) -> Int {
        board.tilesAdjacentTo(vertex: vertex).reduce(0) { acc, tile in
            guard let token = tile.numberToken, tile.type != .barrenLand else { return acc }
            // Number probability weighting (frequency of 36 rolls)
            let freq = [2:1, 3:2, 4:3, 5:4, 6:5, 8:5, 9:4, 10:3, 11:2, 12:1]
            return acc + (freq[token] ?? 0)
        }
    }

    private static func bestFenceEdge(options: [EdgeCoord], board: GameBoard, playerIndex: Int) -> EdgeCoord? {
        // Prefer edges that expand toward high-value unoccupied vertices
        options.max { a, b in
            fenceScore(edge: a, board: board, playerIndex: playerIndex) <
            fenceScore(edge: b, board: board, playerIndex: playerIndex)
        }
    }

    private static func fenceScore(edge: EdgeCoord, board: GameBoard, playerIndex: Int) -> Int {
        // Score the destination vertex
        let dest = board.buildings.contains { $0.vertex == edge.v2 } ? edge.v1 : edge.v2
        return score(vertex: dest, board: board)
    }
}
