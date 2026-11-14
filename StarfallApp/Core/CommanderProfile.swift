import Foundation
import StarfallGalaxy

struct CommodityItem: Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let basePriceCR: Int
    let producedBy: Economy
    let consumedBy: Economy
}

struct StationMarketListing: Identifiable, Sendable {
    let id: String
    let commodity: CommodityItem
    let buyPriceCR: Int
    let sellPriceCR: Int
    let supplyTag: String
}

struct SoloContractMission: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let rewardCR: Int
    let requiredKills: Int
    var currentKills: Int
    var isCompleted: Bool { currentKills >= requiredKills }
}

struct CommanderSaveData: Codable, Sendable {
    var commanderName: String = "CMDR ISIDRO"
    var credits: Int = 25_000
    var unclaimedBountiesCR: Int = 0
    var totalKills: Int = 0
    var systemsVisited: Int = 1
    var tradeProfitCR: Int = 0
    var currentSystemRawID: UInt64 = Galaxy().sol.id.rawValue
    var fuelTons: Float = 16.0
    var maxFuelTons: Float = 16.0
    var cargoCapacity: Int = 20
    var cargoHold: [String: Int] = [:]
    var fsdGrade: Int = 1        // 1..4 (12 LY, 16 LY, 20 LY, 26 LY)
    var shieldGrade: Int = 1     // 1..4
    var thrusterGrade: Int = 1   // 1..4
    var weaponGrade: Int = 1     // 1..4
    var activeMissions: [SoloContractMission] = []
}

@MainActor
final class CommanderProfile: ObservableObject {
    @Published var data = CommanderSaveData()
    @Published var isDocked: Bool = false
    @Published var dockedStationName: String = "Gagarin Gateway"
    @Published var statusBannerMessage: String = "SYSTEMS ONLINE • BLUE THROTTLE ZONE = MAX AGILITY"
    @Published var statusBannerTimer: Float = 4.0

    static let allCommodities: [CommodityItem] = [
        CommodityItem(id: "titanium", name: "Titanium", category: "Metals", basePriceCR: 1_120, producedBy: .refinery, consumedBy: .highTech),
        CommodityItem(id: "superconductors", name: "Superconductors", category: "Materials", basePriceCR: 6_450, producedBy: .refinery, consumedBy: .highTech),
        CommodityItem(id: "quantum_processors", name: "Quantum Processors", category: "Technology", basePriceCR: 8_900, producedBy: .highTech, consumedBy: .industrial),
        CommodityItem(id: "medical_diagnostics", name: "Medical Diagnostic Gear", category: "Technology", basePriceCR: 4_200, producedBy: .highTech, consumedBy: .colony),
        CommodityItem(id: "robotics", name: "Autonomous Robotics", category: "Machinery", basePriceCR: 3_150, producedBy: .industrial, consumedBy: .extraction),
        CommodityItem(id: "power_generators", name: "Fusion Generators", category: "Machinery", basePriceCR: 2_600, producedBy: .industrial, consumedBy: .agriculture),
        CommodityItem(id: "agri_medicines", name: "Agri-Biotech Supplies", category: "Foods & Bio", basePriceCR: 1_850, producedBy: .agriculture, consumedBy: .extraction),
        CommodityItem(id: "painite_ore", name: "Core Crystal Ore", category: "Minerals", basePriceCR: 11_400, producedBy: .extraction, consumedBy: .refinery)
    ]

    init() {
        loadFromDisk()
        if data.activeMissions.isEmpty {
            seedStarterMissions()
        }
    }

    var jumpRangeLY: Double {
        switch data.fsdGrade {
        case 1: return 12.0
        case 2: return 16.5
        case 3: return 21.0
        default: return 27.5
        }
    }

    var shieldBonusMultiplier: Float {
        1.0 + Float(data.shieldGrade - 1) * 0.25
    }

    var weaponBonusMultiplier: Float {
        1.0 + Float(data.weaponGrade - 1) * 0.22
    }

    var thrusterBonusMultiplier: Float {
        1.0 + Float(data.thrusterGrade - 1) * 0.10
    }

    var cargoUsedTons: Int {
        data.cargoHold.values.reduce(0, +)
    }

    var combatRankTitle: String {
        switch data.totalKills {
        case 0: return "HARMLESS"
        case 1...3: return "MOSTLY HARMLESS"
        case 4...8: return "NOVICE"
        case 9...16: return "COMPETENT"
        case 17...30: return "EXPERT"
        case 31...50: return "DANGEROUS"
        case 51...80: return "DEADLY"
        default: return "ELITE"
        }
    }

    var explorerRankTitle: String {
        switch data.systemsVisited {
        case 1: return "AIMLESS"
        case 2...3: return "MOSTLY AIMLESS"
        case 4...7: return "SCOUT"
        case 8...14: return "SURVEYOR"
        case 15...25: return "PATHFINDER"
        case 26...45: return "RANGER"
        default: return "ELITE EXPLORER"
        }
    }

    var tradeRankTitle: String {
        switch data.tradeProfitCR {
        case ..<5_000: return "PENNILESS"
        case 5_000..<25_000: return "PEDDLER"
        case 25_000..<80_000: return "DEALER"
        case 80_000..<250_000: return "MERCHANT"
        case 250_000..<750_000: return "BROKER"
        default: return "ELITE TYCOON"
        }
    }

    func postBanner(_ message: String, duration: Float = 3.5) {
        statusBannerMessage = message
        statusBannerTimer = duration
    }

    func recordPirateKill(callsign: String) {
        let bounty = 12_500
        data.totalKills += 1
        data.unclaimedBountiesCR += bounty
        for i in data.activeMissions.indices {
            if data.activeMissions[i].currentKills < data.activeMissions[i].requiredKills {
                data.activeMissions[i].currentKills += 1
            }
        }
        postBanner("TARGET DESTROYED (\(callsign)) • +\(bounty) CR BOUNTY VOUCHER", duration: 4.0)
        saveToDisk()
    }

    func redeemBounties() -> Int {
        let amount = data.unclaimedBountiesCR
        guard amount > 0 else { return 0 }
        data.credits += amount
        data.unclaimedBountiesCR = 0
        postBanner("AUTHORITY CONTACT: REDEEMED +\(amount) CR IN BOUNTIES")
        saveToDisk()
        return amount
    }

    func claimCompletedMission(_ missionID: String) {
        guard let idx = data.activeMissions.firstIndex(where: { $0.id == missionID && $0.isCompleted }) else { return }
        let reward = data.activeMissions[idx].rewardCR
        data.credits += reward
        data.activeMissions.remove(at: idx)
        if data.activeMissions.count < 3 {
            seedStarterMissions()
        }
        postBanner("MISSION COMPLETE • CREDITED +\(reward) CR")
        saveToDisk()
    }

    func marketListings(for economy: Economy, stationSeed: Int) -> [StationMarketListing] {
        Self.allCommodities.enumerated().map { idx, item in
            let jitter = ((stationSeed + idx * 17) % 11) - 5
            let jitterFactor = 1.0 + Double(jitter) * 0.015
            let priceMultiplier: Double
            let supplyTag: String

            if item.producedBy == economy {
                priceMultiplier = 0.72 * jitterFactor
                supplyTag = "HIGH SUPPLY (CHEAP)"
            } else if item.consumedBy == economy {
                priceMultiplier = 1.34 * jitterFactor
                supplyTag = "HIGH DEMAND (PROFIT)"
            } else {
                priceMultiplier = 1.00 * jitterFactor
                supplyTag = "BALANCED"
            }

            let buyPrice = max(100, Int((Double(item.basePriceCR) * priceMultiplier).rounded()))
            let sellPrice = max(90, Int((Double(buyPrice) * 0.96).rounded()))
            return StationMarketListing(
                id: item.id,
                commodity: item,
                buyPriceCR: buyPrice,
                sellPriceCR: sellPrice,
                supplyTag: supplyTag
            )
        }
    }

    func buyCommodity(_ listing: StationMarketListing) {
        guard cargoUsedTons < data.cargoCapacity else {
            postBanner("CARGO HOLD FULL (\(data.cargoCapacity) T)")
            return
        }
        guard data.credits >= listing.buyPriceCR else {
            postBanner("INSUFFICIENT CREDITS")
            return
        }
        data.credits -= listing.buyPriceCR
        data.cargoHold[listing.id, default: 0] += 1
        postBanner("PURCHASED 1T \(listing.commodity.name.uppercased()) (-\(listing.buyPriceCR) CR)")
        saveToDisk()
    }

    func sellCommodity(_ listing: StationMarketListing) {
        let held = data.cargoHold[listing.id, default: 0]
        guard held > 0 else { return }
        data.cargoHold[listing.id] = held - 1
        if data.cargoHold[listing.id] == 0 {
            data.cargoHold.removeValue(forKey: listing.id)
        }
        data.credits += listing.sellPriceCR
        let profit = max(0, listing.sellPriceCR - listing.commodity.basePriceCR)
        data.tradeProfitCR += max(250, profit)
        postBanner("SOLD 1T \(listing.commodity.name.uppercased()) (+\(listing.sellPriceCR) CR)")
        saveToDisk()
    }

    func upgradeModule(kind: String, costCR: Int) {
        guard data.credits >= costCR else {
            postBanner("INSUFFICIENT CREDITS FOR OUTFITTING")
            return
        }
        switch kind {
        case "FSD":
            guard data.fsdGrade < 4 else { return }
            data.fsdGrade += 1
        case "SHIELD":
            guard data.shieldGrade < 4 else { return }
            data.shieldGrade += 1
        case "THRUSTER":
            guard data.thrusterGrade < 4 else { return }
            data.thrusterGrade += 1
        case "WEAPON":
            guard data.weaponGrade < 4 else { return }
            data.weaponGrade += 1
        default:
            return
        }
        data.credits -= costCR
        postBanner("OUTFITTING INSTALLED: \(kind) UPGRADED")
        saveToDisk()
    }

    private func seedStarterMissions() {
        data.activeMissions = [
            SoloContractMission(
                id: "msn_bounty_1",
                title: "PATROL SWEEP: CLEAR 2 ROGUE DRONES",
                description: "Eliminate 2 hostile aggressor drones in the local orbital patrol sector.",
                rewardCR: 25_000,
                requiredKills: 2,
                currentKills: 0
            ),
            SoloContractMission(
                id: "msn_bounty_2",
                title: "SECURITY CONTRACT: ELIMINATE 5 PIRATES",
                description: "Secure station approach lanes by destroying 5 hostile drones.",
                rewardCR: 65_000,
                requiredKills: 5,
                currentKills: 0
            )
        ]
    }

    private var saveFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("starfall_commander_save.json")
    }

    func saveToDisk() {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: saveFileURL, options: .atomic)
        }
    }

    func loadFromDisk() {
        guard let raw = try? Data(contentsOf: saveFileURL),
              let decoded = try? JSONDecoder().decode(CommanderSaveData.self, from: raw) else {
            return
        }
        data = decoded
    }
}
