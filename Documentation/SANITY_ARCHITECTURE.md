# Sanity product architecture

## Product boundary

Sanity has three deliberately non-overlapping surfaces:

- **Menu bar:** audio controls that should take less than two seconds, plus CPU, RAM, and battery at a glance.
- **Main window:** browsing, configuration, history, layouts, monitoring, cleanup, and every other utility that needs attention.
- **Notch overlay:** ambient media state and short-lived feedback. It is not a third utility launcher.

The current codebase has strong service coverage but presents too much of it in the menu bar. The redesign should move views, not replace working backends.

## Current repository map

### Application and state

- `AppDelegate` owns application lifecycle, the status item, popover, accessory/regular activation transitions, Settings and auxiliary AppKit windows, global menu commands, and service shutdown.
- `StatusItemController` owns the main status item and optional metric status items. It already distinguishes left click, right click, and metric clicks.
- `FeatureRuntime`, `AppFeature`, and `FeaturePreset` form an availability layer above individual feature preferences. This is the existing dependency/lifecycle boundary and should remain authoritative.
- `Defaults` and feature-specific `UserDefaults` keys are the persistence layer. `SettingsRouter` owns navigation into the current main window.
- Most long-lived services are singleton `ObservableObject`s. This is entrenched but reasonably centralized; migrating all of them during a UI redesign would add risk without user value.

### Current UI

- `MenuPanelView` is a full miniature utility hub with tabs for keep awake, brightness, mixer, system, network, disk, power, fan control, utilities, controls, and toggles. This is the principal clutter source.
- `SettingsView` is a `NavigationSplitView` with searchable pages. It already hosts nearly every detailed utility and is the best migration base for the main application window.
- Clipboard, media, cleaner, uninstaller, Homebrew, screenshot, recorder, shelf, command bar, switcher, and window layout already have dedicated views or settings pages.
- There is no notch window in the Vorssaint target.

### Existing feature inventory

- **Audio:** master output volume, master mute read/write, output enumeration and switching, separate system-sound output, per-app gain from 0–200%, per-app mute/restore, per-app output routing, input selection, microphone mute, headphone-disconnect protection, precise volume scrolling, output-cycle shortcut, music-launch blocking.
- **System:** CPU/GPU/memory usage and history, temperatures, memory pressure, network rate/totals, disk capacity and I/O, battery/adapter data, fan speed/control, process usage, notifications, and menu-bar metrics.
- **Clipboard and files:** local text/image/file history, search, pinning, deletion, quick paste, paste as plain text, automatic clearing, shelf, Finder cut/paste and rename, URL cleaning, disk-image installation.
- **Windows and Dock:** app/window switcher, previews, edge snapping, halves/thirds/sixths/corners/center, multi-display movement, restore history, green-button maximize, Dock click actions, auto-quit, and quit/close protection.
- **Input:** scroll inversion, smooth scrolling, focus follows mouse, mouse acceleration, navigation/buttons/gestures, middle click, click and key debounce, Super key, snippets, and global shortcuts.
- **Tools:** command bar, quick launcher/toggles, screenshots, recording, OCR, color picker, camera preview, scratchpad, radial menu, media conversion, cleaner, uninstaller, app updates, Homebrew, process termination, and cleaning mode.
- **Energy/display:** keep awake and automations, display brightness/power, extra XDR brightness, and Bluetooth-on-sleep behavior.

## Reuse decisions

Keep these implementations and put thinner presentation models in front of them:

- `AppVolumeMixer`: retain process discovery, process taps, aggregate-device routing, persistence, failure recovery, output-device observation, and master control.
- `SystemMonitor` and its samplers: retain demand-driven sampling. Each surface must declare only the metrics it currently needs.
- `ClipboardHistoryService`, `WindowLayoutService`, `KeepAwakeManager`, cleaner/uninstaller services, and feature runtime: retain intact.
- `StatusItemController` and the popover animation/anchoring logic: retain for reliability. Replace only its root SwiftUI view.
- `SettingsView` and `SettingsRouter`: use as the migration bridge for the main window, then reorganize the navigation without duplicating service state.
- Boring Notch can be used as a reference for window behaviors, but its complete multi-purpose notch UI should not be transplanted. The Sanity notch needs a smaller event-driven model.

## Technical constraints

### Per-app volume

- Supported by the existing `AppVolumeMixer` on macOS 14.4 and later through Core Audio process taps (`AudioHardwareCreateProcessTap`) and an aggregate output device.
- A muted process tap removes the app from the original mix; Sanity re-renders the tapped stream at the chosen gain/output. This is real routing, not a cosmetic slider, and needs no virtual audio driver.
- macOS requires **Screen & System Audio Recording** consent. Audio is processed live and is not recorded, but the permission wording is system-owned.
- Apps that manage exclusive/pro-audio paths are intentionally marked bypassed. They must be shown as unsupported rather than given a nonfunctional slider.
- A process can hold an audio connection while silent. The quick panel now filters to `isPlaying`; detailed mixer configuration and hidden/inactive app management stay in the main window.
- Boost above 100% is retained because it is already implemented, but the menu UI should visually de-emphasize it. Clipping protection remains the responsibility of the existing limiter/render path.

### Output switching and master volume

- Default output enumeration and switching use public Core Audio device properties and need no privacy permission.
- Hardware mute and volume controls are optional. HDMI, digital, and some aggregate devices expose neither. Sanity must omit/disable those controls and explain the hardware limitation.
- Changing the default output and the default system-sound output are separate Core Audio operations. The quick panel changes the main output only; advanced routing belongs in the main window.

### Now Playing

- macOS has no general public API that gives a third-party app every other app's Now Playing metadata and transport controls.
- The repository's `NowPlayingAdapter` loads private `MediaRemote.framework` symbols through a helper process. Its own comment notes that in-process reads stopped working on macOS 15.4 unless the caller has Apple's signature.
- Boring Notch also depends on private MediaRemote symbols and app-specific AppleScript. Copying that path would create OS-update and App Review risk.
- Recommended boundary: `NowPlayingProviding` with capability reporting. Start with the existing adapter only for direct/distributed builds where that risk is accepted; keep Apple Music/Spotify adapters as fallbacks. Do not expose controls unless the selected provider confirms support.
- Media-key event synthesis/interception may require Accessibility permission and can conflict with system behavior. It should be opt-in and isolated from metadata retrieval.

### Notch window positioning

- Use one borderless, transparent `NSPanel` per selected display, nonactivating by default, at a level above normal windows, with `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, and `.ignoresCycle` behavior.
- Position from the selected `NSScreen.frame` top center. On screens that expose top auxiliary areas, use them to infer notch width; there is no single public “physical notch frame” API that works on every Mac/display.
- External displays and Macs without a notch need a compact centered pill fallback or an explicit “built-in display only” preference.
- Recompute on display configuration, resolution, menu-bar placement, and full-screen Space changes. Avoid key-window activation for transient HUD events; expand into an interactive state only on hover/click.

## Target component architecture

```text
Sources/Vorssaint/
├── App/
│   ├── AppDelegate.swift                  # lifecycle only
│   ├── AppModel.swift                     # surface-level coordination
│   ├── StatusItemController.swift
│   └── MainWindowController.swift
├── Audio/
│   ├── AudioState.swift                   # presentation snapshot/capabilities
│   ├── AudioCoordinator.swift             # adapts existing services
│   └── Existing Audio services            # retained
├── UI/
│   ├── MenuBar/
│   │   ├── FocusedMenuBarPanel.swift
│   │   ├── MasterAudioControls.swift
│   │   ├── ActiveAppVolumeRow.swift
│   │   └── SystemGlanceRow.swift
│   ├── MainWindow/
│   │   ├── MainWindowView.swift
│   │   ├── MainDestination.swift
│   │   ├── OverviewView.swift
│   │   ├── ClipboardWorkspaceView.swift
│   │   ├── WindowWorkspaceView.swift
│   │   ├── SystemWorkspaceView.swift
│   │   ├── FilesWorkspaceView.swift
│   │   └── ToolsWorkspaceView.swift
│   └── Notch/
│       ├── NotchWindowController.swift
│       ├── NotchView.swift
│       ├── NotchModel.swift
│       ├── NotchEvent.swift
│       ├── NotchEventQueue.swift
│       ├── NowPlayingProviding.swift
│       ├── MediaNotchContent.swift
│       └── VolumeNotchContent.swift
└── Services/                              # existing backends retained
```

`AppModel` should coordinate only cross-surface events. Feature data remains owned by its service. `NotchEventQueue` accepts typed, expiring events such as system volume, app volume, output changed, copied, keep awake, and device connected. Priority and coalescing belong in the queue so rapid volume changes update one HUD rather than enqueue dozens.

## Implementation phases

### Phase 1 — focused menu bar and master audio

- Replace the miniature hub with output selection, master mute/volume, active app audio rows, glance metrics, and one main-window action.
- Declare focused monitor sampling needs on appearance and release them on dismissal.
- Preserve right-click context behavior and the existing stable popover controller.
- Status: **first implementation slice complete**. The main-window button currently opens the existing feature hub as a migration bridge.

### Phase 2 — harden per-app audio

- Add a small audio presentation coordinator with explicit supported/bypassed/permission/error states.
- Verify active-session disappearance, mute restore, device loss, sleep/wake, Bluetooth changes, 100% passthrough, boost limiting, and multiple processes per app.
- Feed volume/output changes into a surface-neutral event publisher for the future notch HUD.
- Add focused unit tests around session filtering, event coalescing, capability states, and device selection.

### Phase 3 — main utility window

- Promote the existing Settings window into a named Sanity main window.
- Introduce top-level destinations: Overview, Clipboard, Windows, System, Files, Tools, and Settings.
- Reuse existing views/services; split configuration from working surfaces where needed.
- Move clipboard quick history, window actions, monitor detail, mounted images, cleanup, and utility launchers out of the menu panel. Keep shortcuts intact.

### Phase 4 — notch foundation

- Implement `NotchWindowController`, display observation, collapsed/expanded geometry, hit testing, reduced-motion behavior, and the typed event queue.
- Start with developer-injected events and master-volume events; do not add a generic utility dashboard.

### Phase 5 — media and volume HUD

- Add a capability-aware Now Playing provider and clearly choose whether private MediaRemote is acceptable for distribution.
- Add artwork/title/artist and only supported previous/play/next actions.
- Coalesce master and per-app volume updates into short, interruptible HUD presentations and collapse automatically.

### Phase 6 — polish and edge cases

- Keyboard and VoiceOver audit, reduce motion/transparency, multiple displays/Spaces, full-screen apps, RTL/localization, permission revocation, missing outputs, sleep/wake, app churn, and energy profiling.
- Evaluate scroll-over-status-item volume only after testing event routing and discoverability. Do not ship Option-scroll brightness unless it is reliable and configurable.
