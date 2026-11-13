import SwiftUI
import simd

@MainActor
struct FlightHUDTelemetry {
    var shipName: String = "SF-1V Kestrel"
    var speedMetresPerSec: Float = 0.0
    var maxSpeed: Float = 280.0
    var boostSpeed: Float = 460.0
    var throttle: Float = 0.0
    var isBoosting: Bool = false
    var boostChargeFraction: Float = 1.0
    var flightAssistEnabled: Bool = true
    var hardpointsDeployed: Bool = false
    var landingGearDeployed: Bool = false
    var cameraMode: ShipCameraMode = .cockpit

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
    var waypointScreenX: CGFloat = 0.0
    var waypointScreenY: CGFloat = 0.0
    var waypointIsInFront: Bool = true
    var compassDotX: CGFloat = 0.0
    var compassDotY: CGFloat = 0.0
    var isMassLocked: Bool = false

    // 3D Holographic Sensor Disc contacts
    var sensorContacts: [SensorDiscContact] = []

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
    var targetIsInFront: Bool = false
    var leadScreenX: CGFloat = 0.0
    var leadScreenY: CGFloat = 0.0
    var showHitMarker: Bool = false
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
    let onTriggerBoost: () -> Void
    let onSetThrottle: (Float) -> Void
    let onOpenNavMap: () -> Void
    let onCycleWaypoint: () -> Void
    let onMicroJump: () -> Void
    let onCycleTarget: () -> Void
    let onCycleSubsystem: () -> Void
    let onPipSYS: () -> Void
    let onPipENG: () -> Void
    let onPipWEP: () -> Void
    let onPipReset: () -> Void
    let onOpenTuningDrawer: () -> Void

    var body: some View {
        ZStack {
            CenterSpatialHUDOverlay(hud: hud)
                .allowsHitTesting(false)

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 14) {
                    if !minimalHUDMode {
                        LeftNavAndTargetHoloPanel(
                            hud: hud,
                            onOpenNavMap: onOpenNavMap,
                            onCycleWaypoint: onCycleWaypoint,
                            onMicroJump: onMicroJump,
                            onCycleTarget: onCycleTarget,
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
                            onOpenTuningDrawer: onOpenTuningDrawer
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
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

            if hud.hasLockedTarget && hud.targetIsInFront {
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

    private var edgeAngle: Double {
        Double(atan2(hud.compassDotY, hud.compassDotX))
    }

    private var edgeOffsetX: CGFloat {
        CGFloat(cos(edgeAngle)) * 105.0
    }

    private var edgeOffsetY: CGFloat {
        CGFloat(sin(edgeAngle)) * 105.0
    }

    var body: some View {
        if hud.waypointIsInFront {
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
                    .rotationEffect(.radians(edgeAngle + .pi * 0.5))
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
        "\(hud.targetName) [\(Int(hud.targetShields))/\(Int(hud.targetHull))]"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, lineWidth: 2.0)
                    .frame(width: 34, height: 34)
                Text(labelText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .offset(x: hud.targetScreenX, y: hud.targetScreenY)

            ZStack {
                Circle()
                    .stroke(Color.orange, lineWidth: 2.0)
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
            }
            .offset(x: hud.leadScreenX, y: hud.leadScreenY)
        }
    }
}

// MARK: - Bottom Center: Elite-Style 3D Holographic Sensor Disc & Compass Nav-Ball

private struct CenterSensorDiscConsole: View {
    let hud: FlightHUDTelemetry
    let onOpenNavMap: () -> Void

    private var massLockText: String {
        hud.isMassLocked ? "MASS LOCK" : "JUMP RDY"
    }

    private var massLockColor: Color {
        hud.isMassLocked ? .red : .cyan
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

                Text("KILLS: \(hud.totalKills)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.70))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1.4)
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
            // Radar disc background ellipses
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

// MARK: - Left Cockpit Panel

private struct LeftNavAndTargetHoloPanel: View {
    let hud: FlightHUDTelemetry
    let onOpenNavMap: () -> Void
    let onCycleWaypoint: () -> Void
    let onMicroJump: () -> Void
    let onCycleTarget: () -> Void
    let onCycleSubsystem: () -> Void

    private var wpDistEtaText: String {
        "\(hud.waypointDistanceText) • ETA \(hud.waypointETAText)"
    }

    private var jumpBtnTitle: String {
        hud.isMassLocked ? "MASS LOCKED" : "MICRO-JUMP"
    }

    private var jumpBtnColor: Color {
        hud.isMassLocked ? .red : .cyan
    }

    private var targetHeaderTitle: String {
        hud.hasLockedTarget ? "TARGET: \(hud.targetName)" : "NO COMBAT TARGET"
    }

    private var targetHeaderColor: Color {
        hud.hasLockedTarget ? .red : .secondary
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
                    Text("WAYPOINT LOCK")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(action: onOpenNavMap) {
                    Text("NAV MAP [Y]")
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

                if hud.waypointSupportsLocalJump {
                    Button(action: onMicroJump) {
                        Text(jumpBtnTitle)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(jumpBtnColor.opacity(0.24))
                            .foregroundStyle(jumpBtnColor)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .disabled(hud.isMassLocked)
                }
            }

            Divider()
                .overlay(Color.orange.opacity(0.35))

            HStack {
                Text(targetHeaderTitle)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(targetHeaderColor)
                    .lineLimit(1)
                Spacer()
                Button(action: onCycleTarget) {
                    Text("LOCK [X]")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
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
        .frame(width: 310, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.70))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.50), lineWidth: 1.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Right Cockpit Panel

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

    private var speedText: String {
        String(format: "%03.0f", hud.speedMetresPerSec)
    }

    private var speedColor: Color {
        hud.isBoosting ? .cyan : .orange
    }

    private var playerHealthText: String {
        "SHD \(Int(hud.playerShields))% • HULL \(Int(hud.playerHull))%"
    }

    private var wepCapText: String {
        "WEP CAP \(Int(hud.weaponCapacitor))%"
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

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerHealthText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text(wepCapText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(speedText)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
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
                ThrottlePresetButton(title: "50%", action: { onSetThrottle(0.5) })
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
        .frame(width: 335, alignment: .trailing)
        .padding(12)
        .background(Color.black.opacity(0.70))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.50), lineWidth: 1.3)
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

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))

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
