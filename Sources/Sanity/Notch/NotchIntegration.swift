import Combine
import Foundation

/// The small boundary between the imported notch feature and Sanity's app
/// shell. The notch never creates another settings window or app lifecycle.
@MainActor
final class NotchIntegration {
    static let shared = NotchIntegration()

    var onOpenSettings: (() -> Void)?
    let viewModel: BoringViewModel

    private lazy var controller = NotchController(viewModel: viewModel)
    private var hasStarted = false
    private var keepAwakeObserver: AnyCancellable?

    private init() {
        // Sanity owns onboarding, so the embedded notch must never enter Boring
        // Notch's first-launch presentation state. That state hides the normal
        // content and disables hover handling until its standalone onboarding
        // completes, which leaves an empty, expanded header in the host app.
        let coordinator = BoringViewCoordinator.shared
        coordinator.firstLaunch = false
        coordinator.helloAnimationRunning = false
        viewModel = BoringViewModel()
    }

    func start(_ notification: Notification) {
        guard !hasStarted else { return }
        hasStarted = true

        BoringViewCoordinator.shared.firstLaunch = false
        BoringViewCoordinator.shared.helloAnimationRunning = false
        viewModel.close()
        controller.applicationDidFinishLaunching(notification)
        observeSanityEvents()
    }

    /// Forwards Sanity's own state changes into the notch HUD. Only real
    /// transitions after launch are shown, never the restored launch state.
    private func observeSanityEvents() {
        keepAwakeObserver = KeepAwakeManager.shared.$isActive
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { isActive in
                BoringViewCoordinator.shared.toggleSneakPeek(
                    status: true, type: .keepAwake, duration: 1.8, value: isActive ? 1 : 0)
            }
    }

    func stop(_ notification: Notification) {
        guard hasStarted else { return }
        keepAwakeObserver = nil
        controller.applicationWillTerminate(notification)
        hasStarted = false
    }

    func openSettings() {
        onOpenSettings?()
    }
}
