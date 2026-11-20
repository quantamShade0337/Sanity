import ApplicationServices
import CoreGraphics
import Foundation
import IOKit

/// Runs the original Boring Notch helper operations in-process. Sanity is not
/// sandboxed, so a separately bundled XPC executable would only add fragility.
final class XPCHelperClient: NSObject, @unchecked Sendable {
    nonisolated static let shared = XPCHelperClient()

    private let stateLock = NSLock()
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?

    deinit { stopMonitoringAccessibilityAuthorization() }

    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        stopMonitoringAccessibilityAuthorization()
        let task = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                _ = await self.isAccessibilityAuthorized()
                do { try await Task.sleep(for: .seconds(interval)) } catch { break }
            }
        }
        stateLock.withLock { monitoringTask = task }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        let task = stateLock.withLock {
            let task = monitoringTask
            monitoringTask = nil
            return task
        }
        task?.cancel()
    }

    var isMonitoring: Bool { stateLock.withLock { monitoringTask != nil } }

    nonisolated func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    nonisolated func isAccessibilityAuthorized() async -> Bool {
        let granted = AXIsProcessTrusted()
        notifyAuthorizationChange(granted)
        return granted
    }

    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        if AXIsProcessTrusted() {
            notifyAuthorizationChange(true)
            return true
        }
        if promptIfNeeded {
            requestAccessibilityAuthorization()
            try? await Task.sleep(for: .milliseconds(500))
        }
        let granted = AXIsProcessTrusted()
        notifyAuthorizationChange(granted)
        return granted
    }

    private nonisolated func notifyAuthorizationChange(_ granted: Bool) {
        let changed = stateLock.withLock {
            guard lastKnownAuthorization != granted else { return false }
            lastKnownAuthorization = granted
            return true
        }
        guard changed else { return }
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .accessibilityAuthorizationChanged,
                object: nil,
                userInfo: ["granted": granted]
            )
        }
    }

    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        Self.keyboardClient.isAvailable
    }

    nonisolated func currentKeyboardBrightness() async -> Float? {
        Self.keyboardClient.currentBrightness()
    }

    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        Self.keyboardClient.setBrightness(max(0, min(1, value)))
    }

    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        var brightness: Float = 0
        return displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &brightness)
            || ioServiceFor(displayID: CGMainDisplayID()) != nil
    }

    nonisolated func currentScreenBrightness() async -> Float? {
        var brightness: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &brightness) {
            return brightness
        }
        guard let service = ioServiceFor(displayID: CGMainDisplayID()) else { return nil }
        defer { IOObjectRelease(service) }
        guard IODisplayGetFloatParameter(
            service, 0, kIODisplayBrightnessKey as CFString, &brightness
        ) == kIOReturnSuccess else { return nil }
        return brightness
    }

    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) { return true }
        guard let service = ioServiceFor(displayID: CGMainDisplayID()) else { return false }
        defer { IOObjectRelease(service) }
        return IODisplaySetFloatParameter(
            service, 0, kIODisplayBrightnessKey as CFString, clamped
        ) == kIOReturnSuccess
    }

    private final class KeyboardBrightnessClient: @unchecked Sendable {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            let paths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            ]
            var loaded = false
            for path in paths where !loaded { loaded = Bundle(path: path)?.load() == true }
            if loaded, let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = type.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let function: BrightnessGetter = methodIMP(
                    on: clientInstance, selector: getSelector, as: BrightnessGetter.self
                  ) else { return nil }
            return function(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let function: BrightnessSetter = methodIMP(
                    on: clientInstance, selector: setSelector, as: BrightnessSetter.self
                  ) else { return false }
            return function(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as _: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector) else { return nil }
            return unsafeBitCast(method_getImplementation(method), to: T.self)
        }
    }

    private nonisolated static let keyboardClient = KeyboardBrightnessClient()

    private nonisolated func displayServicesGetBrightness(
        displayID: CGDirectDisplayID, out: inout Float
    ) -> Bool {
        guard let symbol = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else {
            return false
        }
        typealias Function = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        return unsafeBitCast(symbol, to: Function.self)(displayID, &out) == 0
    }

    private nonisolated func displayServicesSetBrightness(
        displayID: CGDirectDisplayID, value: Float
    ) -> Bool {
        guard let symbol = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else {
            return false
        }
        typealias Function = @convention(c) (CGDirectDisplayID, Float) -> Int32
        return unsafeBitCast(symbol, to: Function.self)(displayID, value) == 0
    }

    private nonisolated func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private enum DisplayServicesHandle {
        nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices",
            ]
            for path in paths {
                if let handle = dlopen(path, RTLD_LAZY) { return handle }
            }
            return nil
        }()
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
