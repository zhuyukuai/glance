import Foundation
import CoreGraphics

@main
struct ReplayChallengeSelfTest {
    static func frame(_ t: Double, ear: CGFloat = 0.35, mouth: CGFloat = 0.20,
                      yaw: Float = 0, reliable: Bool = true) -> LivenessFrame {
        LivenessFrame(timestamp: Date(timeIntervalSince1970: t), landmarks: [], interocularDistance: 140,
            yaw: yaw, leftEyeAspectRatio: ear, rightEyeAspectRatio: ear, noseOffsetRatio: CGFloat(yaw) / 3,
            hasReliableLandmarks: reliable, deviceOverlapFraction: nil, mouthAspectRatio: mouth)
    }

    static func neutral(_ challenge: inout ActiveLivenessChallenge, _ time: inout Double) {
        for _ in 0..<10 { _ = challenge.observe(frame(time)); time += 0.1 }
        precondition(challenge.phase == .responding)
    }

    static func respond(_ challenge: inout ActiveLivenessChallenge, _ time: inout Double, _ step: ActiveLivenessChallenge.Step) {
        let samples: [(CGFloat, CGFloat, Float)]
        switch step {
        case .blink:
            samples = [0.35, 0.35, 0.14, 0.35, 0.35, 0.35, 0.35].map { ($0, 0.2, 0) }
        case .openMouth:
            samples = [0.2, 0.3, 0.4, 0.4, 0.4, 0.2, 0.2, 0.2, 0.2].map { (0.35, $0, 0) }
        case .turnLeft, .turnRight:
            let sign: Float = step == .turnLeft ? 1 : -1
            samples = [Float(0), 0.1, 0.2, 0.3, 0.3, 0.3, 0.1, 0, 0, 0, 0].map { (0.35, 0.2, $0 * sign) }
        }
        for (ear, mouth, yaw) in samples {
            _ = challenge.observe(frame(time, ear: ear, mouth: mouth, yaw: yaw)); time += 0.1
        }
    }

    static var permutations: [[ActiveLivenessChallenge.Step]] {
        var result: [[ActiveLivenessChallenge.Step]] = []
        for a in ActiveLivenessChallenge.Step.allCases {
            for b in ActiveLivenessChallenge.Step.allCases where a != b {
                for c in ActiveLivenessChallenge.Step.allCases where c != a && c != b { result.append([a,b,c]) }
            }
        }
        return result
    }

    // The exact pattern that passed all six original challenges, with optional neutral
    // padding. It is fixed in advance and never reads the requested action.
    static func replay(padding: Double) -> [LivenessFrame] {
        var result: [LivenessFrame] = []
        for i in 0..<Int(padding * 10) { result.append(frame(Double(i) * 0.1)) }
        for cycle in 0..<8 {
            let t = padding + Double(cycle) * 1.2
            result += [frame(t), frame(t+0.1, ear: 0.34), frame(t+0.2, ear: 0.14), frame(t+0.3)]
            result += [frame(t+0.4), frame(t+0.5, mouth: 0.21), frame(t+0.6, mouth: 0.22), frame(t+0.7, mouth: 0.4)]
            result += [frame(t+0.8, yaw: -0.15), frame(t+0.9, yaw: -0.05), frame(t+1.0, yaw: 0.05), frame(t+1.1, yaw: 0.15)]
        }
        return result
    }

    @MainActor static func main() {
        for steps in permutations {
            var c = ActiveLivenessChallenge(steps: steps)
            var time = 0.0
            for step in steps {
                neutral(&c, &time)
                respond(&c, &time, step)
                precondition(!c.hasFailed, "Valid response failed: \(step)")
            }
            precondition(c.isComplete)
            for padding in [0.0, 1.0] {
                let analyzer = LivenessAnalyzer(challenge: ActiveLivenessChallenge(steps: steps))
                analyzer.modeProvider = { .heavy }
                var everConfirmed = false
                for f in replay(padding: padding) {
                    let snapshot = analyzer.observe(f, observedAt: f.timestamp)
                    everConfirmed = everConfirmed || snapshot.decision.isConfirmed
                }
                precondition(!everConfirmed, "Fixed replay passed: \(steps)")
                precondition(analyzer.lastSnapshot.decision.isDenied)
            }
        }
        print("PASS: 24 valid three-step sequences; original fixed replay rejected with and without neutral padding.")

        var wrong = ActiveLivenessChallenge(steps: [.openMouth])
        var t = 0.0
        neutral(&wrong, &t)
        _ = wrong.observe(frame(t, ear: 0.14))
        precondition(wrong.hasFailed)
        for f in replay(padding: 0) { _ = wrong.observe(f) }
        precondition(wrong.hasFailed && !wrong.isComplete, "Failure must remain terminal")

        var opposite = ActiveLivenessChallenge(steps: [.turnLeft])
        t = 0; neutral(&opposite, &t)
        _ = opposite.observe(frame(t, yaw: -0.3))
        precondition(opposite.hasFailed)

        var closing = ActiveLivenessChallenge(steps: [.openMouth])
        _ = closing.observe(frame(0, mouth: 0.4))
        precondition(closing.hasFailed, "Starting with an open mouth is not an opening response")

        var tooEarly = ActiveLivenessChallenge(steps: [.blink], neutralHold: 0.4)
        for i in 0...5 { _ = tooEarly.observe(frame(Double(i) * 0.1)) }
        precondition(tooEarly.phase == .responding)
        _ = tooEarly.observe(frame(0.6, ear: 0.14))
        precondition(tooEarly.hasFailed)

        var expired = ActiveLivenessChallenge(steps: [.blink])
        for i in 0..<40 { _ = expired.observe(frame(Double(i) * 0.1)) }
        precondition(expired.hasFailed)
        for bad in [frame(-0.1), frame(0.6), frame(0.1, reliable: false), frame(0.1, mouth: .nan)] {
            var c = ActiveLivenessChallenge(steps: [.blink]); _ = c.observe(frame(0)); _ = c.observe(bad)
            precondition(c.hasFailed)
        }
        print("PASS: wrong/early/opposite actions, closing-only, timeout, missing data, backwards time and frame gaps fail closed.")

        let analyzer = LivenessAnalyzer(challenge: ActiveLivenessChallenge(steps: [.blink]))
        analyzer.modeProvider = { .heavy }
        for f in replay(padding: 1) { _ = analyzer.observe(f, allowChallengeProgress: false, observedAt: f.timestamp) }
        precondition(!analyzer.lastSnapshot.decision.isConfirmed, "Unmatched faces must not advance the challenge")
        print("All replay-challenge self-tests passed.")
    }
}
