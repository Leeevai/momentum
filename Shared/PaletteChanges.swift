import Foundation
import Observation

/// Redraws the views that drew the active palette's colors outside the environment (`goal.tint`,
/// `Color.accent`, the named roles) when the palette changes. Reading those colors in a view's
/// body registers the view with Observation, as reading a store property would; without it, a
/// view whose body reads nothing else that changes kept the old palette's colors.
final class PaletteChanges: Observable, @unchecked Sendable {
    static let shared = PaletteChanges()

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var count = 0

    /// Notes that the caller drew the active palette's colors.
    func track() {
        registrar.access(self, keyPath: \.revision)
    }

    /// Redraws every view that drew them. The store calls it when the active palette changes.
    func changed() {
        registrar.withMutation(of: self, keyPath: \.revision) {
            lock.withLock { count += 1 }
        }
    }

    /// What `track` and `changed` name: how many times the palette changed.
    private var revision: Int { lock.withLock { count } }
}
