import SwiftUI

// MARK: - Resource Type

enum ResourceType: String, CaseIterable, Codable, Hashable, Identifiable {
    case grain, wool, fruit, stone, timber

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grain:  return "Grain"
        case .wool:   return "Wool"
        case .fruit:  return "Fruit"
        case .stone:  return "Stone"
        case .timber: return "Timber"
        }
    }

    var emoji: String {
        switch self {
        case .grain:  return "🌾"
        case .wool:   return "🐑"
        case .fruit:  return "🍎"
        case .stone:  return "🪨"
        case .timber: return "🪵"
        }
    }

    var tintColor: Color {
        switch self {
        case .grain:  return Color(red: 0.95, green: 0.80, blue: 0.20)
        case .wool:   return Color(red: 0.90, green: 0.90, blue: 0.90)
        case .fruit:  return Color(red: 0.85, green: 0.25, blue: 0.20)
        case .stone:  return Color(red: 0.55, green: 0.52, blue: 0.50)
        case .timber: return Color(red: 0.50, green: 0.32, blue: 0.16)
        }
    }
}

// MARK: - Tile Type

enum TileType: String, CaseIterable, Codable {
    case wheatField, pasture, orchard, quarry, forestPlot, barrenLand

    var resource: ResourceType? {
        switch self {
        case .wheatField: return .grain
        case .pasture:    return .wool
        case .orchard:    return .fruit
        case .quarry:     return .stone
        case .forestPlot: return .timber
        case .barrenLand: return nil
        }
    }

    var displayName: String {
        switch self {
        case .wheatField: return "Wheat Field"
        case .pasture:    return "Pasture"
        case .orchard:    return "Orchard"
        case .quarry:     return "Quarry"
        case .forestPlot: return "Forest"
        case .barrenLand: return "Barren"
        }
    }

    var primaryColor: Color {
        switch self {
        case .wheatField: return Color(red: 0.92, green: 0.82, blue: 0.30)
        case .pasture:    return Color(red: 0.52, green: 0.78, blue: 0.40)
        case .orchard:    return Color(red: 0.28, green: 0.62, blue: 0.22)
        case .quarry:     return Color(red: 0.60, green: 0.54, blue: 0.48)
        case .forestPlot: return Color(red: 0.18, green: 0.42, blue: 0.22)
        case .barrenLand: return Color(red: 0.80, green: 0.74, blue: 0.58)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .wheatField: return Color(red: 0.98, green: 0.90, blue: 0.45)
        case .pasture:    return Color(red: 0.62, green: 0.88, blue: 0.50)
        case .orchard:    return Color(red: 0.38, green: 0.72, blue: 0.32)
        case .quarry:     return Color(red: 0.70, green: 0.64, blue: 0.58)
        case .forestPlot: return Color(red: 0.28, green: 0.52, blue: 0.32)
        case .barrenLand: return Color(red: 0.88, green: 0.84, blue: 0.68)
        }
    }

    var icon: String {
        switch self {
        case .wheatField: return "🌾"
        case .pasture:    return "🐑"
        case .orchard:    return "🍏"
        case .quarry:     return "⛏️"
        case .forestPlot: return "🌲"
        case .barrenLand: return "🏜️"
        }
    }
}

// MARK: - Harvest Card

enum HarvestCardType: String, CaseIterable, Codable {
    case scarecrow, bumperCrop, landGrab, marketCorner, prizeCrop

    var displayName: String {
        switch self {
        case .scarecrow:    return "Scarecrow"
        case .bumperCrop:   return "Bumper Crop"
        case .landGrab:     return "Land Grab"
        case .marketCorner: return "Market Corner"
        case .prizeCrop:    return "Prize Crop"
        }
    }

    var description: String {
        switch self {
        case .scarecrow:    return "Move the blight to any tile and steal 1 resource from an adjacent player."
        case .bumperCrop:   return "Take any 2 resources from the supply."
        case .landGrab:     return "Place 2 fences for free."
        case .marketCorner: return "Steal all of one resource type from every other player."
        case .prizeCrop:    return "Worth 1 hidden victory point."
        }
    }

    var icon: String {
        switch self {
        case .scarecrow:    return "🪣"
        case .bumperCrop:   return "🌽"
        case .landGrab:     return "🤝"
        case .marketCorner: return "💰"
        case .prizeCrop:    return "🏆"
        }
    }

    var deckCount: Int {
        switch self {
        case .scarecrow:    return 14
        case .bumperCrop:   return 2
        case .landGrab:     return 2
        case .marketCorner: return 2
        case .prizeCrop:    return 5
        }
    }
}

struct HarvestCard: Codable, Identifiable, Equatable {
    let id: UUID
    let type: HarvestCardType
    let purchasedOnTurn: Int

    static func == (lhs: HarvestCard, rhs: HarvestCard) -> Bool { lhs.id == rhs.id }
}

// MARK: - Coordinates

struct TileCoord: Hashable, Codable, Equatable {
    let col: Int
    let row: Int
}

struct VertexCoord: Hashable, Codable, Equatable, Comparable {
    let col: Int
    let row: Int

    static func < (lhs: VertexCoord, rhs: VertexCoord) -> Bool {
        lhs.row != rhs.row ? lhs.row < rhs.row : lhs.col < rhs.col
    }

    func adjacentVertices(maxCol: Int, maxRow: Int) -> [VertexCoord] {
        [VertexCoord(col: col - 1, row: row),
         VertexCoord(col: col + 1, row: row),
         VertexCoord(col: col, row: row - 1),
         VertexCoord(col: col, row: row + 1)]
            .filter { $0.col >= 0 && $0.col <= maxCol && $0.row >= 0 && $0.row <= maxRow }
    }

    func adjacentTiles(boardCols: Int, boardRows: Int) -> [TileCoord] {
        [TileCoord(col: col - 1, row: row - 1),
         TileCoord(col: col,     row: row - 1),
         TileCoord(col: col - 1, row: row),
         TileCoord(col: col,     row: row)]
            .filter { $0.col >= 0 && $0.col < boardCols && $0.row >= 0 && $0.row < boardRows }
    }
}

struct EdgeCoord: Hashable, Codable, Equatable {
    let v1: VertexCoord
    let v2: VertexCoord

    init(_ a: VertexCoord, _ b: VertexCoord) {
        if a < b { v1 = a; v2 = b } else { v1 = b; v2 = a }
    }

    var isHorizontal: Bool { v1.row == v2.row }

    var midpoint: (col: Double, row: Double) {
        (col: Double(v1.col + v2.col) / 2.0,
         row: Double(v1.row + v2.row) / 2.0)
    }

    func adjacentTiles(boardCols: Int, boardRows: Int) -> [TileCoord] {
        // Tiles that share this edge
        if isHorizontal {
            // horizontal edge: tiles above and below
            let row = v1.row
            return [TileCoord(col: v1.col, row: row - 1),
                    TileCoord(col: v1.col, row: row)]
                .filter { $0.col >= 0 && $0.col < boardCols && $0.row >= 0 && $0.row < boardRows }
        } else {
            // vertical edge: tiles left and right
            let col = v1.col
            return [TileCoord(col: col - 1, row: v1.row),
                    TileCoord(col: col,     row: v1.row)]
                .filter { $0.col >= 0 && $0.col < boardCols && $0.row >= 0 && $0.row < boardRows }
        }
    }
}

// MARK: - Building

enum BuildingType: Codable, Equatable { case farmstead, barn }

struct Building: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let type: BuildingType
    let playerIndex: Int
    let vertex: VertexCoord
}

struct FenceSegment: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    let playerIndex: Int
    let edge: EdgeCoord
}

// MARK: - Market Post

struct MarketPost: Codable, Identifiable {
    let id: UUID
    let vertex: VertexCoord
    let specialResource: ResourceType?

    var tradeRate: Int { specialResource == nil ? 3 : 2 }

    var displayName: String {
        if let res = specialResource { return "\(res.displayName) Market" }
        return "General Market"
    }
}

// MARK: - Game Phase

enum SetupSubPhase: Codable, Equatable {
    case placingFarmstead
    case placingFence
}

enum GamePhase: Codable, Equatable {
    case setup(round: Int, subPhase: SetupSubPhase)
    case preRoll
    case blightDiscard
    case blightMove
    case postRoll
    case playingLandGrab(fencesRemaining: Int)
    case playingMarketCorner
    case playingScarecrow
    case gameOver(winnerIndex: Int)
}

// MARK: - Player Color

enum PlayerColorScheme: Int, CaseIterable, Codable {
    case crimson, cobalt, emerald, amber

    var primary: Color {
        switch self {
        case .crimson: return Color(red: 0.80, green: 0.10, blue: 0.10)
        case .cobalt:  return Color(red: 0.10, green: 0.30, blue: 0.85)
        case .emerald: return Color(red: 0.10, green: 0.60, blue: 0.25)
        case .amber:   return Color(red: 0.90, green: 0.52, blue: 0.05)
        }
    }

    var displayName: String {
        switch self {
        case .crimson: return "Crimson"
        case .cobalt:  return "Cobalt"
        case .emerald: return "Emerald"
        case .amber:   return "Amber"
        }
    }
}

// MARK: - Game Mode

enum GameMode: Equatable {
    case vsBot(botCount: Int)
    case localMultiplayer(playerCount: Int)
    case online
}
