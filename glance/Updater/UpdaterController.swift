//
//  UpdaterController.swift
//  glance
//
//  Strict-offline updater shim. The public surface remains available so existing
//  app wiring compiles, but every update operation is intentionally a local no-op.
//

import Observation

@Observable
@MainActor
final class UpdaterController {
    /// Network update checks are disabled in strict offline mode.
    private(set) var canCheckForUpdates = false

    /// Kept for source compatibility with existing settings bindings. This value
    /// is never persisted or acted upon because update checks are disabled.
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { _ = newValue }
    }

    /// No update UI can be presented in strict offline mode.
    var isPresentingUpdateUI: Bool { false }

    init() {}

    /// Intentionally does nothing: starting an updater could initiate network traffic.
    func start() {}

    /// Intentionally does nothing: manual update checks are disabled offline.
    func checkForUpdates() {}
}
