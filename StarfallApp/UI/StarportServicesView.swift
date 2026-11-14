import SwiftUI
import StarfallGalaxy

enum StarportServiceTab: String, CaseIterable, Identifiable {
    case commodities = "COMMODITIES MARKET"
    case missions = "MISSION BOARD"
    case outfitting = "OUTFITTING"

    var id: String { rawValue }
}

struct StarportServicesView: View {
    @ObservedObject var commander: CommanderProfile
    @ObservedObject var navManager: NavigationWaypointManager
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
                        listings: marketItems
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
    let credits: Int
    @Binding var selectedTab: StarportServiceTab
    let onLaunchShip: () -> Void

    private var subText: String {
        "\(systemName.uppercased()) SYSTEM • \(economyName.uppercased()) ECONOMY • LANDING PAD 04"
    }

    private var creditsText: String {
        "\(credits) CR"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("STARPORT SERVICES — \(stationName.uppercased())")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(subText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }

            Spacer()

            HStack(spacing: 8) {
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
                Text("LAUNCH SHIP")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 14)
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
                .padding(.horizontal, 12)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMANDER STATUS")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(.orange)

            CommanderStatLine(label: "PILOT", value: commander.data.commanderName, color: .cyan)
            CommanderStatLine(label: "BALANCE", value: "\(commander.data.credits) CR", color: .yellow)
            CommanderStatLine(label: "COMBAT RANK", value: commander.combatRankTitle, color: .orange)
            CommanderStatLine(label: "TRADE RANK", value: commander.tradeRankTitle, color: .mint)
            CommanderStatLine(label: "EXPLORER", value: commander.explorerRankTitle, color: .cyan)
            CommanderStatLine(label: "CARGO HOLD", value: cargoStatusText, color: .white)
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
            case .outfitting:
                OutfittingWorkshopPane(commander: commander)
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
            Text("COMMODITIES EXCHANGE • BUY LOW AT PRODUCERS, SELL HIGH AT CONSUMERS")
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
        if listing.supplyTag.contains("PROFIT") { return .cyan }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.commodity.name.uppercased())
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("\(listing.commodity.category) • \(listing.supplyTag)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(tagColor)
            }

            Spacer()

            Text("IN HOLD: \(inHold) T")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .frame(width: 110, alignment: .trailing)

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
                    .background(inHold > 0 ? Color.green.opacity(0.26) : Color.white.opacity(0.06))
                    .foregroundStyle(inHold > 0 ? .green : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(inHold == 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MissionBoardPane: View {
    @ObservedObject var commander: CommanderProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPERATIONS & SOLO BOUNTY CONTRACTS")
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
        "PROGRESS: \(mission.currentKills) / \(mission.requiredKills) KILLS • REWARD: \(mission.rewardCR) CR"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHIP OUTFITTING WORKSHOP — SF-1V KESTREL")
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
                    .background(isMaxed ? Color.white.opacity(0.08) : Color.orange.opacity(0.26))
                    .foregroundStyle(isMaxed ? .secondary : .orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(isMaxed)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
