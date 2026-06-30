import Foundation

struct GameTile: Codable, Identifiable {
    let id: UUID
    let coord: TileCoord
    let type: TileType
    var numberToken: Int?
}

struct GameBoard: Codable {
    let cols: Int
    let rows: Int
    var tiles: [TileCoord: GameTile]
    var marketPosts: [MarketPost]
    var buildings: [Building]
    var fences: [FenceSegment]
    var blightTile: TileCoord

    // MARK: - Derived Geometry

    var allVertices: [VertexCoord] {
        var verts: [VertexCoord] = []
        for row in 0...rows {
            for col in 0...cols {
                verts.append(VertexCoord(col: col, row: row))
            }
        }
        return verts
    }

    var allEdges: [EdgeCoord] {
        var edges: [EdgeCoord] = []
        for row in 0...rows {
            for col in 0...cols {
                let v = VertexCoord(col: col, row: row)
                if col < cols { edges.append(EdgeCoord(v, VertexCoord(col: col + 1, row: row))) }
                if row < rows { edges.append(EdgeCoord(v, VertexCoord(col: col, row: row + 1))) }
            }
        }
        return edges
    }

    // MARK: - Queries

    func tile(at coord: TileCoord) -> GameTile? { tiles[coord] }

    func building(at vertex: VertexCoord) -> Building? {
        buildings.first { $0.vertex == vertex }
    }

    func fence(on edge: EdgeCoord) -> FenceSegment? {
        fences.first { $0.edge == edge }
    }

    func marketPost(at vertex: VertexCoord) -> MarketPost? {
        marketPosts.first { $0.vertex == vertex }
    }

    // Tiles that touch a given vertex
    func tilesAdjacentTo(vertex: VertexCoord) -> [GameTile] {
        vertex.adjacentTiles(boardCols: cols, boardRows: rows)
            .compactMap { tiles[$0] }
    }

    // All vertices on the border of a tile
    func verticesOf(tile coord: TileCoord) -> [VertexCoord] {
        [VertexCoord(col: coord.col,     row: coord.row),
         VertexCoord(col: coord.col + 1, row: coord.row),
         VertexCoord(col: coord.col,     row: coord.row + 1),
         VertexCoord(col: coord.col + 1, row: coord.row + 1)]
    }

    // All edges that border a tile
    func edgesOf(tile coord: TileCoord) -> [EdgeCoord] {
        let tl = VertexCoord(col: coord.col,     row: coord.row)
        let tr = VertexCoord(col: coord.col + 1, row: coord.row)
        let bl = VertexCoord(col: coord.col,     row: coord.row + 1)
        let br = VertexCoord(col: coord.col + 1, row: coord.row + 1)
        return [EdgeCoord(tl, tr), EdgeCoord(bl, br), EdgeCoord(tl, bl), EdgeCoord(tr, br)]
    }

    // All edges touching a vertex
    func edgesOf(vertex v: VertexCoord) -> [EdgeCoord] {
        v.adjacentVertices(maxCol: cols, maxRow: rows).map { EdgeCoord(v, $0) }
    }

    // Players' buildings touching a tile
    func buildingsAdjacentTo(tile coord: TileCoord) -> [Building] {
        verticesOf(tile: coord).compactMap { building(at: $0) }
    }

    // MARK: - Fence network connectivity

    func fenceNetwork(for playerIndex: Int) -> Set<EdgeCoord> {
        Set(fences.filter { $0.playerIndex == playerIndex }.map { $0.edge })
    }

    func verticesReachableByFence(from start: VertexCoord, playerIndex: Int) -> Set<VertexCoord> {
        let network = fenceNetwork(for: playerIndex)
        var visited: Set<VertexCoord> = [start]
        var queue: [VertexCoord] = [start]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for neighbor in current.adjacentVertices(maxCol: cols, maxRow: rows) {
                let edge = EdgeCoord(current, neighbor)
                if network.contains(edge) && !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
        }
        return visited
    }

    // Vertices reachable through any of the player's buildings + fence network
    func reachableVertices(for playerIndex: Int) -> Set<VertexCoord> {
        let playerBuildings = buildings.filter { $0.playerIndex == playerIndex }
        var reachable: Set<VertexCoord> = []
        for b in playerBuildings {
            reachable.formUnion(verticesReachableByFence(from: b.vertex, playerIndex: playerIndex))
        }
        return reachable
    }

    // Longest fence chain length for a player (DFS on fence graph)
    func longestFenceChain(for playerIndex: Int) -> Int {
        let network = fenceNetwork(for: playerIndex)
        guard !network.isEmpty else { return 0 }

        // Build adjacency of fence segments via shared vertices
        var vertexToEdges: [VertexCoord: [EdgeCoord]] = [:]
        for edge in network {
            vertexToEdges[edge.v1, default: []].append(edge)
            vertexToEdges[edge.v2, default: []].append(edge)
        }

        var bestLength = 0

        func dfs(vertex: VertexCoord, visitedEdges: inout Set<EdgeCoord>, length: Int) {
            bestLength = max(bestLength, length)
            for edge in (vertexToEdges[vertex] ?? []) where !visitedEdges.contains(edge) {
                let next = edge.v1 == vertex ? edge.v2 : edge.v1
                visitedEdges.insert(edge)
                dfs(vertex: next, visitedEdges: &visitedEdges, length: length + 1)
                visitedEdges.remove(edge)
            }
        }

        for edge in network {
            var visited: Set<EdgeCoord> = []
            visited.insert(edge)
            dfs(vertex: edge.v1, visitedEdges: &visited, length: 1)
            visited = [edge]
            dfs(vertex: edge.v2, visitedEdges: &visited, length: 1)
        }

        return bestLength
    }

    // MARK: - Placement Validation

    func isDistanceRuleSatisfied(for vertex: VertexCoord) -> Bool {
        let occupied = Set(buildings.map { $0.vertex })
        if occupied.contains(vertex) { return false }
        for neighbor in vertex.adjacentVertices(maxCol: cols, maxRow: rows) {
            if occupied.contains(neighbor) { return false }
        }
        return true
    }

    func validFarmsteadPlacements(for playerIndex: Int, setupPhase: Bool) -> [VertexCoord] {
        allVertices.filter { vertex in
            guard isDistanceRuleSatisfied(for: vertex) else { return false }
            if setupPhase { return true }
            return reachableVertices(for: playerIndex).contains(vertex)
        }
    }

    func validBarnUpgrades(for playerIndex: Int) -> [VertexCoord] {
        buildings.filter { $0.playerIndex == playerIndex && $0.type == .farmstead }
                 .map { $0.vertex }
    }

    func validFencePlacements(for playerIndex: Int, setupPhase: Bool) -> [EdgeCoord] {
        let existingFenceEdges = Set(fences.map { $0.edge })
        let playerBuildings = buildings.filter { $0.playerIndex == playerIndex }
        let playerFenceVertices: Set<VertexCoord> = Set(
            fences.filter { $0.playerIndex == playerIndex }.flatMap { [$0.edge.v1, $0.edge.v2] }
        )
        let buildingVertices = Set(playerBuildings.map { $0.vertex })
        let connectedVertices = buildingVertices.union(playerFenceVertices)

        return allEdges.filter { edge in
            guard !existingFenceEdges.contains(edge) else { return false }
            if setupPhase {
                // During setup, fence must touch the most recently placed farmstead
                // (handled externally via setupFarmsteadVertex)
                return true
            }
            return connectedVertices.contains(edge.v1) || connectedVertices.contains(edge.v2)
        }
    }
}
