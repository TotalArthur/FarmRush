import SwiftUI

struct TileView: View {
    let tile: GameTile
    let isBlighted: Bool
    let isSelectable: Bool
    let tileSize: CGFloat

    @State private var patchworkOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Main field background
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tile.type.primaryColor, tile.type.secondaryColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: tileSize - 2, height: tileSize - 2)
                .overlay {
                    // Inner patchwork texture - slightly rotated inner rectangle
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tile.type.primaryColor.opacity(0.3))
                        .frame(width: tileSize - 14, height: tileSize - 14)
                        .rotationEffect(.degrees(4))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                }

            // Crop/terrain icon
            Text(tile.type.icon)
                .font(.system(size: tileSize * 0.30))
                .offset(y: tile.numberToken != nil ? -8 : 0)

            // Number token
            if let token = tile.numberToken {
                NumberTokenView(number: token)
                    .offset(y: 12)
            }

            // Blight overlay
            if isBlighted {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .frame(width: tileSize - 2, height: tileSize - 2)

                VStack(spacing: 0) {
                    Text("🦟")
                        .font(.system(size: 22))
                    Text("Blight")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            // Selectable highlight ring
            if isSelectable && !isBlighted {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.orange, lineWidth: 2.5)
                    .frame(width: tileSize - 2, height: tileSize - 2)
            }
        }
        .frame(width: tileSize, height: tileSize)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

// MARK: - Number Token

struct NumberTokenView: View {
    let number: Int

    var isHot: Bool { number == 6 || number == 8 }
    var dotCount: Int {
        [2:1, 3:2, 4:3, 5:4, 6:5, 8:5, 9:4, 10:3, 11:2, 12:1][number] ?? 1
    }

    var body: some View {
        VStack(spacing: 1) {
            Text("\(number)")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isHot ? Color(red: 0.8, green: 0.1, blue: 0.1) : .primary)

            // Probability dots
            HStack(spacing: 2) {
                ForEach(0..<dotCount, id: \.self) { _ in
                    Circle()
                        .fill(isHot ? Color(red: 0.8, green: 0.1, blue: 0.1) : Color.gray)
                        .frame(width: 3, height: 3)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.88))
                .shadow(color: .black.opacity(0.2), radius: 1)
        }
    }
}
