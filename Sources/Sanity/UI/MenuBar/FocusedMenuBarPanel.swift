// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The two-second surface: output, volume, active audio sessions and a small
/// system glance. Configuration and the rest of the utility suite stay in the
/// main window.
struct FocusedMenuBarPanel: View {
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeApps: [MixerApp] {
        mixer.apps.filter(\.isPlaying).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masterAudioSection

            Divider()
                .padding(.vertical, 14)

            applicationAudioSection

            Divider()
                .padding(.vertical, 12)

            SystemGlanceRow(snapshot: monitor.snapshot)

            Divider()
                .padding(.top, 12)

            footer
                .padding(.top, 10)
        }
        .padding(16)
        .frame(width: 356)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            SystemMonitor.shared.setMenuPanelNeeds(
                SystemMonitorPanelNeeds(cpu: true, memory: true, battery: true)
            )
        }
        .onDisappear {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
        }
    }

    private var masterAudioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel("Audio")
                Spacer(minLength: 8)
                outputPicker
            }

            if let volume = mixer.systemOutputVolume {
                HStack(spacing: 10) {
                    Button {
                        mixer.toggleCurrentOutputMute()
                    } label: {
                        Image(systemName: masterVolumeSymbol(volume: volume))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(mixer.systemOutputMuted == nil)
                    .help(mixer.systemOutputMuted == true ? "Unmute" : "Mute")
                    .accessibilityLabel(mixer.systemOutputMuted == true ? "Unmute system audio" : "Mute system audio")

                    Slider(value: masterVolumeBinding, in: 0...1)
                        .controlSize(.small)
                        .accessibilityLabel("System volume")

                    Text(volume, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            } else {
                Text("This output does not provide software volume control.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputPicker: some View {
        Picker("Output device", selection: outputSelection) {
            if mixer.currentOutputDeviceUID == nil {
                Text(l10n.s.mixerOutputUnavailable)
                    .tag(MixerRoutingSupport.systemDefaultSelectionID)
            }
            ForEach(mixer.outputDevices.filter(\.canBeDefaultOutput)) { device in
                Text(device.name).tag(device.uid)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: 202, alignment: .trailing)
        .disabled(mixer.outputDevices.filter(\.canBeDefaultOutput).isEmpty)
        .accessibilityLabel("Current output device")
    }

    private var applicationAudioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("App volume")

            if !AppVolumeMixer.isSupported {
                compactMessage(l10n.s.mixerUnavailable, symbol: "speaker.slash")
            } else if mixer.needsPermission {
                permissionMessage
            } else if activeApps.isEmpty {
                compactMessage("Apps appear here while they are producing audio.",
                               symbol: "waveform")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activeApps) { app in
                            ActiveAppVolumeRow(app: app)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxHeight: 252)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18),
                           value: activeApps.map(\.id))
            }
        }
    }

    private var permissionMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.s.mixerPermissionBody)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(l10n.s.permissionOpenSettings) {
                    Permissions.shared.openAudioCaptureSettings()
                }
                .controlSize(.small)
            }
        }
    }

    private func compactMessage(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                appDelegate()?.closePopover {
                    SettingsRouter.shared.page = .features
                    appDelegate()?.openSettingsWindow()
                }
            } label: {
                Text("Open Sanity")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Button {
                appDelegate()?.closePopover {
                    SettingsRouter.shared.page = .general
                    appDelegate()?.openSettingsWindow()
                }
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 16, height: 16)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .help(l10n.s.panelSettings)
            .accessibilityLabel(l10n.s.panelSettings)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private var masterVolumeBinding: Binding<Double> {
        Binding(
            get: { mixer.systemOutputVolume ?? 0 },
            set: { mixer.setCurrentOutputVolume($0) }
        )
    }

    private var outputSelection: Binding<String> {
        Binding(
            get: { mixer.currentOutputDeviceUID ?? MixerRoutingSupport.systemDefaultSelectionID },
            set: { uid in
                guard uid != MixerRoutingSupport.systemDefaultSelectionID else { return }
                mixer.setUniversalOutputDeviceUID(uid)
            }
        )
    }

    private func masterVolumeSymbol(volume: Double) -> String {
        if mixer.systemOutputMuted == true || volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

private struct ActiveAppVolumeRow: View {
    @ObservedObject private var mixer = AppVolumeMixer.shared
    let app: MixerApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: ResponsibleProcess.icon(for: app.ownerPid, pointSize: 26))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(app.volume, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if app.isBypassed {
                    Text("This app manages its own audio.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        MixerVolumeSlider(
                            value: volumeBinding,
                            normalTint: .accentColor,
                            boostTint: .orange,
                            isBoosting: app.volume > 1.005,
                            accentRevision: 0,
                            maximum: AppVolumeMixer.maxVolume,
                            accessibilityLabel: app.name
                        )

                        Button {
                            mixer.toggleMute(app)
                        } label: {
                            Image(systemName: app.volume <= 0.001
                                  ? "speaker.slash.fill"
                                  : "speaker.wave.2.fill")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help(app.volume <= 0.001 ? "Unmute \(app.name)" : "Mute \(app.name)")
                        .accessibilityLabel(app.volume <= 0.001 ? "Unmute \(app.name)" : "Mute \(app.name)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { app.volume },
            set: { mixer.setVolume($0, for: app) }
        )
    }
}

private struct SystemGlanceRow: View {
    let snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 0) {
            glance("CPU", value: snapshot.cpuUsage.map(percent) ?? "—")
            glance("RAM", value: memoryPercent)
            glance("Battery", value: snapshot.power?.chargePercent.map { "\($0)%" } ?? "—")
        }
        .accessibilityElement(children: .combine)
    }

    private func glance(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.system(size: 10.5))
        .frame(maxWidth: .infinity)
    }

    private var memoryPercent: String {
        guard let used = snapshot.memoryUsed,
              let total = snapshot.memoryTotal,
              total > 0 else { return "—" }
        return percent(Double(used) / Double(total))
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
