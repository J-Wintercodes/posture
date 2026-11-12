import Foundation

/// Collects a few seconds of "sit tall, look straight ahead" and turns them
/// into a baseline. Rejects the take if the head was not held still.
struct Calibrator {
    enum Outcome: Equatable {
        case ok(Baseline)
        case unstable
        case noData
    }

    var tuning = PostureTuning()
    private var forward: [Double] = []
    private var lateral: [Double] = []

    var sampleCount: Int { forward.count }

    mutating func add(_ s: HeadSample) {
        let g = s.gravity.normalized
        forward.append(atan2(g.y, -g.z) * 180 / .pi * tuning.forwardSign)
        lateral.append(atan2(g.x, -g.z) * 180 / .pi * tuning.lateralSign)
    }

    func finish() -> Outcome {
        guard forward.count >= 20 else { return .noData }
        let mf = mean(forward)
        let ml = mean(lateral)
        guard spread(forward, around: mf) < 3, spread(lateral, around: ml) < 3 else { return .unstable }
        return .ok(Baseline(forward: mf, lateral: ml, capturedAt: Date(), isProvisional: false))
    }

    private func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }

    private func spread(_ v: [Double], around m: Double) -> Double {
        (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot()
    }
}
