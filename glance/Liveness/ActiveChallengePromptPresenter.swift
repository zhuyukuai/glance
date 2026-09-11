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

    private override init() {
        super.init()
        windowController.contentView = hostingView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(promptDidChange(_:)),
            name: .activeLivenessChallengePromptDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func promptDidChange(_ notification: Notification) {
        guard let prompt = notification.object as? String, !prompt.isEmpty else {
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
