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
                    // Left column: Interactive holographic canvas for the selected tab
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.78))
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.55), lineWidth: 1.5)

                        switch selectedTab {
                        case .sectorGrid:
                            LocalSectorGridCanvas(
                                waypoints: navManager.localWaypoints + navManager.systemBodyWaypoints.prefix(3),
                                activeWaypoint: navManager.activeWaypoint,
                                inspectedWaypoint: currentWaypoint,
                                playerWorldPosition: playerWorldPosition,
                                onSelect: { wp in
                                    inspectedWaypoint = wp
                                    navManager.selectWaypoint(wp)
                                }
                            )
                        case .systemOrrery:
                            SolSystemOrreryCanvas(
                                waypoints: navManager.systemBodyWaypoints,
                                localWaypoints: navManager.localWaypoints,
                                activeWaypoint: navManager.activeWaypoint,
                                inspectedWaypoint: currentWaypoint,
                                onSelect: { wp in
                                    inspectedWaypoint = wp
                                    navManager.selectWaypoint(wp)
                                }
                            )
                        case .galaxyChart:
                            GalaxyStarChartCanvas(
                                starWaypoints: navManager.nearbyStarWaypoints,
                                activeWaypoint: navManager.activeWaypoint,
                                inspectedWaypoint: currentWaypoint,
                                plottedRoute: navManager.plottedRoute,
                                jumpRangeLY: navManager.jumpRangeLY,
                                onSelect: { wp in
                                    inspectedWaypoint = wp
                                    navManager.selectWaypoint(wp)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Right column: Waypoint directory + Selected Target Telemetry & Waypoint Lock actions
                    VStack(spacing: 12) {
                        WaypointDirectoryPanel(
                            waypoints: waypointsForCurrentTab,
                            activeWaypoint: navManager.activeWaypoint,
                            inspectedWaypoint: currentWaypoint,
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

// MARK: - Header Bar

private struct HoloMapHeaderBar: View {
    @Binding var selectedTab: HoloMapTab
    let activeWaypointName: String
    let onClose: () -> Void

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
                    Text("LOCKED WAYPOINT: \(activeWaypointName.uppercased())")
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.orange, lineWidth: 1.2)
                    )
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

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06))
                .foregroundStyle(isSelected ? .cyan : .secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.cyan : Color.orange.opacity(0.3), lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Tab 1: Local Sector 16x16 Tactical Grid (Vendetta + Elite Style)

private struct LocalSectorGridCanvas: View {
    let waypoints: [NavigationWaypoint]
    let activeWaypoint: NavigationWaypoint
    let inspectedWaypoint: NavigationWaypoint
    let playerWorldPosition: SIMD3<Double>
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad: CGFloat = 34
            let gridW = max(100, w - pad * 2)
            let gridH = max(100, h - pad * 2)

            ZStack(alignment: .topLeading) {
                // 16x16 Sector Grid lines
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

                // Concentric tactical radar range rings centered on player
                let playerPt = pointForSector(x: 8, y: 9, pad: pad, gridW: gridW, gridH: gridH)
                Circle()
                    .stroke(Color.cyan.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: 140, height: 140)
                    .position(playerPt)

                Circle()
                    .stroke(Color.orange.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .frame(width: 280, height: 280)
                    .position(playerPt)

                // Active Waypoint Course Line from Player Ship to Locked Waypoint
                if let activeIdx = waypoints.first(where: { $0.id == activeWaypoint.id }) {
                    let destPt = pointForSector(
                        x: activeIdx.sectorGridX,
                        y: activeIdx.sectorGridY,
                        pad: pad,
                        gridW: gridW,
                        gridH: gridH
                    )
                    Path { path in
                        path.move(to: playerPt)
                        path.addLine(to: destPt)
                    }
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.0, dash: [7, 4]))
                }

                // Player Ship Marker
                VStack(spacing: 2) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                    Text("YOU (SF-1V)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .position(playerPt)

                // Waypoint nodes on the sector grid
                ForEach(waypoints) { wp in
                    let pt = pointForSector(x: wp.sectorGridX, y: wp.sectorGridY, pad: pad, gridW: gridW, gridH: gridH)
                    SectorNodeButton(
                        waypoint: wp,
                        isLocked: wp.id == activeWaypoint.id,
                        isInspected: wp.id == inspectedWaypoint.id,
                        action: { onSelect(wp) }
                    )
                    .position(pt)
                }

                // Overlay legend
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
    }

    private func pointForSector(x: Int, y: Int, pad: CGFloat, gridW: CGFloat, gridH: CGFloat) -> CGPoint {
        let fx = (CGFloat(min(15, max(0, x))) + 0.5) / 16.0
        let fy = (CGFloat(min(15, max(0, y))) + 0.5) / 16.0
        return CGPoint(x: pad + fx * gridW, y: pad + fy * gridH)
    }
}

private struct SectorNodeButton: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let isInspected: Bool
    let action: () -> Void

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
                    .foregroundStyle(isLocked ? .cyan : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 2: Sol System Holographic Orrery (Elite System Map Style)

private struct SolSystemOrreryCanvas: View {
    let waypoints: [NavigationWaypoint]
    let localWaypoints: [NavigationWaypoint]
    let activeWaypoint: NavigationWaypoint
    let inspectedWaypoint: NavigationWaypoint
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SOL SYSTEM HOLOGRAPHIC SCHEMATIC • TAP ANY BODY OR STATION TO LOCK WAYPOINT")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            // Horizontal Orrery Strip (Star -> Planets)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 18) {
                    ForEach(waypoints) { wp in
                        OrreryBodyNode(
                            waypoint: wp,
                            isLocked: wp.id == activeWaypoint.id,
                            isInspected: wp.id == inspectedWaypoint.id,
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

            // Local stations & beacons around Earth
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(localWaypoints) { wp in
                    Button {
                        onSelect(wp)
                    } label: {
                        HStack(spacing: 10) {
                            Text(wp.kind.iconName)
                                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                .foregroundStyle(wp.kind.color)
                                .frame(width: 32, height: 32)
                                .background(wp.kind.color.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(wp.name.uppercased())
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(wp.id == activeWaypoint.id ? .cyan : .white)
                                Text(wp.subtitle)
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
                                .stroke(wp.id == activeWaypoint.id ? Color.cyan : Color.orange.opacity(0.35), lineWidth: 1.3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(16)
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if isLocked {
                        Circle()
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.2, dash: [5, 3]))
                            .frame(width: circleDiameter + 18, height: circleDiameter + 18)
                    } else if isInspected {
                        Circle()
                            .stroke(Color.orange, lineWidth: 1.8)
                            .frame(width: circleDiameter + 14, height: circleDiameter + 14)
                    }

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [waypoint.kind.color, waypoint.kind.color.opacity(0.35)],
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: circleDiameter
                            )
                        )
                        .frame(width: circleDiameter, height: circleDiameter)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.45), lineWidth: 1)
                        )
                }
                .frame(width: 88, height: 88)

                Text(waypoint.name.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLocked ? .cyan : .white)

                Text(waypoint.kind.rawValue)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(isInspected ? Color.white.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 3: Galaxy Star Chart (Interstellar High-Wake Map)

private struct GalaxyStarChartCanvas: View {
    let starWaypoints: [NavigationWaypoint]
    let activeWaypoint: NavigationWaypoint
    let inspectedWaypoint: NavigationWaypoint
    let plottedRoute: [SystemSummary]
    let jumpRangeLY: Double
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
            let scalePtsPerLY = min(geo.size.width, geo.size.height) / 34.0

            ZStack(alignment: .topLeading) {
                // Polar distance rings around Sol (5 LY, 10 LY, 15 LY)
                ForEach([5.0, 10.0, 15.0], id: \.self) { ly in
                    let r = CGFloat(ly) * scalePtsPerLY
                    Circle()
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                        .frame(width: r * 2, height: r * 2)
                        .position(center)
                }

                // Jump range circle (12 LY)
                let jumpRadius = CGFloat(jumpRangeLY) * scalePtsPerLY
                Circle()
                    .stroke(Color.cyan.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: jumpRadius * 2, height: jumpRadius * 2)
                    .position(center)

                // A* Plotted Route Polyline
                if plottedRoute.count >= 2 {
                    Path { path in
                        for (idx, sys) in plottedRoute.enumerated() {
                            let pt = pointForGalacticPos(sys.position, center: center, scale: scalePtsPerLY)
                            if idx == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.2, dash: [6, 3]))
                }

                // Sol Origin Marker at center
                VStack(spacing: 2) {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.orange, lineWidth: 2))
                    Text("SOL [HERE]")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
                .position(center)

                // Neighboring catalogued star systems
                ForEach(starWaypoints) { wp in
                    if let sys = wp.targetSystem {
                        let pt = pointForGalacticPos(sys.position, center: center, scale: scalePtsPerLY)
                        Button {
                            onSelect(wp)
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    if wp.id == activeWaypoint.id {
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color.cyan, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                            .rotationEffect(.degrees(45))
                                    }
                                    Circle()
                                        .fill(starColor(for: sys.primaryClass))
                                        .frame(width: 11, height: 11)
                                }
                                Text(sys.name.uppercased())
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(wp.id == activeWaypoint.id ? .cyan : .white.opacity(0.9))
                            }
                        }
                        .buttonStyle(.plain)
                        .position(pt)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("LOCAL INTERSTELLAR NEIGHBOURHOOD (18 LY BUBBLE) • A* ROUTE PLANNER")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text("DASHED CYAN RING = 12.0 LY SINGLE-JUMP RANGE • TAP ANY STAR TO PLOT ROUTE & WAYPOINT")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
        }
    }

    private func pointForGalacticPos(_ pos: GalacticPosition, center: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(pos.x) * scale,
            y: center.y - CGFloat(pos.y) * scale
        )
    }

    private func starColor(for cls: StellarClass) -> Color {
        switch cls {
        case .O, .B: return .cyan
        case .A, .F: return .white
        case .G: return .yellow
        case .K: return .orange
        case .M: return Color(red: 1.0, green: 0.42, blue: 0.28)
        default: return .purple
        }
    }
}

// MARK: - Right Column Directory & Inspector

private struct WaypointDirectoryPanel: View {
    let waypoints: [NavigationWaypoint]
    let activeWaypoint: NavigationWaypoint
    let inspectedWaypoint: NavigationWaypoint
    let playerWorldPosition: SIMD3<Double>
    let onSelect: (NavigationWaypoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAVIGATION TARGETS (\(waypoints.count))")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(waypoints) { wp in
                        let isLocked = wp.id == activeWaypoint.id
                        let isSelected = wp.id == inspectedWaypoint.id
                        let distStr = NavigationWaypointManager.formatDistance(simd_length(wp.worldPosition - playerWorldPosition))

                        Button {
                            onSelect(wp)
                        } label: {
                            HStack(spacing: 8) {
                                Text(wp.kind.iconName)
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundStyle(wp.kind.color)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(wp.name.uppercased())
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isLocked ? .cyan : .white)
                                        .lineLimit(1)
                                    Text(wp.kind.rawValue)
                                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(distStr)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isLocked ? .cyan : .orange)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.orange.opacity(0.20) : Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isLocked ? Color.cyan : (isSelected ? Color.orange : Color.clear), lineWidth: 1.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
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

private struct WaypointInspectorCard: View {
    let waypoint: NavigationWaypoint
    let isLocked: Bool
    let distanceText: String
    let isMassLocked: Bool
    let routeSummary: String?
    let onLockWaypoint: () -> Void
    let onJumpNow: () -> Void

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
                    Text(isLocked ? "WAYPOINT LOCKED ✓" : "SET WAYPOINT")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isLocked ? Color.cyan.opacity(0.28) : Color.orange.opacity(0.28))
                        .foregroundStyle(isLocked ? .cyan : .orange)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isLocked ? Color.cyan : Color.orange, lineWidth: 1.3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if waypoint.supportsLocalJump {
                    Button(action: onJumpNow) {
                        Text(isMassLocked ? "MASS LOCKED" : "MICRO-JUMP")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(isMassLocked ? Color.red.opacity(0.22) : Color.green.opacity(0.25))
                            .foregroundStyle(isMassLocked ? .red : .green)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isMassLocked ? Color.red : Color.green, lineWidth: 1.3)
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
