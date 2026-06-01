import SwiftUI

struct HarvestCardView: View {
    @ObservedObject var state: GameState
    let onPlay: (HarvestCard) -> Void
    @Environment(\.dismiss) var dismiss

    var playableCards: [HarvestCard] {
        state.currentPlayer.harvestCards.filter { state.canPlayCard($0) }
    }

    var futureCards: [HarvestCard] {
        state.currentPlayer.harvestCards.filter { !state.canPlayCard($0) && $0.type != .prizeCrop }
    }

    var prizeCrops: [HarvestCard] {
        state.currentPlayer.harvestCards.filter { $0.type == .prizeCrop }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    let hasCards = !playableCards.isEmpty || !futureCards.isEmpty || !prizeCrops.isEmpty
                    if !hasCards {
                        emptyState
                    } else {
                        if !prizeCrops.isEmpty {
                            Section {
                                HStack {
                                    Text("🏆")
                                        .font(.system(size: 28))
                                    VStack(alignment: .leading) {
                                        Text("Prize Crops × \(prizeCrops.count)")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        Text("+\(prizeCrops.count) Victory Point\(prizeCrops.count == 1 ? "" : "s") (hidden until revealed)")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("+\(prizeCrops.count) VP")
                                        .font(.system(size: 16, weight: .black, design: .rounded))
                                        .foregroundStyle(.orange)
                                }
                                .padding(14)
                                .background {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.orange.opacity(0.1))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                                        }
                                }
                            } header: {
                                sectionHeader("Victory Points", icon: "star.fill", color: .orange)
                            }
                        }

                        if !playableCards.isEmpty {
                            Section {
                                ForEach(playableCards) { card in
                                    HarvestCardRow(card: card, canPlay: true) {
                                        onPlay(card)
                                    }
                                }
                            } header: {
                                sectionHeader("Ready to Play", icon: "play.circle.fill", color: .green)
                            }
                        }

                        if !futureCards.isEmpty {
                            Section {
                                ForEach(futureCards) { card in
                                    HarvestCardRow(card: card, canPlay: false, onPlay: nil)
                                }
                            } header: {
                                sectionHeader("Purchased This Turn", icon: "clock.fill", color: .orange)
                            }
                        }
                    }

                    // Deck stats
                    HStack {
                        Image(systemName: "rectangle.stack.fill")
                        Text("\(state.harvestDeck.count) cards left in deck")
                            .font(.system(size: 13, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Harvest Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Text("🃏")
                .font(.system(size: 52))
            Text("No cards in hand")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Buy a Harvest Card for\n🌾 Grain + 🍏 Fruit + 🐑 Wool")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Card Row

struct HarvestCardRow: View {
    let card: HarvestCard
    let canPlay: Bool
    let onPlay: (() -> Void)?

    @State private var flipped = false

    var body: some View {
        HStack(spacing: 14) {
            // Card icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardGradient(card.type))
                    .frame(width: 52, height: 68)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

                VStack(spacing: 4) {
                    Text(card.type.icon)
                        .font(.system(size: 24))
                    Text(card.type == .prizeCrop ? "?" : "")
                        .font(.system(size: 10))
                }
            }

            // Card info
            VStack(alignment: .leading, spacing: 4) {
                Text(card.type.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Text(card.type.description)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if card.type == .prizeCrop {
                    Label("1 Victory Point", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if canPlay, let play = onPlay {
                Button("Play", action: play)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.green))
            } else if !canPlay {
                Text("Next\nturn")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(canPlay ? Color.green.opacity(0.4) : Color.gray.opacity(0.2),
                                      lineWidth: 1)
                }
        }
        .opacity(canPlay ? 1 : 0.65)
    }

    func cardGradient(_ type: HarvestCardType) -> LinearGradient {
        let colors: [Color]
        switch type {
        case .scarecrow:    colors = [Color(red: 0.7, green: 0.3, blue: 0.1), Color(red: 0.5, green: 0.2, blue: 0.05)]
        case .bumperCrop:   colors = [Color(red: 0.3, green: 0.7, blue: 0.2), Color(red: 0.2, green: 0.5, blue: 0.1)]
        case .landGrab:     colors = [Color(red: 0.5, green: 0.4, blue: 0.7), Color(red: 0.3, green: 0.2, blue: 0.5)]
        case .marketCorner: colors = [Color(red: 0.8, green: 0.65, blue: 0.0), Color(red: 0.6, green: 0.45, blue: 0.0)]
        case .prizeCrop:    colors = [Color(red: 0.15, green: 0.45, blue: 0.85), Color(red: 0.05, green: 0.25, blue: 0.65)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
