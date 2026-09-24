import Foundation
import CoreGraphics

/// A bounded challenge-response state machine, not a proof against all RGB video replay.
/// Each action is revealed only after a fresh, randomly timed neutral hold. Unexpected
/// actions fail the attempt instead of being ignored until a recording happens to comply.
nonisolated struct ActiveLivenessChallenge {
    enum Step: String, CaseIterable, Sendable {
        case blink, openMouth, turnLeft, turnRight

        var prompt: String {
            switch self {
            case .blink: return "Blink once, then look forward"
            case .openMouth: return "Open your mouth, then close it"
            case .turnLeft: return "Turn left, then look forward"
            case .turnRight: return "Turn right, then look forward"
            }
        }
    }

    enum Phase { case settling, responding, returning, complete, failed }
    private(set) var phase: Phase = .settling
    let steps: [Step]
    private(set) var currentIndex = 0
    private let neutralHold: TimeInterval
    private let responseLimit: TimeInterval = 2.5
    private var phaseStarted: Date?
    private var neutralSince: Date?
    private var lastTimestamp: Date?
    private var baseline: Sample?
    private var actionSince: Date?
    private var responseFrames: [LivenessFrame] = []

    init(steps: [Step], neutralHold: TimeInterval = 0.6) {
        precondition(!steps.isEmpty && neutralHold >= 0.4 && neutralHold <= 1.0)
        self.steps = steps
        self.neutralHold = neutralHold
    }

    static func randomized(stepCount: Int = 3) -> Self {
        Self(steps: Array(Step.allCases.shuffled().prefix(min(max(stepCount, 1), Step.allCases.count))),
             neutralHold: Double.random(in: 0.45...0.9))
    }

    var isComplete: Bool { phase == .complete }
    var hasFailed: Bool { phase == .failed }
    var currentStep: Step? { isComplete || hasFailed ? nil : steps[currentIndex] }
    var prompt: String? {
        switch phase {
        case .settling: return "Look straight ahead; keep still until prompted"
        case .responding: return currentStep?.prompt
        case .returning: return "Look forward, eyes open and mouth closed"
        case .complete, .failed: return nil
        }
    }

    /// All data must be fresh and complete. A missing observation must be handled by the
    /// caller's identity/track gate; a gap or backwards timestamp here also fails closed.
    @discardableResult
    mutating func observe(_ frame: LivenessFrame, observedAt: Date? = nil) -> Bool {
        guard !hasFailed, !isComplete else { return false }
        guard let sample = Sample(frame) else { return fail() }
        if let previous = lastTimestamp {
            let dt = frame.timestamp.timeIntervalSince(previous)
            guard dt > 0, dt <= 0.5 else { return fail() }
        }
        lastTimestamp = frame.timestamp
        if phaseStarted == nil { phaseStarted = frame.timestamp }
        guard frame.timestamp.timeIntervalSince(phaseStarted!) <= responseLimit else { return fail() }

        switch phase {
        case .settling:
            // A quiet baseline must precede EACH prompt. Movement before the prompt does
            // not become credit for that prompt, nor does it silently restart its deadline.
            guard sample.isForwardNeutral else { return fail() }
            if let base = baseline {
                guard sample.isNeutral(relativeTo: base) else { return fail() }
            } else {
                baseline = sample
                neutralSince = frame.timestamp
            }
            if frame.timestamp.timeIntervalSince(neutralSince!) >= neutralHold {
                phase = .responding
                phaseStarted = observedAt ?? frame.timestamp
                responseFrames = []
                // This frame belongs to the old prompt, never to the action just revealed.
            }
        case .responding:
            guard let base = baseline, let step = currentStep else { return fail() }
            // Require a human response delay after the prompt. A motion already underway
            // at its appearance must not complete it.
            let elapsed = frame.timestamp.timeIntervalSince(phaseStarted!)
            let blinking = sample.ear < base.ear * 0.65
            let mouthOpen = sample.mouth >= max(base.mouth * 1.45, base.mouth + 0.08)
            let deltaYaw = sample.yaw - base.yaw
            let turning = abs(deltaYaw) > 0.16
            guard elapsed >= 0.18 || (!blinking && !mouthOpen && !turning) else { return fail() }

            // Signs match EnrollmentPose / yawMatches: positive yaw is the user's left.
            let wrong: Bool
            let active: Bool
            switch step {
            case .blink:
                wrong = mouthOpen || turning
                active = blinking
            case .openMouth:
                wrong = blinking || turning
                active = mouthOpen
            case .turnLeft:
                wrong = blinking || mouthOpen || deltaYaw < -0.12
                active = deltaYaw >= 0.25
            case .turnRight:
                wrong = blinking || mouthOpen || deltaYaw > 0.12
                active = deltaYaw <= -0.25
            }
            guard !wrong else { return fail() }
            responseFrames.append(frame)
            if active {
                if actionSince == nil { actionSince = frame.timestamp }
                let held = frame.timestamp.timeIntervalSince(actionSince!)
                let pose = LivenessScoring.poseDepthConsistency(responseFrames)
                let isTurn = step == .turnLeft || step == .turnRight
                if (!isTurn && step == .blink) || (held >= 0.15 && (!isTurn || (pose.confidence > 0 && pose.level >= 0.8))) {
                    phase = .returning
                    neutralSince = nil
                }
            } else {
                actionSince = nil
            }
        case .returning:
            guard let base = baseline, let step = currentStep else { return fail() }
            let deltaYaw = sample.yaw - base.yaw
            let unexpectedBlink = step != .blink && sample.ear < base.ear * 0.65
            let unexpectedMouth = step != .openMouth && sample.mouth >= max(base.mouth * 1.45, base.mouth + 0.08)
            let unexpectedTurn = (step == .blink || step == .openMouth) ? abs(deltaYaw) > 0.16
                : (step == .turnLeft ? deltaYaw < -0.12 : deltaYaw > 0.12)
            guard !unexpectedBlink, !unexpectedMouth, !unexpectedTurn else { return fail() }
            if sample.isNeutral(relativeTo: base) {
                if neutralSince == nil { neutralSince = frame.timestamp }
                if frame.timestamp.timeIntervalSince(neutralSince!) >= 0.2 {
                    currentIndex += 1
                    phase = currentIndex == steps.count ? .complete : .settling
                    phaseStarted = nil
                    neutralSince = nil
                    baseline = nil
                    actionSince = nil
                    responseFrames = []
                    return true
                }
            } else {
                neutralSince = nil
            }
        case .complete, .failed: break
        }
        return false
    }

    private mutating func fail() -> Bool {
        phase = .failed
        responseFrames = []
        return false
    }

    private struct Sample {
        let ear: CGFloat
        let mouth: CGFloat
        let yaw: Float

        init?(_ frame: LivenessFrame) {
            guard frame.hasReliableLandmarks,
                  let l = frame.leftEyeAspectRatio, let r = frame.rightEyeAspectRatio,
                  let mouth = frame.mouthAspectRatio, let yaw = frame.yaw,
                  l.isFinite, r.isFinite, mouth.isFinite, yaw.isFinite,
                  frame.timestamp.timeIntervalSince1970.isFinite,
                  l > 0, r > 0, mouth > 0 else { return nil }
            ear = (l + r) / 2
            self.mouth = mouth
            self.yaw = yaw
        }

        var isForwardNeutral: Bool { abs(yaw) <= 0.12 && ear >= 0.20 && mouth <= 0.35 }
        func isNeutral(relativeTo base: Sample) -> Bool {
            abs(yaw - base.yaw) <= 0.08 && ear >= base.ear * 0.8
                && abs(mouth - base.mouth) <= 0.04
        }
    }
}
