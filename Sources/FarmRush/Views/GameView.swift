import SwiftUI

struct GameView: View {
    let config: GameConfig

    @StateObject private var state: GameState
    @State private var showTrade = false
    @State private var showCards = false
    @State private var showLog = false
    @State private var buildMode: BuildMode = .none
    @State private var scarecrowTarget: TileCoord? = nil
    @State private var bumperSelections: [ResourceType] = []
    @State private var showBumperSheet = false
    @State private var marketCornerResource: ResourceType? = nil
    @State private var showMarketCornerSheet = false
    @Environment(\.dismiss) private var dismiss

    enum BuildMode { case none, fence, farmstead, barn, landGrab }

    init(config: GameConfig) {
        self.config = config
        _state = StateObject(wrappedValue: GameState(board: config.board, players: config.players))
    }

    var body: some View {
        ZStack {
            // Seasonal background
            seasonBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: current player + scores
                TopBarView(state: state)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                // Phase prompt
                PhasePromptView(state: state, buildMode: buildMode)
                    .padding(.top, 4)

                // Game board
                BoardView(
                    state: state,
                    buildMode: $buildMode,
                    scarecrowTarget: $scarecrowTarget,
                    onVertexTap: handleVertexTap,
                    onEdgeTap: handleEdgeTap,
                    onTileTap: handleTileTap
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom panel
                BottomPanelView(
                    state: state,
                    buildMode: $buildMode,
                    showTrade: $showTrade,
                    showCards: $showCards,
                    showLog: $showLog,
                    onRoll: { state.rollDice() },
                    onEndTurn: { state.endTurn(); triggerBotTurnIfNeeded() }
                )
                .padding(.bottom, 4)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Label("Menu", systemImage: "house.fill")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showTrade) {
            TradeView(state: state)
        }
        .sheet(isPresented: $showCards) {
            HarvestCardView(state: state, onPlay: handleCardPlay)
        }
        .sheet(isPresented: $showLog) {
            GameLogView(log: state.gameLog)
        }
        .sheet(isPresented: $showBumperSheet) {
            BumperCropSheet(state: state) { selections in
                state.collectBumperCrop(resources: selections)
                showBumperSheet = false
            }
        }
        .sheet(isPresented: $showMarketCornerSheet) {
            MarketCornerSheet { res in
                state.executeMarketCorner(resource: res)
                showMarketCornerSheet = false
            }
        }
        .overlay {
            if case .gameOver(let winnerIdx) = state.phase {
                GameOverView(winner: state.players[winnerIdx],
                             scores: (0..<state.players.count).map {
                                 (state.players[$0].name, state.victoryPoints(for: $0))
                             }) {
                    dismiss()
                }
            }
        }
        .onChange(of: state.phase) { _, newPhase in
            if case .gameOver = newPhase { return }
            triggerBotTurnIfNeeded()
        }
        .onAppear {
            // Trigger bot if bot goes first in setup
            triggerBotTurnIfNeeded()
        }
    }

    // MARK: - Background

    var seasonBackground: LinearGradient {
        let t = Double(state.turnNumber % 40) / 40.0
        let spring = [Color(red: 0.60, green: 0.82, blue: 0.45), Color(red: 0.40, green: 0.62, blue: 0.28)]
        let summer = [Color(red: 0.72, green: 0.85, blue: 0.38), Color(red: 0.55, green: 0.70, blue: 0.22)]
        let autumn = [Color(red: 0.82, green: 0.62, blue: 0.28), Color(red: 0.68, green: 0.45, blue: 0.15)]
        let winter = [Color(red: 0.72, green: 0.78, blue: 0.80), Color(red: 0.55, green: 0.60, blue: 0.62)]
        let seasons = [spring, summer, autumn, winter]
        let seasonIdx = Int(t * 4) % 4
        let colors = seasons[seasonIdx]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Bot Turn

    func triggerBotTurnIfNeeded() {
        let player = state.currentPlayer
        guard player.isBot else { return }

        // Handle bot during setup
        if case .setup(_, _) = state.phase {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run { performBotSetupMove() }
            }
            return
        }

        guard state.phase == .preRoll || state.phase == .blightMove else { return }
        Task {
            await AIPlayer.takeTurn(state: state, playerIndex: player.playerIndex)
            await MainActor.run { triggerBotTurnIfNeeded() }
        }
    }

    func performBotSetupMove() {
        guard state.currentPlayer.isBot else { return }
        if case .setup(let round, let sub) = state.phase {
            switch sub {
            case .placingFarmstead:
                let options = state.board.validFarmsteadPlacements(
                    for: state.currentPlayerIndex, setupPhase: true)
                if let best = options.max(by: { a, b in
                    state.board.tilesAdjacentTo(vertex: a).count <
                    state.board.tilesAdjacentTo(vertex: b).count
                }) {
                    state.placeFarmstead(at: best)
                    triggerBotTurnIfNeeded()
                }
            case .placingFence:
                let options = state.setupFenceOptions()
                if let edge = options.first {
                    state.placeFenceDuringSetup(on: edge)
                    triggerBotTurnIfNeeded()
                }
            }
            _ = round
        }
    }

    // MARK: - Interaction Handlers

    func handleVertexTap(_ vertex: VertexCoord) {
        switch buildMode {
        case .farmstead:
            if state.board.validFarmsteadPlacements(for: state.currentPlayerIndex,
                                                    setupPhase: state.isInSetup).contains(vertex) {
                if state.isInSetup {
                    state.placeFarmstead(at: vertex)
                } else {
                    state.buildFarmstead(at: vertex)
                }
                buildMode = .none
            }
        case .barn:
            if state.board.validBarnUpgrades(for: state.currentPlayerIndex).contains(vertex) {
                state.upgradeToBarn(at: vertex)
                buildMode = .none
            }
        default:
            break
        }
    }

    func handleEdgeTap(_ edge: EdgeCoord) {
        switch buildMode {
        case .fence:
            let isSetup: Bool
            if case .setup(_, let sub) = state.phase, sub == .placingFence { isSetup = true }
            else { isSetup = false }

            if isSetup {
                let options = state.setupFenceOptions()
                if options.contains(edge) {
                    state.placeFenceDuringSetup(on: edge)
                    buildMode = .none
                    triggerBotTurnIfNeeded()
                }
            } else {
                state.buildFence(on: edge)
                buildMode = .none
            }
        case .landGrab:
            state.placeLandGrabFence(on: edge)
            if case .postRoll = state.phase { buildMode = .none }
        default:
            break
        }
    }

    func handleTileTap(_ coord: TileCoord) {
        if case .blightMove = state.phase {
            let victim = state.board.buildingsAdjacentTo(tile: coord)
                .first(where: { $0.playerIndex != state.currentPlayerIndex })
                .map { $0.playerIndex }
            state.moveBlight(to: coord, stealFrom: victim)
        } else if case .playingScarecrow = state.phase {
            let victim = state.board.buildingsAdjacentTo(tile: coord)
                .first(where: { $0.playerIndex != state.currentPlayerIndex })
                .map { $0.playerIndex }
            state.executeScarecrow(target: coord, stealFrom: victim)
        }
    }

    func handleCardPlay(_ card: HarvestCard) {
        showCards = false
        switch card.type {
        case .bumperCrop:
            state.playCard(card)
            showBumperSheet = true
        case .marketCorner:
            state.playCard(card)
            showMarketCornerSheet = true
        case .landGrab:
            state.playCard(card)
            buildMode = .landGrab
        case .scarecrow:
            state.playCard(card)
            // Phase changes to .playingScarecrow, handled by tile tap
        case .prizeCrop:
            state.playCard(card)
        }
    }
}

// MARK: - Top Bar

struct TopBarView: View {
    @ObservedObject var state: GameState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(state.players.indices, id: \.self) { i in
                let player = state.players[i]
                let vp = state.victoryPoints(for: i)
                let isCurrent = state.currentPlayerIndex == i

                VStack(spacing: 2) {
                    Text(player.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("\(vp) VP")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent
                              ? player.colorScheme.primary
                              : player.colorScheme.primary.opacity(0.3))
                        .overlay {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
                            }
                        }
                }
                .scaleEffect(isCurrent ? 1.05 : 1.0)
                .animation(.spring(response: 0.3), value: isCurrent)

                if i < state.players.count - 1 { Spacer() }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Bottom Panel

struct BottomPanelView: View {
    @ObservedObject var state: GameState
    @Binding var buildMode: GameView.BuildMode
    @Binding var showTrade: Bool
    @Binding var showCards: Bool
    @Binding var showLog: Bool
    let onRoll: () -> Void
    let onEndTurn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Resource strip
            ResourceStripView(player: state.currentPlayer)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.9))

            Divider().opacity(0.3)

            // Action bar
            HStack(spacing: 0) {
                // Dice / roll
                DiceButton(state: state, onRoll: onRoll)

                Divider().frame(height: 36).opacity(0.3)

                // Build buttons
                BuildButtons(state: state, buildMode: $buildMode)

                Divider().frame(height: 36).opacity(0.3)

                // Trade / Cards / Log / End Turn
                ActionButtons(state: state,
                              showTrade: $showTrade,
                              showCards: $showCards,
                              showLog: $showLog,
                              onEndTurn: onEndTurn)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Resource Strip

struct ResourceStripView: View {
    @ObservedObject var player: Player

    var body: some View {
        HStack(spacing: 4) {
            Text(player.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 80, alignment: .leading)

            Spacer()

            ForEach(ResourceType.allCases) { res in
                HStack(spacing: 2) {
                    Text(res.emoji)
                        .font(.system(size: 14))
                    Text("\(player.resource(res))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(player.resource(res) > 0 ? .primary : .secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(player.resource(res) > 0
                              ? res.tintColor.opacity(0.25)
                              : Color.gray.opacity(0.08))
                }
            }
        }
    }
}

// MARK: - Dice Button

struct DiceButton: View {
    @ObservedObject var state: GameState
    let onRoll: () -> Void
    @State private var rolling = false

    var body: some View {
        VStack(spacing: 2) {
            if let (d1, d2) = state.lastDiceRoll {
                HStack(spacing: 4) {
                    DiceFaceView(value: d1)
                    DiceFaceView(value: d2)
                }
                Text("\(d1 + d2)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Button(action: {
                    guard state.phase == .preRoll,
                          !state.currentPlayer.isBot else { return }
                    rolling = true
                    onRoll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { rolling = false }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "dice.fill")
                            .font(.title2)
                            .rotationEffect(.degrees(rolling ? 360 : 0))
                            .animation(.linear(duration: 0.4), value: rolling)
                        Text("Roll")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(state.phase == .preRoll && !state.currentPlayer.isBot
                                     ? .primary : .secondary)
                }
                .disabled(state.phase != .preRoll || state.currentPlayer.isBot)
            }
        }
        .frame(width: 72)
    }
}

struct DiceFaceView: View {
    let value: Int
    var body: some View {
        Text(diceFace(value))
            .font(.system(size: 22))
    }
    func diceFace(_ v: Int) -> String {
        ["⚀","⚁","⚂","⚃","⚄","⚅"][max(0, min(5, v - 1))]
    }
}

// MARK: - Build Buttons

struct BuildButtons: View {
    @ObservedObject var state: GameState
    @Binding var buildMode: GameView.BuildMode

    var body: some View {
        HStack(spacing: 2) {
            BuildBtn(label: "Fence", icon: "minus.square.fill",
                     cost: Player.fenceCost, player: state.currentPlayer,
                     active: buildMode == .fence,
                     enabled: state.phase == .postRoll && !state.currentPlayer.isBot) {
                buildMode = buildMode == .fence ? .none : .fence
            }
            BuildBtn(label: "Farm", icon: "house.fill",
                     cost: Player.farmsteadCost, player: state.currentPlayer,
                     active: buildMode == .farmstead,
                     enabled: state.phase == .postRoll && !state.currentPlayer.isBot) {
                buildMode = buildMode == .farmstead ? .none : .farmstead
            }
            BuildBtn(label: "Barn", icon: "building.2.fill",
                     cost: Player.barnCost, player: state.currentPlayer,
                     active: buildMode == .barn,
                     enabled: state.phase == .postRoll && !state.currentPlayer.isBot &&
                              !state.board.validBarnUpgrades(for: state.currentPlayerIndex).isEmpty) {
                buildMode = buildMode == .barn ? .none : .barn
            }
        }
        .padding(.horizontal, 8)
    }
}

struct BuildBtn: View {
    let label: String
    let icon: String
    let cost: [ResourceType: Int]
    let player: Player
    let active: Bool
    let enabled: Bool
    let action: () -> Void

    var canAfford: Bool { player.canAfford(cost) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(active ? .white : (canAfford && enabled ? .primary : .secondary))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(active ? .white : (canAfford && enabled ? .primary : .secondary))
            }
            .frame(width: 56, height: 44)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.accentColor : (canAfford && enabled
                          ? Color.primary.opacity(0.08) : Color.clear))
            }
        }
        .disabled(!enabled || !canAfford)
    }
}

// MARK: - Action Buttons

struct ActionButtons: View {
    @ObservedObject var state: GameState
    @Binding var showTrade: Bool
    @Binding var showCards: Bool
    @Binding var showLog: Bool
    let onEndTurn: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ActionBtn(icon: "arrow.2.circlepath", label: "Trade",
                      enabled: state.phase == .postRoll && !state.currentPlayer.isBot) {
                showTrade = true
            }

            ActionBtn(icon: "rectangle.stack.fill", label: "Cards",
                      enabled: state.phase == .postRoll && !state.currentPlayer.isBot &&
                               !state.currentPlayer.harvestCards.isEmpty,
                      badge: state.currentPlayer.harvestCards.count > 0
                             ? "\(state.currentPlayer.harvestCards.count)" : nil) {
                showCards = true
            }

            ActionBtn(icon: "list.bullet.rectangle", label: "Log", enabled: true) {
                showLog = true
            }

            ActionBtn(icon: "checkmark.circle.fill", label: "End",
                      enabled: state.phase == .postRoll && !state.currentPlayer.isBot,
                      highlighted: true) {
                onEndTurn()
            }
        }
        .padding(.horizontal, 8)
    }
}

struct ActionBtn: View {
    let icon: String
    let label: String
    let enabled: Bool
    var badge: String? = nil
    var highlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundStyle(enabled ? (highlighted ? .white : .primary) : .secondary)
                .frame(width: 52, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(highlighted && enabled ? Color.accentColor : Color.clear)
                }

                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(.red))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .disabled(!enabled)
    }
}

// MARK: - Game Over

struct GameOverView: View {
    let winner: Player
    let scores: [(String, Int)]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("🎉")
                    .font(.system(size: 72))
                Text("\(winner.name) Wins!")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    ForEach(scores.sorted { $0.1 > $1.1 }, id: \.0) { name, vp in
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(vp) VP")
                                .bold()
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.15)))
                .padding(.horizontal, 24)

                Button("Back to Menu") { onDismiss() }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(winner.colorScheme.primary))
            }
        }
    }
}

// MARK: - Game Log

struct GameLogView: View {
    let log: [String]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(log.reversed(), id: \.self) { entry in
                Text(entry)
                    .font(.system(size: 14, design: .rounded))
            }
            .navigationTitle("Game Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Bumper Crop Sheet

struct BumperCropSheet: View {
    @ObservedObject var state: GameState
    let onDone: ([ResourceType]) -> Void
    @State private var picks: [ResourceType] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Choose 2 Resources")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .padding(.top)

                HStack(spacing: 12) {
                    ForEach(ResourceType.allCases) { res in
                        let selected = picks.filter { $0 == res }.count
                        Button {
                            if picks.count < 2 { picks.append(res) }
                        } label: {
                            VStack(spacing: 6) {
                                Text(res.emoji).font(.system(size: 32))
                                Text(res.displayName).font(.caption)
                                if selected > 0 {
                                    Text("×\(selected)").font(.caption.bold())
                                }
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selected > 0 ? res.tintColor.opacity(0.3) : Color.gray.opacity(0.1))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Button("Confirm") { onDone(picks) }
                    .disabled(picks.count < 2)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(picks.count == 2 ? .green : .gray))

                Button("Clear") { picks = [] }
                    .foregroundStyle(.red)
            }
            .navigationTitle("Bumper Crop")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Market Corner Sheet

struct MarketCornerSheet: View {
    let onSelect: (ResourceType) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Choose a resource to steal from all opponents")
                    .font(.system(size: 15, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top)

                HStack(spacing: 12) {
                    ForEach(ResourceType.allCases) { res in
                        Button { onSelect(res) } label: {
                            VStack(spacing: 6) {
                                Text(res.emoji).font(.system(size: 32))
                                Text(res.displayName).font(.caption)
                            }
                            .padding(14)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(res.tintColor.opacity(0.25))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Market Corner")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
