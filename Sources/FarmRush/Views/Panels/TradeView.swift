import SwiftUI

struct TradeView: View {
    @ObservedObject var state: GameState
    @Environment(\.dismiss) var dismiss

    @State private var selectedGive: ResourceType = .grain
    @State private var selectedReceive: ResourceType = .wool
    @State private var tab: TradeTab = .supply

    enum TradeTab: String, CaseIterable {
        case supply = "Supply"
        case player = "Players"
    }

    var currentPlayer: Player { state.currentPlayer }
    var tradeRate: Int { state.tradeRate(for: state.currentPlayerIndex, resource: selectedGive) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Trade type", selection: $tab) {
                    ForEach(TradeTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if tab == .supply {
                    supplyTradeView
                } else {
                    playerTradeView
                }

                Spacer()
            }
            .navigationTitle("Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Supply Trade

    var supplyTradeView: some View {
        VStack(spacing: 24) {
            // Market rate info
            VStack(spacing: 8) {
                Text("Your best rates:")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(ResourceType.allCases) { res in
                        let rate = state.tradeRate(for: state.currentPlayerIndex, resource: res)
                        VStack(spacing: 3) {
                            Text(res.emoji).font(.system(size: 20))
                            Text("\(rate):1")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(rate < 4 ? .green : .primary)
                        }
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(rate < 4 ? Color.green.opacity(0.12) : Color.gray.opacity(0.08))
                        }
                    }
                }
            }
            .padding(.horizontal)

            Divider()

            // Give selector
            VStack(alignment: .leading, spacing: 10) {
                Text("Give (\(currentPlayer.resource(selectedGive)) available)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ResourceType.allCases) { res in
                            ResourcePicker(resource: res,
                                          count: currentPlayer.resource(res),
                                          isSelected: selectedGive == res) {
                                selectedGive = res
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Receive selector
            VStack(alignment: .leading, spacing: 10) {
                Text("Receive (1 \(selectedReceive.displayName))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ResourceType.allCases.filter { $0 != selectedGive }) { res in
                            ResourcePicker(resource: res,
                                          count: nil,
                                          isSelected: selectedReceive == res) {
                                selectedReceive = res
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Trade button
            let canTrade = currentPlayer.resource(selectedGive) >= tradeRate
            Button {
                state.tradeWithSupply(giving: selectedGive,
                                      giveCount: tradeRate,
                                      receiving: selectedReceive)
            } label: {
                HStack {
                    Text("\(tradeRate)× \(selectedGive.emoji)")
                    Image(systemName: "arrow.right")
                    Text("1× \(selectedReceive.emoji)")
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(canTrade ? Color.green : Color.gray))
            }
            .disabled(!canTrade)
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    // MARK: - Player Trade

    var playerTradeView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Select a player to trade with:")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top)

                ForEach(state.players.indices.filter { $0 != state.currentPlayerIndex }, id: \.self) { i in
                    let other = state.players[i]
                    PlayerTradeRow(
                        player: other,
                        currentPlayer: currentPlayer,
                        onTrade: { give, receive in
                            state.trade(from: state.currentPlayerIndex,
                                       giving: give,
                                       to: i,
                                       receiving: receive)
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Resource Picker Chip

struct ResourcePicker: View {
    let resource: ResourceType
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(resource.emoji).font(.system(size: 28))
                Text(resource.displayName).font(.system(size: 11, design: .rounded))
                if let c = count {
                    Text("×\(c)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(c > 0 ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? resource.tintColor.opacity(0.35)
                          : Color.gray.opacity(0.08))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(resource.tintColor, lineWidth: 2)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Player Trade Row

struct PlayerTradeRow: View {
    let player: Player
    let currentPlayer: Player
    let onTrade: ([ResourceType: Int], [ResourceType: Int]) -> Void

    @State private var offering: [ResourceType: Int] = [:]
    @State private var requesting: [ResourceType: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(player.colorScheme.primary)
                    .frame(width: 10, height: 10)
                Text(player.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(player.totalResources) cards")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text("Offer:")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                ForEach(ResourceType.allCases) { res in
                    MiniResourceStepper(resource: res,
                                        max: currentPlayer.resource(res),
                                        value: Binding(
                                            get: { offering[res] ?? 0 },
                                            set: { offering[res] = max(0, $0) }))
                }
            }

            HStack(spacing: 4) {
                Text("Want:")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                ForEach(ResourceType.allCases) { res in
                    MiniResourceStepper(resource: res,
                                        max: player.resource(res),
                                        value: Binding(
                                            get: { requesting[res] ?? 0 },
                                            set: { requesting[res] = max(0, $0) }))
                }
            }

            let canTrade = offering.values.reduce(0,+) > 0 && requesting.values.reduce(0,+) > 0
            Button("Propose Trade") {
                onTrade(offering.filter { $0.value > 0 }, requesting.filter { $0.value > 0 })
                offering = [:]
                requesting = [:]
            }
            .disabled(!canTrade)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(canTrade ? Color.accentColor : Color.gray))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(player.colorScheme.primary.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

struct MiniResourceStepper: View {
    let resource: ResourceType
    let max: Int
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(resource.emoji).font(.system(size: 16))
            HStack(spacing: 2) {
                Button { value = Swift.max(0, value - 1) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(value > 0 ? .red : .gray.opacity(0.3))
                }
                .disabled(value == 0)

                Text("\(value)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 16)

                Button { value = Swift.min(max, value + 1) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(value < max ? .green : .gray.opacity(0.3))
                }
                .disabled(value >= max)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
