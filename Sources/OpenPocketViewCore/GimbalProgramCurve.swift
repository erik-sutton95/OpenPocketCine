import Foundation

/// A quadratic Bézier fillet joins the two timed straight legs with matching
/// angular velocity at each join. The original B time is the curve midpoint.
public struct GimbalProgramCurve: Equatable, Sendable {
    public let a: GimbalWaypoint
    public let b: GimbalWaypoint
    public let c: GimbalWaypoint
    public private(set) var durationAB: TimeInterval
    public private(set) var durationBC: TimeInterval
    public let halfCornerDuration: TimeInterval

    private struct Piece: Equatable, Sendable {
        var from: GimbalWaypoint
        var control: GimbalWaypoint?
        var to: GimbalWaypoint
        var duration: TimeInterval
    }
    private var pieces: [Piece]

    public init?(program: GimbalProgram) {
        guard let a = program.a, let b = program.b, let c = program.c,
            program.smoothness.isFinite, program.smoothness > 0,
            program.durationAB.isFinite, program.durationBC.isFinite,
            program.durationAB > 0, program.durationBC > 0 else { return nil }
        self.a = a
        self.b = b
        self.c = c
        durationAB = program.durationAB
        durationBC = program.durationBC
        halfCornerDuration = min(durationAB, durationBC) * 0.5 * min(program.smoothness, 1)
        let p = GimbalMoveEngine.lerp(a, b, u: 1 - halfCornerDuration / durationAB)
        let q = GimbalMoveEngine.lerp(b, c, u: halfCornerDuration / durationBC)
        pieces = [
            Piece(from: a, to: p, duration: durationAB - halfCornerDuration),
            Piece(from: p, control: b, to: q, duration: 2 * halfCornerDuration),
            Piece(from: q, to: c, duration: durationBC - halfCornerDuration),
        ]
    }

    public var duration: TimeInterval { durationAB + durationBC }

    public func position(at time: TimeInterval) -> GimbalWaypoint {
        guard let first = pieces.first else { return c }
        if time <= 0 { return first.from }
        if time >= duration { return c }
        var remaining = time
        for piece in pieces {
            if remaining <= piece.duration {
                let u = remaining / piece.duration
                if let control = piece.control {
                    return GimbalMoveEngine.lerp(
                        GimbalMoveEngine.lerp(piece.from, control, u: u),
                        GimbalMoveEngine.lerp(control, piece.to, u: u), u: u)
                }
                return GimbalMoveEngine.lerp(piece.from, piece.to, u: u)
            }
            remaining -= piece.duration
        }
        return c
    }

    /// Cut the remaining first piece, preserving every later control point.
    /// Coast is absorbed by replacing only the cut piece's start with measured pose.
    public func remaining(after time: TimeInterval, from pose: GimbalWaypoint) -> GimbalProgramCurve {
        var result = self
        var consumed = max(0, time)
        var rest: [Piece] = []
        for (index, piece) in pieces.enumerated() {
            if consumed >= piece.duration {
                consumed -= piece.duration
                continue
            }
            let u = consumed / piece.duration
            var cut = piece
            cut.from = pose
            cut.control = piece.control.map { GimbalMoveEngine.lerp($0, piece.to, u: u) }
            cut.duration -= consumed
            rest = [cut] + Array(pieces.dropFirst(index + 1))
            break
        }
        if rest.isEmpty { rest = [Piece(from: pose, to: c, duration: 0.1)] }
        let total = rest.reduce(0) { $0 + $1.duration }
        if total < 0.1 { rest[0].duration += 0.1 - total }
        result.pieces = rest
        result.durationAB = max(0, durationAB - max(0, time))
        result.durationBC = rest.reduce(0) { $0 + $1.duration } - result.durationAB
        return result
    }

    public func samples(count: Int = 80) -> [GimbalWaypoint] {
        let count = max(2, count)
        return (0..<count).map { position(at: duration * Double($0) / Double(count - 1)) }
    }
}
