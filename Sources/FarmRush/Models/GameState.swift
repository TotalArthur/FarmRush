import SwiftUI
import Combine

class GameState: ObservableObject {

    // MARK: - State

    @Published var board: GameBoard
    @Published var players: [Player]
    @Published var currentPlayerIndex: Int = 0
    @Published var phase: GamePhase
    @Published var turnNumber: Int = 1
    @Published var lastDiceRoll: (Int, Int)? = nil
    @Published var harvestDeck: [HarvestCard] = []
    @Published var longestFenceHolder: Int? = nil
    @Published var largestFlockHolder: Int? = nil
    @Published var gameLog: [String] = []
    @Published var setupFarmsteadVertex: VertexCoord? = nil

    // Ephemeral UI state for card-playing flows
    @Published var pendingBumperCropSelections: [ResourceType] = []
    @Published var pendingMarketCornerResource: ResourceType? = nil

    // MARK: - Init

    init(board: GameBoard, players: [Player]) {
        self.board = board
        self.players = players
        self.phase = .setup(round: 1, subPhase: .placingFarmstead)
        self.harvestDeck = GameState.buildDeck()
        log("Game started! \(players.map { $0.name }.joined(separator: " vs "))")
    }

    static func buildDeck() -> [HarvestCard] {
        var deck: [HarvestCard] = []
        var turn = 0
        for type in HarvestCardType.allCases {
            for _ in 0..<type.deckCount {
                deck.append(HarvestCard(id: UUID(), type: type, purchasedOnTurn: turn))
            }
        }
        return deck.shuffled()
    }

    // MARK: - Derived

    var currentPlayer: Player { players[currentPlayerIndex] }

    var lastRollTotal: Int? { lastDiceRoll.map { $0.0 + $0.1 } }

    // MARK: - Victory Points

    func victoryPoints(for playerIndex: Int) -> Int {
        let player = players[playerIndex]
        let farmsteads = board.buildings.filter { $0.playerIndex == playerIndex && $0.type == .farmstead }.count
        let barns      = board.buildings.filter { $0.playerIndex == playerIndex && $0.type == .barn }.count
        let prizeCrops = player.harvestCards.filter { $0.type == .prizeCrop }.count

        var vp = farmsteads * 1 + barns * 2 + prizeCrops
        if longestFenceHolder == playerIndex { vp += 2 }
        if largestFlockHolder == playerIndex { vp += 2 }
        return vp
    }

    func checkVictory() -> Int? {
        for i in players.indices {
            if victoryPoints(for: i) >= 10 { return i }
        }
        return nil
    }

    // MARK: - Longest Fence / Largest Flock

    func updateSpecialTokens() {
        // Longest Fence
        var bestChain = longestFenceHolder.map { board.longestFenceChain(for: $0) } ?? 0
        if bestChain < 5 { bestChain = 4 } // min 5 required to hold
        for i in players.indices {
            let chain = board.longestFenceChain(for: i)
            if chain >= 5 && chain > bestChain {
                if longestFenceHolder != i {
                    log("\(players[i].name) takes Longest Fence Line! (\(chain) fences)")
                }
                longestFenceHolder = i
                bestChain = chain
            }
        }

        // Largest Flock
        var bestFlock = largestFlockHolder.map { players[$0].playedScarecrowCount } ?? 0
        if bestFlock < 3 { bestFlock = 2 }
        for i in players.indices {
            let count = players[i].playedScarecrowCount
            if count >= 3 && count > bestFlock {
                if largestFlockHolder != i {
                    log("\(players[i].name) takes Largest Flock! (\(count) scarecrows)")
                }
                largestFlockHolder = i
                bestFlock = count
            }
        }
    }

    // MARK: - Logging

    func log(_ message: String) {
        gameLog.append(message)
        if gameLog.count > 60 { gameLog.removeFirst() }
    }

    // MARK: - Setup Phase

    var isInSetup: Bool {
        if case .setup = phase { return true }
        return false
    }

    var setupRound: Int {
        if case .setup(let round, _) = phase { return round }
        return 0
    }

    // Valid fences adjacent to the last placed farmstead during setup
    func setupFenceOptions() -> [EdgeCoord] {
        guard let vertex = setupFarmsteadVertex else { return [] }
        let existingEdges = Set(board.fences.map { $0.edge })
        return board.edgesOf(vertex: vertex).filter { !existingEdges.contains($0) }
    }

    func placeFarmstead(at vertex: VertexCoord) {
        guard case .setup(let round, let sub) = phase, sub == .placingFarmstead else { return }

        let building = Building(type: .farmstead, playerIndex: currentPlayerIndex, vertex: vertex)
        board.buildings.append(building)
        setupFarmsteadVertex = vertex
        log("\(currentPlayer.name) placed a farmstead")

        if round == 2 {
            // Collect starting resources
            for tile in board.tilesAdjacentTo(vertex: vertex) {
                if let res = tile.type.resource {
                    currentPlayer.gain(res)
                    log("\(currentPlayer.name) collected 1 \(res.displayName)")
                }
            }
        }

        phase = .setup(round: round, subPhase: .placingFence)
    }

    func placeFenceDuringSetup(on edge: EdgeCoord) {
        guard case .setup(let round, let sub) = phase, sub == .placingFence else { return }

        let fence = FenceSegment(playerIndex: currentPlayerIndex, edge: edge)
        board.fences.append(fence)
        setupFarmsteadVertex = nil
        log("\(currentPlayer.name) placed a fence")

        advanceSetup(round: round)
    }

    private func advanceSetup(round: Int) {
        let count = players.count
        if round == 1 {
            if currentPlayerIndex < count - 1 {
                currentPlayerIndex += 1
                phase = .setup(round: 1, subPhase: .placingFarmstead)
            } else {
                // Start snake round 2 (reverse order)
                phase = .setup(round: 2, subPhase: .placingFarmstead)
                // currentPlayerIndex stays at last player
            }
        } else {
            // Round 2, reverse
            if currentPlayerIndex > 0 {
                currentPlayerIndex -= 1
                phase = .setup(round: 2, subPhase: .placingFarmstead)
            } else {
                // Setup done
                currentPlayerIndex = 0
                phase = .preRoll
                log("Setup complete! \(currentPlayer.name) goes first.")
            }
        }
    }

    // MARK: - Dice Roll

    func rollDice() {
        guard case .preRoll = phase else { return }

        let d1 = Int.random(in: 1...6)
        let d2 = Int.random(in: 1...6)
        lastDiceRoll = (d1, d2)
        let total = d1 + d2
        log("\(currentPlayer.name) rolled \(d1) + \(d2) = \(total)")

        if total == 7 {
            handleBlight()
        } else {
            distributeResources(for: total)
            phase = .postRoll
        }
    }

    private func distributeResources(for number: Int) {
        for tile in board.tiles.values where tile.numberToken == number && tile.coord != board.blightTile {
            guard let resource = tile.type.resource else { continue }
            for building in board.buildingsAdjacentTo(tile: tile.coord) {
                let amount = building.type == .barn ? 2 : 1
                players[building.playerIndex].gain(resource, amount: amount)
                log("\(players[building.playerIndex].name) +\(amount) \(resource.displayName)")
            }
        }
    }

    // MARK: - Blight

    private func handleBlight() {
        for player in players where player.totalResources >= 8 {
            let keep = player.totalResources / 2
            discardDownTo(player: player, keep: keep)
        }
        log("Blight strikes! \(currentPlayer.name) moves the blight.")
        phase = .blightMove
    }

    func discardDownTo(player: Player, keep: Int) {
        var total = player.totalResources
        var types = ResourceType.allCases.shuffled()
        var idx = 0
        while total > keep {
            let t = types[idx % types.count]
            if (player.resources[t] ?? 0) > 0 {
                player.resources[t]! -= 1
                total -= 1
                log("\(player.name) discarded 1 \(t.displayName)")
            }
            idx += 1
        }
    }

    func moveBlight(to coord: TileCoord, stealFrom victimIndex: Int?) {
        guard case .blightMove = phase else { return }
        board.blightTile = coord
        log("\(currentPlayer.name) moved the blight to \(board.tiles[coord]?.type.displayName ?? "?")")

        if let victimIdx = victimIndex, victimIdx != currentPlayerIndex {
            stealOneRandom(from: victimIdx, to: currentPlayerIndex)
        }
        phase = .postRoll
    }

    private func stealOneRandom(from victimIndex: Int, to thiefIndex: Int) {
        let victim = players[victimIndex]
        let available = victim.resources.filter { $0.value > 0 }.keys.shuffled()
        guard let stolen = available.first else { return }
        victim.resources[stolen]! -= 1
        players[thiefIndex].gain(stolen)
        log("\(players[thiefIndex].name) stole 1 \(stolen.displayName) from \(victim.name)")
    }

    // MARK: - Building

    func buildFence(on edge: EdgeCoord) {
        guard phase == .postRoll else { return }
        guard currentPlayer.canAfford(Player.fenceCost) else { return }
        let fence = FenceSegment(playerIndex: currentPlayerIndex, edge: edge)
        board.fences.append(fence)
        currentPlayer.spend(Player.fenceCost)
        log("\(currentPlayer.name) built a fence")
        updateSpecialTokens()
        if let winner = checkVictory() { phase = .gameOver(winnerIndex: winner) }
    }

    func buildFarmstead(at vertex: VertexCoord) {
        guard phase == .postRoll else { return }
        guard currentPlayer.canAfford(Player.farmsteadCost) else { return }
        let b = Building(type: .farmstead, playerIndex: currentPlayerIndex, vertex: vertex)
        board.buildings.append(b)
        currentPlayer.spend(Player.farmsteadCost)
        log("\(currentPlayer.name) built a farmstead")
        updateSpecialTokens()
        if let winner = checkVictory() { phase = .gameOver(winnerIndex: winner) }
    }

    func upgradeToBarn(at vertex: VertexCoord) {
        guard phase == .postRoll else { return }
        guard currentPlayer.canAfford(Player.barnCost) else { return }
        guard let idx = board.buildings.firstIndex(where: {
            $0.playerIndex == currentPlayerIndex && $0.vertex == vertex && $0.type == .farmstead
        }) else { return }
        board.buildings[idx] = Building(id: board.buildings[idx].id,
                                         type: .barn,
                                         playerIndex: currentPlayerIndex,
                                         vertex: vertex)
        currentPlayer.spend(Player.barnCost)
        log("\(currentPlayer.name) upgraded a farmstead to a barn!")
        updateSpecialTokens()
        if let winner = checkVictory() { phase = .gameOver(winnerIndex: winner) }
    }

    func buyHarvestCard() {
        guard phase == .postRoll, !harvestDeck.isEmpty else { return }
        guard currentPlayer.canAfford(Player.harvestCardCost) else { return }
        currentPlayer.spend(Player.harvestCardCost)
        var card = harvestDeck.removeFirst()
        // Re-stamp with current turn so "same turn" rule works
        let bought = HarvestCard(id: card.id, type: card.type, purchasedOnTurn: turnNumber)
        card = bought
        currentPlayer.harvestCards.append(bought)
        log("\(currentPlayer.name) bought a Harvest Card")
        if let winner = checkVictory() { phase = .gameOver(winnerIndex: winner) }
    }

    // MARK: - Harvest Card Play

    func canPlayCard(_ card: HarvestCard) -> Bool {
        // Prize Crops are VP cards held in hand, not actively played
        guard card.type != .prizeCrop else { return false }
        guard phase == .postRoll, card.purchasedOnTurn < turnNumber else { return false }
        return currentPlayer.harvestCards.contains(card)
    }

    func playCard(_ card: HarvestCard, scarecrowTarget: TileCoord? = nil, stealTarget: Int? = nil) {
        guard canPlayCard(card) else { return }
        currentPlayer.harvestCards.removeAll { $0.id == card.id }

        switch card.type {
        case .scarecrow:
            currentPlayer.playedScarecrowCount += 1
            updateSpecialTokens()
            if let target = scarecrowTarget {
                board.blightTile = target
                log("\(currentPlayer.name) played Scarecrow, moved blight")
                if let victimIdx = stealTarget {
                    stealOneRandom(from: victimIdx, to: currentPlayerIndex)
                }
            } else {
                phase = .playingScarecrow
                return
            }

        case .bumperCrop:
            log("\(currentPlayer.name) played Bumper Crop!")
            // UI handles picking 2 resources

        case .landGrab:
            log("\(currentPlayer.name) played Land Grab! 2 free fences.")
            phase = .playingLandGrab(fencesRemaining: 2)
            return

        case .marketCorner:
            log("\(currentPlayer.name) played Market Corner!")
            phase = .playingMarketCorner
            return

        case .prizeCrop:
            log("\(currentPlayer.name) played Prize Crop (+1 VP)")
            if let winner = checkVictory() { phase = .gameOver(winnerIndex: winner) }
            return
        }

        if let winner = checkVictory() { phase = .gameOver(winnerIndex: winner) }
    }

    func collectBumperCrop(resources: [ResourceType]) {
        for res in resources.prefix(2) {
            currentPlayer.gain(res)
        }
        log("\(currentPlayer.name) collected from Bumper Crop")
    }

    func executeMarketCorner(resource: ResourceType) {
        var total = 0
        for i in players.indices where i != currentPlayerIndex {
            let amount = players[i].resource(resource)
            if amount > 0 {
                players[i].resources[resource] = 0
                total += amount
            }
        }
        currentPlayer.gain(resource, amount: total)
        log("\(currentPlayer.name) cornered the \(resource.displayName) market! (+\(total))")
        phase = .postRoll
    }

    func placeLandGrabFence(on edge: EdgeCoord) {
        guard case .playingLandGrab(let remaining) = phase, remaining > 0 else { return }
        let fence = FenceSegment(playerIndex: currentPlayerIndex, edge: edge)
        board.fences.append(fence)
        log("\(currentPlayer.name) placed a free fence (Land Grab)")
        updateSpecialTokens()
        if remaining - 1 == 0 {
            phase = .postRoll
        } else {
            phase = .playingLandGrab(fencesRemaining: remaining - 1)
        }
    }

    func executeScarecrow(target: TileCoord, stealFrom victimIndex: Int?) {
        board.blightTile = target
        currentPlayer.playedScarecrowCount += 1
        updateSpecialTokens()
        log("\(currentPlayer.name) played Scarecrow, moved blight")
        if let v = victimIndex { stealOneRandom(from: v, to: currentPlayerIndex) }
        phase = .postRoll
        if let winner = checkVictory() { phase = .gameOver(winnerIndex: winner) }
    }

    // MARK: - Trading

    func tradeWithSupply(giving: ResourceType, giveCount: Int, receiving: ResourceType) {
        guard currentPlayer.resource(giving) >= giveCount else { return }
        currentPlayer.resources[giving]! -= giveCount
        currentPlayer.gain(receiving)
        log("\(currentPlayer.name) traded \(giveCount) \(giving.displayName) for 1 \(receiving.displayName)")
    }

    func tradeRate(for playerIndex: Int, resource: ResourceType) -> Int {
        // Check for adjacent market post
        let playerVertices = Set(board.buildings
            .filter { $0.playerIndex == playerIndex }
            .map { $0.vertex })
        for market in board.marketPosts {
            let marketVertices: Set<VertexCoord> = Set([market.vertex] +
                market.vertex.adjacentVertices(maxCol: board.cols, maxRow: board.rows))
            if !playerVertices.isDisjoint(with: marketVertices) {
                if market.specialResource == resource { return 2 }
                if market.specialResource == nil { return min(3, 4) }
            }
        }
        return 4
    }

    func trade(from givingPlayerIndex: Int, giving: [ResourceType: Int],
               to receivingPlayerIndex: Int, receiving: [ResourceType: Int]) {
        let giver = players[givingPlayerIndex]
        let receiver = players[receivingPlayerIndex]
        guard giver.canAfford(giving) && receiver.canAfford(receiving) else { return }
        giver.spend(giving)
        giver.gain(receiving)
        receiver.spend(receiving)
        receiver.gain(giving)
        let giveStr = giving.map { "\($0.value) \($0.key.displayName)" }.joined(separator: ", ")
        let recStr  = receiving.map { "\($0.value) \($0.key.displayName)" }.joined(separator: ", ")
        log("\(giver.name) traded \(giveStr) ↔ \(recStr) with \(receiver.name)")
    }

    // MARK: - End Turn

    func endTurn() {
        guard case .postRoll = phase else { return }
        log("---")
        turnNumber += 1
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
        phase = .preRoll
    }

    // MARK: - Board size helpers for views

    var boardCols: Int { board.cols }
    var boardRows: Int { board.rows }
}
