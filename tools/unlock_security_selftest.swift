import Foundation
import CoreGraphics

@main
struct UnlockSecuritySelfTest {
    static func main() throws {
        let first = UUID(), second = UUID()
        let box = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }
        var stable = FaceScanContinuity()
        precondition(!stable.observe(identity: nil, box: nil, at: date(0)))
        precondition(stable.observe(identity: first, box: box, at: date(0.1)))
        precondition(stable.observe(identity: first, box: box.offsetBy(dx: 0.01, dy: 0), at: date(0.2)))
        precondition(stable.isFresh(at: date(0.3)))
        precondition(!stable.isFresh(at: date(0.8)))
        for (identity, nextBox, time) in [(Optional(second), Optional(box), 0.3),
                                         (nil, nil, 0.3), (first, box.offsetBy(dx: 0.5, dy: 0), 0.3),
                                         (first, box, 1.0), (first, box, 0.1)] {
            var changed = stable
            precondition(!changed.observe(identity: identity, box: nextBox, at: date(time)))
            precondition(changed.hasFailed)
            precondition(!changed.observe(identity: first, box: box, at: date(1.1)))
        }
        print("PASS: identity changes, missing faces, box jumps, gaps and backwards frames terminate the scan.")

        let now = ContinuousClock.now
        var lifetime = CredentialSessionLifetime(now: now)
        precondition(lifetime.isValid(now: now.advanced(by: .seconds(3599)), idleLimit: 3600))
        precondition(!lifetime.isValid(now: now.advanced(by: .seconds(3600)), idleLimit: 3600))
        lifetime.recordUse(at: now.advanced(by: .seconds(7 * 3600)))
        precondition(lifetime.isValid(now: now.advanced(by: .seconds(7 * 3600 + 1)), idleLimit: 3600))
        precondition(!lifetime.isValid(now: now.advanced(by: .seconds(8 * 3600)), idleLimit: 3600))
        print("PASS: idle expiry and absolute eight-hour expiry remain independent of repeated use.")
        var budget = ScanAttemptBudget()
        for _ in 0..<3 { precondition(budget.consume()) }
        for _ in 0..<20 { precondition(!budget.consume()) }
        budget = ScanAttemptBudget()
        precondition(budget.consume())
        let attempt = UnlockAttempt()
        precondition(attempt.isValid); attempt.cancel(); precondition(!attempt.isValid)
        let bytes = Data("abc".utf8)
        for cutoff in 0...6 {
            var events: [PasswordDelivery.Event] = []
            do {
                try PasswordDelivery.run(bytes, validate: { events.count < cutoff }, post: { events.append($0) })
                preconditionFailure("Invalid context must interrupt delivery")
            } catch PasswordDeliveryError.invalidContext {}
            precondition(events.count == cutoff)
            precondition(!events.contains(.enter(down: true)), "Never submit a partial password")
        }
        var delivered: [PasswordDelivery.Event] = []
        try PasswordDelivery.run(Data("密🙂".utf8), validate: { true }, post: { delivered.append($0) })
        precondition(delivered == [.character("密", down: true), .character("", down: false),
                                  .character("🙂", down: true), .character("", down: false),
                                  .enter(down: true), .enter(down: false)])
        var events: [PasswordDelivery.Event] = []
        try PasswordDelivery.run(bytes, validate: { !events.contains(.enter(down: true)) }, post: { events.append($0) })
        precondition(events.count == 7, "Unlock after Return must suppress the trailing event")
        print("PASS: cancellation/context loss at every output boundary prevents remaining text and Return; Unicode preserved.")
        print("All unlock-security self-tests passed. No keyboard events were posted.")
    }
}
