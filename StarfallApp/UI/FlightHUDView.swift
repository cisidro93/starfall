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

    /// Screen-space offset (-120...120 pt) of the velocity prograde vector relative to ship nose.
    var progradeOffsetX: CGFloat = 0.0
    var progradeOffsetY: CGFloat = 0.0
    var hasValidPrograde: Bool = false

    // Double-precision distances in metres
    var stationName: String = "Gagarin Gateway"
    var stationDistanceMetres: Double = 900.0
    var earthAltitudeKm: Double = 9_100.0
    var moonDistanceKm: Double = 384_400.0
    var originRecenterCount: Int = 0
}

struct FlightHUDView: View {
    let hud: FlightHUDTelemetry
    let onToggleCamera: () -> Void
    let onToggleFlightAssist: () -> Void
    let onTriggerBoost: () -> Void
    let onSetThrottle: (Float) -> Void

    var body: some View {
        ZStack {
            // Center reticle + prograde velocity vector pip
            FlightReticleOverlay(
                progradeX: hud.progradeOffsetX,
                progradeY: hud.progradeOffsetY,
                showPrograde: hud.hasValidPrograde,
                isBoosting: hud.isBoosting
            )
            .allowsHitTesting(false)

            // Bottom-left and bottom-right holographic cockpit panels
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    NavigationHoloPanel(hud: hud)
                    Spacer()
                    FlightSystemsHoloPanel(
                        hud: hud,
                        onToggleCamera: onToggleCamera,
                        onToggleFlightAssist: onToggleFlightAssist,
                        onTriggerBoost: onTriggerBoost,
                        onSetThrottle: onSetThrottle
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
        }
    }
}

private struct FlightReticleOverlay: View {
    let progradeX: CGFloat
    let progradeY: CGFloat
    let showPrograde: Bool
    let isBoosting: Bool

    private var ringColor: Color {
        isBoosting ? .cyan : Color.orange.opacity(0.75)
    }

    var body: some View {
        ZStack {
            // Outer boresight brackets
            Circle()
                .trim(from: 0.08, to: 0.42)
                .stroke(ringColor, lineWidth: 1.8)
                .frame(width: 56, height: 56)

            Circle()
                .trim(from: 0.58, to: 0.92)
                .stroke(ringColor, lineWidth: 1.8)
                .frame(width: 56, height: 56)

            // Center nose pip
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)

            // Prograde velocity vector marker (shows true drift direction)
            if showPrograde {
                ZStack {
                    Circle()
                        .stroke(Color.cyan, lineWidth: 2.0)
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 4, height: 4)
                }
                .offset(x: progradeX, y: progradeY)
            }
        }
    }
}

private struct NavigationHoloPanel: View {
    let hud: FlightHUDTelemetry

    private var stationDistanceText: String {
        if hud.stationDistanceMetres >= 1_000.0 {
            return String(format: "%.2f km", hud.stationDistanceMetres / 1_000.0)
        } else {
            return String(format: "%.0f m", hud.stationDistanceMetres)
        }
    }

    private var earthDistanceText: String {
        String(format: "%.0f km", hud.earthAltitudeKm)
    }

    private var moonDistanceText: String {
        String(format: "%.0f km", hud.moonDistanceKm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("SOL SYSTEM • ORBITAL NAV")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            Divider()
                .overlay(Color.orange.opacity(0.35))

            NavRow(label: hud.stationName.uppercased(), value: stationDistanceText, highlight: true)
            NavRow(label: "EARTH ALTITUDE", value: earthDistanceText, highlight: false)
            NavRow(label: "MOON DISTANCE", value: moonDistanceText, highlight: false)
            NavRow(label: "ORIGIN SHIFTS", value: "\(hud.originRecenterCount)", highlight: false)
        }
        .frame(width: 280, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct NavRow: View {
    let label: String
    let value: String
    let highlight: Bool

    private var valueColor: Color {
        highlight ? .cyan : .white
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }
}

private struct FlightSystemsHoloPanel: View {
    let hud: FlightHUDTelemetry
    let onToggleCamera: () -> Void
    let onToggleFlightAssist: () -> Void
    let onTriggerBoost: () -> Void
    let onSetThrottle: (Float) -> Void

    private var speedText: String {
        String(format: "%03.0f", hud.speedMetresPerSec)
    }

    private var throttlePercentText: String {
        let pct = Int((hud.throttle * 100.0).rounded())
        return "THR \(pct)% [LB+RT/LT]"
    }

    private var boostStatusText: String {
        if hud.isBoosting {
            return "BOOSTING"
        } else if hud.boostChargeFraction >= 0.999 {
            return "BOOST READY [A]"
        } else {
            let pct = Int((hud.boostChargeFraction * 100.0).rounded())
            return "CAPACITOR \(pct)%"
        }
    }

    private var faButtonLabel: String {
        hud.flightAssistEnabled ? "FA: ON [B]" : "FA: OFF [B]"
    }

    private var faButtonColor: Color {
        hud.flightAssistEnabled ? .green : .orange
    }

    private var camButtonLabel: String {
        "CAM: \(hud.cameraMode.rawValue) [RB]"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Speed & Boost header
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hud.shipName.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text( throttlePercentText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(speedText)
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(hud.isBoosting ? .cyan : .orange)
                    Text("m/s")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Speed & Throttle horizontal gauge
            SpeedThrottleBar(
                speedFraction: min(1.0, hud.speedMetresPerSec / max(1.0, hud.boostSpeed)),
                throttleFraction: hud.throttle * (hud.maxSpeed / max(1.0, hud.boostSpeed)),
                isBoosting: hud.isBoosting
            )

            // Quick throttle preset buttons + Boost button
            HStack(spacing: 6) {
                ThrottlePresetButton(title: "0%", action: { onSetThrottle(0.0) })
                ThrottlePresetButton(title: "50%", action: { onSetThrottle(0.5) })
                ThrottlePresetButton(title: "100%", action: { onSetThrottle(1.0) })

                Spacer()

                Button(action: onTriggerBoost) {
                    Text(boostStatusText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(hud.boostChargeFraction >= 0.999 ? Color.cyan.opacity(0.28) : Color.gray.opacity(0.2))
                        .foregroundStyle(hud.boostChargeFraction >= 0.999 ? .cyan : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Flight Assist & Camera Mode buttons
            HStack(spacing: 8) {
                Button(action: onToggleFlightAssist) {
                    Text(faButtonLabel)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(faButtonColor.opacity(0.22))
                        .foregroundStyle(faButtonColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button(action: onToggleCamera) {
                    Text(camButtonLabel)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.22))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(width: 340, alignment: .trailing)
        .padding(14)
        .background(Color.black.opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .frame(height: 12)
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
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
