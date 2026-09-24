//
//  POCController.swift
//  glance
//
//  Orchestration for credential storage: wires SecureCredentialManager to
//  KeystrokeInjector and exposes session/password status for Settings.
//

import Foundation
import Observation

@Observable
@MainActor
final class POCController {
    var accessibilityGranted: Bool = KeystrokeInjector.isAccessibilityTrusted()

    var hasStoredPassword: Bool = SecureCredentialManager.hasStoredPassword()
    var isSessionUnlocked: Bool = SecureCredentialManager.isSessionUnlocked
    var sessionError: String? = nil

    /// Bound to the setup SecureField. Cleared immediately after a successful save.
    var passwordInput: String = ""

    var statusMessage: String = "Idle"

    func refreshAccessibilityStatus() {
        accessibilityGranted = KeystrokeInjector.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        KeystrokeInjector.promptForAccessibility()
    }

    func refreshCredentialStatus() {
        hasStoredPassword = SecureCredentialManager.hasStoredPassword()
        isSessionUnlocked = SecureCredentialManager.isSessionUnlocked
    }

    // MARK: - Session (Touch ID gate)

    /// Must succeed before `savePassword()` or `injectStoredPassword()` will do anything.
    func unlockSession() async {
        sessionError = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                try SecureCredentialManager.unlockSession(reason: "Authenticate to set up or use glance")
            }.value
            isSessionUnlocked = true
        } catch {
            isSessionUnlocked = false
            sessionError = error.localizedDescription
        }
    }

    func lockSession() {
        SecureCredentialManager.lockSession()
        isSessionUnlocked = false
    }

    // MARK: - Setup flow

    /// Encrypts and stores `passwordInput`. Requires the session to already
    /// be unlocked (Touch ID happens in `unlockSession()`, not here).
    func savePassword() async {
        guard !passwordInput.isEmpty else {
            statusMessage = "Enter a password first."
            return
        }
        let plaintext = passwordInput
        passwordInput = ""

        do {
            try await Task.detached(priority: .userInitiated) {
                guard var bytes = plaintext.data(using: .utf8) else {
                    throw SecureCredentialError.emptyPassword
                }
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try SecureCredentialManager.savePassword(bytes)
            }.value
            statusMessage = "Password saved and encrypted."
            hasStoredPassword = true
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Injection

    /// Returns true only after a submitted password is followed by an observed unlock.
    /// All callers must supply a revocable scan token; there is no unguarded injection API.
    func injectStoredPassword(attempt: UnlockAttempt) async -> Bool {
        guard !Task.isCancelled, attempt.isValid, KeystrokeInjector.isAccessibilityTrusted(),
              SecureCredentialManager.isSessionUnlocked,
              let target = LockScreenTarget.resolve() else {
            statusMessage = "Skipped: no verified lock-screen input target or authorized session."
            return false
        }
        statusMessage = "Entering password…"
        do {
            try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    guard attempt.isValid, target.isCurrent else { throw PasswordDeliveryError.invalidContext }
                    var bytes = try SecureCredentialManager.readPassword()
                    defer { bytes.resetBytes(in: 0..<bytes.count) }
                    try KeystrokeInjector.typeAndReturn(bytes, target: target, attempt: attempt)
                }.value
            } onCancel: {
                attempt.cancel()
            }
            for _ in 0..<20 {
                if LockMonitor.isScreenActuallyUnlocked() {
                    statusMessage = "Unlock observed."
                    return true
                }
                guard !Task.isCancelled, attempt.isValid else { return false }
                try await Task.sleep(for: .milliseconds(50))
            }
            statusMessage = "Unlock not confirmed — enter your password manually."
        } catch {
            statusMessage = "Password entry stopped — use manual login."
        }
        return false
    }
}
