//
//  LivenessAnalyzer.swift
//  glance
//
//  Rolling-window driver for the liveness cues. Takes `LivenessFrame`, not
//  `FaceRecognitionResult`, keeping this file's dependency graph shallow enough
//  to compile standalone in `tools/liveness_selftest.swift`.
//

import Foundation

extension Notification.Name {
    /// `object` is the prompt String; `nil` means hide the prompt. The UI-side presenter
    /// deliberately lives outside this file so the liveness core remains AppKit-free/testable.
    static let activeLivenessChallengePromptDidChange = Notification.Name(
        "ActiveLivenessChallenge.promptDidChange"
    )
}

@MainActor
final class LivenessAnalyzer {
    private let windowDuration: TimeInterval

    /// Read fresh on every `observe()`, not captured at init, so a mid-scan Settings change takes effect immediately.
    var modeProvider: () -> LivenessMode = { .light }
    var tuningProvider: () -> LivenessTuning = { .default }
    /// Face Lab can switch individual cues off to isolate one; the unlock
    /// path leaves this at "all enabled."
    var enabledCuesProvider: () -> Set<LivenessCue> = { Set(LivenessCue.allCases) }

    private var frames: [LivenessFrame] = []
    private var evaluator = LivenessEvaluator()
    private var activeChallenge = ActiveLivenessChallenge.randomized()
    private var announcedChallengePrompt: String?
    private(set) var lastSnapshot = LivenessSnapshot.empty
    /// Kept for Face Lab's diagnostics panel (excess ratio, coherence, pair
    /// counts, yaw range) — the numbers behind the flat-vs-3D cue's level.
    private(set) var lastGeometry = GeometryLivenessResult.empty

    init(windowDuration: TimeInterval = 2.0) {
        self.windowDuration = windowDuration
    }

    func reset() {
        frames.removeAll()
        evaluator.reset()
        activeChallenge = .randomized()
        announcedChallengePrompt = nil
        postChallengePrompt(nil)
        lastSnapshot = .empty
        lastGeometry = .empty
    }

    /// Call once per frame with a detected face, regardless of whether it matched an identity,
    /// so passive liveness stays an independent gate. In addition, every scan must complete a
    /// fresh two-step randomized active challenge before a passive confirmation can unlock.
    /// The rolling passive window is time-pruned (~2s) but the evaluator's fire counts are not —
    /// they accumulate across the whole scan, so a spoof tell can't be waited out.
    @discardableResult
    func observe(_ frame: LivenessFrame) -> LivenessSnapshot {
        frames.append(frame)
        frames.removeAll { frame.timestamp.timeIntervalSince($0.timestamp) > windowDuration }

        evaluator.mode = modeProvider()
        evaluator.tuning = tuningProvider()
        evaluator.enabledCues = enabledCuesProvider()

        let geometry = GeometryLiveness.evaluate(frames)
        lastGeometry = geometry

        let readings = LivenessCues.readings(window: frames, geometry: geometry)
        let passiveSnapshot = evaluator.observe(readings)

        // A deny cue is terminal and takes precedence over challenge progress.
        if passiveSnapshot.decision.isDenied {
            postChallengePrompt(nil)
            lastSnapshot = passiveSnapshot
            return passiveSnapshot
        }

        announceCurrentChallengeIfNeeded()
        if activeChallenge.observe(frame) {
            announceCurrentChallengeIfNeeded()
        }

        // Passive confirmation is necessary but no longer sufficient. A replayed video can
        // look naturally 3D and blink; requiring two fresh, ordered actions after random prompts
        // makes a pre-recording substantially harder to synchronize with the current attempt.
        let finalDecision: LivenessDecision = activeChallenge.isComplete
            ? passiveSnapshot.decision
            : .pending

        if activeChallenge.isComplete {
            postChallengePrompt(nil)
        }

        let snapshot = LivenessSnapshot(
            decision: finalDecision,
            mode: passiveSnapshot.mode,
            cueStates: passiveSnapshot.cueStates,
            frameCount: passiveSnapshot.frameCount
        )
        lastSnapshot = snapshot
        return snapshot
    }

    private func announceCurrentChallengeIfNeeded() {
        let prompt = activeChallenge.prompt
        guard prompt != announcedChallengePrompt else { return }
        announcedChallengePrompt = prompt
        postChallengePrompt(prompt)
    }

    private func postChallengePrompt(_ prompt: String?) {
        NotificationCenter.default.post(
            name: .activeLivenessChallengePromptDidChange,
            object: prompt
        )
    }
}
