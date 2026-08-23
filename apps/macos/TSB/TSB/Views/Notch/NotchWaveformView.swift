import SwiftUI

/// Adapted from OpenDictation/Views/Notch/NotchWaveformView.swift (MIT, Copyright (c) 2025 Kenny).
struct NotchWaveformView: View {
    let audioLevel: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let scales: [CGFloat] = [0.45, 0.8, 0.6, 0.95, 0.7, 1, 0.55, 0.82]

    var body: some View {
        let level = CGFloat(min(max(audioLevel, 0), 1))
        HStack(alignment: .center, spacing: 2) {
            ForEach(scales.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2.5, height: 4 + 18 * max(0.2, level) * scales[index])
            }
        }
        .frame(width: 36, height: 26)
        .animation(Self.animation(reduceMotion: reduceMotion), value: level)
    }

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.08)
    }
}
