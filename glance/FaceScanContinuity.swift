import Foundation
import CoreGraphics

/// One scan is one continuously observed enrolled identity. Failures are terminal so
/// neither challenge progress nor spoof denials can be laundered through a tracking reset.
nonisolated struct FaceScanContinuity {
    private(set) var identityID: UUID?
    private var box: CGRect?
    private var lastSeen: Date?
    private(set) var hasFailed = false

    mutating func observe(identity: UUID?, box: CGRect?, at now: Date) -> Bool {
        guard !hasFailed else { return false }
        guard let identity, let box else {
            if identityID != nil { hasFailed = true }
            return false
        }
        guard now.timeIntervalSince1970.isFinite,
              [box.minX, box.minY, box.width, box.height].allSatisfy({ $0.isFinite }),
              box.width > 0, box.height > 0 else { hasFailed = true; return false }
        if let previousID = identityID, let previous = self.box, let lastSeen {
            let elapsed = now.timeIntervalSince(lastSeen)
            let overlap = previous.intersection(box)
            let intersection = overlap.isNull ? 0 : overlap.width * overlap.height
            let union = previous.width * previous.height + box.width * box.height - intersection
            guard previousID == identity, elapsed > 0, elapsed <= 0.5,
                  union > 0, intersection / union >= 0.35 else { hasFailed = true; return false }
        }
        identityID = identity
        self.box = box
        lastSeen = now
        return true
    }

    func isFresh(at now: Date) -> Bool {
        guard !hasFailed else { return false }
        guard let lastSeen else { return true }
        let age = now.timeIntervalSince(lastSeen)
        return age >= 0 && age <= 0.5
    }
}
