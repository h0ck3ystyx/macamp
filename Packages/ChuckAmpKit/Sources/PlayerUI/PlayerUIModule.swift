import AppKit
import Contracts
import Skins

public enum PlayerUIModule {
    public static let isPrototypeImplemented = true
}

/// Placeholder content for the window feasibility spike. Production UI must bind
/// the same views to PlaybackSnapshot and QueueSnapshot instead.
public struct PlayerUIPreviewState: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var elapsed: TimeInterval
    public var duration: TimeInterval
    public var formatDescription: String
    public var playlist: [String]

    public init(
        title: String = "Northern Lights",
        artist: String = "The Cassette Signals",
        elapsed: TimeInterval = 222,
        duration: TimeInterval = 312,
        formatDescription: String = "FLAC · 44.1 kHz · Stereo",
        playlist: [String] = ["The Cassette Signals — Northern Lights", "Soft Relay — Waiting Room", "Juniper Arcade — Last Train Home"]
    ) {
        self.title = title; self.artist = artist; self.elapsed = elapsed; self.duration = duration
        self.formatDescription = formatDescription; self.playlist = playlist
    }
}

public enum PlayerUISkinPreview: String, CaseIterable, Sendable { case graphite, paper }

@MainActor
public protocol PlayerUICommandRouting: AnyObject { func send(_ command: PlayerCommand) }

@MainActor
public final class PlayerUIWindowController: NSObject {
    public static let defaultPlayerSize = NSSize(width: 360, height: 160)
    public static let defaultEqualizerSize = NSSize(width: 360, height: 160)
    public static let defaultPlaylistSize = NSSize(width: 360, height: 300)
    public static let compactPlayerSize = NSSize(width: 360, height: 40)

    public weak var commandRouter: PlayerUICommandRouting?
    public var importFeedback: (([URL], Bool) -> Void)?
    public private(set) var previewSkin: PlayerUISkinPreview
    public private(set) var isCompact = false

    private var model: PlayerUIStateModel
    private let snapDistance: CGFloat
    private let windowDelegateProxy = ModuleWindowDelegate()
    private var windows: [PlayerModule: NSWindow] = [:]
    private var isApplyingLayout = false
    private var lastPlayerOrigin: NSPoint?
    private var connectedModules: Set<PlayerModule> = [.player, .playlist]
    private var visibleModules: Set<PlayerModule> = [.player, .playlist]

    public init(previewSkin: PlayerUISkinPreview = .graphite, playback: PlaybackSnapshot = PlaybackSnapshot(), queue: QueueSnapshot = QueueSnapshot(), snapDistance: CGFloat = 10) {
        self.previewSkin = previewSkin; self.model = PlayerUIStateModel(playback: playback, queue: queue); self.snapDistance = snapDistance
        super.init()
        windowDelegateProxy.owner = self
        createWindows(); resetLayout()
    }

    public static func preview(skin: PlayerUISkinPreview = .graphite, state: PlayerUIPreviewState = PlayerUIPreviewState()) -> PlayerUIWindowController {
        let snapshots = PlayerUIPreviewAdapter.snapshots(from: state)
        return PlayerUIWindowController(previewSkin: skin, playback: snapshots.0, queue: snapshots.1)
    }

    public func update(playback: PlaybackSnapshot, queue: QueueSnapshot) {
        let oldModel = model
        model = PlayerUIStateModel(playback: playback, queue: queue, filterText: model.filterText)
        (windows[.player]?.contentViewController as? PlayerViewController)?.update(model)
        (windows[.player]?.contentViewController as? CompactPlayerViewController)?.update(model)
        if oldModel.playback.equalizer != playback.equalizer {
            windows[.equalizer]?.contentViewController = EqualizerViewController(theme: theme, model: model, actions: actions)
        }
        if oldModel.queue != queue {
            windows[.playlist]?.contentViewController = PlaylistViewController(theme: theme, model: model, actions: actions)
        }
    }

    public func setPlaylistFilter(_ text: String) {
        model.filterText = text
        windows[.playlist]?.contentViewController = PlaylistViewController(theme: theme, model: model, actions: actions)
    }

    public func applySkin(_ skin: ResolvedSkin) {
        resolvedTheme = PlayerUITheme(skin)
        refreshContent()
    }

    public func openFiles(replacingQueue: Bool) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            self.receiveFiles(panel.urls, replacingQueue: replacingQueue)
        }
    }

    public func dispatch(_ command: PlayerCommand) { commandRouter?.send(command) }

    public func receiveFiles(_ urls: [URL], replacingQueue: Bool) {
        guard !urls.isEmpty else { return }
        importFeedback?(urls, replacingQueue)
        dispatch(replacingQueue ? .open(urls) : .append(urls))
    }

    public func show() {
        for module in [PlayerModule.player, .equalizer, .playlist] where shouldShow(module) { windows[module]?.orderFront(nil) }
        windows[.player]?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func hideAll() { windows.values.forEach { $0.orderOut(nil) } }

    public func setModule(_ module: PlayerModule, visible: Bool) {
        guard module != .player, let window = windows[module] else { return }
        if module == .equalizer, connectedModules.contains(.playlist), let player = windows[.player], let playlist = windows[.playlist] {
            let targetY = visible ? player.frame.minY - window.frame.height - playlist.frame.height : player.frame.minY - playlist.frame.height
            isApplyingLayout = true
            window.setFrameOrigin(NSPoint(x: player.frame.minX, y: player.frame.minY - window.frame.height))
            playlist.setFrameOrigin(NSPoint(x: player.frame.minX, y: targetY))
            connectedModules.insert(.equalizer)
            isApplyingLayout = false
        }
        if visible { visibleModules.insert(module); window.makeKeyAndOrderFront(nil) }
        else { visibleModules.remove(module); window.orderOut(nil) }
    }

    public func toggleCompactMode() { setCompactMode(!isCompact) }

    public func setCompactMode(_ compact: Bool) {
        guard compact != isCompact, let player = windows[.player] else { return }
        isCompact = compact
        let oldTop = player.frame.maxY
        let size = compact ? Self.compactPlayerSize : Self.defaultPlayerSize
        let secondaryDelta = player.frame.height - size.height
        isApplyingLayout = true
        player.setFrame(NSRect(x: player.frame.minX, y: oldTop - size.height, width: size.width, height: size.height), display: true)
        for module in connectedModules where module != .player {
            guard let window = windows[module] else { continue }
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY + secondaryDelta))
        }
        player.contentViewController = compact ? CompactPlayerViewController(theme: theme, model: model, actions: actions) : PlayerViewController(theme: theme, model: model, actions: actions)
        isApplyingLayout = false
    }

    public func applyPreviewSkin(_ skin: PlayerUISkinPreview) {
        previewSkin = skin; resolvedTheme = nil; refreshContent()
    }

    public func resetLayout(on screen: NSScreen? = nil) {
        guard let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        isCompact = false
        let x = min(max(visible.midX - 180, visible.minX), visible.maxX - 360)
        let playlistHeight = min(300, max(180, visible.height - 160 - 36))
        let top = min(visible.maxY, max(visible.minY + 160 + playlistHeight, visible.maxY - 36))
        let playerFrame = NSRect(x: x, y: top - 160, width: 360, height: 160)
        let eqFrame = NSRect(x: x, y: playerFrame.minY - 160, width: 360, height: 160)
        let playlistFrame = NSRect(x: x, y: playerFrame.minY - playlistHeight, width: 360, height: playlistHeight)
        isApplyingLayout = true
        windows[.player]?.setFrame(playerFrame, display: true)
        windows[.equalizer]?.setFrame(eqFrame, display: true)
        windows[.playlist]?.setFrame(playlistFrame, display: true)
        windows[.player]?.contentViewController = PlayerViewController(theme: theme, model: model, actions: actions)
        windows[.equalizer]?.orderOut(nil); visibleModules = [.player, .playlist]
        connectedModules = [.player, .equalizer, .playlist]; lastPlayerOrigin = playerFrame.origin
        isApplyingLayout = false
    }

    public func currentLayout() -> WindowLayout {
        WindowLayout(scale: 1, isCompact: isCompact, modules: PlayerModule.allCases.compactMap { module in
            guard let window = windows[module] else { return nil }
            return ModuleLayout(module: module, frame: WindowRect(x: window.frame.minX, y: window.frame.minY, width: window.frame.width, height: window.frame.height), isVisible: visibleModules.contains(module), groupID: connectedModules.contains(module) ? Self.previewGroupID : nil)
        })
    }

    private static let previewGroupID = UUID(uuidString: "A42D19BA-2D3E-4E3F-9276-7F51AC97DBE0")!
    private var resolvedTheme: PlayerUITheme?
    private var theme: PlayerUITheme { resolvedTheme ?? PlayerUITheme(previewSkin) }
    private var actions: PlayerUIActions {
        PlayerUIActions(send: { [weak self] in self?.dispatch($0) }, compact: { [weak self] in self?.toggleCompactMode() }, showEqualizer: { [weak self] in self?.setModule(.equalizer, visible: true) }, showPlaylist: { [weak self] in self?.setModule(.playlist, visible: true) }, importFiles: { [weak self] replace in self?.openFiles(replacingQueue: replace) }, receiveFiles: { [weak self] urls, replace in self?.receiveFiles(urls, replacingQueue: replace) }, search: { [weak self] in self?.setPlaylistFilter($0) })
    }
    private func shouldShow(_ module: PlayerModule) -> Bool { visibleModules.contains(module) }

    private func createWindows() {
        windows[.player] = makeWindow(module: .player, size: Self.defaultPlayerSize, resizable: false)
        windows[.equalizer] = makeWindow(module: .equalizer, size: Self.defaultEqualizerSize, resizable: false)
        windows[.playlist] = makeWindow(module: .playlist, size: Self.defaultPlaylistSize, resizable: true)
        applyPreviewSkin(previewSkin)
    }

    private func refreshContent() {
        windows[.player]?.contentViewController = isCompact ? CompactPlayerViewController(theme: theme, model: model, actions: actions) : PlayerViewController(theme: theme, model: model, actions: actions)
        windows[.equalizer]?.contentViewController = EqualizerViewController(theme: theme, model: model, actions: actions)
        windows[.playlist]?.contentViewController = PlaylistViewController(theme: theme, model: model, actions: actions)
    }

    private func makeWindow(module: PlayerModule, size: NSSize, resizable: Bool) -> NSWindow {
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { mask.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        window.title = title(for: module); window.identifier = NSUserInterfaceItemIdentifier("ChuckAmp.\(module.rawValue)")
        window.titleVisibility = .visible; window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed; window.collectionBehavior = [.fullScreenAuxiliary]
        window.minSize = module == .playlist ? NSSize(width: 360, height: 180) : size
        window.delegate = windowDelegateProxy; window.setAccessibilityLabel(title(for: module))
        return window
    }

    private func title(for module: PlayerModule) -> String {
        switch module { case .player: "ChuckAmp Player"; case .equalizer: "ChuckAmp Equalizer"; case .playlist: "ChuckAmp Playlist" }
    }

    fileprivate func windowWillMove(_ window: NSWindow) {
        guard !isApplyingLayout, let module = module(for: window) else { return }
        if module == .player { lastPlayerOrigin = window.frame.origin } else { connectedModules.remove(module) }
    }
    fileprivate func windowDidMove(_ window: NSWindow) {
        guard !isApplyingLayout, let module = module(for: window) else { return }
        if module == .player { moveConnectedWindows(with: window) } else { snapSecondaryWindow(module, window: window) }
    }
    fileprivate func windowShouldClose(_ window: NSWindow) -> Bool {
        guard let module = module(for: window) else { return true }
        if module == .player { hideAll() } else { visibleModules.remove(module); window.orderOut(nil) }
        return false
    }
    private func module(for window: NSWindow) -> PlayerModule? { windows.first(where: { $0.value === window })?.key }
    private func moveConnectedWindows(with player: NSWindow) {
        guard let previous = lastPlayerOrigin else { lastPlayerOrigin = player.frame.origin; return }
        let delta = NSPoint(x: player.frame.minX - previous.x, y: player.frame.minY - previous.y)
        guard delta != .zero else { return }
        isApplyingLayout = true
        for module in connectedModules where module != .player {
            guard let window = windows[module] else { continue }
            window.setFrameOrigin(NSPoint(x: window.frame.minX + delta.x, y: window.frame.minY + delta.y))
        }
        isApplyingLayout = false; lastPlayerOrigin = player.frame.origin
    }
    private func snapSecondaryWindow(_ module: PlayerModule, window: NSWindow) {
        let anchors = windows.filter { $0.key != module && connectedModules.contains($0.key) }.map(\.value.frame)
        guard let snapped = anchors.compactMap({ WindowSnapGeometry.snappedFrame(moving: window.frame, to: $0, threshold: snapDistance) }).min(by: {
            hypot($0.minX - window.frame.minX, $0.minY - window.frame.minY) < hypot($1.minX - window.frame.minX, $1.minY - window.frame.minY)
        }) else { return }
        isApplyingLayout = true; window.setFrameOrigin(snapped.origin); connectedModules.insert(module); isApplyingLayout = false
    }
}

private final class ModuleWindowDelegate: NSObject, NSWindowDelegate {
    weak var owner: PlayerUIWindowController?
    func windowWillMove(_ notification: Notification) { if let window = notification.object as? NSWindow { owner?.windowWillMove(window) } }
    func windowDidMove(_ notification: Notification) { if let window = notification.object as? NSWindow { owner?.windowDidMove(window) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { owner?.windowShouldClose(sender) ?? true }
}

public enum WindowSnapGeometry {
    public static func snappedFrame(moving: NSRect, to anchor: NSRect, threshold: CGFloat) -> NSRect? {
        let points = [NSPoint(x: anchor.minX, y: anchor.minY - moving.height), NSPoint(x: anchor.minX, y: anchor.maxY), NSPoint(x: anchor.minX - moving.width, y: anchor.minY), NSPoint(x: anchor.maxX, y: anchor.minY)]
        return points.map { NSRect(origin: $0, size: moving.size) }
            .filter { abs($0.minX - moving.minX) <= threshold && abs($0.minY - moving.minY) <= threshold }
            .min { hypot($0.minX - moving.minX, $0.minY - moving.minY) < hypot($1.minX - moving.minX, $1.minY - moving.minY) }
    }
}
