//
//  replay_challenge_selftest.swift
//  glance (tools)
//
//  Camera-free tests for the randomized active replay challenge. These tests
//  intentionally exercise ordering and freshness: an action that happened before
//  its prompt must not be reusable after the challenge advances.
//

import Foundation
import CoreGraphics

@main
struct ReplayChallengeSelfTest {
    static func main() {
        testBlinkThenMouth()
        testTurnHead()
        testPriorActionCannotSatisfyNextPrompt()
        print("All replay-challenge self-tests passed.")
    }

    private static func frame(
        _ t: TimeInterval,
        ear: CGFloat = 0.35,
        mouth: CGFloat = 0.20,
        yaw: Float = 0,
        noseOffset: CGFloat = 0
    ) -> LivenessFrame {
        LivenessFrame(
            timestamp: Date(timeIntervalSince1970: t),
            landmarks: [],
            interocularDistance: 140,
            yaw: yaw,
            leftEyeAspectRatio: ear,
            rightEyeAspectRatio: ear,
            noseOffsetRatio: noseOffset,
            hasReliableLandmarks: true,
            deviceOverlapFraction: nil,
            mouthAspectRatio: mouth
        )
    }

    private static func testBlinkThenMouth() {
        var challenge = ActiveLivenessChallenge(steps: [.blink, .openMouth])
        precondition(challenge.prompt == "Blink now")

        let blinkFrames = [
            frame(0.0, ear: 0.35),
            frame(0.1, ear: 0.34),
            frame(0.2, ear: 0.14),
            frame(0.3, ear: 0.35),
        ]
        var advanced = false
        for sample in blinkFrames { advanced = challenge.observe(sample) || advanced }
        precondition(advanced, "Blink should complete the first challenge step.")
        precondition(challenge.prompt == "Open your mouth")
        precondition(!challenge.isComplete)

        let mouthFrames = [
            frame(0.4, mouth: 0.20),
            frame(0.5, mouth: 0.21),
            frame(0.6, mouth: 0.22),
            frame(0.7, mouth: 0.40),
        ]
        for sample in mouthFrames { _ = challenge.observe(sample) }
        precondition(challenge.isComplete, "Mouth opening should complete the second step.")
        precondition(challenge.prompt == nil)
    }

    private static func testTurnHead() {
        var challenge = ActiveLivenessChallenge(steps: [.turnHead])
        let samples = [
            frame(1.0, yaw: -0.15, noseOffset: -0.050),
            frame(1.1, yaw: -0.05, noseOffset: -0.017),
            frame(1.2, yaw:  0.05, noseOffset:  0.017),
            frame(1.3, yaw:  0.15, noseOffset:  0.050),
        ]
        for sample in samples { _ = challenge.observe(sample) }
        precondition(challenge.isComplete, "A correlated 3D head turn should complete the turn challenge.")
    }

    private static func testPriorActionCannotSatisfyNextPrompt() {
        var challenge = ActiveLivenessChallenge(steps: [.openMouth, .blink])

        // Include a blink while the *mouth* prompt is active. It must be discarded
        // when the mouth step completes and therefore cannot satisfy the later blink prompt.
        let firstStep = [
            frame(2.0, ear: 0.35, mouth: 0.20),
            frame(2.1, ear: 0.14, mouth: 0.21),
            frame(2.2, ear: 0.35, mouth: 0.22),
            frame(2.3, ear: 0.35, mouth: 0.40),
        ]
        for sample in firstStep { _ = challenge.observe(sample) }
        precondition(challenge.prompt == "Blink now")
        precondition(!challenge.isComplete)

        // One ordinary open-eye frame after the prompt must not inherit the old blink.
        _ = challenge.observe(frame(2.4, ear: 0.35, mouth: 0.20))
        precondition(!challenge.isComplete, "A pre-prompt blink was incorrectly reused.")

        let freshBlink = [
            frame(2.5, ear: 0.35),
            frame(2.6, ear: 0.34),
            frame(2.7, ear: 0.14),
            frame(2.8, ear: 0.35),
        ]
        for sample in freshBlink { _ = challenge.observe(sample) }
        precondition(challenge.isComplete, "A fresh post-prompt blink should complete the challenge.")
    }
}
