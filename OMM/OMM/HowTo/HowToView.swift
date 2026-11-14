import SwiftUI
import OMMKit

/// Draws one moment of a how-to move: equipment, then the figure. Side views
/// draw the far arm and leg lighter so you can tell them apart.
struct HowToCanvas: View {
    let move: HowToMove
    let pose: HowToPose

    private static let near = Theme.text
    private static let far = Color(hex: 0xA0AEC0)
    private static let prop = Theme.primary
    private static let propFill = Color(hex: 0xE3E8FB)
    private static let floor = Color(hex: 0xCBD5E0)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / HowToBody.sceneWidth, size.height / HowToBody.sceneHeight)
            let dx = (size.width - HowToBody.sceneWidth * scale) / 2
            let dy = (size.height - HowToBody.sceneHeight * scale) / 2
            context.translateBy(x: dx, y: dy)
            context.scaleBy(x: scale, y: scale)
            draw(in: &context)
        }
        .aspectRatio(HowToBody.sceneWidth / HowToBody.sceneHeight, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext) {
        let figure = move.figure(for: pose)
        let p = figure.pose
        let front = move.view == .front
        let farColor = front ? Self.near : Self.far
        let floorY = HowToBody.floor

        line(&context, [HowToPoint(6, floorY), HowToPoint(194, floorY)], Self.floor, 2)

        // Equipment behind the figure.
        for prop in move.props {
            switch prop {
            case let .bench(x, y, width):
                rect(&context, x: x, y: y, width: width, height: 5)
                line(&context, [HowToPoint(x + 6, y + 5), HowToPoint(x + 6, floorY)], Self.prop, 3)
                line(&context, [HowToPoint(x + width - 6, y + 5), HowToPoint(x + width - 6, floorY)], Self.prop, 3)
            case let .seat(x, y, width, backTop):
                rect(&context, x: x, y: y, width: width, height: 5)
                rect(&context, x: x - 5, y: backTop, width: 5, height: y + 5 - backTop)
                line(&context, [HowToPoint(x + width / 2, y + 5), HowToPoint(x + width / 2, floorY)], Self.prop, 3)
            case let .tower(x, top):
                line(&context, [HowToPoint(x, floorY), HowToPoint(x, top - 8)], Self.prop, 4)
                circle(&context, HowToPoint(x, top), 4, fill: Self.propFill, stroke: Self.prop, width: 2)
            case let .cable(from, nearHand):
                line(&context, [from, nearHand ? figure.nearArm.end : figure.farArm.end], Self.prop, 1.5)
            case let .lever(pivot, postX):
                line(&context, [HowToPoint(postX, floorY), HowToPoint(postX, pivot.y), pivot], Self.prop, 4)
            case .barbell, .dumbbells, .squeeze:
                break
            }
        }

        let hasDumbbells = move.props.contains(.dumbbells)
        if !p.hideBody {
            limb(&context, figure.farLeg, farColor)
        }
        if hasDumbbells && !front {
            dumbbell(&context, at: figure.farArm.end)
        }
        limb(&context, figure.farArm, farColor)
        if front {
            line(&context, [p.shoulder - p.shoulderHalf, p.shoulder + p.shoulderHalf], Self.near, 5)
            if !p.hideBody {
                line(&context, [p.hip - p.hipHalf, p.hip + p.hipHalf], Self.near, 5)
            }
        }
        if !p.hideBody {
            line(&context, [p.hip, p.shoulder], Self.near, 6)
            limb(&context, figure.nearLeg, Self.near)
        }
        circle(&context, figure.head, HowToBody.headRadius, fill: Self.near)
        for prop in move.props {
            if case let .lever(pivot, _) = prop {
                line(&context, [pivot, figure.nearArm.end], Self.prop, 4)
                circle(&context, pivot, 4, fill: Self.propFill, stroke: Self.prop, width: 2)
            }
        }
        limb(&context, figure.nearArm, Self.near)

        // Equipment in the hands, in front of the figure.
        for prop in move.props {
            switch prop {
            case .barbell:
                circle(&context, figure.nearArm.end, 11, fill: Self.propFill, stroke: Self.prop, width: 3)
                circle(&context, figure.nearArm.end, 2.5, fill: Self.prop)
            case .dumbbells:
                if front {
                    circle(&context, figure.nearArm.end, 5, fill: Self.prop)
                    circle(&context, figure.farArm.end, 5, fill: Self.prop)
                } else {
                    dumbbell(&context, at: figure.nearArm.end)
                }
            case .squeeze:
                let c = figure.nearArm.end.mixed(with: figure.farArm.end, 0.5)
                line(&context, [HowToPoint(c.x - 16, c.y - 4), HowToPoint(c.x - 11, c.y), HowToPoint(c.x - 16, c.y + 4)], Self.prop, 2)
                line(&context, [HowToPoint(c.x + 16, c.y - 4), HowToPoint(c.x + 11, c.y), HowToPoint(c.x + 16, c.y + 4)], Self.prop, 2)
            default:
                break
            }
        }
    }

    private func cg(_ p: HowToPoint) -> CGPoint {
        CGPoint(x: p.x, y: p.y)
    }

    private func line(_ context: inout GraphicsContext, _ points: [HowToPoint], _ color: Color, _ width: Double) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: cg(first))
        for point in points.dropFirst() {
            path.addLine(to: cg(point))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func limb(_ context: inout GraphicsContext, _ limb: HowToLimb, _ color: Color) {
        line(&context, [limb.root, limb.joint, limb.end], color, 5)
    }

    private func circle(_ context: inout GraphicsContext, _ center: HowToPoint, _ radius: Double,
                        fill: Color, stroke: Color? = nil, width: Double = 0) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(fill))
        if let stroke {
            context.stroke(path, with: .color(stroke), lineWidth: width)
        }
    }

    private func rect(_ context: inout GraphicsContext, x: Double, y: Double, width: Double, height: Double) {
        let path = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: 2)
        context.fill(path, with: .color(Self.prop))
    }

    private func dumbbell(_ context: inout GraphicsContext, at point: HowToPoint) {
        rect(&context, x: point.x - 7, y: point.y - 3.5, width: 14, height: 7)
    }
}

/// The move playing on a loop. With Reduce Motion on, the start and end
/// poses sit side by side instead.
struct HowToAnimation: View {
    let move: HowToMove
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            HStack(spacing: 8) {
                HowToCanvas(move: move, pose: move.keyPose(0))
                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
                HowToCanvas(move: move, pose: move.keyPose(1))
            }
        } else {
            TimelineView(.animation) { timeline in
                HowToCanvas(move: move, pose: move.pose(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}

/// Opened from an exercise row: the looping drawing and a few form tips.
struct HowToSheet: View {
    let move: HowToMove
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = ExerciseText.split(move.exercise)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HowToAnimation(move: move)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.shadow.opacity(0.12), radius: 10, y: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.text)
                        if let note = text.note {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(move.tips.enumerated()), id: \.offset) { index, tip in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.footnote.weight(.heavy))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.labelBackground, in: Circle())
                                    .accessibilityHidden(true)
                                Text(tip)
                                    .font(.body)
                                    .foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.sheet)
            .navigationTitle("How To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Lets `.sheet(item:)` show a move.
struct HowToItem: Identifiable {
    let move: HowToMove
    var id: String { move.exercise }
}
