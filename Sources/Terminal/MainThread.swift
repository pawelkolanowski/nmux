import Foundation

/// Runs `body` on the main actor, after `seconds`: the one hop to the main thread, from any thread.
public func onMain(after seconds: Double = 0, _ body: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(body) }
}
