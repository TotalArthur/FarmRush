import Foundation

enum BoardGenerator {

    static func generate(cols: Int = 5, rows: Int = 5) -> GameBoard {
        var tiles: [TileCoord: GameTile] = [:]

        // Tile type distribution for a 5×5 = 25 tile board
        // 5 Wheat, 5 Pasture, 4 Orchard, 4 Quarry, 5 Forest, 2 Barren
        var typePool: [TileType] = []
        typePool += Array(repeating: .wheatField, count: 5)
        typePool += Array(repeating: .pasture,    count: 5)
        typePool += Array(repeating: .orchard,    count: 4)
        typePool += Array(repeating: .quarry,     count: 4)
        typePool += Array(repeating: .forestPlot, count: 5)
        typePool += Array(repeating: .barrenLand, count: 2)
        typePool.shuffle()

        // Number token distribution (23 producing tiles)
        var tokenPool: [Int] = [
            2,
            3, 3,
            4, 4,
            5, 5, 5,
            6, 6, 6,
            8, 8, 8,
            9, 9, 9,
            10, 10,
            11, 11,
            12,
            5  // extra to fill 23
        ]
        tokenPool.shuffle()

        var tokenIdx = 0
        var tileIdx = 0
        for row in 0..<rows {
            for col in 0..<cols {
                let coord = TileCoord(col: col, row: row)
                let type = typePool[tileIdx]
                let token: Int? = (type == .barrenLand) ? nil : tokenPool[tokenIdx]
                if type != .barrenLand { tokenIdx += 1 }
                tiles[coord] = GameTile(id: UUID(), coord: coord, type: type, numberToken: token)
                tileIdx += 1
            }
        }

        // Ensure blight starts on a barren tile
        let barren = tiles.values.first { $0.type == .barrenLand }
        let blightStart = barren?.coord ?? TileCoord(col: 2, row: 2)

        // Market posts at edge vertices
        let marketPosts = makeMarketPosts(cols: cols, rows: rows)

        return GameBoard(
            cols: cols,
            rows: rows,
            tiles: tiles,
            marketPosts: marketPosts,
            buildings: [],
            fences: [],
            blightTile: blightStart
        )
    }

    private static func makeMarketPosts(cols: Int, rows: Int) -> [MarketPost] {
        // Place 4 market posts at edge/corner vertices
        // One general (3:1), three specific (2:1)
        let specs: [ResourceType?] = [nil, .grain, .stone, .timber]
        let positions: [VertexCoord] = [
            VertexCoord(col: 0,    row: 0),
            VertexCoord(col: cols, row: 0),
            VertexCoord(col: 0,    row: rows),
            VertexCoord(col: cols, row: rows)
        ]
        return zip(specs, positions).map { (res, vert) in
            MarketPost(id: UUID(), vertex: vert, specialResource: res)
        }
    }
}
