import SwiftUI

struct MainMenuView: View {
    @State private var navigateToGame: GameConfig? = nil
    @State private var showModeSheet = false
    @State private var selectedMode: GameModeOption = .vsBot

    enum GameModeOption: CaseIterable {
        case vsBot, localMultiplayer, casual, ranked, privateRoom

        var title: String {
            switch self {
            case .vsBot:            return "vs Bots"
            case .localMultiplayer: return "Local Play"
            case .casual:           return "Casual Online"
            case .ranked:           return "Ranked"
            case .privateRoom:      return "Private Room"
            }
        }
        var subtitle: String {
            switch self {
            case .vsBot:            return "Single player – practice mode"
            case .localMultiplayer: return "Pass & play with friends"
            case .casual:           return "Online matchmaking"
            case .ranked:           return "Competitive ladder"
            case .privateRoom:      return "Custom lobby with friends"
            }
        }
        var icon: String {
            switch self {
            case .vsBot:            return "cpu"
            case .localMultiplayer: return "person.2.fill"
            case .casual:           return "network"
            case .ranked:           return "trophy.fill"
            case .privateRoom:      return "lock.fill"
            }
        }
        var available: Bool {
            switch self {
            case .vsBot, .localMultiplayer: return true
            default: return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.75, blue: 0.35),
                             Color(red: 0.38, green: 0.58, blue: 0.22)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                // Field texture dots
                FieldTextureView()

                VStack(spacing: 0) {
                    // Title
                    VStack(spacing: 4) {
                        Text("🌾")
                            .font(.system(size: 72))
                            .shadow(radius: 4)
                        Text("FarmRush")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        Text("Build · Trade · Harvest")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .tracking(2)
                    }
                    .padding(.top, 60)

                    Spacer()

                    // Mode cards
                    VStack(spacing: 12) {
                        ForEach(GameModeOption.allCases, id: \.title) { mode in
                            ModeCardView(mode: mode) {
                                if mode.available {
                                    selectedMode = mode
                                    showModeSheet = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Text("First to 10 victory points wins")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 32)
                }
            }
            .navigationDestination(item: $navigateToGame) { config in
                GameView(config: config)
            }
        }
        .sheet(isPresented: $showModeSheet) {
            GameSetupSheet(mode: selectedMode, onStart: { config in
                showModeSheet = false
                navigateToGame = config
            })
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Mode Card

struct ModeCardView: View {
    let mode: MainMenuView.GameModeOption
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(mode.available ? .white : .white.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode.available ? .white : .white.opacity(0.4))
                    Text(mode.subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(mode.available ? .white.opacity(0.75) : .white.opacity(0.3))
                }

                Spacer()

                if mode.available {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("SOON")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.1)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(mode.available ? 0.18 : 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
            }
        }
        .disabled(!mode.available)
        .buttonStyle(.plain)
    }
}

// MARK: - Game Setup Sheet

struct GameConfig: Identifiable {
    let id = UUID()
    let players: [Player]
    let board: GameBoard
}

struct GameSetupSheet: View {
    let mode: MainMenuView.GameModeOption
    let onStart: (GameConfig) -> Void

    @State private var playerName = "Farmer"
    @State private var botCount = 1
    @State private var localCount = 2

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Name") {
                    TextField("Enter name", text: $playerName)
                }

                if mode == .vsBot {
                    Section("Opponents") {
                        Stepper("Bot count: \(botCount)", value: $botCount, in: 1...3)
                    }
                } else if mode == .localMultiplayer {
                    Section("Players") {
                        Stepper("Player count: \(localCount)", value: $localCount, in: 2...4)
                    }
                }

                Section {
                    Button("Start Game") {
                        onStart(buildConfig())
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.2))
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func buildConfig() -> GameConfig {
        let board = BoardGenerator.generate()
        var players: [Player] = []
        let colors = PlayerColorScheme.allCases

        let humanName = playerName.isEmpty ? "Farmer" : playerName
        players.append(Player(name: humanName, colorScheme: colors[0], isBot: false, playerIndex: 0))

        if mode == .vsBot {
            let botNames = ["Agatha Bot", "Barnard Bot", "Clara Bot"]
            for i in 0..<botCount {
                players.append(Player(name: botNames[i % botNames.count],
                                      colorScheme: colors[(i + 1) % colors.count],
                                      isBot: true,
                                      playerIndex: i + 1))
            }
        } else {
            let names = ["Player 2", "Player 3", "Player 4"]
            for i in 1..<localCount {
                players.append(Player(name: names[i - 1],
                                      colorScheme: colors[i % colors.count],
                                      isBot: false,
                                      playerIndex: i))
            }
        }

        return GameConfig(players: players, board: board)
    }
}

// MARK: - Field Texture

struct FieldTextureView: View {
    var body: some View {
        Canvas { ctx, size in
            let dotSize: CGFloat = 3
            let spacing: CGFloat = 28
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: x + CGFloat.random(in: -4...4),
                                     y: y + CGFloat.random(in: -4...4),
                                     width: dotSize, height: dotSize)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.07)))
                    y += spacing
                }
                x += spacing
            }
        }
        .ignoresSafeArea()
    }
}
