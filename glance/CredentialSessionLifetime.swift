import Foundation

/// ContinuousClock includes sleep and is unaffected by wall-clock/time-zone changes.
/// Successful face unlocks may extend idle time, but never the original authorization.
nonisolated struct CredentialSessionLifetime {
    let authorizedAt: ContinuousClock.Instant
    private(set) var lastUsed: ContinuousClock.Instant

    init(now: ContinuousClock.Instant = .now) {
        authorizedAt = now
        lastUsed = now
    }

    mutating func recordUse(at now: ContinuousClock.Instant = .now) { lastUsed = now }

    func isValid(now: ContinuousClock.Instant = .now, idleLimit: TimeInterval) -> Bool {
        let total = now - authorizedAt
        let idle = now - lastUsed
        return total >= .zero && idle >= .zero
            && total < .seconds(8 * 60 * 60)
            && idle < .seconds(min(max(idleLimit, 1), 8 * 60 * 60))
    }
}
