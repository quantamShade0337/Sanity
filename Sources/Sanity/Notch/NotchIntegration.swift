import Combine
import Defaults
import CoreAudio
import Foundation

/// Which of Sanity's own events flash in the notch. Each is a UserDefaults
/// bool so the Notch settings page can bind to it with `@AppStorage`.
enum NotchSanityEvent: String, CaseIterable, Identifiable {
    case keepAwake, copied, capture, output
    var id: String { rawValue }

    var defaultsKey: String { "notchSanityEvent.\(rawValue)" }

    /// Copying happens constantly, so that one is opt-in.
    var enabledByDefault: Bool { self != .copied }

    func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? enabledByDefault
    }

    var titleKey: GuideKey {
        switch self {
        case .keepAwake: return .notchEventKeepAwake
        case .copied: return .notchEventCopied
        case .capture: return .notchEventCapture
        case .output: return .notchEventOutput
        }
    }
}

/// The small boundary between the imported notch feature and Sanity's app
/// shell. The notch never creates another settings window or app lifecycle.
@MainActor
final class NotchIntegration {
    static let shared = NotchIntegration()

    var onOpenSettings: (() -> Void)?
    let viewModel: BoringViewModel

    private lazy var controller = NotchController(viewModel: viewModel)
    private var hasStarted = false
    private var observers: [AnyCancellable] = []
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var lastOutputDevice: AudioDeviceID = 0

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
        // The decorative HUD options (glow, gradient bar, accent tint) were
        // removed with the move to the iPhone Dynamic Island look; make sure
        // values saved by older versions can't bring them back.
        Defaults[.systemEventIndicatorShadow] = false
        Defaults[.enableGradient] = false
        Defaults[.systemEventIndicatorUseAccent] = false
        controller.applicationDidFinishLaunching(notification)
        observeSanityEvents()
    }

    func stop(_ notification: Notification) {
        guard hasStarted else { return }
        observers.removeAll()
        stopObservingOutputDevice()
        controller.applicationWillTerminate(notification)
        hasStarted = false
    }

    func openSettings() {
        onOpenSettings?()
    }

    // MARK: - Sanity events

    /// Shows one compact island alert: a glyph left of the camera and one
    /// short word right of it, for about as long as iPhone shows Silent mode.
    private func show(_ event: NotchSanityEvent, icon: String, label: GuideKey, active: Bool = true) {
        show(event, icon: icon, text: GuideText.t(label), active: active)
    }

    private func show(_ event: NotchSanityEvent, icon: String, text: String, active: Bool = true) {
        guard event.isEnabled() else { return }
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true, type: .event, duration: 2.0, value: active ? 1 : 0, icon: icon, label: text)
    }

    /// Forwards Sanity's own state changes into the notch HUD. Only real
    /// transitions after launch are shown, never the restored launch state,
    /// and only for features that are installed.
    private func observeSanityEvents() {
        if AppFeature.keepAwake.isAvailable {
            KeepAwakeManager.shared.$isActive
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isActive in
                    self?.show(.keepAwake,
                               icon: isActive ? "cup.and.heat.waves.fill" : "cup.and.saucer.fill",
                               label: isActive ? .on : .evOff, active: isActive)
                }
                .store(in: &observers)
        }

        if AppFeature.clipboardHistory.isAvailable {
            // Only a copy newer than anything seen so far counts: deleting or
            // pinning entries also changes the list but is not a copy.
            var newestSeen = ClipboardHistoryService.shared.entries.map(\.copiedAt).max() ?? .distantPast
            ClipboardHistoryService.shared.$entries
                .compactMap { $0.map(\.copiedAt).max() }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] latest in
                    guard latest > newestSeen else { return }
                    newestSeen = latest
                    self?.show(.copied, icon: "doc.on.clipboard.fill", label: .evCopied)
                }
                .store(in: &observers)
        }

        if AppFeature.screenshot.isAvailable || AppFeature.screenRecorder.isAvailable {
            RecentCaptureService.shared.$entries
                .map { entries in entries.max(by: { $0.createdAt < $1.createdAt }) }
                .removeDuplicates { $0?.id == $1?.id }
                .dropFirst()
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] entry in
                    let isRecording = entry.kind == .recording
                    self?.show(.capture,
                               icon: isRecording ? "record.circle.fill" : "camera.viewfinder",
                               label: .evSaved)
                }
                .store(in: &observers)
        }

        observeOutputDevice()
    }

    // MARK: Default output device

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static func currentOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        return status == noErr ? device : 0
    }

    private static func deviceName(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private func observeOutputDevice() {
        lastOutputDevice = Self.currentOutputDevice()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.outputDeviceChanged() }
        }
        var address = Self.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, DispatchQueue.main, block) == noErr {
            outputListener = block
        }
    }

    private func stopObservingOutputDevice() {
        guard let block = outputListener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, DispatchQueue.main, block)
        outputListener = nil
    }

    private func outputDeviceChanged() {
        let device = Self.currentOutputDevice()
        guard device != 0, device != lastOutputDevice else { return }
        lastOutputDevice = device
        guard let name = Self.deviceName(device) else { return }
        let lower = name.lowercased()
        let icon = lower.contains("airpods") ? "airpods"
            : (lower.contains("headphone") || lower.contains("buds")) ? "headphones"
            : lower.contains("display") || lower.contains("tv") ? "tv"
            : "hifispeaker.fill"
        show(.output, icon: icon, text: name)
    }
}
