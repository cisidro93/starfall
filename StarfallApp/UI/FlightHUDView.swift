import SwiftUI
import simd

@MainActor
struct FlightHUDTelemetry {
    var shipName: String = "SF-1V Kestrel"
    var currentSystemName: String = "Sol"
    var currentSystemSecurity: String = "1.0 HIGH-SEC"
    var credits: Int = 25_000
    var unclaimedBountiesCR: Int = 0
    var cargoSummaryText: String = "0/20 T"
    var statusBannerText: String = "SYSTEMS ONLINE"
    var radioSender: String = "FLIGHT CONTROL"
    var radioMessage: String = "Maintain safe speed inside the station perimeter."
    var autopilotStatusText: String = ""
    var isAudioMuted: Bool = false

    var speedMetresPerSec: Float = 0.0
    var maxSpeed: Float = 260.0
    var boostSpeed: Float = 440.0
    var throttle: Float = 0.48
    var isInBlueZone: Bool = true
    var isBoosting: Bool = false
    var boostChargeFraction: Float = 1.0
    var flightAssistEnabled: Bool = true
    var autoTrackEnabled: Bool = true
    var hardpointsDeployed: Bool = false
    var landingGearDeployed: Bool = false
    var cameraMode: ShipCameraMode = .cockpit

    // FSD & Docking state
    var isFSDCharging: Bool = false
    var fsdCountdownText: String = ""
    var isHyperspaceJumping: Bool = false
    var hyperspaceDestinationName: String = ""
    var canDockAtStation: Bool = false

    // Prograde drift indicator
    var progradeOffsetX: CGFloat = 0.0
    var progradeOffsetY: CGFloat = 0.0
    var hasValidPrograde: Bool = false

    // Active Waypoint projection & Compass Nav-Ball
    var waypointName: String = "Gagarin Gateway"
    var waypointKind: WaypointKind = .station
    var waypointDistanceText: String = "900 m"
    var waypointETAText: String = "0:04"
    var waypointSupportsLocalJump: Bool = true
    var waypointIsInterstellar: Bool = false
    var waypointScreenX: CGFloat = 0.0
    var waypointScreenY: CGFloat = 0.0
    var waypointIsOnScreen: Bool = true
    var waypointBearingAngle: Double = 0.0
    var waypointIsInFront: Bool = true
    var compassDotX: CGFloat = 0.0
    var compassDotY: CGFloat = 0.0
    var isMassLocked: Bool = false

    // 3D Holographic Sensor Disc & EVE Tactical Overview contacts
    var sensorContacts: [SensorDiscContact] = []
    var overviewContacts: [OverviewContactItem] = []

    // Combat Target Lock & Predictive Lead Reticle
    var hasLockedTarget: Bool = false
    var targetName: String = "NO TARGET"
    var targetStateText: String = ""
    var targetSubsystem: String = "CHASSIS / HULL"
    var targetDistanceText: String = "--"
    var targetShields: Float = 100.0
    var targetHull: Float = 100.0
    var targetScreenX: CGFloat = 0.0
    var targetScreenY: CGFloat = 0.0
    var targetIsOnScreen: Bool = false
    var targetBearingAngle: Double = 0.0
    var leadScreenX: CGFloat = 0.0
    var leadScreenY: CGFloat = 0.0
    var showHitMarker: Bool = false
    var showShieldHitFlash: Bool = false
    var totalKills: Int = 0

    // Player Shields, Hull, Weapon Capacitor & SYS/ENG/WEP Pips
    var playerShields: Float = 100.0
    var playerHull: Float = 100.0
    var weaponCapacitor: Float = 100.0
    var sysPips: Int = 2
    var engPips: Int = 2
    var wepPips: Int = 2

    // Orbital distances
    var stationDistanceMetres: Double = 900.0
    var earthAltitudeKm: Double = 9_100.0
    var moonDistanceKm: Double = 384_400.0
    var originRecenterCount: Int = 0
}

struct FlightHUDView: View {
    let hud: FlightHUDTelemetry
    let minimalHUDMode: Bool
    let onToggleCamera: () -> Void
    let onToggleFlightAssist: () -> Void
    let onToggleAutoTrack: () -> Void
    let onToggleAudioMute: () -> Void
    let onTriggerBoost: () -> Void
    let onSetThrottle: (Float) -> Void
    let onOpenNavMap: () -> Void
    let onCycleWaypoint: () -> Void
    let onEngageFSD: () -> Void
    let onDockAtStation: () -> Void
    let onCycleTarget: () -> Void
    let onCycleSubsystem: () -> Void
    let onPipSYS: () -> Void
    let onPipENG: () -> Void
    let onPipWEP: () -> Void
    let onPipReset: () -> Void
    let onOpenTuningDrawer: () -> Void
    let onSelectOverviewItem: (OverviewContactItem) -> Void
    let onOverviewApproach: (OverviewContactItem) -> Void
    let onOverviewOrbit: (OverviewContactItem) -> Void
    let onOverviewTractor: () -> Void
    let onOverviewWarpOrDock: (OverviewContactItem) -> Void
    let onSetTouchPrimaryFire: (Bool) -> Void
    let onSetTouchSecondaryFire: (Bool) -> Void

    @State private var showOverviewExpanded: Bool = true
    @State private var selectedOverviewCategory: OverviewCategory = .all
    @State private var selectedOverviewID: String? = nil

    var body: some View {
        ZStack {
            CenterSpatialHUDOverlay(hud: hud)
                .allowsHitTesting(false)

            if hud.showShieldHitFlash {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.cyan.opacity(0.65), lineWidth: 6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if hud.isHyperspaceJumping {
                HyperspaceWitchSpaceOverlay(destinationName: hud.hyperspaceDestinationName)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    Spacer()

                    TopCommanderStatusBanner(
                        hud: hud,
                        onToggleAudioMute: onToggleAudioMute
                    )

                    Spacer()

                    if !minimalHUDMode {
                        EveTacticalOverviewPanel(
                            contacts: hud.overviewContacts,
                            autopilotStatusText: hud.autopilotStatusText,
                            isExpanded: $showOverviewExpanded,
                            selectedCategory: $selectedOverviewCategory,
                            selectedID: $selectedOverviewID,
                            onSelectItem: onSelectOverviewItem,
                            onApproach: onOverviewApproach,
                            onOrbit: onOverviewOrbit,
                            onTractor: onOverviewTractor,
                            onWarpOrDock: onOverviewWarpOrDock
                        )
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 18)

                Spacer()

                HStack(alignment: .bottom, spacing: 14) {
                    if !minimalHUDMode {
                        LeftNavAndTargetHoloPanel(
                            hud: hud,
                            onOpenNavMap: onOpenNavMap,
                            onCycleWaypoint: onCycleWaypoint,
                            onEngageFSD: onEngageFSD,
                            onDockAtStation: onDockAtStation,
                            onCycleTarget: onCycleTarget,
                            onToggleAutoTrack: onToggleAutoTrack,
                            onCycleSubsystem: onCycleSubsystem
                        )
                    }

                    Spacer()

                    CenterSensorDiscConsole(
                        hud: hud,
                        onOpenNavMap: onOpenNavMap
                    )

                    Spacer()

                    if !minimalHUDMode {
                        RightFlightAndPipsHoloPanel(
                            hud: hud,
                            onToggleCamera: onToggleCamera,
                            onToggleFlightAssist: onToggleFlightAssist,
                            onTriggerBoost: onTriggerBoost,
                            onSetThrottle: onSetThrottle,
                            onPipSYS: onPipSYS,
                            onPipENG: onPipENG,
                            onPipWEP: onPipWEP,
                            onPipReset: onPipReset,
                            onOpenTuningDrawer: onOpenTuningDrawer,
                            onSetTouchPrimaryFire: onSetTouchPrimaryFire,
                            onSetTouchSecondaryFire: onSetTouchSecondaryFire
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Top Commander, Security & Live Radio Comms Banner

private struct TopCommanderStatusBanner: View {
    let hud: FlightHUDTelemetry
    let onToggleAudioMute: () -> Void

    private var sysHeader: String {
        "\(hud.currentSystemName.uppercased()) (\(hud.currentSystemSecurity)) • \(hud.shipName.uppercased()) • \(hud.credits) CR • HOLD \(hud.cargoSummaryText)"
    }

    private var radioLine: String {
        "[\(hud.radioSender)]: \"\(hud.radioMessage)\""
    }

    private var audioTitle: String {
        hud.isAudioMuted ? "AUDIO:MUTE" : "AUDIO:ON"
    }

    private var audioColor: Color {
        hud.isAudioMuted ? .secondary : .mint
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                Text(sysHeader)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                Button(action: onToggleAudioMute) {
                    Text(audioTitle)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(audioColor.opacity(0.22))
                        .foregroundStyle(audioColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if hud.isFSDCharging {
                Text(hud.fsdCountdownText)
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.28))
                    .foregroundStyle(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(hud.statusBannerText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }

            Text(radioLine)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(.mint)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - EVE Online Tactical Overview Panel (Collapsible Right-Side Table)

private struct EveTacticalOverviewPanel: View {
    let contacts: [OverviewContactItem]
    let autopilotStatusText: String
    @Binding var isExpanded: Bool
    @Binding var selectedCategory: OverviewCategory
    @Binding var selectedID: String?
    let onSelectItem: (OverviewContactItem) -> Void
    let onApproach: (OverviewContactItem) -> Void
    let onOrbit: (OverviewContactItem) -> Void
    let onTractor: () -> Void
    let onWarpOrDock: (OverviewContactItem) -> Void

    private var filteredContacts: [OverviewContactItem] {
        let base: [OverviewContactItem]
        if selectedCategory == .all {
            base = contacts
        } else {
            base = contacts.filter { $0.category == selectedCategory }
        }
        return Array(base.prefix(5))
    }

    private var activeSelectedItem: OverviewContactItem? {
        if let id = selectedID, let match = contacts.first(where: { $0.id == id }) {
            return match
        }
        return filteredContacts.first
    }

    private var toggleHeaderTitle: String {
        isExpanded ? "▾ EVE OVERVIEW" : "▸ EVE OVERVIEW (\(contacts.count))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(toggleHeaderTitle)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.cyan)
                }

                Spacer()

                if !autopilotStatusText.isEmpty {
                    Text(autopilotStatusText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            if isExpanded {
                // One-Tap EVE Command Action Bar
                HStack(spacing: 5) {
                    OverviewCommandButton(
                        title: "APPROACH",
                        color: .cyan,
                        action: {
                            if let item = activeSelectedItem {
                                onApproach(item)
                            }
                        }
                    )
                    OverviewCommandButton(
                        title: "ORBIT 500M",
                        color: .mint,
                        action: {
                            if let item = activeSelectedItem {
                                onOrbit(item)
                            }
                        }
                    )
                    OverviewCommandButton(
                        title: "TRACTOR",
                        color: .green,
                        action: onTractor
                    )
                    OverviewCommandButton(
                        title: "WARP/DOCK",
                        color: .orange,
                        action: {
                            if let item = activeSelectedItem {
                                onWarpOrDock(item)
                            }
                        }
                    )
                }

                // Filter Category Tabs
                HStack(spacing: 4) {
                    ForEach(OverviewCategory.allCases) { cat in
                        OverviewFilterTabButton(
                            title: cat.rawValue,
                            isSelected: selectedCategory == cat,
                            action: { selectedCategory = cat }
                        )
                    }
                }

                // Distance-Sorted Contact Rows
                VStack(spacing: 3) {
                    ForEach(filteredContacts) { item in
                        OverviewContactRowView(
                            item: item,
                            isSelected: activeSelectedItem?.id == item.id,
                            onTap: {
                                selectedID = item.id
                                onSelectItem(item)
                            }
                        )
                    }
                }
            }
        }
        .frame(width: isExpanded ? 335 : 185, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.50), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct OverviewCommandButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(color.opacity(0.22))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct OverviewFilterTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private var bgColor: Color {
        isSelected ? Color.orange.opacity(0.26) : Color.white.opacity(0.06)
    }

    private var fgColor: Color {
        isSelected ? .orange : .secondary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(bgColor)
                .foregroundStyle(fgColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct OverviewContactRowView: View {
    let item: OverviewContactItem
    let isSelected: Bool
    let onTap: () -> Void

    private var rowColor: Color {
        if item.isHostile { return .red }
        if item.isCanister { return .green }
        if item.isAsteroid { return .yellow }
        if item.isStation { return .cyan }
        return .white
    }

    private var bgColor: Color {
        isSelected ? Color.cyan.opacity(0.22) : Color.white.opacity(0.04)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(rowColor)
                    .lineLimit(1)
                Spacer()
                Text(item.typeBadge)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.distanceText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .frame(width: 68, alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

private struct HyperspaceWitchSpaceOverlay: View {
    let destinationName: String

    private var jumpTitle: String {
        "WITCH-SPACE HYPERSPACE CONDUIT → \(destinationName.uppercased())"
    }

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.08, blue: 0.18).opacity(0.82)
                .ignoresSafeArea()

            Circle()
                .stroke(Color.cyan.opacity(0.65), lineWidth: 4)
                .frame(width: 220, height: 220)

            Circle()
                .stroke(Color.orange.opacity(0.55), lineWidth: 2.5)
                .frame(width: 420, height: 420)

            Circle()
                .stroke(Color.cyan.opacity(0.35), lineWidth: 2)
                .frame(width: 680, height: 680)

            VStack(spacing: 8) {
                Text("FRAME SHIFT DRIVE ACTIVE")
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.cyan)
                Text(jumpTitle)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            .padding(18)
            .background(Color.black.opacity(0.80))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Center Spatial Reticles

private struct CenterSpatialHUDOverlay: View {
    let hud: FlightHUDTelemetry

    var body: some View {
        ZStack {
            BoresightReticleRing(isBoosting: hud.isBoosting, showHitMarker: hud.showHitMarker)

            if hud.hasValidPrograde {
                ProgradePipMarker(offsetX: hud.progradeOffsetX, offsetY: hud.progradeOffsetY)
            }

            WaypointSpatialMarker(hud: hud)

            if hud.hasLockedTarget {
                CombatTargetSpatialMarker(hud: hud)
            }
        }
    }
}

private struct BoresightReticleRing: View {
    let isBoosting: Bool
    let showHitMarker: Bool

    private var ringColor: Color {
        isBoosting ? .cyan : Color.orange.opacity(0.80)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.18), style: StrokeStyle(lineWidth: 1.0, dash: [6, 6]))
                .frame(width: 210, height: 210)

            Circle()
                .trim(from: 0.08, to: 0.42)
                .stroke(ringColor, lineWidth: 1.8)
                .frame(width: 58, height: 58)

            Circle()
                .trim(from: 0.58, to: 0.92)
                .stroke(ringColor, lineWidth: 1.8)
                .frame(width: 58, height: 58)

            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)

            if showHitMarker {
                HitMarkerCross()
            }
        }
    }
}

private struct ProgradePipMarker: View {
    let offsetX: CGFloat
    let offsetY: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.cyan, lineWidth: 2.0)
                .frame(width: 18, height: 18)
            Circle()
                .fill(Color.cyan)
                .frame(width: 4, height: 4)
        }
        .offset(x: offsetX, y: offsetY)
    }
}

private struct HitMarkerCross: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.cyan)
                .frame(width: 22, height: 2)
                .rotationEffect(.degrees(45))
            Rectangle()
                .fill(Color.cyan)
                .frame(width: 22, height: 2)
                .rotationEffect(.degrees(-45))
        }
    }
}

private struct WaypointSpatialMarker: View {
    let hud: FlightHUDTelemetry

    private var bannerText: String {
        "\(hud.waypointName.uppercased()) • \(hud.waypointDistanceText)"
    }

    private var edgeOffsetX: CGFloat {
        CGFloat(cos(hud.waypointBearingAngle)) * 125.0
    }

    private var edgeOffsetY: CGFloat {
        CGFloat(sin(hud.waypointBearingAngle)) * 125.0
    }

    var body: some View {
        if hud.waypointIsOnScreen {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.cyan, lineWidth: 2.0)
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(45))
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 4, height: 4)
                }
                Text(bannerText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .offset(x: hud.waypointScreenX, y: hud.waypointScreenY)
        } else {
            VStack(spacing: 2) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.cyan)
                    .rotationEffect(.radians(hud.waypointBearingAngle + .pi * 0.5))
                Text("WP")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            .offset(x: edgeOffsetX, y: edgeOffsetY)
        }
    }
}

private struct CombatTargetSpatialMarker: View {
    let hud: FlightHUDTelemetry

    private var labelText: String {
        "\(hud.targetName) • \(hud.targetDistanceText) [\(Int(hud.targetShields))/\(Int(hud.targetHull))]"
    }

    private var offscreenText: String {
        "HOSTILE \(hud.targetDistanceText)"
    }

    private var edgeOffsetX: CGFloat {
        CGFloat(cos(hud.targetBearingAngle)) * 140.0
    }

    private var edgeOffsetY: CGFloat {
        CGFloat(sin(hud.targetBearingAngle)) * 140.0
    }

    var body: some View {
        if hud.targetIsOnScreen {
            ZStack {
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.red, lineWidth: 2.2)
                        .frame(width: 40, height: 40)
                    Text(labelText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.80))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .offset(x: hud.targetScreenX, y: hud.targetScreenY)

                ZStack {
                    Circle()
                        .stroke(Color.orange, lineWidth: 2.2)
                        .frame(width: 26, height: 26)
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
                .offset(x: hud.leadScreenX, y: hud.leadScreenY)
            }
        } else {
            VStack(spacing: 2) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.red)
                    .rotationEffect(.radians(hud.targetBearingAngle + .pi * 0.5))
                Text(offscreenText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.78))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .offset(x: edgeOffsetX, y: edgeOffsetY)
        }
    }
}

// MARK: - Bottom Center: Elite-Style 3D Holographic Sensor Disc & Compass Nav-Ball

private struct CenterSensorDiscConsole: View {
    let hud: FlightHUDTelemetry
    let onOpenNavMap: () -> Void

    private var massLockText: String {
        hud.isMassLocked ? "MASS LOCK" : "FSD RDY"
    }

    private var massLockColor: Color {
        hud.isMassLocked ? .red : .cyan
    }

    private var bountyBadgeText: String {
        hud.unclaimedBountiesCR > 0 ? "+\(hud.unclaimedBountiesCR / 1000)K CR" : "KILLS: \(hud.totalKills)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompassNavBallView(
                dotX: hud.compassDotX,
                dotY: hud.compassDotY,
                isInFront: hud.waypointIsInFront
            )

            HoloSensorDiscView(contacts: hud.sensorContacts)
                .frame(width: 220, height: 118)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenNavMap()
                }

            VStack(alignment: .trailing, spacing: 6) {
                Text(massLockText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(massLockColor.opacity(0.24))
                    .foregroundStyle(massLockColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(bountyBadgeText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.60), lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct CompassNavBallView: View {
    let dotX: CGFloat
    let dotY: CGFloat
    let isInFront: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(Color.orange.opacity(0.75), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                Rectangle()
                    .fill(Color.orange.opacity(0.35))
                    .frame(width: 40, height: 1)
                Rectangle()
                    .fill(Color.orange.opacity(0.35))
                    .frame(width: 1, height: 40)

                if isInFront {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 9, height: 9)
                        .offset(x: dotX * 16.0, y: dotY * 16.0)
                } else {
                    Circle()
                        .stroke(Color.cyan, lineWidth: 2.2)
                        .frame(width: 10, height: 10)
                        .offset(x: dotX * 16.0, y: dotY * 16.0)
                }
            }
            Text("NAV")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
        }
    }
}

private struct HoloSensorDiscView: View {
    let contacts: [SensorDiscContact]

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.orange.opacity(0.08))
                .frame(width: 202, height: 84)
                .offset(y: 8)

            Ellipse()
                .stroke(Color.orange.opacity(0.75), lineWidth: 1.6)
                .frame(width: 202, height: 84)
                .offset(y: 8)

            Ellipse()
                .stroke(Color.orange.opacity(0.35), lineWidth: 1.0)
                .frame(width: 116, height: 48)
                .offset(y: 8)

            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .offset(y: 8)

            ForEach(contacts) { contact in
                SensorContactStalkView(contact: contact)
            }
        }
    }
}

private struct SensorContactStalkView: View {
    let contact: SensorDiscContact

    private var baseX: CGFloat {
        CGFloat(contact.discX) * 95.0
    }

    private var baseY: CGFloat {
        8.0 + CGFloat(contact.discZ) * 39.0
    }

    private var headY: CGFloat {
        baseY - CGFloat(contact.elevationY) * 26.0
    }

    private var stalkHeight: CGFloat {
        max(1.0, abs(headY - baseY))
    }

    private var stalkMidY: CGFloat {
        (baseY + headY) * 0.5
    }

    private var markerColor: Color {
        if contact.isHostile { return .red }
        if contact.isStation || contact.isWaypoint { return .cyan }
        return .orange
    }

    private var boxSize: CGFloat {
        contact.isLockedTarget ? 8.0 : 6.0
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(markerColor.opacity(0.70))
                .frame(width: 1.5, height: stalkHeight)
                .offset(x: baseX, y: stalkMidY)

            Circle()
                .fill(markerColor.opacity(0.45))
                .frame(width: 4, height: 4)
                .offset(x: baseX, y: baseY)

            Rectangle()
                .fill(markerColor)
                .frame(width: boxSize, height: boxSize)
                .offset(x: baseX, y: headY)
        }
    }
}

// MARK: - Left Cockpit Panel ([1] EXT PANEL)

private struct LeftNavAndTargetHoloPanel: View {
    let hud: FlightHUDTelemetry
    let onOpenNavMap: () -> Void
    let onCycleWaypoint: () -> Void
    let onEngageFSD: () -> Void
    let onDockAtStation: () -> Void
    let onCycleTarget: () -> Void
    let onToggleAutoTrack: () -> Void
    let onCycleSubsystem: () -> Void

    private var wpDistEtaText: String {
        "\(hud.waypointDistanceText) • ETA \(hud.waypointETAText)"
    }

    private var fsdBtnTitle: String {
        if hud.waypointIsInterstellar {
            return "HYPERSPACE JUMP"
        }
        return hud.isMassLocked ? "MASS LOCKED" : "SUPERCRUISE"
    }

    private var fsdBtnColor: Color {
        if hud.waypointIsInterstellar { return .cyan }
        return hud.isMassLocked ? .red : .cyan
    }

    private var targetHeaderTitle: String {
        hud.hasLockedTarget ? "LOCKED: \(hud.targetName)" : "NO COMBAT TARGET"
    }

    private var targetHeaderColor: Color {
        hud.hasLockedTarget ? .red : .secondary
    }

    private var autoTrackTitle: String {
        hud.autoTrackEnabled ? "AUTO-AIM:ON" : "AUTO-AIM:OFF"
    }

    private var autoTrackColor: Color {
        hud.autoTrackEnabled ? .green : .secondary
    }

    private var targetHealthText: String {
        "SHD \(Int(hud.targetShields))% • HULL \(Int(hud.targetHull))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(hud.waypointKind.iconName)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text("[1] NAV & CONTACTS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(action: onOpenNavMap) {
                    Text("GALAXY MAP [Y]")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.26))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }

            HStack {
                Text(hud.waypointName.uppercased())
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                Spacer()
                Text(wpDistEtaText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                Button(action: onCycleWaypoint) {
                    Text("NEXT WP")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                if hud.waypointSupportsLocalJump || hud.waypointIsInterstellar {
                    Button(action: onEngageFSD) {
                        Text(fsdBtnTitle)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(fsdBtnColor.opacity(0.24))
                            .foregroundStyle(fsdBtnColor)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .disabled(hud.isMassLocked && !hud.waypointIsInterstellar)
                }

                if hud.canDockAtStation {
                    Button(action: onDockAtStation) {
                        Text("DOCK PAD 04")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.28))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }

            Divider()
                .overlay(Color.orange.opacity(0.35))

            HStack(spacing: 6) {
                Text(targetHeaderTitle)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(targetHeaderColor)
                    .lineLimit(1)
                Spacer()
                Button(action: onToggleAutoTrack) {
                    Text(autoTrackTitle)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(autoTrackColor.opacity(0.22))
                        .foregroundStyle(autoTrackColor)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Button(action: onCycleTarget) {
                    Text("LOCK [X]")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.24))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }

            if hud.hasLockedTarget {
                HStack {
                    Text(targetHealthText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Button(action: onCycleSubsystem) {
                        Text("SUB: \(hud.targetSubsystem)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .frame(width: 345, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Right Cockpit Panel ([4] INT PANEL + Touch Fire Triggers)

private struct RightFlightAndPipsHoloPanel: View {
    let hud: FlightHUDTelemetry
    let onToggleCamera: () -> Void
    let onToggleFlightAssist: () -> Void
    let onTriggerBoost: () -> Void
    let onSetThrottle: (Float) -> Void
    let onPipSYS: () -> Void
    let onPipENG: () -> Void
    let onPipWEP: () -> Void
    let onPipReset: () -> Void
    let onOpenTuningDrawer: () -> Void
    let onSetTouchPrimaryFire: (Bool) -> Void
    let onSetTouchSecondaryFire: (Bool) -> Void

    @State private var isFiringLasersTouch: Bool = false
    @State private var isFiringCannonsTouch: Bool = false

    private var speedText: String {
        String(format: "%03.0f", hud.speedMetresPerSec)
    }

    private var speedColor: Color {
        hud.isBoosting ? .cyan : .orange
    }

    private var playerHealthText: String {
        "SHD \(Int(hud.playerShields))% • HULL \(Int(hud.playerHull))%"
    }

    private var agilityZoneText: String {
        hud.isInBlueZone ? "BLUE ZONE (+35% TURN)" : "WEP CAP \(Int(hud.weaponCapacitor))%"
    }

    private var agilityZoneColor: Color {
        hud.isInBlueZone ? .cyan : .orange
    }

    private var boostBtnTitle: String {
        hud.isBoosting ? "BOOSTING" : "BOOST [A]"
    }

    private var boostReadyColor: Color {
        hud.boostChargeFraction >= 0.99 ? .cyan : .secondary
    }

    private var faTitle: String {
        hud.flightAssistEnabled ? "FA:ON [B]" : "FA:OFF [B]"
    }

    private var faColor: Color {
        hud.flightAssistEnabled ? .green : .orange
    }

    private var laserBtnBg: Color {
        isFiringLasersTouch ? Color.cyan.opacity(0.45) : Color.cyan.opacity(0.18)
    }

    private var cannonBtnBg: Color {
        isFiringCannonsTouch ? Color.orange.opacity(0.45) : Color.orange.opacity(0.18)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            // Touch-screen Primary & Secondary Weapon Fire Triggers (Hold or Toggle)
            HStack(spacing: 8) {
                Button {
                    isFiringLasersTouch.toggle()
                    onSetTouchPrimaryFire(isFiringLasersTouch)
                } label: {
                    Text(isFiringLasersTouch ? "LASERS: FIRING" : "FIRE LASERS [RT]")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(laserBtnBg)
                        .foregroundStyle(.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button {
                    isFiringCannonsTouch.toggle()
                    onSetTouchSecondaryFire(isFiringCannonsTouch)
                } label: {
                    Text(isFiringCannonsTouch ? "CANNONS: FIRING" : "CANNONS [LT]")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(cannonBtnBg)
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerHealthText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text(agilityZoneText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(agilityZoneColor)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(speedText)
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .foregroundStyle(speedColor)
                    Text("m/s")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            SpeedThrottleBar(
                speedFraction: min(1.0, hud.speedMetresPerSec / max(1.0, hud.boostSpeed)),
                throttleFraction: hud.throttle * (hud.maxSpeed / max(1.0, hud.boostSpeed)),
                isBoosting: hud.isBoosting
            )

            PowerDistributorPipsRow(
                sysPips: hud.sysPips,
                engPips: hud.engPips,
                wepPips: hud.wepPips,
                onPipSYS: onPipSYS,
                onPipENG: onPipENG,
                onPipWEP: onPipWEP,
                onPipReset: onPipReset
            )

            HStack(spacing: 6) {
                ThrottlePresetButton(title: "0%", action: { onSetThrottle(0.0) })
                ThrottlePresetButton(title: "BLUE 50%", action: { onSetThrottle(0.52) })
                ThrottlePresetButton(title: "100%", action: { onSetThrottle(1.0) })

                Spacer()

                Button(action: onTriggerBoost) {
                    Text(boostBtnTitle)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(boostReadyColor.opacity(0.22))
                        .foregroundStyle(boostReadyColor)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }

            HStack(spacing: 6) {
                Button(action: onToggleFlightAssist) {
                    Text(faTitle)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(faColor.opacity(0.22))
                        .foregroundStyle(faColor)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                Button(action: onToggleCamera) {
                    Text("CAM [RB]")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.22))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                Button(action: onOpenTuningDrawer) {
                    Text("TUNE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.25))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .frame(width: 345, alignment: .trailing)
        .padding(12)
        .background(Color.black.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PowerDistributorPipsRow: View {
    let sysPips: Int
    let engPips: Int
    let wepPips: Int
    let onPipSYS: () -> Void
    let onPipENG: () -> Void
    let onPipWEP: () -> Void
    let onPipReset: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            PipChannelButton(label: "SYS", pips: sysPips, color: .cyan, action: onPipSYS)
            PipChannelButton(label: "ENG", pips: engPips, color: .orange, action: onPipENG)
            PipChannelButton(label: "WEP", pips: wepPips, color: .red, action: onPipWEP)
            Button(action: onPipReset) {
                Text("RST")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

private struct PipChannelButton: View {
    let label: String
    let pips: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                HStack(spacing: 2) {
                    PipBlockView(isFilled: pips >= 1, color: color)
                    PipBlockView(isFilled: pips >= 2, color: color)
                    PipBlockView(isFilled: pips >= 3, color: color)
                    PipBlockView(isFilled: pips >= 4, color: color)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

private struct PipBlockView: View {
    let isFilled: Bool
    let color: Color

    private var fillColor: Color {
        isFilled ? color : Color.white.opacity(0.15)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(fillColor)
            .frame(width: 5, height: 11)
    }
}

private struct SpeedThrottleBar: View {
    let speedFraction: Float
    let throttleFraction: Float
    let isBoosting: Bool

    private var barFillColor: Color {
        isBoosting ? .cyan : .orange
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let speedW = max(0, min(w, w * CGFloat(speedFraction)))
            let thrX = max(0, min(w - 3, w * CGFloat(throttleFraction)))
            let blueStart = w * 0.24
            let blueWidth = w * 0.16

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))

                Rectangle()
                    .fill(Color.cyan.opacity(0.32))
                    .frame(width: blueWidth, height: 11)
                    .offset(x: blueStart)

                RoundedRectangle(cornerRadius: 4)
                    .fill(barFillColor)
                    .frame(width: speedW)

                Rectangle()
                    .fill(Color.green)
                    .frame(width: 3, height: 14)
                    .offset(x: thrX)
            }
        }
        .frame(height: 11)
    }
}

private struct ThrottlePresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}

// MARK: - Native Cockpit Holographic Dual-Thumbstick Touch Overlay (Crash-Proof Touch Pad)

struct HoloTouchFlightSticksOverlay: View {
    @ObservedObject var inputManager: ControllerInputManager

    private var rightModeTitle: String {
        inputManager.touchStrafeMode ? "RIGHT PAD: 6DoF STRAFE" : "RIGHT PAD: ROLL & THR"
    }

    private var rightModeColor: Color {
        inputManager.touchStrafeMode ? .cyan : .orange
    }

    var body: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                SingleHoloThumbstickPad(
                    title: "LEFT STICK • PITCH / STEER",
                    accentColor: .cyan,
                    stickValue: $inputManager.touchLeftStick
                )

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        inputManager.touchStrafeMode.toggle()
                    } label: {
                        Text(rightModeTitle)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(rightModeColor.opacity(0.24))
                            .foregroundStyle(rightModeColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(rightModeColor.opacity(0.65), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    SingleHoloThumbstickPad(
                        title: inputManager.touchStrafeMode ? "STRAFE LAT / VERT" : "ROLL / THROTTLE",
                        accentColor: rightModeColor,
                        stickValue: $inputManager.touchRightStick
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 250)
        }
    }
}

private struct SingleHoloThumbstickPad: View {
    let title: String
    let accentColor: Color
    @Binding var stickValue: SIMD2<Float>

    private let padRadius: CGFloat = 76.0

    private var knobOffsetX: CGFloat {
        CGFloat(stickValue.x) * (padRadius - 22.0)
    }

    private var knobOffsetY: CGFloat {
        CGFloat(-stickValue.y) * (padRadius - 22.0)
    }

    private var readoutText: String {
        String(format: "X:%+.2f  Y:%+.2f", stickValue.x, stickValue.y)
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.62))
                    .frame(width: padRadius * 2, height: padRadius * 2)

                Circle()
                    .stroke(accentColor.opacity(0.55), lineWidth: 1.8)
                    .frame(width: padRadius * 2, height: padRadius * 2)

                Circle()
                    .stroke(accentColor.opacity(0.22), lineWidth: 1.0)
                    .frame(width: padRadius * 1.1, height: padRadius * 1.1)

                Rectangle()
                    .fill(accentColor.opacity(0.22))
                    .frame(width: padRadius * 1.8, height: 1)

                Rectangle()
                    .fill(accentColor.opacity(0.22))
                    .frame(width: 1, height: padRadius * 1.8)

                Circle()
                    .fill(accentColor.opacity(0.38))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Circle()
                            .stroke(accentColor, lineWidth: 2.2)
                    )
                    .offset(x: knobOffsetX, y: knobOffsetY)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = Float(value.location.x - padRadius) / Float(padRadius - 18.0)
                        let dy = Float(padRadius - value.location.y) / Float(padRadius - 18.0)
                        let raw = SIMD2<Float>(dx, dy)
                        let len = simd_length(raw)
                        if len > 1.0 {
                            stickValue = raw / len
                        } else {
                            stickValue = raw
                        }
                    }
                    .onEnded { _ in
                        stickValue = .zero
                    }
            )

            Text(readoutText)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
