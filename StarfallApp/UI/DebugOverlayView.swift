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
    @Published var autoPanEnabled: Bool = true

    private var smoothedDelta: Double = 1.0 / 60.0
    private var timeSinceLastPublish: Double = 0.0

    func recordFrame(deltaTime: TimeInterval, rootEntity: Entity) {
        let clampedDelta = min(max(deltaTime, 0.001), 0.25)
        smoothedDelta = smoothedDelta * 0.9 + clampedDelta * 0.1
        timeSinceLastPublish += clampedDelta

        guard timeSinceLastPublish >= 0.25 else { return }
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
    @Binding var showSolSheet: Bool

    private var budgetDotColor: Color {
        metrics.isWithinFrameBudget ? .green : .orange
    }

    private var autoPanLabel: String {
        metrics.autoPanEnabled ? "Auto-Pan: ON" : "Auto-Pan: OFF"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(budgetDotColor)
                    .frame(width: 10, height: 10)
                Text("STARFALL TELEMETRY")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }

            DebugMetricRow(label: "FRAME", value: "\(metrics.fpsText) (\(metrics.frameTimeText))")
            DebugMetricRow(label: "ENTITIES", value: metrics.entityCountText)
            DebugMetricRow(label: "MEMORY", value: metrics.memoryText)
            DebugMetricRow(label: "THERMAL", value: metrics.thermalText)

            Divider()
                .overlay(Color.white.opacity(0.2))

            HStack(spacing: 10) {
                Button {
                    metrics.autoPanEnabled.toggle()
                } label: {
                    Text(autoPanLabel)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundStyle(.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button {
                    showSolSheet = true
                } label: {
                    Text("Sol Data")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.22))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.68))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DebugMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}
