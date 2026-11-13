import SwiftUI
import simd
import StarfallGalaxy

enum HoloMapTab: String, CaseIterable, Identifiable {
    case sectorGrid = "LOCAL SECTOR GRID"
    case systemOrrery = "SOL SYSTEM ORRERY"
    case galaxyChart = "GALAXY STAR CHART"

    var id: String { rawValue }
}

struct HoloNavigationMapView: View {
    @ObservedObject var navManager: NavigationWaypointManager
    let playerWorldPosition: SIMD3<Double>
    let isMassLocked: Bool
    let onEngageLocalJump: (NavigationWaypoint) -> Void
    let onClose: () -> Void

    @State private var selectedTab: HoloMapTab = .sectorGrid
    @State private var inspectedWaypoint: NavigationWaypoint?

    private var currentWaypoint: NavigationWaypoint {
        inspectedWaypoint ?? navManager.activeWaypoint
    }

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HoloMapHeaderBar(
                    selectedTab: $selectedTab,
                    activeWaypointName: navManager.activeWaypoint.name,
                    onClose: onClose
                )

                HStack(spacing: 14) {
                    HoloMapLeftCanvasContainer(
                        selectedTab: selectedTab,
                        navManager: navManager,
                        currentWaypoint: currentWaypoint,
                        onSelect: { wp in
                            inspectedWaypoint = wp
                            navManager.selectWaypoint(wp)
                        }
                    )

                    VStack(spacing: 12) {
                        WaypointDirectoryPanel(
                            waypoints: waypointsForCurrentTab,
                            activeWaypointID: navManager.activeWaypoint.id,
                            inspectedWaypointID: currentWaypoint.id,
                            playerWorldPosition: playerWorldPosition,
                            onSelect: { wp in
                                inspectedWaypoint = wp
                                navManager.selectWaypoint(wp)
                            }
                        )

                        WaypointInspectorCard(
                            waypoint: currentWaypoint,
                            isLocked: currentWaypoint.id == navManager.activeWaypoint.id,
                            distanceText: distanceString(for: currentWaypoint),
                            isMassLocked: isMassLocked,
                            routeSummary: routeSummaryText,
                            onLockWaypoint: {
                                navManager.selectWaypoint(currentWaypoint)
                            },
                            onJumpNow: {
                                navManager.selectWaypoint(currentWaypoint)
                                onEngageLocalJump(currentWaypoint)
                                onClose()
                            }
                        )
                    }
                    .frame(width: 360)
                }
            }
            .padding(18)
        }
        .onAppear {
            inspectedWaypoint = navManager.activeWaypoint
        }
    }

    private var waypointsForCurrentTab: [NavigationWaypoint] {
        switch selectedTab {
        case .sectorGrid:
            return navManager.localWaypoints + Array(navManager.systemBodyWaypoints.prefix(3))
        case .systemOrrery:
            return navManager.localWaypoints + navManager.systemBodyWaypoints
        case .galaxyChart:
            return navManager.nearbyStarWaypoints
        }
    }

    private var routeSummaryText: String? {
        guard !navManager.plottedRoute.isEmpty else { return nil }
        let names = navManager.plottedRoute.map(\.name).joined(separator: " → ")
        return "ROUTE (\(max(1, navManager.plottedRoute.count - 1)) JUMPS): \(names)"
    }

    private func distanceString(for wp: NavigationWaypoint) -> String {
        let d = simd_length(wp.worldPosition - playerWorldPosition)
        return NavigationWaypointManager.formatDistance(d)
    }
}

private struct HoloMapLeftCanvasContainer: View {
    let selectedTab: HoloMapTab
    @ObservedObject var navManager: NavigationWaypointManager
    let currentWaypoint: NavigationWaypoint
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.78))
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1.5)

            switch selectedTab {
            case .sectorGrid:
                LocalSectorGridCanvas(
                    waypoints: navManager.localWaypoints + Array(navManager.systemBodyWaypoints.prefix(3)),
                    activeWaypointID: navManager.activeWaypoint.id,
                    inspectedWaypointID: currentWaypoint.id,
                    onSelect: onSelect
                )
            case .systemOrrery:
                SolSystemOrreryCanvas(
                    waypoints: navManager.systemBodyWaypoints,
                    localWaypoints: navManager.localWaypoints,
                    activeWaypointID: navManager.activeWaypoint.id,
                    inspectedWaypointID: currentWaypoint.id,
                    onSelect: onSelect
                )
            case .galaxyChart:
                GalaxyStarChartCanvas(
                    starWaypoints: navManager.nearbyStarWaypoints,
                    activeWaypointID: navManager.activeWaypoint.id,
                    jumpRangeLY: navManager.jumpRangeLY,
                    onSelect: onSelect
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Header Bar

private struct HoloMapHeaderBar: View {
    @Binding var selectedTab: HoloMapTab
    let activeWaypointName: String
    let onClose: () -> Void

    private var lockedText: String {
        "LOCKED WAYPOINT: \(activeWaypointName.uppercased())"
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ASTROGATION & TACTICAL NAV CONSOLE")
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text(lockedText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(HoloMapTab.allCases) { tab in
                    HoloTabButton(
                        title: tab.rawValue,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
            }

            Spacer()

            Button(action: onClose) {
                Text("CLOSE [Y]")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.24))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct HoloTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private var bgColor: Color {
        isSelected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06)
    }

    private var fgColor: Color {
        isSelected ? .cyan : .secondary
    }

    private var strokeColor: Color {
        isSelected ? .cyan : Color.orange.opacity(0.3)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bgColor)
                .foregroundStyle(fgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(strokeColor, lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Tab 1: Local Sector 16x16 Tactical Grid

private struct LocalSectorGridCanvas: View {
    let waypoints: [NavigationWaypoint]
    let activeWaypointID: String
    let inspectedWaypointID: String
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad: CGFloat = 34
            let gridW = max(100, w - pad * 2)
            let gridH = max(100, h - pad * 2)
            let playerPt = Self.pointForSector(x: 8, y: 9, pad: pad, gridW: gridW, gridH: gridH)

            ZStack(alignment: .topLeading) {
                SectorGridLinesBackground(pad: pad, gridW: gridW, gridH: gridH, playerPt: playerPt)

                PlayerShipGridMarker()
                    .position(playerPt)

                ForEach(waypoints) { wp in
                    SectorNodeButton(
                        waypoint: wp,
                        isLocked: wp.id == activeWaypointID,
                        isInspected: wp.id == inspectedWaypointID,
                        action: { onSelect(wp) }
                    )
                    .position(Self.pointForSector(x: wp.sectorGridX, y: wp.sectorGridY, pad: pad, gridW: gridW, gridH: gridH))
                }

                SectorGridLegendHeader()
            }
        }
    }

    static func pointForSector(x: Int, y: Int, pad: CGFloat, gridW: CGFloat, gridH: CGFloat) -> CGPoint {
        let fx = (CGFloat(min(15, max(0, x))) + 0.5) / 16.0
        let fy = (CGFloat(min(15, max(0, y))) + 0.5) / 16.0
        return CGPoint(x: pad + fx * gridW, y: pad + fy * gridH)
    }
}

private struct SectorGridLinesBackground: View {
    let pad: CGFloat
    let gridW: CGFloat
    let gridH: CGFloat
    let playerPt: CGPoint

    var body: some View {
        ZStack {
            Path { path in
                for i in 0...16 {
                    let frac = CGFloat(i) / 16.0
                    let x = pad + frac * gridW
                    let y = pad + frac * gridH
                    path.move(to: CGPoint(x: x, y: pad))
                    path.addLine(to: CGPoint(x: x, y: pad + gridH))
                    path.move(to: CGPoint(x: pad, y: y))
                    path.addLine(to: CGPoint(x: pad + gridW, y: y))
                }
            }
            .stroke(Color.orange.opacity(0.16), lineWidth: 1.0)

            Circle()
                .stroke(Color.cyan.opacity(0.22), lineWidth: 1)
                .frame(width: 140, height: 140)
                .position(playerPt)

            Circle()
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                .frame(width: 280, height: 280)
                .position(playerPt)
        }
    }
}

private struct PlayerShipGridMarker: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.green)
            Text("YOU (SF-1V)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
        }
    }
}

private struct SectorGridLegendHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("EARTH ORBITAL SECTOR GRID (16×16) • TAP NODE TO SET WAYPOINT")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
            Text("[S] STATION   [▲] HOSTILE DRONES   [◇] BEACON / HULK   [●] CELESTIAL BODY")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }
}

private struct SectorNodeButton: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let isInspected: Bool
    let action: () -> Void

    private var labelColor: Color {
        isLocked ? .cyan : .white
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    if isLocked {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.cyan, lineWidth: 2.2)
                            .frame(width: 34, height: 34)
                            .rotationEffect(.degrees(45))
                    } else if isInspected {
                        Circle()
                            .stroke(Color.orange, lineWidth: 1.8)
                            .frame(width: 32, height: 32)
                    }

                    Circle()
                        .fill(waypoint.kind.color.opacity(0.28))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(waypoint.kind.color, lineWidth: 1.5)
                        )

                    Text(waypoint.kind.iconName)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(waypoint.kind.color)
                }

                Text(waypoint.name.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.85))
                    .foregroundStyle(labelColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 2: Sol System Holographic Orrery

private struct SolSystemOrreryCanvas: View {
    let waypoints: [NavigationWaypoint]
    let localWaypoints: [NavigationWaypoint]
    let activeWaypointID: String
    let inspectedWaypointID: String
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SOL SYSTEM HOLOGRAPHIC SCHEMATIC • TAP ANY BODY OR STATION TO LOCK WAYPOINT")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 18) {
                    ForEach(waypoints) { wp in
                        OrreryBodyNode(
                            waypoint: wp,
                            isLocked: wp.id == activeWaypointID,
                            isInspected: wp.id == inspectedWaypointID,
                            action: { onSelect(wp) }
                        )
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 10)
            }
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("EARTH ORBITAL INFRASTRUCTURE & COMBAT ZONES")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(localWaypoints) { wp in
                    OrreryLocalStationCard(
                        waypoint: wp,
                        isLocked: wp.id == activeWaypointID,
                        action: { onSelect(wp) }
                    )
                }
            }

            Spacer()
        }
        .padding(16)
    }
}

private struct OrreryLocalStationCard: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let action: () -> Void

    private var titleColor: Color {
        isLocked ? .cyan : .white
    }

    private var borderColor: Color {
        isLocked ? .cyan : Color.orange.opacity(0.35)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(waypoint.kind.iconName)
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(waypoint.kind.color)
                    .frame(width: 32, height: 32)
                    .background(waypoint.kind.color.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(waypoint.name.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(titleColor)
                    Text(waypoint.subtitle)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.black.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1.3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct OrreryBodyNode: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let isInspected: Bool
    let action: () -> Void

    private var circleDiameter: CGFloat {
        switch waypoint.kind {
        case .star: return 68
        case .planet:
            if waypoint.name == "Jupiter" || waypoint.name == "Saturn" { return 52 }
            if waypoint.name == "Uranus" || waypoint.name == "Neptune" { return 42 }
            return 34
        case .moon: return 22
        default: return 30
        }
    }

    private var nameColor: Color {
        isLocked ? .cyan : .white
    }

    private var cardBg: Color {
        isInspected ? Color.white.opacity(0.07) : Color.clear
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if isLocked {
                        Circle()
                            .stroke(Color.cyan, lineWidth: 2.2)
                            .frame(width: circleDiameter + 18, height: circleDiameter + 18)
                    } else if isInspected {
                        Circle()
                            .stroke(Color.orange, lineWidth: 1.8)
                            .frame(width: circleDiameter + 14, height: circleDiameter + 14)
                    }

                    Circle()
                        .fill(waypoint.kind.color.opacity(0.65))
                        .frame(width: circleDiameter, height: circleDiameter)
                        .overlay(
                            Circle().stroke(waypoint.kind.color, lineWidth: 1.5)
                        )
                }
                .frame(width: 88, height: 88)

                Text(waypoint.name.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(nameColor)

                Text(waypoint.kind.rawValue)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 3: Galaxy Star Chart

private struct GalaxyStarChartCanvas: View {
    let starWaypoints: [NavigationWaypoint]
    let activeWaypointID: String
    let jumpRangeLY: Double
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
            let scalePtsPerLY = min(geo.size.width, geo.size.height) / 34.0
            let jumpDiameter = CGFloat(jumpRangeLY) * scalePtsPerLY * 2.0

            ZStack(alignment: .topLeading) {
                Circle()
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                    .frame(width: scalePtsPerLY * 10.0, height: scalePtsPerLY * 10.0)
                    .position(center)

                Circle()
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                    .frame(width: scalePtsPerLY * 20.0, height: scalePtsPerLY * 20.0)
                    .position(center)

                Circle()
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1.5)
                    .frame(width: jumpDiameter, height: jumpDiameter)
                    .position(center)

                SolCenterNodeView()
                    .position(center)

                ForEach(starWaypoints) { wp in
                    GalaxyStarNodeButton(
                        waypoint: wp,
                        isLocked: wp.id == activeWaypointID,
                        center: center,
                        scalePtsPerLY: scalePtsPerLY,
                        action: { onSelect(wp) }
                    )
                }

                GalaxyChartHeaderLegend()
            }
        }
    }
}

private struct SolCenterNodeView: View {
    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color.yellow)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.orange, lineWidth: 2))
            Text("SOL [HERE]")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.yellow)
        }
    }
}

private struct GalaxyStarNodeButton: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let center: CGPoint
    let scalePtsPerLY: CGFloat
    let action: () -> Void

    private var nodePosition: CGPoint {
        guard let sys = waypoint.targetSystem else { return center }
        return CGPoint(
            x: center.x + CGFloat(sys.position.x) * scalePtsPerLY,
            y: center.y - CGFloat(sys.position.y) * scalePtsPerLY
        )
    }

    private var dotColor: Color {
        guard let cls = waypoint.targetSystem?.primaryClass else { return .white }
        switch cls {
        case .O, .B: return .cyan
        case .A, .F: return .white
        case .G: return .yellow
        case .K: return .orange
        case .M: return Color(red: 1.0, green: 0.42, blue: 0.28)
        default: return .purple
        }
    }

    private var nameColor: Color {
        isLocked ? .cyan : .white.opacity(0.9)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    if isLocked {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.cyan, lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .rotationEffect(.degrees(45))
                    }
                    Circle()
                        .fill(dotColor)
                        .frame(width: 11, height: 11)
                }
                Text(waypoint.name.uppercased())
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(nameColor)
            }
        }
        .buttonStyle(.plain)
        .position(nodePosition)
    }
}

private struct GalaxyChartHeaderLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("LOCAL INTERSTELLAR NEIGHBOURHOOD (18 LY BUBBLE) • A* ROUTE PLANNER")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
            Text("CYAN RING = 12.0 LY SINGLE-JUMP RANGE • TAP ANY STAR TO PLOT ROUTE & WAYPOINT")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }
}

// MARK: - Right Column Directory & Inspector

private struct WaypointDirectoryPanel: View {
    let waypoints: [NavigationWaypoint]
    let activeWaypointID: String
    let inspectedWaypointID: String
    let playerWorldPosition: SIMD3<Double>
    let onSelect: (NavigationWaypoint) -> Void

    private var headerText: String {
        "NAVIGATION TARGETS (\(waypoints.count))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(waypoints) { wp in
                        WaypointDirectoryRowButton(
                            waypoint: wp,
                            isLocked: wp.id == activeWaypointID,
                            isSelected: wp.id == inspectedWaypointID,
                            distanceText: NavigationWaypointManager.formatDistance(simd_length(wp.worldPosition - playerWorldPosition)),
                            action: { onSelect(wp) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct WaypointDirectoryRowButton: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let isSelected: Bool
    let distanceText: String
    let action: () -> Void

    private var nameColor: Color {
        isLocked ? .cyan : .white
    }

    private var distColor: Color {
        isLocked ? .cyan : .orange
    }

    private var rowBg: Color {
        isSelected ? Color.orange.opacity(0.20) : Color.white.opacity(0.04)
    }

    private var strokeColor: Color {
        if isLocked { return .cyan }
        if isSelected { return .orange }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(waypoint.kind.iconName)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(waypoint.kind.color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(waypoint.name.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(nameColor)
                        .lineLimit(1)
                    Text(waypoint.kind.rawValue)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(distanceText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(distColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(rowBg)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct WaypointInspectorCard: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let distanceText: String
    let isMassLocked: Bool
    let routeSummary: String?
    let onLockWaypoint: () -> Void
    let onJumpNow: () -> Void

    private var lockBtnTitle: String {
        isLocked ? "WAYPOINT LOCKED ✓" : "SET WAYPOINT"
    }

    private var lockBtnColor: Color {
        isLocked ? .cyan : .orange
    }

    private var jumpBtnTitle: String {
        isMassLocked ? "MASS LOCKED" : "MICRO-JUMP"
    }

    private var jumpBtnColor: Color {
        isMassLocked ? .red : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(waypoint.name.uppercased())
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.cyan)
                Spacer()
                Text(distanceText)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            Text(waypoint.subtitle)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)

            Text(waypoint.detailText)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let routeSummary {
                Text(routeSummary)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.mint)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button(action: onLockWaypoint) {
                    Text(lockBtnTitle)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(lockBtnColor.opacity(0.28))
                        .foregroundStyle(lockBtnColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(lockBtnColor, lineWidth: 1.3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if waypoint.supportsLocalJump {
                    Button(action: onJumpNow) {
                        Text(jumpBtnTitle)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(jumpBtnColor.opacity(0.24))
                            .foregroundStyle(jumpBtnColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(jumpBtnColor, lineWidth: 1.3)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .disabled(isMassLocked)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.84))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.55), lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
