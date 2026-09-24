import Foundation

/// Explicit cancellation bridges the main-actor scan and synchronous event delivery.
/// A cancelled scan never becomes valid again, even if the screen locks again.
nonisolated final class UnlockAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true

    var isValid: Bool {
        lock.lock(); defer { lock.unlock() }
        return valid
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        valid = false
    }
}

nonisolated enum PasswordDeliveryError: Error {
    case invalidContext
    case invalidPassword
}

/// Testable sequencing shared by the real injector. No global keyboard output lives here.
/// Validate immediately before every event, including Return. Delivery stays pinned to
/// the loginwindow process by the caller, so a focus race cannot redirect it to another app.
nonisolated enum PasswordDelivery {
    enum Event: Equatable {
        case character(String, down: Bool)
        case enter(down: Bool)
    }

    static func run(_ bytes: Data, validate: () -> Bool, post: (Event) throws -> Void) throws {
        guard let password = String(data: bytes, encoding: .utf8), !password.isEmpty else {
            throw PasswordDeliveryError.invalidPassword
        }
        for character in password {
            for down in [true, false] {
                guard validate() else { throw PasswordDeliveryError.invalidContext }
                // Key-up carries no password text.
                try post(.character(down ? String(character) : "", down: down))
            }
        }
        guard validate() else { throw PasswordDeliveryError.invalidContext }
        try post(.enter(down: true))
        // Return-down can itself unlock. Do not treat that expected transition as an error
        // or send a trailing key-up to an invalid session.
        if validate() { try post(.enter(down: false)) }
    }
}

/// Shared across retries and wake events; the coordinator resets only after an actual unlock.
nonisolated struct ScanAttemptBudget {
    private(set) var used = 0
    mutating func consume() -> Bool {
        guard used < 3 else { return false }
        used += 1
        return true
    }
}
