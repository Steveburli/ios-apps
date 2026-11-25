import SwiftUI
import ArgumentKit

/// What a stress test has done to the tower so far. TowerView animates between scenes.
struct TowerScene: Equatable {
    /// Claims that have fallen, in the order they fell (even ones fall left, odd ones right).
    var fallen: [String] = []
    /// Source ids an opponent has pulled out.
    var pulled: Set<String> = []
    /// Claims whose belief clouds have blown away.
    var cloudsGone: Set<String> = []
    var toppled = false
    /// The lean once the test is over; nil keeps the evaluation's lean.
    var lean: Double?
    var pressed = false
}

/// The drawing's fixed coordinate space, the same as web/js/tower.js.
enum TowerSpace {
    static let width: CGFloat = 640, height: CGFloat = 560
    static let ground: CGFloat = 482, foot: CGFloat = 404
    static let beamY: CGFloat = 176, beamHeight: CGFloat = 24
    static let spanLeft: CGFloat = 78, spanRight: CGFloat = 562
    static let sag: CGFloat = 48
}

struct TowerColumn: Identifiable {
    var id: String { claim.id }
    let claim: Claim
    let result: ClaimResult?
    let index: Int
    let cx: CGFloat
    let pw: CGFloat
    let slot: CGFloat

    var stability: Double { result?.stability ?? 0 }
    var status: ClaimStatus { result?.status ?? .failing }

    func beamTop(fallen: Bool) -> CGFloat {
        if fallen { return TowerSpace.beamY + TowerSpace.sag * 3 }
        return TowerSpace.beamY + CGFloat(1 - min(1, stability)) * TowerSpace.sag
    }
}

/// An argument map drawn as a building. See web/js/tower.js for the legend.
struct TowerView: View {
    let map: ArgumentMap
    let evaluation: Evaluation
    var scene = TowerScene()
    var compact = false
    /// Bump to shake the tower (earthquake).
    var quake = 0
    /// Bump to sway the tower (wind).
    var gust = 0

    typealias S = TowerSpace

    var columns: [TowerColumn] {
        let roots = map.roots
        let n = CGFloat(max(1, roots.count))
        let slot = (S.spanRight - S.spanLeft) / n
        return roots.enumerated().map { i, claim in
            let r = evaluation.claims[claim.id]
            let cx = S.spanLeft + slot * (CGFloat(i) + 0.5)
            let pw = max(16, min(96, slot * (0.2 + 0.5 * CGFloat(min(1, r?.strength ?? 0)))))
            return TowerColumn(claim: claim, result: r, index: i, cx: cx, pw: pw, slot: slot)
        }
    }

    var leanDegrees: Double {
        if scene.toppled {
            let dir: Double = (scene.lean ?? evaluation.lean) < 0 ? -1 : 1
            return dir * 9
        }
        return scene.lean ?? evaluation.lean
    }

    var body: some View {
        GeometryReader { geo in
            drawing
                .frame(width: S.width, height: S.height, alignment: .topLeading)
                .scaleEffect(geo.size.width / S.width, anchor: .topLeading)
        }
        .aspectRatio(S.width / S.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 14))
        .overlay(RoundedRectangle(cornerRadius: compact ? 6 : 14).stroke(Theme.line))
        .accessibilityElement()
        .accessibilityLabel(description)
    }

    var description: String {
        if map.claims.isEmpty { return "An empty lot: no reasons yet." }
        return "A tower for \(map.thesis.isEmpty ? map.topic : map.thesis): \(evaluation.grade.label), \(evaluation.score.percent) stable, leaning \(Int(abs(evaluation.lean).rounded())) degrees."
    }

    var drawing: some View {
        let cols = columns
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Theme.skyTop, Theme.skyBottom], startPoint: .top, endPoint: .bottom)
                .frame(width: S.width, height: S.ground)
            if !compact {
                Canvas { context, _ in
                    context.opacity = 0.7
                    for (x, y, w) in [(90.0, 74.0, 70.0), (540.0, 52.0, 54.0)] {
                        let p = cloudPath(cx: x, cy: y, w: w)
                        context.fill(p, with: .color(Theme.cloud))
                        context.stroke(p, with: .color(Theme.cloudEdge), lineWidth: 1.5)
                    }
                }
                .frame(width: S.width, height: S.height)
                .offset(x: gust > 0 && !scene.cloudsGone.isEmpty ? 160 : 0)
            }
            structure(cols)
                .rotationEffect(.degrees(leanDegrees), anchor: UnitPoint(x: 0.5, y: S.ground / S.height))
                .shadow(color: scene.pressed ? Theme.failing : .clear, radius: 6)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: quake) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-6, duration: 0.06)
                        LinearKeyframe(5, duration: 0.06)
                        LinearKeyframe(-5, duration: 0.06)
                        LinearKeyframe(6, duration: 0.06)
                        LinearKeyframe(-4, duration: 0.06)
                        LinearKeyframe(5, duration: 0.06)
                        LinearKeyframe(-6, duration: 0.06)
                        LinearKeyframe(4, duration: 0.06)
                        LinearKeyframe(-3, duration: 0.06)
                        LinearKeyframe(3, duration: 0.06)
                        LinearKeyframe(0, duration: 0.06)
                    }
                }
                .keyframeAnimator(initialValue: CGFloat(0), trigger: gust) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(6, duration: 0.45)
                        CubicKeyframe(-2, duration: 0.45)
                        CubicKeyframe(5, duration: 0.45)
                        CubicKeyframe(0, duration: 0.45)
                    }
                }
            ground(cols)
        }
        .frame(width: S.width, height: S.height, alignment: .topLeading)
    }

    // MARK: Structure

    func structure(_ cols: [TowerColumn]) -> some View {
        ZStack(alignment: .topLeading) {
            if cols.isEmpty {
                Text("Add a reason to raise the first pillar")
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .position(x: S.width / 2, y: 320)
            }
            ForEach(cols) { col in
                supports(col)
                pillar(col)
            }
            if !cols.isEmpty {
                roof(cols)
            }
        }
        .frame(width: S.width, height: S.height, alignment: .topLeading)
    }

    func fallAngle(_ id: String) -> Double {
        guard let i = scene.fallen.firstIndex(of: id) else { return 0 }
        return i % 2 == 0 ? -72 : 72
    }

    func pillar(_ col: TowerColumn) -> some View {
        let id = col.claim.id
        let angle = fallAngle(id)
        return ZStack {
            Canvas { context, _ in drawPillar(col, in: &context) }
                .frame(width: S.width, height: S.height)
            Canvas { context, _ in drawCounters(col, in: &context) }
                .frame(width: S.width, height: S.height)
                .opacity(angle == 0 ? 1 : 0)
        }
        .rotationEffect(.degrees(angle), anchor: UnitPoint(x: col.cx / S.width, y: S.foot / S.height))
        .opacity(angle == 0 ? 1 : 0.6)
    }

    func drawPillar(_ col: TowerColumn, in context: inout GraphicsContext) {
        let top = col.beamTop(fallen: false) + S.beamHeight
        let h = S.foot - top
        let x = col.cx - col.pw / 2
        var rnd = Jitter(seed: col.claim.id)
        let status = col.status
        let termites = col.result?.termites ?? false

        let shaft = Path(CGRect(x: x, y: top, width: col.pw, height: h))
        context.fill(shaft, with: .color(termites ? Theme.stoneDark : Theme.stone))
        let edge: Color = {
            switch status {
            case .solid: return Theme.stoneEdge
            case .strained: return Theme.strained
            case .sagging: return Theme.sagging
            case .failing, .fallen: return Theme.failing
            }
        }()
        context.stroke(shaft, with: .color(edge), style: StrokeStyle(lineWidth: 2, dash: termites ? [4, 3] : []))
        let flutes = max(1, Int(col.pw / 14))
        for i in 1...flutes {
            let fx = x + col.pw * CGFloat(i) / CGFloat(flutes + 1)
            var line = Path()
            line.move(to: CGPoint(x: fx, y: top + 6))
            line.addLine(to: CGPoint(x: fx, y: S.foot - 6))
            context.stroke(line, with: .color(Theme.stoneEdge.opacity(0.35)), lineWidth: 1.2)
        }
        for y in [top - 2, S.foot - 8] {
            let cap = Path(roundedRect: CGRect(x: x - 5, y: y, width: col.pw + 10, height: 8), cornerRadius: 1)
            context.fill(cap, with: .color(Theme.stoneDark))
            context.stroke(cap, with: .color(Theme.stoneEdge), lineWidth: 1.5)
        }
        let cracks: Int = {
            switch status {
            case .solid: return 0
            case .strained: return 1
            case .sagging: return 2
            case .failing, .fallen: return 3
            }
        }()
        for _ in 0..<cracks {
            let y0 = top + 12 + rnd.next() * h * 0.4
            let y1 = y0 + h * (0.25 + rnd.next() * 0.3)
            var crack = Path()
            crack.move(to: CGPoint(x: col.cx + (rnd.next() - 0.5) * col.pw * 0.5, y: y0))
            for step in 1...5 {
                let y = y0 + (y1 - y0) * CGFloat(step) / 5
                crack.addLine(to: CGPoint(x: col.cx + (rnd.next() - 0.5) * col.pw * 0.7, y: y))
            }
            context.stroke(crack, with: .color(Theme.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        if termites {
            for _ in 0..<7 {
                let hx = x + 4 + rnd.next() * (col.pw - 8)
                let hy = top + 14 + rnd.next() * (h - 28)
                let rx = 1.6 + rnd.next() * 2, ry = 1.2 + rnd.next() * 1.6
                context.fill(Path(ellipseIn: CGRect(x: hx - rx, y: hy - ry, width: rx * 2, height: ry * 2)), with: .color(Theme.ink.opacity(0.7)))
            }
        }
        if !compact {
            let badge = Path(ellipseIn: CGRect(x: col.cx - 10, y: top + 12, width: 20, height: 20))
            context.fill(badge, with: .color(Theme.surface))
            context.stroke(badge, with: .color(Theme.stoneEdge), lineWidth: 1.5)
            context.draw(Text("\(col.index + 1)").font(Theme.mono(12, weight: .bold)).foregroundStyle(Theme.ink),
                         at: CGPoint(x: col.cx, y: top + 22))
        }
    }

    func drawCounters(_ col: TowerColumn, in context: inout GraphicsContext) {
        let top = col.beamTop(fallen: false) + S.beamHeight
        for (i, k) in col.claim.counters.enumerated() {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            let ax = col.cx + side * (col.pw / 2 + 4)
            let ay = top + 40 + CGFloat(i) * 34
            if ay > S.foot - 20 { continue }
            let len = 14 + CGFloat(k.strength) * 5
            let color = k.answered ? Theme.muted : Theme.failing
            var shaft = Path()
            shaft.move(to: CGPoint(x: ax + side * len, y: ay))
            shaft.addLine(to: CGPoint(x: ax + side * 6, y: ay))
            context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var head = Path()
            head.move(to: CGPoint(x: ax + side * 7, y: ay - 5))
            head.addLine(to: CGPoint(x: ax, y: ay))
            head.addLine(to: CGPoint(x: ax + side * 7, y: ay + 5))
            head.closeSubpath()
            context.fill(head, with: .color(color))
            if k.answered {
                var bar = Path()
                bar.move(to: CGPoint(x: ax + side * 9, y: ay - 7))
                bar.addLine(to: CGPoint(x: ax + side * 9, y: ay + 7))
                context.stroke(bar, with: .color(Theme.solid), lineWidth: 3.5)
            }
        }
    }

    // MARK: Supports

    enum SupportItem {
        case post(Source)
        case block(Claim, Int)
        case cloud
    }

    func supportItems(_ col: TowerColumn) -> [SupportItem] {
        let dropped = Set(col.result?.droppedSources ?? [])
        var items: [SupportItem] = col.claim.sources.filter { !dropped.contains($0.id) }.prefix(3).map { .post($0) }
        for (i, kid) in map.children(of: col.claim.id).enumerated() { items.append(.block(kid, i)) }
        if col.claim.cloud { items.append(.cloud) }
        return items
    }

    func supports(_ col: TowerColumn) -> some View {
        let items = supportItems(col)
        let footW = max(col.pw + 18, min(col.slot - 8, 26 + CGFloat(items.count) * 26))
        let x0 = col.cx - footW / 2
        let gap = footW / CGFloat(max(1, items.count))
        let postXs: [CGFloat] = items.enumerated().compactMap { i, item in
            if case .post = item { return x0 + gap * (CGFloat(i) + 0.5) }
            return nil
        }
        let anyPulled = col.claim.sources.contains { scene.pulled.contains($0.id) }

        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let footing = Path(roundedRect: CGRect(x: x0, y: S.foot, width: footW, height: 12), cornerRadius: 2)
                context.fill(footing, with: .color(Theme.stoneDark))
                context.stroke(footing, with: .color(Theme.stoneEdge), lineWidth: 1.5)
                if items.isEmpty {
                    let void = Path(roundedRect: CGRect(x: x0 + 4, y: S.foot + 14, width: footW - 8, height: S.ground - S.foot - 16), cornerRadius: 3)
                    context.stroke(void, with: .color(Theme.failing), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    if !compact {
                        context.draw(Text("no support").font(Theme.mono(12)).foregroundStyle(Theme.failing),
                                     at: CGPoint(x: col.cx, y: S.foot + 46))
                    }
                }
                // Distrusted sources lie on the ground.
                let ghosts = col.claim.sources.filter { (col.result?.droppedSources ?? []).contains($0.id) }.prefix(3)
                for (i, _) in ghosts.enumerated() {
                    let gx = x0 + 6 + CGFloat(i) * 10
                    var ctx = context
                    ctx.translateBy(x: gx, y: S.ground)
                    ctx.rotate(by: .degrees(-8 + Double(i) * 6))
                    ctx.fill(Path(CGRect(x: 0, y: -5, width: 22, height: 4)), with: .color(Theme.stoneDark.opacity(0.8)))
                }
            }
            .frame(width: S.width, height: S.height)

            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let x = x0 + gap * (CGFloat(i) + 0.5)
                switch item {
                case .post(let source):
                    let pulled = scene.pulled.contains(source.id)
                    Rectangle()
                        .fill(Theme.stone)
                        .overlay(Rectangle().stroke(Theme.stoneEdge, lineWidth: 1.5))
                        .frame(width: 6, height: S.ground - S.foot - 12)
                        .rotationEffect(.degrees(pulled ? 60 : 0), anchor: .bottom)
                        .offset(y: pulled ? 40 : 0)
                        .opacity(pulled ? 0 : 1)
                        .position(x: x, y: S.foot + 12 + (S.ground - S.foot - 12) / 2)
                case .block(let kid, let k):
                    block(kid, index: k, colIndex: col.index, x: x, gap: gap)
                case .cloud:
                    let gone = scene.cloudsGone.contains(col.claim.id)
                    CloudShape()
                        .fill(Theme.cloud)
                        .overlay(CloudShape().stroke(Theme.cloudEdge, lineWidth: 1.5))
                        .frame(width: min(gap + 14, 56), height: 34)
                        .position(x: x, y: S.ground - 26)
                        .offset(x: gone ? 700 : 0)
                        .opacity(gone ? 0 : 1)
                }
            }

            if postXs.count >= 3 {
                Canvas { context, _ in
                    let a = postXs[0], b = postXs[2]
                    var brace = Path()
                    brace.move(to: CGPoint(x: a, y: S.foot + 18))
                    brace.addLine(to: CGPoint(x: b, y: S.ground - 4))
                    brace.move(to: CGPoint(x: b, y: S.foot + 18))
                    brace.addLine(to: CGPoint(x: a, y: S.ground - 4))
                    context.stroke(brace, with: .color(Theme.stoneEdge), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .frame(width: S.width, height: S.height)
                .opacity(anyPulled ? 0 : 1)
            }
        }
        .frame(width: S.width, height: S.height, alignment: .topLeading)
    }

    func block(_ kid: Claim, index: Int, colIndex: Int, x: CGFloat, gap: CGFloat) -> some View {
        let r = evaluation.claims[kid.id]
        let status = r?.status ?? .failing
        let bw = max(10, min(gap - 4, 10 + 20 * CGFloat(min(1, r?.strength ?? 0))))
        let h = S.ground - S.foot - 14
        let angle = fallAngle(kid.id)
        let label = "\(colIndex + 1)" + ArgumentMap.letter(index)
        return ZStack {
            RoundedRectangle(cornerRadius: 2).fill(Theme.soft(status))
            RoundedRectangle(cornerRadius: 2).stroke(Theme.stoneEdge, lineWidth: 1.5)
            if !compact {
                Text(label).font(Theme.mono(10, weight: .bold)).foregroundStyle(Theme.ink).fixedSize()
            }
        }
        .frame(width: bw, height: h)
        .rotationEffect(.degrees(angle), anchor: .bottom)
        .opacity(angle == 0 ? 1 : 0.6)
        .position(x: x, y: S.foot + 14 + h / 2)
    }

    // MARK: Roof

    func roof(_ cols: [TowerColumn]) -> some View {
        let fallen = Set(scene.fallen)
        let tops = cols.map { Double($0.beamTop(fallen: fallen.contains($0.claim.id))) }
        let xs = cols.map(\.cx)
        let dir: CGFloat = leanDegrees < 0 ? -1 : 1
        return ZStack(alignment: .topLeading) {
            RoofShape(xs: xs, tops: AnimatableVector(values: tops), part: .pediment)
                .fill(Theme.stoneDark)
            RoofShape(xs: xs, tops: AnimatableVector(values: tops), part: .pediment)
                .stroke(Theme.stoneEdge, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            RoofShape(xs: xs, tops: AnimatableVector(values: tops), part: .beam)
                .fill(Theme.stone)
            RoofShape(xs: xs, tops: AnimatableVector(values: tops), part: .beam)
                .stroke(Theme.stoneEdge, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            if !compact {
                let peak = tops.reduce(0, +) / Double(tops.count) - 74
                Text("LOAD \(evaluation.weight)")
                    .font(Theme.mono(12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .fixedSize()
                    .position(x: 320, y: peak + 48)
            }
            if evaluation.flags.headInClouds && !compact {
                let peak = tops.reduce(0, +) / Double(tops.count) - 74
                let xs: [CGFloat] = [250, 390]
                let dys: [CGFloat] = [20, 8]
                let ws: [CGFloat] = [70, 80]
                ForEach(0..<2, id: \.self) { i in
                    CloudShape()
                        .fill(Theme.cloud)
                        .overlay(CloudShape().stroke(Theme.cloudEdge, lineWidth: 1.5))
                        .frame(width: ws[i], height: ws[i] * 0.5)
                        .position(x: xs[i], y: peak + dys[i])
                        .offset(x: scene.cloudsGone.isEmpty ? 0 : 700)
                }
            }
        }
        .frame(width: S.width, height: S.height, alignment: .topLeading)
        .rotationEffect(.degrees(scene.toppled ? Double(dir) * 24 : 0), anchor: .center)
        .offset(x: scene.toppled ? dir * 60 : 0, y: scene.toppled ? 200 : 0)
    }

    // MARK: Ground

    func ground(_ cols: [TowerColumn]) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let rect = CGRect(x: 0, y: S.ground, width: S.width, height: S.height - S.ground)
                context.fill(Path(rect), with: .color(Theme.soil))
                var hatch = context
                hatch.clip(to: Path(rect))
                var x: CGFloat = -200
                while x < S.width + 200 {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: S.ground))
                    line.addLine(to: CGPoint(x: x + 46, y: S.height))
                    hatch.stroke(line, with: .color(Theme.soilDark), lineWidth: 6)
                    x += 16
                }
                var grade = Path()
                grade.move(to: CGPoint(x: 0, y: S.ground))
                grade.addLine(to: CGPoint(x: S.width, y: S.ground))
                context.stroke(grade, with: .color(Theme.ink.opacity(0.35)), lineWidth: 1.5)
                if !compact {
                    for col in cols {
                        let tier = (col.result?.tier ?? "").isEmpty ? "–" : (col.result?.tier ?? "")
                        context.draw(Text("\(col.index + 1) · \(tier)").font(Theme.mono(13)).foregroundStyle(Color(light: 0xF4EFE6, dark: 0xF4EFE6)),
                                     at: CGPoint(x: col.cx, y: S.ground + 22))
                    }
                }
            }
            .frame(width: S.width, height: S.height)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shapes

func cloudPath(cx: CGFloat, cy: CGFloat, w: CGFloat) -> Path {
    let r = w / 4
    var p = Path()
    p.move(to: CGPoint(x: cx - 2 * r, y: cy + r * 0.6))
    p.addCurve(to: CGPoint(x: cx - 1.6 * r, y: cy - r * 0.7), control1: CGPoint(x: cx - 2.6 * r, y: cy), control2: CGPoint(x: cx - 2.2 * r, y: cy - r * 0.8))
    p.addCurve(to: CGPoint(x: cx + 0.2 * r, y: cy - r * 1.2), control1: CGPoint(x: cx - 1.3 * r, y: cy - 1.8 * r), control2: CGPoint(x: cx - 0.1 * r, y: cy - 1.9 * r))
    p.addCurve(to: CGPoint(x: cx + 1.8 * r, y: cy - r * 0.5), control1: CGPoint(x: cx + 0.9 * r, y: cy - 1.9 * r), control2: CGPoint(x: cx + 1.9 * r, y: cy - 1.4 * r))
    p.addCurve(to: CGPoint(x: cx + 2 * r, y: cy + r * 0.6), control1: CGPoint(x: cx + 2.5 * r, y: cy - r * 0.4), control2: CGPoint(x: cx + 2.6 * r, y: cy + r * 0.5))
    p.closeSubpath()
    return p
}

/// A cloud that fills its frame.
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 1.25
        return cloudPath(cx: rect.midX, cy: rect.midY + rect.height * 0.15, w: w)
    }
}

/// A list of numbers SwiftUI can animate between, for the roof's sag over each pillar.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, +)
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, -)
    }

    private static func combine(_ a: AnimatableVector, _ b: AnimatableVector, _ op: (Double, Double) -> Double) -> AnimatableVector {
        let n = max(a.values.count, b.values.count)
        return AnimatableVector(values: (0..<n).map { i in
            op(i < a.values.count ? a.values[i] : 0, i < b.values.count ? b.values[i] : 0)
        })
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

/// The beam across the pillar tops, or the pediment above it, in the tower's coordinates.
struct RoofShape: Shape {
    enum Part { case beam, pediment }
    let xs: [CGFloat]
    var tops: AnimatableVector
    let part: Part

    var animatableData: AnimatableVector {
        get { tops }
        set { tops = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let ys = (0..<xs.count).map { i in CGFloat(i < tops.values.count ? tops.values[i] : Double(TowerSpace.beamY)) }
        guard let firstX = xs.first, let lastX = xs.last, let firstY = ys.first, let lastY = ys.last else { return Path() }
        let points = [CGPoint(x: TowerSpace.spanLeft - 26, y: firstY)] + zip(xs, ys).map { CGPoint(x: $0, y: $1) }
            + [CGPoint(x: TowerSpace.spanRight + 26, y: lastY)]
        _ = firstX; _ = lastX
        var p = Path()
        switch part {
        case .beam:
            p.move(to: points[0])
            for pt in points.dropFirst() { p.addLine(to: pt) }
            for pt in points.reversed() { p.addLine(to: CGPoint(x: pt.x, y: pt.y + TowerSpace.beamHeight)) }
            p.closeSubpath()
        case .pediment:
            let peak = ys.reduce(0, +) / CGFloat(ys.count) - 74
            let l = points[0], r = points[points.count - 1]
            p.move(to: CGPoint(x: l.x - 8, y: l.y))
            p.addLine(to: CGPoint(x: 320, y: peak))
            p.addLine(to: CGPoint(x: r.x + 8, y: r.y))
            p.closeSubpath()
        }
        return p
    }
}

/// Repeatable jitter, so cracks and termite holes stay put between redraws.
struct Jitter {
    private var state: UInt32

    init(seed: String) {
        var h: UInt32 = 2_166_136_261
        for byte in seed.utf8 {
            h ^= UInt32(byte)
            h = h &* 16_777_619
        }
        state = h == 0 ? 1 : h
    }

    mutating func next() -> CGFloat {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return CGFloat(state % 10_000) / 10_000
    }
}
