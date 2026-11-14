import SwiftUI
import StarfallGalaxy

enum StarportServiceTab: String, CaseIterable, Identifiable {
    case commodities = "COMMODITIES"
    case missions = "MISSION BOARD"
    case shipyard = "SHIPYARD"
    case outfitting = "OUTFITTING"
    case codex = "CODEX & LORE"

    var id: String { rawValue }
}

struct StarportServicesView: View {
    @ObservedObject var commander: CommanderProfile
    @ObservedObject var navManager: NavigationWaypointManager
    let onShipChanged: (ShipHullCatalogItem) -> Void
    let onRepairAndRefuel: () -> Void
    let onLaunchShip: () -> Void

    @State private var selectedTab: StarportServiceTab = .commodities

    private var marketItems: [StationMarketListing] {
        let seed = abs(navManager.primaryStationName.hashValue % 997)
        return commander.marketListings(for: navManager.primaryEconomy, stationSeed: seed)
    }

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                StarportHeaderBar(
                    stationName: navManager.primaryStationName,
                    systemName: navManager.currentSystem.name,
                    economyName: navManager.primaryEconomy.rawValue,
                    securityText: navManager.primarySecurityText,
                    credits: commander.data.credits,
                    selectedTab: $selectedTab,
                    onLaunchShip: onLaunchShip
                )

                HStack(spacing: 14) {
                    StarportLeftHangarColumn(
                        commander: commander,
                        onRepairAndRefuel: onRepairAndRefuel,
                        onLaunchShip: onLaunchShip
                    )
                    .frame(width: 310)

                    StarportRightMainPane(
                        selectedTab: selectedTab,
                        commander: commander,
                        listings: marketItems,
                        onShipChanged: onShipChanged
                    )
                }
            }
            .padding(18)
        }
    }
}

private struct StarportHeaderBar: View {
    let stationName: String
    let systemName: String
    let economyName: String
    let securityText: String
    let credits: Int
    @Binding var selectedTab: StarportServiceTab
    let onLaunchShip: () -> Void

    private var subText: String {
        "\(systemName.uppercased()) (\(securityText)) • \(economyName.uppercased()) ECONOMY"
    }

    private var creditsText: String {
        "\(credits) CR"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("STARPORT SERVICES — \(stationName.uppercased())")
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(subText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(StarportServiceTab.allCases) { tab in
                    StarportTabButton(
                        title: tab.rawValue,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
            }

            Spacer()

            Text(creditsText)
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(.yellow)

            Button(action: onLaunchShip) {
                Text("LAUNCH")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.orange.opacity(0.30))
                    .foregroundStyle(.orange)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.orange, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.60), lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct StarportTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private var bgColor: Color {
        isSelected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06)
    }

    private var fgColor: Color {
        isSelected ? .cyan : .secondary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(bgColor)
                .foregroundStyle(fgColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct StarportLeftHangarColumn: View {
    @ObservedObject var commander: CommanderProfile
    let onRepairAndRefuel: () -> Void
    let onLaunchShip: () -> Void

    private var bountyBtnTitle: String {
        "REDEEM BOUNTIES (+\(commander.data.unclaimedBountiesCR) CR)"
    }

    private var hasBounties: Bool {
        commander.data.unclaimedBountiesCR > 0
    }

    private var bountyColor: Color {
        hasBounties ? .green : .secondary
    }

    private var cargoStatusText: String {
        "\(commander.cargoUsedTons) / \(commander.data.cargoCapacity) T"
    }

    private var jumpRangeText: String {
        String(format: "%.1f LY", commander.jumpRangeLY)
    }

    private var tractorRangeText: String {
        String(format: "%.0f m", commander.tractorRangeMetres)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                Image(commander.activeHull.artworkAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 112)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(commander.activeHull.name.uppercased())
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text(commander.activeHull.roleTitle.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.55), lineWidth: 1.2)
            )

            Text("COMMANDER & ACTIVE HULL")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(.orange)

            CommanderStatLine(label: "PILOT", value: commander.data.commanderName, color: .cyan)
            CommanderStatLine(label: "ACTIVE SHIP", value: commander.activeHull.name, color: .orange)
            CommanderStatLine(label: "BALANCE", value: "\(commander.data.credits) CR", color: .yellow)
            CommanderStatLine(label: "COMBAT RANK", value: commander.combatRankTitle, color: .orange)
            CommanderStatLine(label: "TRADE RANK", value: commander.tradeRankTitle, color: .mint)
            CommanderStatLine(label: "EXPLORER", value: commander.explorerRankTitle, color: .cyan)
            CommanderStatLine(label: "CARGO HOLD", value: cargoStatusText, color: .white)
            CommanderStatLine(label: "TRACTOR BEAM", value: tractorRangeText, color: .mint)
            CommanderStatLine(label: "FSD RANGE", value: jumpRangeText, color: .cyan)

            Divider()
                .overlay(Color.orange.opacity(0.35))

            Text("STATION CONTACTS")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            Button(action: onRepairAndRefuel) {
                Text("REFUEL & REPAIR HULL (FREE)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.cyan.opacity(0.22))
                    .foregroundStyle(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button {
                _ = commander.redeemBounties()
            } label: {
                Text(bountyBtnTitle)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(bountyColor.opacity(0.22))
                    .foregroundStyle(bountyColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(!hasBounties)

            Spacer()

            Text(commander.statusBannerMessage)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.mint)
                .lineLimit(2)

            Button(action: onLaunchShip) {
                Text("UNDOCK & LAUNCH TO ORBIT")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.orange.opacity(0.28))
                    .foregroundStyle(.orange)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct CommanderStatLine: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

private struct StarportRightMainPane: View {
    let selectedTab: StarportServiceTab
    @ObservedObject var commander: CommanderProfile
    let listings: [StationMarketListing]
    let onShipChanged: (ShipHullCatalogItem) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.82))
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.45), lineWidth: 1.3)

            switch selectedTab {
            case .commodities:
                CommoditiesMarketPane(commander: commander, listings: listings)
            case .missions:
                MissionBoardPane(commander: commander)
            case .shipyard:
                ShipyardCatalogPane(commander: commander, onShipChanged: onShipChanged)
            case .outfitting:
                OutfittingWorkshopPane(commander: commander)
            case .codex:
                CodexAndHandbookPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommoditiesMarketPane: View {
    @ObservedObject var commander: CommanderProfile
    let listings: [StationMarketListing]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMODITIES EXCHANGE • SELL MINED ORE, SALVAGE CORES & TRADE GOODS")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(listings) { item in
                        CommodityRowView(
                            listing: item,
                            inHold: commander.data.cargoHold[item.id, default: 0],
                            onBuy: { commander.buyCommodity(item) },
                            onSell: { commander.sellCommodity(item) }
                        )
                    }
                }
            }
        }
        .padding(14)
    }
}

private struct CommodityRowView: View {
    let listing: StationMarketListing
    let inHold: Int
    let onBuy: () -> Void
    let onSell: () -> Void

    private var tagColor: Color {
        if listing.supplyTag.contains("CHEAP") { return .green }
        if listing.supplyTag.contains("HIGH") { return .cyan }
        return .secondary
    }

    private var sellBgColor: Color {
        inHold > 0 ? Color.green.opacity(0.26) : Color.white.opacity(0.06)
    }

    private var sellFgColor: Color {
        inHold > 0 ? .green : .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.commodity.name.uppercased())
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("\(listing.commodity.category) • \(listing.supplyTag)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tagColor)
                Text(listing.commodity.exportHintText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("HOLD: \(inHold) T")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .frame(width: 95, alignment: .trailing)

            Button(action: onBuy) {
                Text("BUY \(listing.buyPriceCR) CR")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.24))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button(action: onSell) {
                Text("SELL \(listing.sellPriceCR) CR")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(sellBgColor)
                    .foregroundStyle(sellFgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(inHold == 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ShipyardCatalogPane: View {
    @ObservedObject var commander: CommanderProfile
    let onShipChanged: (ShipHullCatalogItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STARPORT SHIPYARD — 5 SPECIALIZED HULLS (OWNED SHIPS STORED IN HANGAR)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(CommanderProfile.shipyardCatalog) { hull in
                        ShipyardHullCardView(
                            hull: hull,
                            isActive: commander.activeHull.id == hull.id,
                            isOwned: commander.isHullOwned(hull.id),
                            onSelect: {
                                if commander.buyOrActivateShip(hull) {
                                    onShipChanged(hull)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(14)
    }
}

private struct ShipyardHullCardView: View {
    let hull: ShipHullCatalogItem
    let isActive: Bool
    let isOwned: Bool
    let onSelect: () -> Void

    private var specsLine: String {
        let spd = Int(hull.flightSpec.maxSpeed)
        let bst = Int(hull.flightSpec.boostSpeed)
        let shd = Int(hull.baseShieldHP)
        let trc = Int(hull.tractorRangeMetres)
        return "SPEED \(spd)/\(bst) m/s • SHIELD \(shd) • CARGO \(hull.cargoCapacity)T • TRACTOR \(trc)m • MINING \(hull.miningYieldBonus)x"
    }

    private var btnTitle: String {
        if isActive { return "ACTIVE SHIP" }
        if isOwned { return "BOARD SHIP" }
        return "BUY (\(hull.priceCR) CR)"
    }

    private var btnBgColor: Color {
        if isActive { return Color.cyan.opacity(0.24) }
        if isOwned { return Color.green.opacity(0.26) }
        return Color.orange.opacity(0.26)
    }

    private var btnFgColor: Color {
        if isActive { return .cyan }
        if isOwned { return .green }
        return .orange
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(hull.artworkAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 132, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(btnFgColor.opacity(0.65), lineWidth: 1.3)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(hull.name.uppercased())
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(hull.roleTitle.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
                Text(hull.summary)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(specsLine)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button(action: onSelect) {
                Text(btnTitle)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(btnBgColor)
                    .foregroundStyle(btnFgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(isActive)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MissionBoardPane: View {
    @ObservedObject var commander: CommanderProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPERATIONS BOARD — BOUNTY, ASTEROID MINING & SALVAGE CONTRACTS")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            ForEach(commander.data.activeMissions) { mission in
                MissionContractCardView(
                    mission: mission,
                    onClaim: { commander.claimCompletedMission(mission.id) }
                )
            }
            Spacer()
        }
        .padding(14)
    }
}

private struct MissionContractCardView: View {
    let mission: SoloContractMission
    let onClaim: () -> Void

    private var progressText: String {
        "\(mission.kind.rawValue) • PROGRESS: \(mission.currentKills) / \(mission.requiredKills) • REWARD: \(mission.rewardCR) CR"
    }

    private var btnColor: Color {
        mission.isCompleted ? .green : .secondary
    }

    private var btnTitle: String {
        mission.isCompleted ? "CLAIM +\(mission.rewardCR) CR" : "IN PROGRESS"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mission.title)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.cyan)
                Text(mission.description)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(progressText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button(action: onClaim) {
                Text(btnTitle)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(btnColor.opacity(0.24))
                    .foregroundStyle(btnColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(!mission.isCompleted)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OutfittingWorkshopPane: View {
    @ObservedObject var commander: CommanderProfile

    private var headerText: String {
        "SHIP OUTFITTING WORKSHOP — \(commander.activeHull.name.uppercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerText)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            OutfittingUpgradeRow(
                title: "FRAME SHIFT DRIVE (JUMP RANGE)",
                currentGrade: commander.data.fsdGrade,
                costCR: 18_000,
                onUpgrade: { commander.upgradeModule(kind: "FSD", costCR: 18_000) }
            )
            OutfittingUpgradeRow(
                title: "BI-WEAVE SHIELD GENERATOR",
                currentGrade: commander.data.shieldGrade,
                costCR: 15_000,
                onUpgrade: { commander.upgradeModule(kind: "SHIELD", costCR: 15_000) }
            )
            OutfittingUpgradeRow(
                title: "A-RATED VECTOR THRUSTERS",
                currentGrade: commander.data.thrusterGrade,
                costCR: 16_000,
                onUpgrade: { commander.upgradeModule(kind: "THRUSTER", costCR: 16_000) }
            )
            OutfittingUpgradeRow(
                title: "OVERCHARGED GIMBAL WEAPON ARRAY",
                currentGrade: commander.data.weaponGrade,
                costCR: 20_000,
                onUpgrade: { commander.upgradeModule(kind: "WEAPON", costCR: 20_000) }
            )
            Spacer()
        }
        .padding(14)
    }
}

private struct OutfittingUpgradeRow: View {
    let title: String
    let currentGrade: Int
    let costCR: Int
    let onUpgrade: () -> Void

    private var classLetter: String {
        switch currentGrade {
        case 1: return "CLASS D (STOCK)"
        case 2: return "CLASS C"
        case 3: return "CLASS B"
        default: return "CLASS A (MAX)"
        }
    }

    private var isMaxed: Bool {
        currentGrade >= 4
    }

    private var btnTitle: String {
        isMaxed ? "MAX CLASS A" : "UPGRADE (\(costCR) CR)"
    }

    private var btnBgColor: Color {
        isMaxed ? Color.white.opacity(0.08) : Color.orange.opacity(0.26)
    }

    private var btnFgColor: Color {
        isMaxed ? .secondary : .orange
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("INSTALLED: \(classLetter)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            Spacer()
            Button(action: onUpgrade) {
                Text(btnTitle)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(btnBgColor)
                    .foregroundStyle(btnFgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(isMaxed)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CodexEntryItem: Identifiable {
    let id: String
    let category: String
    let title: String
    let bodyText: String
    let artworkName: String
}

private struct CodexAndHandbookPane: View {
    private static let entries: [CodexEntryItem] = [
        CodexEntryItem(
            id: "guide_flight",
            category: "PILOT'S HANDBOOK • FLIGHT & DOGFIGHTING",
            title: "BLUE-ZONE AGILITY & POWER DISTRIBUTOR PIPS (SYS / ENG / WEP)",
            bodyText: "Keep your throttle inside the glowing cyan Blue Zone (40%–65%) during dogfights for a +35% pitch and yaw turn-rate boost. Use D-Pad (or touch SYS/ENG/WEP buttons) to route reactor power: 4 Pips to SYS cuts incoming shield damage by 52% and speeds shield regen; 4 Pips to ENG maximizes cruise speed and boost recharge; 4 Pips to WEP keeps your Pulse Lasers and Multi-Cannons firing continuously.",
            artworkName: "art_ship_viper"
        ),
        CodexEntryItem(
            id: "guide_overview",
            category: "PILOT'S HANDBOOK • EVE TACTICAL OVERVIEW",
            title: "USING THE COLLAPSIBLE RIGHT-HAND TACTICAL OVERVIEW",
            bodyText: "Tap any contact in the top-right EVE Overview list (Pirates, Mineable Asteroids, Ore Canisters, Stations, or Signal Sources) and tap APPROACH or ORBIT 500M to engage hands-free flight assist. Touching the flight stick at any time immediately returns you to manual control.",
            artworkName: "art_ship_cobra"
        ),
        CodexEntryItem(
            id: "guide_mining",
            category: "PILOT'S HANDBOOK • ASTEROID MINING & SALVAGE",
            title: "THERMAL LASER MINING & MAGNETIC TRACTOR SCOOP",
            bodyText: "Supercruise to Asteroid Belt Alpha or a Crystalline Anomaly and fire your Pulse Lasers at mineral-rich asteroids (Titanium, Core Crystal, or Void Opals). At 50% and 0% rock integrity, glowing 3D Ore Canisters fracture into space. Fly within 130m–260m (or tap TRACTOR on the Overview) to beam canisters into your hold.",
            artworkName: "art_ship_atlas"
        ),
        CodexEntryItem(
            id: "lore_sol",
            category: "GALNET ARCHIVE • 3312 HUMAN BUBBLE",
            title: "THE SOL CORRIDOR & GAGARIN GATEWAY",
            bodyText: "Following the activation of the first Frame Shift Witch-Space conduits, humanity expanded across the 20-light-year Solar Neighbourhood. Gagarin Gateway in high Earth orbit serves as the primary High-Tech logistics ring for independent Commanders licensed by the Pilots' Guild.",
            artworkName: "art_starport_concourse"
        ),
        CodexEntryItem(
            id: "lore_forsaken",
            category: "GALNET ARCHIVE • FRONTIER MYSTERIES",
            title: "THE FORSAKEN RELAY INCIDENT & ROGUE DRONE SWARMS",
            bodyText: "Deep-space telemetry relays across Barnard's Star, Wolf 359, and Sol have gone dark following raids by autonomous 'Vortex' aggressor wings. Salvage crews recovering Ancient Salvage Cores from shattered relay hulks report encrypted navigational beacons pointing toward uncharted sectors.",
            artworkName: "art_codex_hyperdrive"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMANDER'S CODEX, PILOT'S HANDBOOK & GALNET ARCHIVES")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Self.entries) { entry in
                        CodexEntryCardView(entry: entry)
                    }
                }
            }
        }
        .padding(14)
    }
}

private struct CodexEntryCardView: View {
    let entry: CodexEntryItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(entry.artworkName)
                .resizable()
                .scaledToFill()
                .frame(width: 148, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.cyan.opacity(0.55), lineWidth: 1.2)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.category)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Text(entry.title)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(entry.bodyText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
