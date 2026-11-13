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
            // 1. Center Boresight, Prograde Vector, In-Space Waypoint Diamond & Combat Lead Reticle
            CenterSpatialHUDOverlay(hud: hud)
                .allowsHitTesting(false)

            // 2. Bottom Cockpit Console: Left Nav/Target Panel, Center 3D Sensor Disc, Right Systems/Pips Panel
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

                    // Elite-Style 3D Holographic Sensor Disc + Compass Nav-Ball (always visible)
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

// MARK: - Center Spatial Reticles (Boresight, Waypoint Diamond, Target Box & Predictive Lead)

private struct CenterSpatialHUDOverlay: View {
    let hud: FlightHUDTelemetry

    private var ringColor: Color {
        hud.isBoosting ? .cyan : Color.orange.opacity(0.80)
    }

    var body: some View {
        ZStack {
            // Outer boresight brackets
            Circle()
                .trim(from: 0.08, to: 0.42)
                .stroke(ringColor, lineWidth: 1.8)
                .frame(width: 58, height: 58)

            Circle()
                .trim(from: 0.58, to: 0.92)
                .stroke(ringColor, lineWidth: 1.8)
                .frame(width: 58, height: 58)

            // Center nose dot
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)

            // Hit confirmation marker
            if hud.showHitMarker {
                HitMarkerCross()
            }

            // Prograde velocity vector marker
            if hud.hasValidPrograde {
                ZStack {
                    Circle()
                        .stroke(Color.cyan, lineWidth: 2.0)
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 4, height: 4)
                }
                .offset(x: hud.progradeOffsetX, y: hud.progradeOffsetY)
            }

            // In-Space Projected Waypoint Diamond
            WaypointSpatialMarker(hud: hud)

            // Locked Combat Target Bracket + Vendetta Predictive Lead Reticle
            if hud.hasLockedTarget && hud.targetIsInFront {
                CombatTargetSpatialMarker(hud: hud)
            }
        }
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
                Text("\(hud.waypointName.uppercased()) • \(hud.waypointDistanceText)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .offset(x: hud.waypointScreenX, y: hud.waypointScreenY)
        } else {
            // Off-screen directional perimeter indicator around center reticle
            let angle = atan2(hud.compassDotY, hud.compassDotX)
            let radius: CGFloat = 105.0
            VStack(spacing: 2) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.cyan)
                    .rotationEffect(.radians(Double(angle) + .pi * 0.5))
                Text("WP")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
        }
    }
}

private struct CombatTargetSpatialMarker: View {
    let hud: FlightHUDTelemetry

    var body: some View {
        ZStack {
            // Target bounding box around enemy drone
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, lineWidth: 2.0)
                    .frame(width: 34, height: 34)
                Text("\(hud.targetName) [\(Int(hud.targetShields))/\(Int(hud.targetHull))]")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .offset(x: hud.targetScreenX, y: hud.targetScreenY)

            // Dashed line connecting target to its Predictive Lead Reticle
            Path { path in
                path.move(to: CGPoint(x: hud.targetScreenX, y: hud.targetScreenY))
                path.addLine(to: CGPoint(x: hud.leadScreenX, y: hud.leadScreenY))
            }
            .stroke(Color.orange.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            .frame(width: 1, height: 1)

            // Vendetta-style Predictive Lead Aiming Circle
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

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                // Elite 3D Compass Nav-Ball (Top-Left of Sensor Disc)
                CompassNavBallView(
                    dotX: hud.compassDotX,
                    dotY: hud.compassDotY,
                    isInFront: hud.waypointIsInFront
                )

                // 3D Angled Holographic Radar Disc with vertical elevation stalks
                HoloSensorDiscCanvas(contacts: hud.sensorContacts)
                    .frame(width: 220, height: 118)
                    .onTapGesture {
                        onOpenNavMap()
                    }

                // Proximity / Mass-Lock & Kill Counter badge
                VStack(alignment: .trailing, spacing: 4) {
                    Text(hud.isMassLocked ? "MASS LOCK" : "JUMP RDY")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(hud.isMassLocked ? Color.red.opacity(0.26) : Color.cyan.opacity(0.22))
                        .foregroundStyle(hud.isMassLocked ? .red : .cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("KILLS: \(hud.totalKills)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
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

                // Crosshair ticks
                Rectangle()
                    .fill(Color.orange.opacity(0.35))
                    .frame(width: 40, height: 1)
                Rectangle()
                    .fill(Color.orange.opacity(0.35))
                    .frame(width: 1, height: 40)

                // Waypoint bearing dot: solid cyan = ahead, hollow ring = behind
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

private struct HoloSensorDiscCanvas: View {
    let contacts: [SensorDiscContact]

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width * 0.5
            let cy = geo.size.height * 0.58
            let rx: CGFloat = geo.size.width * 0.46
            let ry: CGFloat = geo.size.height * 0.36

            ZStack {
                // Outer & inner tilted 3D radar ellipses
                Ellipse()
                    .fill(Color.orange.opacity(0.07))
                    .frame(width: rx * 2, height: ry * 2)
                    .position(x: cx, y: cy)

                Ellipse()
                    .stroke(Color.orange.opacity(0.75), lineWidth: 1.6)
                    .frame(width: rx * 2, height: ry * 2)
                    .position(x: cx, y: cy)

                Ellipse()
                    .stroke(Color.orange.opacity(0.35), style: StrokeStyle(lineWidth: 1.0, dash: [4, 3]))
                    .frame(width: rx * 1.15, height: ry * 1.15)
                    .position(x: cx, y: cy)

                // Forward sensor cone V-lines
                Path { path in
                    path.move(to: CGPoint(x: cx, y: cy))
                    path.addLine(to: CGPoint(x: cx - rx * 0.62, y: cy - ry * 0.78))
                    path.move(to: CGPoint(x: cx, y: cy))
                    path.addLine(to: CGPoint(x: cx + rx * 0.62, y: cy - ry * 0.78))
                }
                .stroke(Color.cyan.opacity(0.40), lineWidth: 1.1)

                // Player ship triangle at center of disc
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .position(x: cx, y: cy)

                // Contacts with vertical 3D elevation stalks
                ForEach(contacts) { c in
                    let basePt = CGPoint(
                        x: cx + CGFloat(c.discX) * rx,
                        y: cy + CGFloat(c.discZ) * ry
                    )
                    let headPt = CGPoint(
                        x: basePt.x,
                        y: basePt.y - CGFloat(c.elevationY) * 28.0
                    )
                    let contactColor: Color = c.isHostile ? .red : (c.isStation || c.isWaypoint ? .cyan : .orange)

                    // Vertical stalk from disc plane to contact 3D altitude
                    Path { path in
                        path.move(to: basePt)
                        path.addLine(to: headPt)
                    }
                    .stroke(contactColor.opacity(0.75), lineWidth: 1.4)

                    // Base foot tick on disc plane
                    Circle()
                        .fill(contactColor.opacity(0.45))
                        .frame(width: 4, height: 4)
                        .position(basePt)

                    // Contact head icon
                    Rectangle()
                        .fill(contactColor)
                        .frame(width: c.isLockedTarget ? 8 : 6, height: c.isLockedTarget ? 8 : 6)
                        .overlay(
                            Rectangle()
                                .stroke(Color.white, lineWidth: c.isLockedTarget ? 1.5 : 0)
                        )
                        .position(headPt)
                }
            }
        }
    }
}

// MARK: - Left Cockpit Panel: Waypoint Navigation & Locked Combat Target

private struct LeftNavAndTargetHoloPanel: View {
    let hud: FlightHUDTelemetry
    let onOpenNavMap: () -> Void
    let onCycleWaypoint: () -> Void
    let onMicroJump: () -> Void
    let onCycleTarget: () -> Void
    let onCycleSubsystem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Waypoint Header & Map Button
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
                Text("\(hud.waypointDistanceText) • ETA \(hud.waypointETAText)")
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
                        Text(hud.isMassLocked ? "MASS LOCKED" : "MICRO-JUMP")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(hud.isMassLocked ? Color.red.opacity(0.22) : Color.cyan.opacity(0.25))
                            .foregroundStyle(hud.isMassLocked ? .red : .cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .disabled(hud.isMassLocked)
                }
            }

            Divider()
                .overlay(Color.orange.opacity(0.35))

            // Combat Target Lock Section
            HStack {
                Text(hud.hasLockedTarget ? "TARGET: \(hud.targetName)" : "NO COMBAT TARGET")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(hud.hasLockedTarget ? .red : .secondary)
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
                    Text("SHD \(Int(hud.targetShields))% • HULL \(Int(hud.targetHull))%")
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

// MARK: - Right Cockpit Panel: Flight Systems, Shields/Hull & SYS/ENG/WEP Power Distributor

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

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Top Row: Player Shield/Hull + Speed Readout
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHD \(Int(hud.playerShields))% • HULL \(Int(hud.playerHull))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text("WEP CAP \(Int(hud.weaponCapacitor))%")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(speedText)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(hud.isBoosting ? .cyan : .orange)
                    Text("m/s")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Speed & Throttle Bar
            SpeedThrottleBar(
                speedFraction: min(1.0, hud.speedMetresPerSec / max(1.0, hud.boostSpeed)),
                throttleFraction: hud.throttle * (hud.maxSpeed / max(1.0, hud.boostSpeed)),
                isBoosting: hud.isBoosting
            )

            // Step 8: SYS / ENG / WEP Power Distributor Pips (D-Pad or Touch)
            PowerDistributorPipsRow(
                sysPips: hud.sysPips,
                engPips: hud.engPips,
                wepPips: hud.wepPips,
                onPipSYS: onPipSYS,
                onPipENG: onPipENG,
                onPipWEP: onPipWEP,
                onPipReset: onPipReset
            )

            // Throttle Presets & Boost
            HStack(spacing: 6) {
                ThrottlePresetButton(title: "0%", action: { onSetThrottle(0.0) })
                ThrottlePresetButton(title: "50%", action: { onSetThrottle(0.5) })
                ThrottlePresetButton(title: "100%", action: { onSetThrottle(1.0) })

                Spacer()

                Button(action: onTriggerBoost) {
                    Text(hud.isBoosting ? "BOOSTING" : "BOOST [A]")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(hud.boostChargeFraction >= 0.99 ? Color.cyan.opacity(0.28) : Color.gray.opacity(0.2))
                        .foregroundStyle(hud.boostChargeFraction >= 0.99 ? .cyan : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }

            // Flight Assist, Camera & Live Tuning Drawer buttons
            HStack(spacing: 6) {
                Button(action: onToggleFlightAssist) {
                    Text(hud.flightAssistEnabled ? "FA:ON [B]" : "FA:OFF [B]")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background((hud.flightAssistEnabled ? Color.green : Color.orange).opacity(0.22))
                        .foregroundStyle(hud.flightAssistEnabled ? .green : .orange)
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
                    ForEach(0..<4, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(idx < pips ? color : Color.white.opacity(0.15))
                            .frame(width: 5, height: 11)
                    }
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

private struct SpeedThrottleBar: View {
    let speedFraction: Float
    let throttleFraction: Float
    let isBoosting: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let speedW = max(0, min(w, w * CGFloat(speedFraction)))
            let thrX = max(0, min(w - 3, w * CGFloat(throttleFraction)))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))

                RoundedRectangle(cornerRadius: 4)
                    .fill(isBoosting ? Color.cyan : Color.orange)
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
