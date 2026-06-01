import Foundation

class Player: ObservableObject, Identifiable, Codable {
    let id: UUID
    var name: String
    var colorScheme: PlayerColorScheme
    var isBot: Bool
    var playerIndex: Int

    @Published var resources: [ResourceType: Int]
    @Published var harvestCards: [HarvestCard]
    var playedScarecrowCount: Int
    var pendingCardPlay: HarvestCard?

    // Limits
    static let maxFences = 15
    static let maxFarmsteads = 5
    static let maxBarns = 4

    init(id: UUID = UUID(),
         name: String,
         colorScheme: PlayerColorScheme,
         isBot: Bool,
         playerIndex: Int) {
        self.id = id
        self.name = name
        self.colorScheme = colorScheme
        self.isBot = isBot
        self.playerIndex = playerIndex
        self.resources = Dictionary(uniqueKeysWithValues: ResourceType.allCases.map { ($0, 0) })
        self.harvestCards = []
        self.playedScarecrowCount = 0
        self.pendingCardPlay = nil
    }

    var totalResources: Int { resources.values.reduce(0, +) }

    func resource(_ type: ResourceType) -> Int { resources[type] ?? 0 }

    func canAfford(_ cost: [ResourceType: Int]) -> Bool {
        cost.allSatisfy { (type, amount) in resource(type) >= amount }
    }

    func spend(_ cost: [ResourceType: Int]) {
        for (type, amount) in cost {
            resources[type, default: 0] -= amount
        }
    }

    func gain(_ type: ResourceType, amount: Int = 1) {
        resources[type, default: 0] += amount
    }

    func gain(_ bundle: [ResourceType: Int]) {
        for (type, amount) in bundle {
            resources[type, default: 0] += amount
        }
    }

    // MARK: - Build Costs

    static let fenceCost: [ResourceType: Int]      = [.timber: 1, .wool: 1]
    static let farmsteadCost: [ResourceType: Int]  = [.timber: 1, .wool: 1, .grain: 1, .fruit: 1]
    static let barnCost: [ResourceType: Int]        = [.grain: 2, .stone: 3]
    static let harvestCardCost: [ResourceType: Int] = [.grain: 1, .fruit: 1, .wool: 1]

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, colorScheme, isBot, playerIndex
        case resources, harvestCards, playedScarecrowCount
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        colorScheme = try c.decode(PlayerColorScheme.self, forKey: .colorScheme)
        isBot = try c.decode(Bool.self, forKey: .isBot)
        playerIndex = try c.decode(Int.self, forKey: .playerIndex)
        resources = try c.decode([ResourceType: Int].self, forKey: .resources)
        harvestCards = try c.decode([HarvestCard].self, forKey: .harvestCards)
        playedScarecrowCount = try c.decode(Int.self, forKey: .playedScarecrowCount)
        pendingCardPlay = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(colorScheme, forKey: .colorScheme)
        try c.encode(isBot, forKey: .isBot)
        try c.encode(playerIndex, forKey: .playerIndex)
        try c.encode(resources, forKey: .resources)
        try c.encode(harvestCards, forKey: .harvestCards)
        try c.encode(playedScarecrowCount, forKey: .playedScarecrowCount)
    }
}
