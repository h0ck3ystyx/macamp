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
    public static let defaultEqualizerSize = NSSize(width: 360, height: 200)
    public static let defaultPlaylistSize = NSSize(width: 360, height: 260)
    public static let compactPlayerSize = NSSize(width: 360, height: 40)

    public weak var commandRouter: PlayerUICommandRouting?
    public var importFeedback: (([URL], Bool) -> Void)?
    public var layoutDidChange: ((WindowLayout) -> Void)?
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
    private var uiScale: Double = 1

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
            replaceContentController(EqualizerViewController(theme: theme, model: model, actions: actions), for: .equalizer)
        }
        if oldModel.queue != queue {
            replaceContentController(PlaylistViewController(theme: theme, model: model, actions: actions), for: .playlist)
        }
    }

    public func setPlaylistFilter(_ text: String) {
        model.filterText = text
        replaceContentController(PlaylistViewController(theme: theme, model: model, actions: actions), for: .playlist)
    }

    public func revealPlayingTrack() {
        guard model.playback.currentEntryID != nil else { return }
        setPlaylistFilter("")
        setModule(.playlist, visible: true)
        (windows[.playlist]?.contentViewController as? PlaylistViewController)?.revealPlaying()
    }

    public func focusPlaylistSearch() {
        setModule(.playlist, visible: true)
        windows[.playlist]?.makeKeyAndOrderFront(nil)
        (windows[.playlist]?.contentViewController as? PlaylistViewController)?.focusSearch()
    }

    public func applySkin(_ skin: ResolvedSkin) {
        resolvedTheme = skin
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
        notifyLayoutChanged()
    }

    public func toggleCompactMode() { setCompactMode(!isCompact) }

    public func setCompactMode(_ compact: Bool) {
        guard compact != isCompact, let player = windows[.player] else { return }
        isCompact = compact
        let oldTop = player.frame.maxY
        let baseSize = compact ? Self.compactPlayerSize : Self.defaultPlayerSize
        let contentSize = NSSize(width: baseSize.width * uiScale, height: baseSize.height * uiScale)
        let frameSize = player.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let secondaryDelta = player.frame.height - frameSize.height
        isApplyingLayout = true
        player.contentViewController = compact ? CompactPlayerViewController(theme: theme, model: model, actions: actions) : PlayerViewController(theme: theme, model: model, actions: actions)
        updateContentMinimum(for: .player, window: player)
        player.setFrame(NSRect(x: player.frame.minX, y: oldTop - frameSize.height, width: frameSize.width, height: frameSize.height), display: true)
        for module in connectedModules where module != .player {
            guard let window = windows[module] else { continue }
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY + secondaryDelta))
        }
        isApplyingLayout = false
        notifyLayoutChanged()
    }

    public func applyPreviewSkin(_ skin: PlayerUISkinPreview) {
        previewSkin = skin; resolvedTheme = nil; refreshContent()
    }

    public func resetLayout(on screen: NSScreen? = nil) {
        guard let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        isCompact = false
        guard let player = windows[.player], let equalizer = windows[.equalizer], let playlist = windows[.playlist] else { return }
        let playlistContentHeight = min(Self.defaultPlaylistSize.height, max(180, visible.height - Self.defaultPlayerSize.height - 72))
        let playerSize = frameSize(forContentSize: Self.defaultPlayerSize, in: player)
        let equalizerSize = frameSize(forContentSize: Self.defaultEqualizerSize, in: equalizer)
        let playlistSize = frameSize(forContentSize: NSSize(width: Self.defaultPlaylistSize.width, height: playlistContentHeight), in: playlist)
        let x = min(max(visible.midX - playerSize.width / 2, visible.minX), visible.maxX - playerSize.width)
        let top = min(visible.maxY, max(visible.minY + playerSize.height + playlistSize.height, visible.maxY - 36))
        let playerFrame = NSRect(x: x, y: top - playerSize.height, width: playerSize.width, height: playerSize.height)
        let eqFrame = NSRect(x: x, y: playerFrame.minY - equalizerSize.height, width: equalizerSize.width, height: equalizerSize.height)
        let playlistFrame = NSRect(x: x, y: playerFrame.minY - playlistSize.height, width: playlistSize.width, height: playlistSize.height)
        isApplyingLayout = true
        uiScale = 1
        windows[.player]?.contentViewController = PlayerViewController(theme: theme, model: model, actions: actions)
        updateContentMinimum(for: .player, window: player)
        windows[.player]?.setFrame(playerFrame, display: true)
        windows[.equalizer]?.setFrame(eqFrame, display: true)
        windows[.playlist]?.setFrame(playlistFrame, display: true)
        refreshContent()
        windows[.equalizer]?.orderOut(nil); visibleModules = [.player, .playlist]
        connectedModules = [.player, .equalizer, .playlist]; lastPlayerOrigin = playerFrame.origin
        isApplyingLayout = false
        notifyLayoutChanged()
    }

    /// Restores only frames that can be recovered onto an attached display. Invalid
    /// or empty layouts fall back to the normal stacked layout.
    public func applyLayout(_ layout: WindowLayout) {
        guard !layout.modules.isEmpty, layout.scale.isFinite, (0.75...2).contains(layout.scale) else {
            resetLayout()
            return
        }
        isApplyingLayout = true
        uiScale = layout.scale
        visibleModules.removeAll()
        connectedModules.removeAll()
        isCompact = layout.isCompact
        for (module, window) in windows { updateContentMinimum(for: module, window: window) }
        windows[.player]?.contentViewController = isCompact
            ? CompactPlayerViewController(theme: theme, model: model, actions: actions)
            : PlayerViewController(theme: theme, model: model, actions: actions)
        if let player = windows[.player] { updateContentMinimum(for: .player, window: player) }
        let grouped = Dictionary(grouping: layout.modules.compactMap(\.groupID), by: { $0 })
        let connectedGroup = grouped.max(by: { $0.value.count < $1.value.count })?.key
        var savedFrames: [PlayerModule: NSRect] = [:]
        for saved in layout.modules {
            guard let window = windows[saved.module], saved.frame.width.isFinite, saved.frame.height.isFinite,
                  saved.frame.x.isFinite, saved.frame.y.isFinite, saved.frame.width >= 100, saved.frame.height >= 36 else { continue }
            let minimum = frameSize(forContentSize: window.contentMinSize, in: window)
            savedFrames[saved.module] = NSRect(x: saved.frame.x, y: saved.frame.y, width: saved.frame.width, height: saved.frame.height)
            let proposed = NSRect(
                x: saved.frame.x,
                y: saved.frame.y,
                width: max(saved.frame.width, minimum.width),
                height: max(saved.frame.height, minimum.height)
            )
            window.setFrame(recover(proposed), display: true)
            if saved.isVisible { visibleModules.insert(saved.module) }
            if saved.groupID == connectedGroup { connectedModules.insert(saved.module) }
        }
        reattachConnectedFrames(from: savedFrames)
        refreshContent()
        visibleModules.insert(.player)
        connectedModules.insert(.player)
        for (module, window) in windows {
            if visibleModules.contains(module) { window.orderFront(nil) } else { window.orderOut(nil) }
        }
        lastPlayerOrigin = windows[.player]?.frame.origin
        isApplyingLayout = false
        notifyLayoutChanged()
    }

    public func setScale(_ scale: Double) {
        guard [1.0, 1.25, 1.5].contains(scale), scale != uiScale else { return }
        let ratio = scale / uiScale
        isApplyingLayout = true
        let oldFrames = Dictionary(uniqueKeysWithValues: windows.map { ($0.key, $0.value.frame) })
        uiScale = scale
        let anchorX = windows[.player]?.frame.minX ?? 0
        let anchorY = windows[.player]?.frame.maxY ?? 0
        var newSizes: [PlayerModule: NSSize] = [:]
        for (module, window) in windows {
            let old = oldFrames[module] ?? window.frame
            let oldContentSize = window.contentRect(forFrameRect: old).size
            let newContentSize = NSSize(width: oldContentSize.width * ratio, height: oldContentSize.height * ratio)
            newSizes[module] = frameSize(forContentSize: newContentSize, in: window)
            updateContentMinimum(for: module, window: window)
        }
        var newFrames: [PlayerModule: NSRect] = [:]
        if let playerSize = newSizes[.player] {
            newFrames[.player] = NSRect(x: anchorX, y: anchorY - playerSize.height, width: playerSize.width, height: playerSize.height)
        }
        var pending = connectedModules.subtracting([.player])
        while !pending.isEmpty {
            var placedAny = false
            for module in pending {
                guard let movingOld = oldFrames[module], let movingSize = newSizes[module] else { continue }
                for anchor in connectedModules where anchor != module {
                    guard let anchorOld = oldFrames[anchor], let anchorNew = newFrames[anchor],
                          let attached = WindowScaleGeometry.attachedFrame(movingOld: movingOld, movingSize: movingSize, anchorOld: anchorOld, anchorNew: anchorNew) else { continue }
                    newFrames[module] = attached
                    pending.remove(module)
                    placedAny = true
                    break
                }
            }
            if !placedAny { break }
        }
        for module in PlayerModule.allCases where newFrames[module] == nil {
            guard let old = oldFrames[module], let size = newSizes[module] else { continue }
            let newTop = anchorY + (old.maxY - anchorY) * ratio
            let newX = anchorX + (old.minX - anchorX) * ratio
            newFrames[module] = NSRect(x: newX, y: newTop - size.height, width: size.width, height: size.height)
        }
        for module in PlayerModule.allCases {
            guard let window = windows[module], let frame = newFrames[module] else { continue }
            window.setFrame(recover(frame), display: true)
        }
        refreshContent()
        lastPlayerOrigin = windows[.player]?.frame.origin
        isApplyingLayout = false
        notifyLayoutChanged()
    }

    public func currentLayout() -> WindowLayout {
        WindowLayout(scale: uiScale, isCompact: isCompact, modules: PlayerModule.allCases.compactMap { module in
            guard let window = windows[module] else { return nil }
            return ModuleLayout(module: module, frame: WindowRect(x: window.frame.minX, y: window.frame.minY, width: window.frame.width, height: window.frame.height), isVisible: visibleModules.contains(module), groupID: connectedModules.contains(module) ? Self.previewGroupID : nil)
        })
    }

    private static let previewGroupID = UUID(uuidString: "A42D19BA-2D3E-4E3F-9276-7F51AC97DBE0")!
    private var resolvedTheme: ResolvedSkin?
    private var theme: PlayerUITheme {
        if let resolvedTheme { return PlayerUITheme(resolvedTheme, scale: uiScale) }
        return PlayerUITheme(previewSkin, scale: uiScale)
    }
    private var actions: PlayerUIActions {
        PlayerUIActions(send: { [weak self] in self?.dispatch($0) }, compact: { [weak self] in self?.toggleCompactMode() }, showEqualizer: { [weak self] in self?.setModule(.equalizer, visible: true) }, showPlaylist: { [weak self] in self?.setModule(.playlist, visible: true) }, importFiles: { [weak self] replace in self?.openFiles(replacingQueue: replace) }, receiveFiles: { [weak self] urls, replace in self?.receiveFiles(urls, replacingQueue: replace) }, search: { [weak self] in self?.setPlaylistFilter($0) })
    }
    private func shouldShow(_ module: PlayerModule) -> Bool { visibleModules.contains(module) }

    private func recover(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let visible = screens.first(where: { $0.intersects(frame) }) ?? NSScreen.main?.visibleFrame ?? screens.first else { return frame }
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return NSRect(
            x: min(max(frame.minX, visible.minX), visible.maxX - width),
            y: min(max(frame.minY, visible.minY), visible.maxY - height),
            width: width,
            height: height
        )
    }

    private func frameSize(forContentSize contentSize: NSSize, in window: NSWindow) -> NSSize {
        window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }

}

public enum WindowScaleGeometry {
    public static func attachedFrame(movingOld: NSRect, movingSize: NSSize, anchorOld: NSRect, anchorNew: NSRect) -> NSRect? {
        let tolerance: CGFloat = 1.5
        if abs(movingOld.minX - anchorOld.minX) <= tolerance {
            if abs(movingOld.maxY - anchorOld.minY) <= tolerance {
                return NSRect(x: anchorNew.minX, y: anchorNew.minY - movingSize.height, width: movingSize.width, height: movingSize.height)
            }
            if abs(movingOld.minY - anchorOld.maxY) <= tolerance {
                return NSRect(x: anchorNew.minX, y: anchorNew.maxY, width: movingSize.width, height: movingSize.height)
            }
        }
        if abs(movingOld.minY - anchorOld.minY) <= tolerance {
            if abs(movingOld.maxX - anchorOld.minX) <= tolerance {
                return NSRect(x: anchorNew.minX - movingSize.width, y: anchorNew.minY, width: movingSize.width, height: movingSize.height)
            }
            if abs(movingOld.minX - anchorOld.maxX) <= tolerance {
                return NSRect(x: anchorNew.maxX, y: anchorNew.minY, width: movingSize.width, height: movingSize.height)
            }
        }
        return nil
    }
}

extension PlayerUIWindowController {
    private func notifyLayoutChanged() {
        guard !isApplyingLayout else { return }
        layoutDidChange?(currentLayout())
    }


    private func createWindows() {
        windows[.player] = makeWindow(module: .player, size: Self.defaultPlayerSize, resizable: false)
        windows[.equalizer] = makeWindow(module: .equalizer, size: Self.defaultEqualizerSize, resizable: false)
        windows[.playlist] = makeWindow(module: .playlist, size: Self.defaultPlaylistSize, resizable: true)
        applyPreviewSkin(previewSkin)
    }

    private func refreshContent() {
        replaceContentController(isCompact ? CompactPlayerViewController(theme: theme, model: model, actions: actions) : PlayerViewController(theme: theme, model: model, actions: actions), for: .player)
        replaceContentController(EqualizerViewController(theme: theme, model: model, actions: actions), for: .equalizer)
        replaceContentController(PlaylistViewController(theme: theme, model: model, actions: actions), for: .playlist)
    }

    /// AppKit may resize a window to a replacement controller's fitting size. Queue,
    /// EQ, search, and skin refreshes must retain the user's window geometry.
    private func replaceContentController(_ controller: NSViewController, for module: PlayerModule) {
        guard let window = windows[module] else { return }
        let frame = window.frame
        let wasApplyingLayout = isApplyingLayout
        isApplyingLayout = true
        window.contentViewController = controller
        updateContentMinimum(for: module, window: window)
        if window.frame != frame { window.setFrame(frame, display: true) }
        isApplyingLayout = wasApplyingLayout
    }

    private func updateContentMinimum(for module: PlayerModule, window: NSWindow) {
        let base: NSSize
        switch module {
        case .player: base = isCompact ? Self.compactPlayerSize : Self.defaultPlayerSize
        case .equalizer: base = Self.defaultEqualizerSize
        case .playlist: base = NSSize(width: Self.defaultPlaylistSize.width, height: 180)
        }
        window.contentMinSize = NSSize(width: base.width * uiScale, height: base.height * uiScale)
    }

    /// A newer release may increase a module's minimum size. Rebuild the saved
    /// attachment graph around the player so upgrading the frame cannot create
    /// overlaps or gaps in a previously connected stack.
    private func reattachConnectedFrames(from savedFrames: [PlayerModule: NSRect]) {
        guard let player = windows[.player] else { return }
        var restoredFrames: [PlayerModule: NSRect] = [.player: player.frame]
        var pending = connectedModules.subtracting([.player])
        while !pending.isEmpty {
            var placedAny = false
            for module in pending {
                guard let movingOld = savedFrames[module], let movingWindow = windows[module] else { continue }
                for anchor in connectedModules where anchor != module {
                    guard let anchorOld = savedFrames[anchor], let anchorNew = restoredFrames[anchor],
                          let attached = WindowScaleGeometry.attachedFrame(
                            movingOld: movingOld,
                            movingSize: movingWindow.frame.size,
                            anchorOld: anchorOld,
                            anchorNew: anchorNew
                          ) else { continue }
                    movingWindow.setFrame(attached, display: true)
                    restoredFrames[module] = attached
                    pending.remove(module)
                    placedAny = true
                    break
                }
            }
            if !placedAny { break }
        }
    }

    private func makeWindow(module: PlayerModule, size: NSSize, resizable: Bool) -> NSWindow {
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { mask.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        window.title = title(for: module); window.identifier = NSUserInterfaceItemIdentifier("MacAmp.\(module.rawValue)")
        window.titleVisibility = .visible; window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed; window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentMinSize = module == .playlist ? NSSize(width: 360, height: 180) : size
        window.delegate = windowDelegateProxy; window.setAccessibilityLabel(title(for: module))
        return window
    }

    private func title(for module: PlayerModule) -> String {
        switch module { case .player: "MacAmp Player"; case .equalizer: "MacAmp Equalizer"; case .playlist: "MacAmp Playlist" }
    }

    fileprivate func windowWillMove(_ window: NSWindow) {
        guard !isApplyingLayout, let module = module(for: window) else { return }
        if module == .player { lastPlayerOrigin = window.frame.origin } else { connectedModules.remove(module) }
    }
    fileprivate func windowDidMove(_ window: NSWindow) {
        guard !isApplyingLayout, let module = module(for: window) else { return }
        if module == .player { moveConnectedWindows(with: window) } else { snapSecondaryWindow(module, window: window) }
        notifyLayoutChanged()
    }
    fileprivate func windowDidResize(_ window: NSWindow) {
        guard !isApplyingLayout, module(for: window) != nil else { return }
        notifyLayoutChanged()
    }
    fileprivate func windowShouldClose(_ window: NSWindow) -> Bool {
        guard let module = module(for: window) else { return true }
        if module == .player {
            hideAll()
            notifyLayoutChanged()
        } else {
            setModule(module, visible: false)
        }
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
    func windowDidResize(_ notification: Notification) { if let window = notification.object as? NSWindow { owner?.windowDidResize(window) } }
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
