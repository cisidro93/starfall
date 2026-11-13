import Foundation
import SwiftUI
import RealityKit
import Darwin

@MainActor
final class DebugMetrics: ObservableObject {
    @Published var fpsText: String = "60.0 FPS"
    @Published var frameTimeText: String = "16.7 ms"
    @Published var entityCountText: String = "0"
    @Published var memoryText: String = "-- MB"
    @Published var thermalText: String = "Nominal"
    @Published var isWithinFrameBudget: Bool = true
    @Published var isExpanded: Bool = true
    @Published var hud = FlightHUDTelemetry()

    private var smoothedDelta: Double = 1.0 / 60.0
    private var timeSinceLastPublish: Double = 0.0

    func recordFrame(deltaTime: TimeInterval, rootEntity: Entity, latestHUD: FlightHUDTelemetry) {
        let clampedDelta = min(max(deltaTime, 0.001), 0.25)
        smoothedDelta = smoothedDelta * 0.9 + clampedDelta * 0.1
        timeSinceLastPublish += clampedDelta

        // Publish HUD telemetry at ~20 Hz so gauges feel instant without saturating SwiftUI
        if timeSinceLastPublish >= 0.05 {
            hud = latestHUD
        }

        guard timeSinceLastPublish >= 0.20 else { return }
        timeSinceLastPublish = 0.0

        let fps = 1.0 / max(smoothedDelta, 0.0001)
        let ms = smoothedDelta * 1000.0
        fpsText = String(format: "%.1f FPS", fps)
        frameTimeText = String(format: "%.2f ms", ms)
        isWithinFrameBudget = ms <= 17.5

        let count = Self.countEntities(in: rootEntity)
        entityCountText = "\(count)"
        memoryText = Self.readMemoryString()
        thermalText = Self.thermalStateString(ProcessInfo.processInfo.thermalState)
    }

    private static func countEntities(in entity: Entity) -> Int {
        var total = 1
        for child in entity.children {
            total += countEntities(in: child)
        }
        return total
    }

    private static func readMemoryString() -> String {
        var usage = rusage()
        let rssMB: Double
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            rssMB = Double(usage.ru_maxrss) / (1024.0 * 1024.0)
        } else {
            rssMB = 0
        }
        let availBytes = os_proc_available_memory()
        let availGB = Double(availBytes) / (1024.0 * 1024.0 * 1024.0)
        if rssMB > 0 && availBytes > 0 {
            return String(format: "%.0f MB (%.1f GB free)", rssMB, availGB)
        } else if availBytes > 0 {
            return String(format: "%.2f GB free", availGB)
        } else {
            return String(format: "%.0f MB", rssMB)
        }
    }

    private static func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

struct DebugOverlayView: View {
    @ObservedObject var metrics: DebugMetrics
    @ObservedObject var inputManager: ControllerInputManager
    @Binding var showSolSheet: Bool

    private var budgetDotColor: Color {
        metrics.isWithinFrameBudget ? .green : .orange
    }

    private var virtualPadButtonLabel: String {
        inputManager.isUsingVirtualController ? "Hide Touch Pad" : "Touch Pad"
    }

    private var toggleExpandLabel: String {
        metrics.isExpanded ? "▾ Hide" : "▸ Telemetry"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(budgetDotColor)
                    .frame(width: 10, height: 10)
                Text("\(metrics.fpsText) • \(metrics.frameTimeText)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Spacer()
                Button {
                    metrics.isExpanded.toggle()
                } label: {
                    Text(toggleExpandLabel)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if metrics.isExpanded {
                DebugMetricRow(label: "ENTITIES", value: metrics.entityCountText)
                DebugMetricRow(label: "MEMORY", value: metrics.memoryText)
                DebugMetricRow(label: "THERMAL", value: metrics.thermalText)

                Divider()
                    .overlay(Color.white.opacity(0.2))

                InputTelemetrySection(
                    statusText: inputManager.controllerStatusText,
                    state: inputManager.state,
                    recentLogs: inputManager.recentLogs
                )

                Divider()
                    .overlay(Color.white.opacity(0.2))

                HStack(spacing: 8) {
                    Button {
                        inputManager.toggleVirtualController()
                    } label: {
                        Text(virtualPadButtonLabel)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.24))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Button {
                        showSolSheet = true
                    } label: {
                        Text("Sol Data [Y]")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.22))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .frame(width: metrics.isExpanded ? 400 : 270, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.70))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct InputTelemetrySection: View {
    let statusText: String
    let state: InputStateComponent
    let recentLogs: [String]

    private var rotAxesText: String {
        String(format: "P:%+.2f  R:%+.2f  Y:%+.2f", state.pitch, state.roll, state.yaw)
    }

    private var thrAxesText: String {
        let thrPct = Int((state.throttle * 100.0).rounded())
        return String(format: "LAT:%+.2f VRT:%+.2f THR:%d%%", state.lateralThrust, state.verticalThrust, thrPct)
    }

    private var flagsText: String {
        let fa = state.flightAssistEnabled ? "FA:ON" : "FA:OFF"
        let hp = state.hardpointsDeployed ? "HP:OUT" : "HP:IN"
        let gear = state.landingGearDeployed ? "GEAR:DN" : "GEAR:UP"
        let mod = state.isModifierHeld ? "[LB HELD]" : ""
        return "\(fa) • \(hp) • \(gear) \(mod)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DebugMetricRow(label: "PAD", value: statusText)
            DebugMetricRow(label: "ATTITUDE", value: rotAxesText)
            DebugMetricRow(label: "THRUST", value: thrAxesText)
            DebugMetricRow(label: "SYSTEMS", value: flagsText)

            if !recentLogs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INPUT LOG:")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.mint)
                    ForEach(Array(recentLogs.prefix(4).enumerated()), id: \.offset) { item in
                        Text("› \(item.element)")
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct DebugMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
