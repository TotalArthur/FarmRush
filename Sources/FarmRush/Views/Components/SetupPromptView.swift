import SwiftUI

/// A contextual banner shown during setup and special game phases.
struct PhasePromptView: View {
    @ObservedObject var state: GameState
    let buildMode: GameView.BuildMode

    var message: String? {
        switch state.phase {
        case .setup(let round, let sub):
            let playerName = state.currentPlayer.name
            switch sub {
            case .placingFarmstead:
                return "Round \(round): \(playerName) – tap a highlighted spot to place your farmstead"
            case .placingFence:
                return "\(playerName) – tap an edge to place your fence"
            }
        case .blightMove:
            return "\(state.currentPlayer.name) – tap a tile to move the blight 🦟"
        case .playingScarecrow:
            return "\(state.currentPlayer.name) – tap a tile to place the Scarecrow 🪣"
        case .playingLandGrab(let remaining):
            return "Land Grab: place \(remaining) more fence\(remaining == 1 ? "" : "s")"
        case .playingMarketCorner:
            return "Market Corner – choose a resource in the sheet above"
        case .blightDiscard:
            return "Players with 8+ resources are discarding..."
        case .gameOver(let winnerIdx):
            return "🎉 \(state.players[winnerIdx].name) wins!"
        case .postRoll where buildMode == .fence:
            return "Tap an edge to place your fence"
        case .postRoll where buildMode == .farmstead:
            return "Tap a highlighted vertex to place your farmstead"
        case .postRoll where buildMode == .barn:
            return "Tap your farmstead to upgrade it to a barn"
        case .postRoll where buildMode == .landGrab:
            return "Land Grab – tap 2 edges for free fences"
        default:
            return nil
        }
    }

    var body: some View {
        if let msg = message {
            Text(msg)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                        .shadow(radius: 4)
                }
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4), value: msg)
        }
    }
}
