import SwiftUI
import OMMKit

/// The simple line drawing of a stretch or pose, from `StretchFigures`.
struct StretchFigureView: View {
    let stretchID: String
    var color: Color = Theme.primary

    var body: some View {
        Canvas { context, size in
            guard let figure = StretchFigures.figure(for: stretchID) else { return }
            let scale = min(size.width, size.height) / 100
            let origin = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }
            func path(_ line: [Double]) -> Path {
                var path = Path()
                var i = 0
                while i + 1 < line.count {
                    let p = point(line[i], line[i + 1])
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    i += 2
                }
                return path
            }
            let thin = StrokeStyle(lineWidth: max(1, 2 * scale), lineCap: .round, lineJoin: .round)
            let thick = StrokeStyle(lineWidth: max(2, 5 * scale), lineCap: .round, lineJoin: .round)
            for line in figure.props {
                context.stroke(path(line), with: .color(Theme.doneText), style: thin)
            }
            for line in figure.body {
                context.stroke(path(line), with: .color(color), style: thick)
            }
            let r = StretchFigure.headRadius * scale
            let center = point(figure.head.x, figure.head.y)
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
