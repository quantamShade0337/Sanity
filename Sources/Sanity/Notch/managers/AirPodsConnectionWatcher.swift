// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Ethan Soh

import CoreAudio
import CoreBluetooth
import Foundation
import IOBluetooth

/// Notices AirPods (or Beats) connecting to this Mac however it happens, so
/// the island appears the moment they connect, as on iPhone:
///
/// - a Bluetooth connection, even when macOS doesn't switch sound to them;
/// - a new AirPods audio device appearing (covers the case where Bluetooth
///   notifications aren't delivered because Bluetooth access was declined);
/// - sound switching to AirPods that were already connected (handled by
///   NotchIntegration's default-output listener, which calls `report`).
///
/// Every source funnels through `report`, which drops repeats for the same
/// device within a few seconds, so one connection shows one alert.
@MainActor
final class AirPodsConnectionWatcher: NSObject {
    var onConnect: ((String) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var knownAudioDevices: Set<String> = []
    private var lastAlert: [String: Date] = [:]
    /// IOBluetooth replays devices that are already connected right after
    /// registering; those aren't new connections.
    private var startedAt = Date.distantFuture
    private let launchQuietPeriod: TimeInterval = 3
    private let repeatWindow: TimeInterval = 8

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        startedAt = Date()
        startBluetoothIfAllowed()

        knownAudioDevices = Self.audioDeviceNames()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.audioDevicesChanged() }
        }
        var address = Self.devicesAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, DispatchQueue.main, block) == noErr {
            devicesListener = block
        }
    }

    /// Bluetooth notifications only once Sanity already has Bluetooth access.
    /// Registering without it makes macOS ask for access on launch and blocks
    /// the main thread until the person answers, freezing a first launch.
    /// Until then the audio-device listener still catches AirPods connecting.
    private func startBluetoothIfAllowed() {
        guard connectNotification == nil, CBManager.authorization == .allowedAlways else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(bluetoothDeviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        if let block = devicesListener {
            var address = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                   &address, DispatchQueue.main, block)
            devicesListener = nil
        }
    }

    /// Shows the alert for `name` unless it was just shown for this device.
    func report(_ name: String) {
        guard AirPodsStatus.looksLikeAirPods(name) else { return }
        let key = name.replacingOccurrences(of: "’", with: "'").lowercased()
        let now = Date()
        if let last = lastAlert[key], now.timeIntervalSince(last) < repeatWindow { return }
        lastAlert[key] = now
        onConnect?(name)
    }

    @objc private func bluetoothDeviceConnected(_ notification: IOBluetoothUserNotification,
                                                device: IOBluetoothDevice) {
        guard Date().timeIntervalSince(startedAt) > launchQuietPeriod,
              let name = device.name else { return }
        report(name)
    }

    private func audioDevicesChanged() {
        startBluetoothIfAllowed()  // picks up access granted since launch
        let current = Self.audioDeviceNames()
        let added = current.subtracting(knownAudioDevices)
        knownAudioDevices = current
        for name in added { report(name) }
    }

    private static func audioDeviceNames() -> Set<String> {
        var address = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return Set(devices.compactMap(deviceName))
    }

    static func deviceName(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
