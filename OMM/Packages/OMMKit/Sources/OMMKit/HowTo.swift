import Foundation

// Looping stick-figure how-to animations, one per exercise. The drawings are
// original and live as data in HowToMoves.swift, which is generated from
// OMM/tools/howto/moves.js (see the README there). This file is the shared
// math: poses blend over time, then elbows and knees are worked out from fixed
// bone lengths so limbs never stretch. The app only has to draw lines.
//
// The scene is 200 × 140 points with y growing down and the floor at y = 124.

public struct HowToPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = HowToPoint(0, 0)

    public static func + (a: HowToPoint, b: HowToPoint) -> HowToPoint { HowToPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: HowToPoint, b: HowToPoint) -> HowToPoint { HowToPoint(a.x - b.x, a.y - b.y) }
    public static func * (a: HowToPoint, k: Double) -> HowToPoint { HowToPoint(a.x * k, a.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public var unit: HowToPoint {
        let l = length
        return l > 0 ? HowToPoint(x / l, y / l) : .zero
    }

    /// Turns the vector; with y pointing down, positive angles turn clockwise on screen.
    public func rotated(by radians: Double) -> HowToPoint {
        HowToPoint(x * cos(radians) - y * sin(radians), x * sin(radians) + y * cos(radians))
    }

    public func mixed(with other: HowToPoint, _ t: Double) -> HowToPoint {
        HowToPoint(x + (other.x - x) * t, y + (other.y - y) * t)
    }
}

/// Body measurements and the scene size, shared by the drawing and the tests.
public enum HowToBody {
    public static let sceneWidth = 200.0
    public static let sceneHeight = 140.0
    public static let floor = 124.0
    public static let neck = 3.0
    public static let headRadius = 8.0
    public static let upperArm = 21.0
    public static let forearm = 20.0
    public static let thigh = 26.0
    public static let shin = 25.0
}

/// Where the hip, shoulder, hands and feet are at one moment. "Near" limbs are
/// on the viewer's side (drawn dark in side views).
public struct HowToPose: Sendable {
    public var hip: HowToPoint
    public var shoulder: HowToPoint
    public var nearHand: HowToPoint
    public var farHand: HowToPoint
    public var nearFoot: HowToPoint
    public var farFoot: HowToPoint
    /// Half the shoulder width; zero in side views. The near arm hangs from shoulder + this.
    public var shoulderHalf: HowToPoint
    /// Half the hip width; zero in side views.
    public var hipHalf: HowToPoint
    /// Degrees to turn the head away from the line of the spine.
    public var headTurn: Double
    /// Front views of push-ups hide the torso and legs, which point away from you.
    public var hideBody: Bool

    public init(hip: HowToPoint, shoulder: HowToPoint, nearHand: HowToPoint, farHand: HowToPoint,
                nearFoot: HowToPoint, farFoot: HowToPoint, shoulderHalf: HowToPoint = .zero,
                hipHalf: HowToPoint = .zero, headTurn: Double = 0, hideBody: Bool = false) {
        self.hip = hip
        self.shoulder = shoulder
        self.nearHand = nearHand
        self.farHand = farHand
        self.nearFoot = nearFoot
        self.farFoot = farFoot
        self.shoulderHalf = shoulderHalf
        self.hipHalf = hipHalf
        self.headTurn = headTurn
        self.hideBody = hideBody
    }

    /// Standing still, for a move with no frames.
    public static let standing = HowToPose(hip: HowToPoint(100, 73), shoulder: HowToPoint(100, 35),
                                           nearHand: HowToPoint(100, 76), farHand: HowToPoint(100, 76),
                                           nearFoot: HowToPoint(100, 124), farFoot: HowToPoint(100, 124))

    public func mixed(with other: HowToPose, _ t: Double) -> HowToPose {
        HowToPose(hip: hip.mixed(with: other.hip, t),
                  shoulder: shoulder.mixed(with: other.shoulder, t),
                  nearHand: nearHand.mixed(with: other.nearHand, t),
                  farHand: farHand.mixed(with: other.farHand, t),
                  nearFoot: nearFoot.mixed(with: other.nearFoot, t),
                  farFoot: farFoot.mixed(with: other.farFoot, t),
                  shoulderHalf: shoulderHalf.mixed(with: other.shoulderHalf, t),
                  hipHalf: hipHalf.mixed(with: other.hipHalf, t),
                  headTurn: headTurn + (other.headTurn - headTurn) * t,
                  hideBody: hideBody)
    }
}

/// One key pose: hold it, then move to the next one (the last moves back to the first).
public struct HowToFrame: Sendable {
    public let pose: HowToPose
    public let hold: Double
    public let move: Double

    public init(_ pose: HowToPose, hold: Double, move: Double) {
        self.pose = pose
        self.hold = hold
        self.move = move
    }
}

/// Equipment drawn around the figure.
public enum HowToProp: Hashable, Sendable {
    case bench(x: Double, y: Double, width: Double)
    /// A seat pad with a backrest that reaches up to `backTop`.
    case seat(x: Double, y: Double, width: Double, backTop: Double)
    /// A cable tower with its pulley at `top`.
    case tower(x: Double, top: Double)
    /// A cable from a pulley to one hand.
    case cable(from: HowToPoint, nearHand: Bool)
    /// A machine arm swinging from `pivot` to the near hand, on a post at `postX`.
    case lever(pivot: HowToPoint, postX: Double)
    case barbell
    case dumbbells
    /// Little arrows pressing in on the hands, for squeezes.
    case squeeze
}

/// One arm or leg, solved: where it starts, bends and ends.
public struct HowToLimb: Sendable {
    public let root: HowToPoint
    public let joint: HowToPoint
    public let end: HowToPoint

    /// Places the joint so both bones keep their length. When the target is out
    /// of reach the limb goes straight toward it. `bend` (+1 or −1) picks
    /// which way the elbow or knee points.
    public static func solve(root: HowToPoint, target: HowToPoint, first a: Double, second b: Double,
                             bend: Double) -> HowToLimb {
        let toTarget = target - root
        let distance = toTarget.length
        let direction = toTarget.unit
        if distance >= a + b {
            return HowToLimb(root: root, joint: root + direction * a, end: root + direction * (a + b))
        }
        let d = max(distance, abs(a - b) + 0.01)
        let cosine = min(1, max(-1, (a * a + d * d - b * b) / (2 * a * d)))
        let joint = root + direction.rotated(by: bend * acos(cosine)) * a
        return HowToLimb(root: root, joint: joint, end: root + direction * d)
    }
}

/// A whole figure at one moment, ready to draw.
public struct HowToFigure: Sendable {
    public let pose: HowToPose
    public let nearArm: HowToLimb
    public let farArm: HowToLimb
    public let nearLeg: HowToLimb
    public let farLeg: HowToLimb
    public let head: HowToPoint
}

public struct HowToMove: Sendable {
    public enum View: Sendable {
        case side
        case front
    }

    /// Which way each joint bends: +1 or −1.
    public struct Bends: Sendable {
        public let nearArm: Double
        public let farArm: Double
        public let nearLeg: Double
        public let farLeg: Double
    }

    /// The exercise name exactly as it appears in the catalog.
    public let exercise: String
    public let view: View
    public let bends: Bends
    public let props: [HowToProp]
    public let frames: [HowToFrame]
    /// Two or three short form cues.
    public let tips: [String]

    /// How long one loop takes, in seconds.
    public var loopSeconds: Double {
        frames.reduce(0) { $0 + $1.hold + $1.move }
    }

    /// The blended pose at any time; the loop repeats forever.
    public func pose(at seconds: Double) -> HowToPose {
        guard let first = frames.first else { return .standing }
        let total = loopSeconds
        guard total > 0 else { return first.pose }
        var t = seconds.truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }
        for (index, frame) in frames.enumerated() {
            if t < frame.hold { return frame.pose }
            t -= frame.hold
            if t < frame.move {
                let u = t / frame.move
                let eased = u * u * (3 - 2 * u)
                return frame.pose.mixed(with: frames[(index + 1) % frames.count].pose, eased)
            }
            t -= frame.move
        }
        return first.pose
    }

    /// The pose of key frame `index`, for still pictures.
    public func keyPose(_ index: Int) -> HowToPose {
        frames.indices.contains(index) ? frames[index].pose : (frames.first?.pose ?? .standing)
    }

    public func figure(at seconds: Double) -> HowToFigure {
        figure(for: pose(at: seconds))
    }

    public func figure(for pose: HowToPose) -> HowToFigure {
        let arm = (HowToBody.upperArm, HowToBody.forearm)
        let leg = (HowToBody.thigh, HowToBody.shin)
        let nearArm = HowToLimb.solve(root: pose.shoulder + pose.shoulderHalf, target: pose.nearHand,
                                      first: arm.0, second: arm.1, bend: bends.nearArm)
        let farArm = HowToLimb.solve(root: pose.shoulder - pose.shoulderHalf, target: pose.farHand,
                                     first: arm.0, second: arm.1, bend: bends.farArm)
        let nearLeg = HowToLimb.solve(root: pose.hip + pose.hipHalf, target: pose.nearFoot,
                                      first: leg.0, second: leg.1, bend: bends.nearLeg)
        let farLeg = HowToLimb.solve(root: pose.hip - pose.hipHalf, target: pose.farFoot,
                                     first: leg.0, second: leg.1, bend: bends.farLeg)
        let spine = (pose.shoulder - pose.hip).unit.rotated(by: pose.headTurn * .pi / 180)
        let head = pose.shoulder + spine * (HowToBody.neck + HowToBody.headRadius)
        return HowToFigure(pose: pose, nearArm: nearArm, farArm: farArm, nearLeg: nearLeg, farLeg: farLeg, head: head)
    }
}

public enum HowTo {
    /// The animation for one exercise in one muscle group, if it has been drawn yet.
    public static func move(groupKey: String, exercise: String) -> HowToMove? {
        drawn[groupKey]?.first { $0.exercise == exercise }
    }

    /// Group keys that have animations so far.
    public static var groupKeys: [String] {
        drawn.keys.sorted()
    }

    static func moves(groupKey: String) -> [HowToMove] {
        drawn[groupKey] ?? []
    }
}
