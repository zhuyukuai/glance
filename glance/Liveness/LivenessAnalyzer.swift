//
//  LivenessAnalyzer.swift
//  glance
//
//  Rolling-window driver for the liveness cues. Takes `LivenessFrame`, not
//  `FaceRecognitionResult`, keeping this file's dependency graph shallow enough
//  to compile standalone in `tools/liveness_selftest.swift`.
//

import Foundation

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
    private var activeChallenge: ActiveLivenessChallenge
    /// Owned by the scan; Face Lab leaves this unset and never controls lock-screen UI.
    var onPromptChange: ((String?) -> Void)?
    private var announcedChallengePrompt: String?
    private(set) var lastSnapshot = LivenessSnapshot.empty
    /// Kept for Face Lab's diagnostics panel (excess ratio, coherence, pair
    /// counts, yaw range) — the numbers behind the flat-vs-3D cue's level.
    private(set) var lastGeometry = GeometryLivenessResult.empty

    init(windowDuration: TimeInterval = 2.0, challenge: ActiveLivenessChallenge = .randomized()) {
        self.windowDuration = windowDuration
        self.activeChallenge = challenge
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
    /// fresh randomized active challenge before a passive confirmation can unlock.
    /// The rolling passive window is time-pruned (~2s) but the evaluator's fire counts are not —
    /// they accumulate across the whole scan, so a spoof tell can't be waited out.
    @discardableResult
    func observe(_ frame: LivenessFrame, allowChallengeProgress: Bool = true, observedAt: Date = Date()) -> LivenessSnapshot {
        if allowChallengeProgress { frames.append(frame) } else { frames.removeAll() }
        frames.removeAll { frame.timestamp.timeIntervalSince($0.timestamp) > windowDuration }

        evaluator.mode = modeProvider()
        evaluator.tuning = tuningProvider()
        evaluator.enabledCues = enabledCuesProvider()

        let geometry = GeometryLiveness.evaluate(frames)
        lastGeometry = geometry

        var readings = LivenessCues.readings(window: allowChallengeProgress ? frames : [frame], geometry: geometry)
        if !allowChallengeProgress {
            for cue in LivenessCue.allCases where cue.role == .confirm { readings[cue] = CueReading.none }
        }
        let passiveSnapshot = evaluator.observe(readings)

        // A deny cue is terminal and takes precedence over challenge progress.
        if passiveSnapshot.decision.isDenied {
            postChallengePrompt(nil)
            lastSnapshot = passiveSnapshot
            return passiveSnapshot
        }

        if allowChallengeProgress {
            _ = activeChallenge.observe(frame, observedAt: observedAt)
            announceCurrentChallengeIfNeeded()
        }

        // Passive confirmation is necessary but no longer sufficient. A replayed video can
        // look naturally 3D and blink; requiring fresh, ordered actions after random prompts
        // makes a pre-recording substantially harder to synchronize with the current attempt.
        let finalDecision: LivenessDecision = activeChallenge.hasFailed ? .challengeFailed
            : (allowChallengeProgress && activeChallenge.isComplete ? passiveSnapshot.decision : .pending)

        if activeChallenge.isComplete || activeChallenge.hasFailed {
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
        onPromptChange?(prompt)
    }
}
