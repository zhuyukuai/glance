//
//  ActiveChallengePromptPresenter.swift
//  glance
//
//  Lock-screen-visible prompt surface for the randomized replay challenge.
//  It reuses the same NotchWindowController/SkyLight delegation path as the
//  existing unlock overlay, but remains click-through and carries no secrets.
//

import AppKit
import SwiftUI

@MainActor
final class ActiveChallengePromptPresenter: NSObject {
    static let shared = ActiveChallengePromptPresenter()

    private let windowController = NotchWindowController()
    private let hostingView = NSHostingView(rootView: ChallengePromptView(prompt: ""))

    private var activeScan: UUID?

    private override init() {
        super.init()
        windowController.contentView = hostingView
    }

    func begin(scanID: UUID) {
        windowController.hide()
        activeScan = scanID
    }

    func end(scanID: UUID) {
        guard activeScan == scanID else { return }
        activeScan = nil
        windowController.hide()
    }

    func update(_ prompt: String?, scanID: UUID) {
        // Late callbacks or cleanup from a cancelled scan cannot overwrite a newer scan.
        guard activeScan == scanID else { return }
        guard LockMonitor.isScreenActuallyLocked(), let prompt, !prompt.isEmpty else {
            windowController.hide()
            return
        }
        hostingView.rootView = ChallengePromptView(prompt: prompt)
        windowController.show()
        windowController.displaySynchronously()
    }

}

private struct ChallengePromptView: View {
    let prompt: String

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 12, weight: .semibold))
                Text(prompt)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.88), in: Capsule())
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
