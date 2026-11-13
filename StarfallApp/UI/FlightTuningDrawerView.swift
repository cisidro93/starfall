import SwiftUI

struct FlightTuningDrawerView: View {
    @Binding var spec: ShipSpec
    @Binding var deadZone: Float
    @Binding var responseExponent: Float
    @Binding var minimalHUDMode: Bool
    let onResetDefaults: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLIGHT FEEL & HUD TUNING CONSOLE")
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text("LIVE 60 HZ TELEMETRY OVERRIDE • SF-1V KESTREL")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
                Spacer()
                Button("RESET") {
                    onResetDefaults()
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("DONE") {
                    onClose()
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.28))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()
                .overlay(Color.orange.opacity(0.4))

            Toggle(isOn: $minimalHUDMode) {
                Text("MINIMAL / CINEMATIC HUD MODE (HIDE SIDE PANELS)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            .tint(.cyan)

            ScrollView {
                VStack(spacing: 10) {
                    TuningSliderRow(
                        label: "MAX CRUISE SPEED",
                        value: $spec.maxSpeed,
                        range: 140...450,
                        unit: "m/s",
                        format: "%.0f"
                    )
                    TuningSliderRow(
                        label: "BOOST IMPULSE SPEED",
                        value: $spec.boostSpeed,
                        range: 280...750,
                        unit: "m/s",
                        format: "%.0f"
                    )
                    TuningSliderRow(
                        label: "FORWARD THRUST ACCEL",
                        value: $spec.forwardAcceleration,
                        range: 30...160,
                        unit: "m/s²",
                        format: "%.0f"
                    )
                    TuningSliderRow(
                        label: "LATERAL / VERT STRAFE",
                        value: $spec.lateralAcceleration,
                        range: 20...120,
                        unit: "m/s²",
                        format: "%.0f"
                    )
                    TuningSliderRow(
                        label: "PITCH RATE",
                        value: $spec.pitchRateDeg,
                        range: 35...130,
                        unit: "°/s",
                        format: "%.0f"
                    )
                    TuningSliderRow(
                        label: "ROLL RATE",
                        value: $spec.rollRateDeg,
                        range: 60...240,
                        unit: "°/s",
                        format: "%.0f"
                    )
                    TuningSliderRow(
                        label: "YAW RATE",
                        value: $spec.yawRateDeg,
                        range: 20...95,
                        unit: "°/s",
                        format: "%.0f"
                    )
                    TuningSliderRow(
                        label: "FLIGHT ASSIST DAMPING",
                        value: $spec.linearDampingFA,
                        range: 0.4...5.0,
                        unit: "1/s",
                        format: "%.2f"
                    )
                    TuningSliderRow(
                        label: "STICK DEAD-ZONE",
                        value: $deadZone,
                        range: 0.02...0.28,
                        unit: "",
                        format: "%.2f"
                    )
                    TuningSliderRow(
                        label: "STICK RESPONSE CURVE",
                        value: $responseExponent,
                        range: 1.0...2.8,
                        unit: "exp",
                        format: "%.2f"
                    )
                }
                .padding(.trailing, 4)
            }
        }
        .padding(16)
        .frame(width: 460, height: 470)
        .background(Color.black.opacity(0.90))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.65), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TuningSliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: String
    let format: String

    private var formattedValue: String {
        let num = String(format: format, value)
        return unit.isEmpty ? num : "\(num) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            Slider(value: $value, in: range)
                .tint(.orange)
        }
    }
}
