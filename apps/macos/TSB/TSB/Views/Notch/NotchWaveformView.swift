import SwiftUI

/// Adapted from OpenDictation/Views/Notch/NotchWaveformView.swift (MIT, Copyright (c) 2025 Kenny).
struct NotchWaveformView: View {
    let audioLevel: Float

    private let scales: [CGFloat] = [0.45, 0.8, 0.6, 0.95]

    var body: some View {
        let level = CGFloat(min(max(audioLevel, 0), 1))
        HStack(spacing: 2) {
            ForEach(scales.indices, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 2, height: 4 + 10 * max(0.35, level) * scales[index])
            }
        }
        .frame(height: 14)
    }
}
