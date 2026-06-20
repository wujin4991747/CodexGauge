import SwiftUI

// MARK: - Gauge Dial (Canvas-based dashboard gauge)

struct GaugeDial: View {
    let percent: Double      // 0-100
    let state: QuotaState

    // Geometry constants
    private let startDeg: Double = 150
    private let endDeg: Double = 390
    private var sweepDeg: Double { endDeg - startDeg } // 240

    private var needleDeg: Double {
        startDeg + (percent / 100.0) * sweepDeg
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.78)
            let radius = min(size.width / 2 - 12, size.height - 28)

            // ── 1. Background arc (full sweep) ──
            var bg = Path()
            bg.addArc(center: center, radius: radius,
                      startAngle: .degrees(startDeg),
                      endAngle: .degrees(endDeg),
                      clockwise: true)
            context.stroke(bg, with: .color(.white.opacity(0.07)),
                          style: StrokeStyle(lineWidth: 22, lineCap: .round))

            // ── 2. Active arc (gradient via segments) ──
            let totalDeg = sweepDeg
            let activeDeg = (percent / 100.0) * totalDeg
            let segments = 80
            for i in 0..<segments {
                let segStart = startDeg + (totalDeg / Double(segments)) * Double(i)
                if segStart >= startDeg + activeDeg { break }
                let segEnd = min(segStart + totalDeg / Double(segments) + 0.5,
                                 startDeg + activeDeg)
                let t = Double(i) / Double(segments)

                var seg = Path()
                seg.addArc(center: center, radius: radius,
                          startAngle: .degrees(segStart),
                          endAngle: .degrees(segEnd),
                          clockwise: true)
                context.stroke(seg, with: .color(gaugeColor(at: t)),
                              style: StrokeStyle(lineWidth: 16, lineCap: .butt))
            }

            // ── 3. Tick marks ──
            for i in 0...20 {
                let tickPct = Double(i) * 5
                let angle = Angle.degrees(startDeg + tickPct * (totalDeg / 100.0))
                let isMajor = i % 5 == 0
                let innerR = radius - (isMajor ? 16 : 11)
                let outerR = radius + (isMajor ? 8 : 4)

                var tick = Path()
                tick.move(to: point(angle: angle, radius: innerR, center: center))
                tick.addLine(to: point(angle: angle, radius: outerR, center: center))
                context.stroke(tick, with: .color(.white.opacity(isMajor ? 0.45 : 0.15)),
                              style: StrokeStyle(lineWidth: isMajor ? 2 : 1, lineCap: .round))
            }

            // ── 4. Glow arc (wider, transparent, behind active) ──
            var glow = Path()
            glow.addArc(center: center, radius: radius,
                       startAngle: .degrees(startDeg),
                       endAngle: .degrees(startDeg + activeDeg),
                       clockwise: true)
            context.stroke(glow, with: .color(gaugeColor(at: percent / 100.0).opacity(0.25)),
                          style: StrokeStyle(lineWidth: 22, lineCap: .round))

            // ── 5. Needle ──
            let na = Angle.degrees(needleDeg)
            let needleLen = radius - 34
            let baseW = radius * 0.12

            // Needle shadow
            var needleShadow = Path()
            needleShadow.move(to: point(angle: na, radius: needleLen, center: center))
            needleShadow.addLine(to: point(angle: .degrees(needleDeg + 92), radius: baseW, center: center))
            needleShadow.addLine(to: point(angle: .degrees(needleDeg - 92), radius: baseW, center: center))
            needleShadow.closeSubpath()
            context.fill(needleShadow, with: .color(.black.opacity(0.25)))

            // Needle body
            var needle = Path()
            needle.move(to: point(angle: na, radius: needleLen, center: center))
            needle.addLine(to: point(angle: .degrees(needleDeg + 92), radius: baseW * 0.75, center: center))
            needle.addLine(to: point(angle: .degrees(needleDeg - 92), radius: baseW * 0.75, center: center))
            needle.closeSubpath()
            context.fill(needle, with: .color(.white))

            // ── 6. Center cap ──
            let capOuter = Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10,
                                                   width: 20, height: 20))
            context.fill(capOuter, with: .color(.white.opacity(0.95)))
            let capInner = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5,
                                                   width: 10, height: 10))
            context.fill(capInner, with: .color(gaugeColor(at: percent / 100.0)))
        }
        .drawingGroup() // Metal-accelerated
    }

    // ── Helpers ──

    private func point(angle: Angle, radius: Double, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(CGFloat(angle.radians)),
            y: center.y + radius * sin(CGFloat(angle.radians))
        )
    }

    /// Color gradient: 0% red → 50% yellow → 100% green
    private func gaugeColor(at t: Double) -> Color {
        let ct = max(0, min(1, t))
        if ct < 0.5 {
            let s = ct * 2
            return Color(red: 1.0, green: 0.60 * s, blue: 0.05 * s)
        } else {
            let s = (ct - 0.5) * 2
            return Color(red: 1.0 - 0.85 * s, green: 0.60 + 0.30 * s, blue: 0.05 + 0.28 * s)
        }
    }
}

// MARK: - Preview

#Preview("Gauge - 83%") {
    GaugeDial(percent: 83, state: .ok)
        .frame(width: 280, height: 220)
        .padding()
        .background(.black)
}

#Preview("Gauge - 8%") {
    GaugeDial(percent: 8, state: .critical)
        .frame(width: 280, height: 220)
        .padding()
        .background(.black)
}

#Preview("Gauge - 45%") {
    GaugeDial(percent: 45, state: .warning)
        .frame(width: 280, height: 220)
        .padding()
        .background(.black)
}
