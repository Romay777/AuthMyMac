import SwiftUI

public struct CountdownIndicator: View {
    private let remainingSeconds: Int
    private let period: Int

    public init(remainingSeconds: Int, period: Int) {
        self.remainingSeconds = remainingSeconds
        self.period = period
    }

    public var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.10), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AuthMyMacColors.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(remainingSeconds, format: .number)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: AuthMyMacMetrics.countdownSize, height: AuthMyMacMetrics.countdownSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue("\(remainingSeconds) seconds")
    }

    private var progress: Double {
        min(max(Double(remainingSeconds) / Double(max(period, 1)), 0), 1)
    }
}
