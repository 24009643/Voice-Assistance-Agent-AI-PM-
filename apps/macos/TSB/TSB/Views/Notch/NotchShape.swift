import SwiftUI

/// Adapted from OpenDictation/Views/Notch/NotchShape.swift (MIT, Copyright (c) 2025 Kenny).
struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14

    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius), control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY), control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius), control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
