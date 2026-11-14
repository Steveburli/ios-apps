/// A simple line drawing of a stretch, on a 100 × 100 grid with y pointing
/// down. The app draws `body` as thick lines, `head` as a circle and `props`
/// (ground, wall, step, towel) as thin grey lines.
public struct StretchFigure: Sendable {
    /// Center of the head.
    public let head: (x: Double, y: Double)
    /// Polylines as flat x, y pairs.
    public let body: [[Double]]
    public let props: [[Double]]

    public static let headRadius = 6.0
}

/// One drawing per library move, keyed by `Stretch.id`. Drawn for this app.
public enum StretchFigures {
    public static func figure(for id: String) -> StretchFigure? {
        all[id]
    }

    private static let ground: [Double] = [2, 90, 98, 90]

    // Standing pieces, side view facing right.
    private static func standingLegs(_ x: Double) -> [[Double]] {
        [[x, 52, x, 70, x, 88], [x, 52, x + 2, 70, x + 4, 88]]
    }

    // Standing pieces, front view.
    private static let frontTorso: [Double] = [50, 20, 50, 54]
    private static let frontShoulders: [Double] = [39, 26, 61, 26]
    private static let frontLegs: [[Double]] = [[50, 54, 43, 71, 41, 88], [50, 54, 57, 71, 59, 88]]

    /// `legsAt` adds side-view standing legs at that x; `front` adds front-view legs.
    private static func fig(_ head: (Double, Double), _ body: [[Double]], legsAt: Double? = nil,
                            front: Bool = false, props: [[Double]] = [ground]) -> StretchFigure {
        var lines = body
        if let legsAt { lines.append(contentsOf: standingLegs(legsAt)) }
        if front { lines.append(contentsOf: frontLegs) }
        return StretchFigure(head: (head.0, head.1), body: lines, props: props)
    }

    static let all: [String: StretchFigure] = {
        var figures: [String: StretchFigure] = [:]
        // Core
        figures["cobra-lift"] = fig((85, 52), [[12, 88, 34, 87, 55, 86, 78, 62], [78, 62, 79, 75, 80, 88]])
        figures["sphinx"] = fig((81, 60), [[12, 88, 32, 87, 52, 87, 72, 70], [72, 70, 73, 88, 90, 88]])
        figures["lying-twist"] = fig((50, 16), [[50, 22, 50, 56], [16, 28, 84, 28], [50, 56, 72, 50, 74, 72], [50, 56, 66, 60, 68, 84]],
                                      props: [[8, 4, 92, 4, 92, 96, 8, 96, 8, 4]])
        figures["side-reach"] = fig((38, 16), [[50, 56, 48, 40, 43, 24], [35, 27, 51, 22], [51, 22, 45, 8, 31, 3], [35, 27, 31, 42, 33, 56],
                                     [50, 56, 44, 72, 42, 88], [50, 56, 56, 72, 58, 88]])
        figures["seated-twist"] = fig((34, 47), [[34, 86, 34, 54], [34, 86, 60, 87, 84, 87], [34, 86, 50, 64, 47, 87],
                                       [34, 60, 46, 64, 50, 64], [34, 60, 22, 73, 16, 87]])
        // Thighs
        figures["quad-pull"] = fig((45, 13), [[45, 20, 45, 52], [45, 52, 45, 70, 46, 88], [45, 52, 47, 70, 33, 58],
                                    [45, 26, 37, 43, 33, 57], [45, 26, 62, 34, 74, 36]],
                         props: [ground, [76, 8, 76, 90]])
        figures["hamstring-reach"] = fig((55, 54), [[30, 86, 56, 87, 82, 87], [30, 86, 48, 62], [48, 62, 64, 72, 78, 80],
                                          [30, 86, 40, 77, 45, 87]])
        figures["forward-fold"] = fig((59, 77), [[42, 88, 41, 69, 40, 50], [40, 50, 50, 57, 56, 68], [55, 66, 62, 77, 64, 88]])
        figures["butterfly"] = fig((50, 43), [[50, 50, 50, 80], [42, 54, 58, 54], [50, 82, 28, 74, 48, 88], [50, 82, 72, 74, 52, 88],
                                    [42, 54, 39, 70, 47, 86], [58, 54, 61, 70, 53, 86]])
        figures["figure-four"] = fig((14, 84), [[21, 86, 52, 86], [52, 86, 66, 66, 78, 88], [52, 86, 46, 66, 66, 64],
                                      [25, 85, 40, 74, 50, 68]])
        figures["low-lunge"] = fig((49, 31), [[46, 70, 48, 39], [46, 70, 68, 68, 70, 88], [46, 70, 30, 88, 12, 88],
                                    [48, 43, 51, 24, 53, 6]])
        figures["warrior-two"] = fig((52, 16), [[50, 23, 50, 56], [14, 28, 86, 28], [50, 56, 68, 68, 70, 88], [50, 56, 34, 72, 18, 88]])
        figures["happy-baby"] = fig((14, 84), [[21, 86, 50, 86], [50, 86, 62, 66, 58, 46], [50, 86, 56, 68, 52, 48],
                                     [25, 84, 42, 64, 56, 48]])
        figures["bridge"] = fig((12, 83), [[20, 87, 50, 62], [50, 62, 66, 63, 70, 88], [22, 88, 36, 88, 50, 88]])
        // Calves
        figures["wall-calf"] = fig((64, 20), [[49, 54, 61, 28], [61, 30, 71, 33, 81, 30], [49, 54, 60, 70, 62, 88],
                                    [49, 54, 36, 71, 24, 88]],
                         props: [ground, [83, 8, 83, 90]])
        figures["heel-drop"] = fig((52, 12), [[52, 19, 52, 50], [52, 50, 51, 64, 46, 79], [42, 81, 53, 78], [52, 26, 66, 32, 79, 34]],
                         props: [ground, [48, 78, 88, 78], [88, 78, 88, 90], [80, 30, 80, 78]])
        figures["calf-towel"] = fig((36, 50), [[28, 86, 56, 87, 80, 86, 82, 78], [28, 86, 34, 57], [34, 62, 52, 68, 66, 72]],
                          props: [ground, [66, 72, 84, 76, 82, 86]])
        figures["shin-stretch"] = fig((50, 13), [[50, 20, 50, 52], [50, 52, 52, 70, 52, 88], [50, 52, 42, 70, 34, 84, 26, 88],
                                       [50, 26, 60, 34, 71, 34]],
                            props: [ground, [73, 8, 73, 90]])
        figures["downward-dog"] = fig((67, 72), [[20, 88, 32, 61, 44, 34], [44, 34, 62, 62], [62, 62, 80, 88]])
        // Chest
        figures["doorway-opener"] = fig((61, 16), [[55, 23, 47, 54], [55, 26, 44, 26, 44, 12], [47, 54, 57, 70, 59, 88],
                                         [47, 54, 39, 72, 31, 88]],
                              props: [ground, [44, 4, 44, 90]])
        figures["hands-behind"] = fig((51, 13), [[50, 20, 50, 52], [50, 26, 38, 44, 30, 50]], legsAt: 50)
        figures["wall-chest"] = fig((56, 14), [[56, 21, 56, 54], [46, 26, 66, 26], [46, 26, 32, 26, 21, 26], [66, 26, 68, 41, 68, 56],
                                     [56, 54, 50, 71, 48, 88], [56, 54, 62, 71, 64, 88]],
                          props: [ground, [19, 6, 19, 90]])
        figures["puppy"] = fig((64, 84), [[14, 88, 34, 88, 34, 62], [34, 62, 58, 80], [58, 80, 76, 88, 94, 88]])
        // Back
        figures["childs-pose"] = fig((67, 83), [[20, 88, 46, 88, 26, 78], [26, 78, 60, 80], [60, 80, 76, 86, 93, 88]])
        figures["knee-hug"] = fig((14, 84), [[21, 86, 50, 86], [50, 86, 36, 66, 54, 66], [25, 84, 30, 73, 38, 67]])
        figures["neck-tilt"] = fig((58, 17), [[50, 26, 54, 22], [50, 26, 50, 56], [38, 30, 62, 30], [62, 30, 68, 16, 61, 10],
                                    [38, 30, 36, 46, 36, 60], [50, 56, 44, 72, 42, 88], [50, 56, 56, 72, 58, 88]])
        figures["cat-cow"] = fig((68, 66), [[30, 58, 46, 47, 62, 58], [62, 58, 62, 88], [30, 58, 30, 88, 14, 88]])
        // Shoulders
        figures["cross-arm"] = fig((50, 13), [frontTorso, frontShoulders, [61, 26, 44, 32, 27, 34], [39, 26, 40, 40, 47, 33]], front: true)
        figures["thread-needle"] = fig((68, 80), [[30, 58, 60, 66], [30, 58, 30, 88, 14, 88], [60, 66, 64, 88], [60, 66, 50, 82, 36, 87]])
        figures["eagle-arms"] = fig((50, 13), [frontTorso, frontShoulders, [61, 26, 53, 38, 48, 14], [39, 26, 47, 38, 52, 14]], front: true)
        figures["upward-reach"] = fig((50, 14), [frontTorso, frontShoulders, [39, 26, 38, 12, 41, 1], [61, 26, 62, 12, 59, 1]], front: true)
        // Arms
        figures["triceps-reach"] = fig((50, 13), [frontTorso, frontShoulders, [61, 26, 60, 4, 53, 24], [39, 26, 40, 10, 57, 5]], front: true)
        figures["wrist-pull"] = fig((41, 13), [[40, 20, 40, 52], [40, 27, 58, 28, 74, 28, 78, 36], [40, 28, 56, 38, 77, 36]], legsAt: 40)
        figures["biceps-wall"] = fig((53, 14), [[52, 21, 52, 54], [52, 28, 36, 40, 21, 50]], legsAt: 52,
                           props: [ground, [19, 6, 19, 90]])
        figures["prayer-hands"] = fig((50, 13), [frontTorso, frontShoulders, [39, 26, 32, 42, 50, 40, 50, 30], [61, 26, 68, 42, 50, 40]], front: true)
        return figures
    }()
}
