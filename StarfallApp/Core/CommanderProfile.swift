import Foundation
import StarfallGalaxy

struct ShipHullCatalogItem: Identifiable, Sendable {
    let id: String
    let name: String
    let roleTitle: String
    let summary: String
    let priceCR: Int
    let cargoCapacity: Int
    let baseShieldHP: Float
    let baseHullHP: Float
    let tractorRangeMetres: Double
    let miningYieldBonus: Int
    let jumpRangeBonusLY: Double
    let weaponDamageMultiplier: Float
    let flightSpec: ShipSpec

    var artworkAssetName: String {
        switch id {
        case "sf2a_viper": return "art_ship_viper"
        case "sf4c_cobra": return "art_ship_cobra"
        case "sf7t_atlas": return "art_ship_atlas"
        case "sf9x_astrolabe": return "art_ship_astrolabe"
        default: return "art_ship_kestrel"
        }
    }
}

struct CommodityItem: Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let basePriceCR: Int
    let producedBy: Economy
    let consumedBy: Economy

    var exportHintText: String {
        "PRODUCED BY \(producedBy.rawValue.uppercased()) → EXPORT TO \(consumedBy.rawValue.uppercased()) (+34%)"
    }
}

struct StationMarketListing: Identifiable, Sendable {
    let id: String
    let commodity: CommodityItem
    let buyPriceCR: Int
    let sellPriceCR: Int
    let supplyTag: String
}

enum SoloContractKind: String, Codable, Sendable {
    case bounty = "BOUNTY SWEEP"
    case mining = "MINING QUOTA"
    case salvage = "SALVAGE RECOVERY"
}

struct SoloContractMission: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let rewardCR: Int
    let requiredKills: Int
    var currentKills: Int
    var contractKindRaw: String?

    var kind: SoloContractKind {
        SoloContractKind(rawValue: contractKindRaw ?? "") ?? .bounty
    }

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
    var currentHullID: String? = "sf1v_kestrel"
    var ownedHullIDs: [String]? = ["sf1v_kestrel"]
    var fuelTons: Float = 16.0
    var maxFuelTons: Float = 16.0
    var cargoCapacity: Int = 20
    var cargoHold: [String: Int] = [:]
    var fsdGrade: Int = 1        // 1..4 (Class D..A)
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

    // Live Procedural Radio Comms Ticker
    @Published var radioSender: String = "FLIGHT CONTROL"
    @Published var radioMessage: String = "Welcome to orbital space, Commander. Maintain safe speed inside the station perimeter."
    private var commsTimer: Float = 9.0
    private var commsIndex: Int = 0

    static let shipyardCatalog: [ShipHullCatalogItem] = [
        ShipHullCatalogItem(
            id: "sf1v_kestrel",
            name: "SF-1V Kestrel",
            roleTitle: "Light Multi-Role Scout",
            summary: "Balanced starter delta starfighter with nimble pitch authority and 20T modular cargo bay.",
            priceCR: 0,
            cargoCapacity: 20,
            baseShieldHP: 100.0,
            baseHullHP: 100.0,
            tractorRangeMetres: 130.0,
            miningYieldBonus: 1,
            jumpRangeBonusLY: 0.0,
            weaponDamageMultiplier: 1.0,
            flightSpec: ShipSpec.loadStarterSpec()
        ),
        ShipHullCatalogItem(
            id: "sf2a_viper",
            name: "SF-2A Viper",
            roleTitle: "Heavy Combat Interceptor",
            summary: "High-velocity bounty-hunting interceptor with twin overcharged hardpoints (+30% DPS) and 305 m/s cruise speed.",
            priceCR: 65_000,
            cargoCapacity: 18,
            baseShieldHP: 140.0,
            baseHullHP: 125.0,
            tractorRangeMetres: 145.0,
            miningYieldBonus: 1,
            jumpRangeBonusLY: 1.5,
            weaponDamageMultiplier: 1.30,
            flightSpec: ShipSpec(
                id: "sf2a_viper",
                name: "SF-2A Viper",
                shipClass: "Heavy Interceptor",
                maxSpeed: 305.0,
                reverseMaxSpeed: 150.0,
                boostSpeed: 495.0,
                forwardAcceleration: 118.0,
                reverseAcceleration: 78.0,
                lateralAcceleration: 84.0,
                verticalAcceleration: 84.0,
                pitchRateDeg: 74.0,
                rollRateDeg: 112.0,
                yawRateDeg: 66.0,
                angularResponse: 12.5,
                linearDampingFA: 6.0,
                boostDuration: 2.4,
                boostCooldown: 3.8,
                boostAcceleration: 255.0
            )
        ),
        ShipHullCatalogItem(
            id: "sf4c_cobra",
            name: "SF-4C Cobra Mk IV",
            roleTitle: "Medium Multi-Role Combat Trader",
            summary: "Iconic twin-strut frontier cruiser combining 48T cargo capacity, reinforced shields, and +20% weapon output.",
            priceCR: 145_000,
            cargoCapacity: 48,
            baseShieldHP: 180.0,
            baseHullHP: 175.0,
            tractorRangeMetres: 170.0,
            miningYieldBonus: 1,
            jumpRangeBonusLY: 3.5,
            weaponDamageMultiplier: 1.20,
            flightSpec: ShipSpec(
                id: "sf4c_cobra",
                name: "SF-4C Cobra Mk IV",
                shipClass: "Multi-Role Cruiser",
                maxSpeed: 278.0,
                reverseMaxSpeed: 135.0,
                boostSpeed: 460.0,
                forwardAcceleration: 98.0,
                reverseAcceleration: 68.0,
                lateralAcceleration: 70.0,
                verticalAcceleration: 70.0,
                pitchRateDeg: 64.0,
                rollRateDeg: 96.0,
                yawRateDeg: 60.0,
                angularResponse: 11.2,
                linearDampingFA: 5.6,
                boostDuration: 2.3,
                boostCooldown: 4.2,
                boostAcceleration: 230.0
            )
        ),
        ShipHullCatalogItem(
            id: "sf7t_atlas",
            name: "SF-7T Atlas Barge",
            roleTitle: "Industrial Miner & Heavy Freighter",
            summary: "Dedicated deep-belt mining & trade vessel with 100T cargo hold, 260m magnetic tractor array, and 2x ore extraction yield.",
            priceCR: 260_000,
            cargoCapacity: 100,
            baseShieldHP: 220.0,
            baseHullHP: 250.0,
            tractorRangeMetres: 260.0,
            miningYieldBonus: 2,
            jumpRangeBonusLY: 4.0,
            weaponDamageMultiplier: 1.15,
            flightSpec: ShipSpec(
                id: "sf7t_atlas",
                name: "SF-7T Atlas Barge",
                shipClass: "Industrial Miner & Hauler",
                maxSpeed: 235.0,
                reverseMaxSpeed: 115.0,
                boostSpeed: 395.0,
                forwardAcceleration: 82.0,
                reverseAcceleration: 58.0,
                lateralAcceleration: 62.0,
                verticalAcceleration: 62.0,
                pitchRateDeg: 54.0,
                rollRateDeg: 80.0,
                yawRateDeg: 52.0,
                angularResponse: 9.8,
                linearDampingFA: 5.2,
                boostDuration: 2.2,
                boostCooldown: 4.6,
                boostAcceleration: 195.0
            )
        ),
        ShipHullCatalogItem(
            id: "sf9x_astrolabe",
            name: "SF-9X Astrolabe Corvette",
            roleTitle: "Endgame Deep-Space Flagship",
            summary: "Pinnacle gold-trimmed command corvette with 320 Shield/Hull, +50% weapon damage, +8 LY jump range, and 85T hold.",
            priceCR: 550_000,
            cargoCapacity: 85,
            baseShieldHP: 320.0,
            baseHullHP: 300.0,
            tractorRangeMetres: 240.0,
            miningYieldBonus: 2,
            jumpRangeBonusLY: 8.0,
            weaponDamageMultiplier: 1.50,
            flightSpec: ShipSpec(
                id: "sf9x_astrolabe",
                name: "SF-9X Astrolabe",
                shipClass: "Command Corvette",
                maxSpeed: 295.0,
                reverseMaxSpeed: 145.0,
                boostSpeed: 485.0,
                forwardAcceleration: 112.0,
                reverseAcceleration: 76.0,
                lateralAcceleration: 78.0,
                verticalAcceleration: 78.0,
                pitchRateDeg: 68.0,
                rollRateDeg: 102.0,
                yawRateDeg: 64.0,
                angularResponse: 11.8,
                linearDampingFA: 5.8,
                boostDuration: 2.6,
                boostCooldown: 3.6,
                boostAcceleration: 250.0
            )
        )
    ]

    static let allCommodities: [CommodityItem] = [
        CommodityItem(id: "titanium", name: "Titanium", category: "Metals", basePriceCR: 1_120, producedBy: .refinery, consumedBy: .highTech),
        CommodityItem(id: "superconductors", name: "Superconductors", category: "Materials", basePriceCR: 6_450, producedBy: .refinery, consumedBy: .highTech),
        CommodityItem(id: "quantum_processors", name: "Quantum Processors", category: "Technology", basePriceCR: 8_900, producedBy: .highTech, consumedBy: .industrial),
        CommodityItem(id: "medical_diagnostics", name: "Medical Diagnostic Gear", category: "Technology", basePriceCR: 4_200, producedBy: .highTech, consumedBy: .colony),
        CommodityItem(id: "robotics", name: "Autonomous Robotics", category: "Machinery", basePriceCR: 3_150, producedBy: .industrial, consumedBy: .extraction),
        CommodityItem(id: "power_generators", name: "Fusion Generators", category: "Machinery", basePriceCR: 2_600, producedBy: .industrial, consumedBy: .agriculture),
        CommodityItem(id: "agri_medicines", name: "Agri-Biotech Supplies", category: "Foods & Bio", basePriceCR: 1_850, producedBy: .agriculture, consumedBy: .extraction),
        CommodityItem(id: "painite_ore", name: "Core Crystal Ore", category: "Minerals (Mined)", basePriceCR: 11_400, producedBy: .extraction, consumedBy: .refinery),
        CommodityItem(id: "void_opals", name: "Void Opal Crystals", category: "Deep Minerals (Mined)", basePriceCR: 16_800, producedBy: .extraction, consumedBy: .highTech),
        CommodityItem(id: "salvage_core", name: "Ancient Salvage Core", category: "Recovered Salvage", basePriceCR: 14_200, producedBy: .colony, consumedBy: .highTech)
    ]

    init() {
        loadFromDisk()
        syncHullCapacity()
        if data.activeMissions.count < 3 {
            seedStarterMissions()
        }
    }

    var activeHull: ShipHullCatalogItem {
        let id = data.currentHullID ?? "sf1v_kestrel"
        return Self.shipyardCatalog.first(where: { $0.id == id }) ?? Self.shipyardCatalog[0]
    }

    func isHullOwned(_ hullID: String) -> Bool {
        (data.ownedHullIDs ?? ["sf1v_kestrel"]).contains(hullID)
    }

    var jumpRangeLY: Double {
        let base: Double
        switch data.fsdGrade {
        case 1: base = 12.0
        case 2: base = 16.5
        case 3: base = 21.0
        default: base = 27.5
        }
        return base + activeHull.jumpRangeBonusLY
    }

    var shieldBonusMultiplier: Float {
        let hullRatio = activeHull.baseShieldHP / 100.0
        let moduleMult = 1.0 + Float(data.shieldGrade - 1) * 0.25
        return hullRatio * moduleMult
    }

    var weaponBonusMultiplier: Float {
        let moduleMult = 1.0 + Float(data.weaponGrade - 1) * 0.25
        return activeHull.weaponDamageMultiplier * moduleMult
    }

    var thrusterBonusMultiplier: Float {
        1.0 + Float(data.thrusterGrade - 1) * 0.10
    }

    var tractorRangeMetres: Double {
        activeHull.tractorRangeMetres
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

    func postRadioComms(sender: String, message: String) {
        radioSender = sender
        radioMessage = message
        commsTimer = 11.0
    }

    func stepCommsTicker(dt: Float, systemName: String, stationName: String, securityText: String) {
        commsTimer -= dt
        guard commsTimer <= 0.0 else { return }
        commsTimer = 14.0
        commsIndex += 1

        let chatter: [(String, String)] = [
            ("\(stationName.uppercased()) CONTROL", "Heavy Hauler CSV-Demeter cleared for Approach Lane 04. Maintain 100 m/s inside perimeter."),
            ("MINING BARGE [BELT ALPHA]", "Cracked a high-purity Void Opal motherlode in the Asteroid Belt—tractor beams at full capacity!"),
            ("\(systemName.uppercased()) AUTHORITY", "Security status \(securityText). All pilots report rogue drone telemetry immediately."),
            ("CONVOY ESCORT [NAV BEACON]", "Trade lane to \(stationName) is green. Watch for pirate interceptors near the Forsaken Hulk."),
            ("DEEP SALVAGE CREW", "Picking up encrypted black-box transponders near the Unidentified Signal Source."),
            ("TRADER COMM-LINK", "High-Tech systems are paying top credit for Void Opals, Superconductors, and Salvage Cores today.")
        ]
        let pick = chatter[commsIndex % chatter.count]
        radioSender = pick.0
        radioMessage = pick.1
    }

    func recordPirateKill(callsign: String, isBoss: Bool = false) {
        let bounty = isBoss ? 25_000 : 12_500
        data.totalKills += 1
        data.unclaimedBountiesCR += bounty
        for i in data.activeMissions.indices {
            if data.activeMissions[i].kind == .bounty && data.activeMissions[i].currentKills < data.activeMissions[i].requiredKills {
                data.activeMissions[i].currentKills += 1
            }
        }
        postBanner("TARGET DESTROYED (\(callsign)) • +\(bounty) CR BOUNTY VOUCHER", duration: 4.2)
        if isBoss {
            postRadioComms(sender: "SYSTEM AUTHORITY", message: "Confirmed kill on Wanted Dread-Leader \(callsign)! Bounty voucher logged.")
        }
        saveToDisk()
    }

    func collectCanister(commodityID: String, label: String, isMiningOre: Bool) {
        let yieldTons = isMiningOre ? activeHull.miningYieldBonus : 1
        let spaceLeft = max(0, data.cargoCapacity - cargoUsedTons)
        guard spaceLeft > 0 else {
            postBanner("CARGO HOLD FULL (\(data.cargoCapacity) T) • SELL CARGO AT STARPORT", duration: 3.5)
            return
        }
        let added = min(spaceLeft, yieldTons)
        data.cargoHold[commodityID, default: 0] += added

        let targetKind: SoloContractKind = isMiningOre ? .mining : .salvage
        for i in data.activeMissions.indices {
            if data.activeMissions[i].kind == targetKind && data.activeMissions[i].currentKills < data.activeMissions[i].requiredKills {
                data.activeMissions[i].currentKills = min(
                    data.activeMissions[i].requiredKills,
                    data.activeMissions[i].currentKills + added
                )
            }
        }

        CockpitAudioManager.shared.playTractorScoop()
        postBanner("TRACTOR SCOOP: +\(added)T \(label.uppercased()) (\(cargoUsedTons)/\(data.cargoCapacity) T)", duration: 3.5)
        saveToDisk()
    }

    func buyOrActivateShip(_ hull: ShipHullCatalogItem) -> Bool {
        var owned = data.ownedHullIDs ?? ["sf1v_kestrel"]
        if owned.contains(hull.id) {
            data.currentHullID = hull.id
            syncHullCapacity()
            postBanner("SHIPYARD: BOARDED \(hull.name.uppercased())")
            saveToDisk()
            return true
        }

        guard data.credits >= hull.priceCR else {
            postBanner("INSUFFICIENT CREDITS FOR \(hull.name.uppercased())")
            return false
        }

        data.credits -= hull.priceCR
        owned.append(hull.id)
        data.ownedHullIDs = owned
        data.currentHullID = hull.id
        syncHullCapacity()
        postBanner("SHIPYARD: PURCHASED & BOARDED \(hull.name.uppercased())!")
        saveToDisk()
        return true
    }

    private func syncHullCapacity() {
        data.cargoCapacity = activeHull.cargoCapacity
        if data.ownedHullIDs == nil {
            data.ownedHullIDs = ["sf1v_kestrel"]
        }
        if data.currentHullID == nil {
            data.currentHullID = "sf1v_kestrel"
        }
    }

    func redeemBounties() -> Int {
        let amount = data.unclaimedBountiesCR
        guard amount > 0 else { return 0 }
        data.credits += amount
        data.unclaimedBountiesCR = 0
        CockpitAudioManager.shared.playTractorScoop()
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
        CockpitAudioManager.shared.playTractorScoop()
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
                supplyTag = "HIGH SUPPLY (BUY CHEAP)"
            } else if item.consumedBy == economy {
                priceMultiplier = 1.36 * jitterFactor
                supplyTag = "HIGH DEMAND (SELL HIGH)"
            } else {
                priceMultiplier = 1.00 * jitterFactor
                supplyTag = "BALANCED MARKET"
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
        data.tradeProfitCR += max(450, profit)
        CockpitAudioManager.shared.playTractorScoop()
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
        CockpitAudioManager.shared.playTractorScoop()
        postBanner("OUTFITTING INSTALLED: \(kind) UPGRADED TO CLASS \(gradeLetter(for: kind))")
        saveToDisk()
    }

    private func gradeLetter(for kind: String) -> String {
        let g: Int
        switch kind {
        case "FSD": g = data.fsdGrade
        case "SHIELD": g = data.shieldGrade
        case "THRUSTER": g = data.thrusterGrade
        default: g = data.weaponGrade
        }
        switch g {
        case 1: return "D"
        case 2: return "C"
        case 3: return "B"
        default: return "A"
        }
    }

    private func seedStarterMissions() {
        let existingIDs = Set(data.activeMissions.map(\.id))
        let pool: [SoloContractMission] = [
            SoloContractMission(
                id: "msn_bounty_1",
                title: "PATROL SWEEP: ELIMINATE 2 PIRATES",
                description: "Destroy 2 wanted pirate drones in the HazRES or station perimeter.",
                rewardCR: 28_000,
                requiredKills: 2,
                currentKills: 0,
                contractKindRaw: SoloContractKind.bounty.rawValue
            ),
            SoloContractMission(
                id: "msn_mining_1",
                title: "MINING QUOTA: EXTRACT 3T ASTEROID ORE",
                description: "Warp to Asteroid Belt Alpha, blast mineral rocks with lasers, and tractor-scoop 3 canisters of ore.",
                rewardCR: 36_000,
                requiredKills: 3,
                currentKills: 0,
                contractKindRaw: SoloContractKind.mining.rawValue
            ),
            SoloContractMission(
                id: "msn_salvage_1",
                title: "SALVAGE OP: RECOVER 2 WRECK CORES",
                description: "Tractor-scoop 2 salvage canisters from destroyed raiders, derelict hulks, or Signal Sources.",
                rewardCR: 32_000,
                requiredKills: 2,
                currentKills: 0,
                contractKindRaw: SoloContractKind.salvage.rawValue
            )
        ]

        for m in pool where !existingIDs.contains(m.id) && data.activeMissions.count < 3 {
            data.activeMissions.append(m)
        }
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
