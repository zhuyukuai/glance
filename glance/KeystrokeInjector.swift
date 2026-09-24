//
//  KeystrokeInjector.swift
//  glance
//
//  Delivers credentials only to a verified system loginwindow process while locked.
//

import Foundation
import ApplicationServices
import CoreGraphics
import AppKit
import Darwin

enum KeystrokeError: LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission required. Open System Settings → Privacy & Security → Accessibility and enable glance."
        case .eventCreationFailed:
            return "Couldn't create CGEvent for keystroke."
        }
    }
}

enum KeystrokeInjector {
    /// Returns true if the app has Accessibility permission (no prompt).
    nonisolated static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system prompt to grant Accessibility (deep links to System Settings).
    @discardableResult
    nonisolated static func promptForAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Targets only the verified system loginwindow. There is deliberately no global-HID
    /// fallback: if this route is unsupported on an OS release, manual login is required.
    nonisolated static func typeAndReturn(_ passwordBytes: Data, target: LockScreenTarget,
                                         attempt: UnlockAttempt) throws {
        guard isAccessibilityTrusted() else { throw KeystrokeError.accessibilityNotGranted }
        let source = CGEventSource(stateID: .privateState)
        try PasswordDelivery.run(passwordBytes, validate: {
            attempt.isValid && SecureCredentialManager.isSessionUnlocked
                && isAccessibilityTrusted() && target.isCurrent
        }, post: { event in
            let key: CGKeyCode
            let down: Bool
            let text: String?
            switch event {
            case .character(let value, let keyDown):
                key = 0; down = keyDown; text = keyDown ? value : nil
            case .enter(let keyDown):
                key = 0x24; down = keyDown; text = nil
            }
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                throw KeystrokeError.eventCreationFailed
            }
            event.flags = []
            if let text {
                var utf16 = Array(text.utf16)
                defer { for i in utf16.indices { utf16[i] = 0 } }
                utf16.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
            }
            // Recheck after event construction as well as before it. postToPid prevents
            // a focus transition from redirecting credentials to an editor or terminal.
            guard attempt.isValid, target.isCurrent, SecureCredentialManager.isSessionUnlocked else {
                throw PasswordDeliveryError.invalidContext
            }
            event.postToPid(target.pid)
            Thread.sleep(forTimeInterval: 0.012)
        })
    }
}

nonisolated struct LockScreenTarget: Sendable {
    let pid: pid_t
    let consoleSet: UInt32
    private static let executable = "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"

    @MainActor static func resolve() -> Self? {
        guard let consoleSet = LockMonitor.lockedConsoleSet() else { return nil }
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow")
            .filter { !$0.isTerminated && $0.executableURL?.path == executable }
        guard candidates.count == 1, let app = candidates.first else { return nil }
        let target = Self(pid: app.processIdentifier, consoleSet: consoleSet)
        return target.isCurrent ? target : nil
    }

    var isCurrent: Bool {
        guard LockMonitor.lockedConsoleSet() == consoleSet else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = path.withUnsafeMutableBytes { buffer in
            proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        return count > 0 && String(cString: path) == Self.executable
    }
}
