import AppKit
import Audio
import Contracts
import Library
import MacIntegration
import PlayerUI
import Skins
import UniformTypeIdentifiers

@MainActor
final class ApplicationCommandRouter: PlayerUICommandRouting {
    var coordinator: ProductionPlaybackCoordinator?

    func send(_ command: PlayerCommand) {
        guard let coordinator else { return }
        Task { await coordinator.send(command) }
    }
}

@MainActor
final class MacAmpApplicationDelegate: NSObject, NSApplicationDelegate {
    private var playerWindows: PlayerUIWindowController?
    private let commandRouter = ApplicationCommandRouter()
    private var coordinator: ProductionPlaybackCoordinator?
    private var systemMediaController: SystemMediaController?
    private var observationTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var pendingOpenURLs: [URL] = []
    private var supportRoot: URL?
    private var savedPlaylists: SavedPlaylistStore?
    private var skinPackages: SkinPackageManager?
    private var activeSkin: ResolvedSkin?
    private var savedPlaylistsMenu: NSMenu?
    private var playPauseMenuItem: NSMenuItem?
    private var latestPlayback = PlaybackSnapshot()
    private var playbackKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        playbackKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 49, modifiers.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
            self?.playPause()
            return nil
        }
        let playerWindows = PlayerUIWindowController()
        self.playerWindows = playerWindows
        playerWindows.commandRouter = commandRouter
        loadBundledSkin(.studioGraphite)
        playerWindows.show()
        startPlaybackServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { playerWindows?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        if let playbackKeyMonitor { NSEvent.removeMonitor(playbackKeyMonitor) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let coordinator {
            handleOpenURLs(urls, coordinator: coordinator)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    @objc private func openFiles() { playerWindows?.openFiles(replacingQueue: true) }
    @objc private func addFiles() { playerWindows?.openFiles(replacingQueue: false) }
    @objc private func showEqualizer() { playerWindows?.setModule(.equalizer, visible: true) }
    @objc private func showPlaylist() { playerWindows?.setModule(.playlist, visible: true) }
    @objc private func toggleCompactMode() { playerWindows?.toggleCompactMode() }
    @objc private func resetLayout() { playerWindows?.resetLayout() }
    @objc private func useGraphiteSkin() { loadBundledSkin(.studioGraphite) }
    @objc private func usePaperSkin() { loadBundledSkin(.paper) }
    @objc private func useTerminalSkin() { loadBundledSkin(.terminal) }
    @objc private func undoQueueMutation() { Task { _ = await coordinator?.undoLastQueueMutation() } }
    @objc private func clearPlaylist() { Task { await coordinator?.clearQueue() } }
    @objc private func focusPlaylistSearch() { playerWindows?.focusPlaylistSearch() }
    @objc private func revealPlayingTrack() { playerWindows?.revealPlayingTrack() }
    @objc private func scale100() { playerWindows?.setScale(1) }
    @objc private func scale125() { playerWindows?.setScale(1.25) }
    @objc private func scale150() { playerWindows?.setScale(1.5) }
    @objc private func useFlatEQ() { applyEQPreset(.flat) }
    @objc private func useRockEQ() { applyEQPreset(.rock) }
    @objc private func usePopEQ() { applyEQPreset(.pop) }
    @objc private func useJazzEQ() { applyEQPreset(.jazz) }
    @objc private func useClassicalEQ() { applyEQPreset(.classical) }
    @objc private func useBassBoostEQ() { applyEQPreset(.bassBoost) }
    @objc private func playPause() {
        let command: PlayerCommand
        if case .playing = latestPlayback.state { command = .pause } else { command = .play }
        commandRouter.send(command)
    }
    @objc private func stopPlayback() { commandRouter.send(.stop) }
    @objc private func previousTrack() { commandRouter.send(.previous) }
    @objc private func nextTrack() { commandRouter.send(.next) }

    private func applyEQPreset(_ preset: EqualizerPreset) {
        guard let coordinator else { return }
        Task { await coordinator.send(.setEqualizer(preset.settings)) }
    }

    private func startPlaybackServices() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fileManager = FileManager.default
                let supportBase = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let supportRoot = try ApplicationSupportMigration.prepare(
                    preferredRoot: supportBase.appendingPathComponent("MacAmp", isDirectory: true),
                    legacyRoot: supportBase.appendingPathComponent("ChuckAmp", isDirectory: true),
                    fileManager: fileManager
                )
                self.supportRoot = supportRoot
                let sessionStore = AtomicSessionStore(fileURL: supportRoot.appendingPathComponent("session.json"))
                let restored = try await sessionStore.load()
                self.savedPlaylists = SavedPlaylistStore(fileURL: supportRoot.appendingPathComponent("playlists.json"))
                self.skinPackages = SkinPackageManager(installedSkinsURL: supportRoot.appendingPathComponent("Skins", isDirectory: true))
                if let layout = restored?.windowLayout, !layout.modules.isEmpty {
                    self.playerWindows?.applyLayout(layout)
                }
                self.loadSkin(id: restored?.skinID ?? PrototypeSkin.studioGraphite.skinID)
                let coordinator = try await ProductionPlaybackCoordinator.makeProduction(sessionStore: sessionStore)
                self.coordinator = coordinator
                self.commandRouter.coordinator = coordinator
                if let activeSkin = self.activeSkin {
                    await coordinator.updatePresentationState(skinID: activeSkin.manifest.id)
                }
                self.playerWindows?.layoutDidChange = { [weak self] layout in
                    guard let coordinator = self?.coordinator else { return }
                    Task { await coordinator.updatePresentationState(windowLayout: layout) }
                }
                self.systemMediaController = SystemMediaController { command in
                    Task { await coordinator.send(command) }
                }
                self.noticeTask = Task { [weak self] in
                    for await message in coordinator.notices {
                        guard !Task.isCancelled else { return }
                        self?.showNotice(message)
                    }
                }
                self.refreshSavedPlaylistsMenu()
                if !self.pendingOpenURLs.isEmpty {
                    let urls = self.pendingOpenURLs
                    self.pendingOpenURLs.removeAll()
                    self.handleOpenURLs(urls, coordinator: coordinator)
                }
                for await snapshot in coordinator.snapshots {
                    guard !Task.isCancelled else { return }
                    let queue = await coordinator.queueSnapshot()
                    self.latestPlayback = snapshot
                    if case .playing = snapshot.state { self.playPauseMenuItem?.title = "Pause" }
                    else { self.playPauseMenuItem?.title = "Play" }
                    self.playerWindows?.update(playback: snapshot, queue: queue)
                    self.systemMediaController?.update(playback: snapshot, queue: queue)
                }
            } catch {
                let failure = PlaybackFailure(code: .unknown, message: error.localizedDescription)
                self.playerWindows?.update(
                    playback: PlaybackSnapshot(state: .failed(failure)),
                    queue: QueueSnapshot()
                )
            }
        }
    }

    private func loadBundledSkin(_ skin: PrototypeSkin) {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Skins", isDirectory: true) else {
            playerWindows?.applyPreviewSkin(skin == .studioGraphite ? .graphite : .paper)
            return
        }
        do {
            applySkin(try SkinResolver().resolve(skin, under: root))
        } catch {
            playerWindows?.applyPreviewSkin(skin == .studioGraphite ? .graphite : .paper)
        }
    }

    private func loadSkin(id: String) {
        if let bundled = PrototypeSkin.allCases.first(where: { $0.skinID == id }) {
            loadBundledSkin(bundled)
            return
        }
        do {
            guard let skinPackages else { throw SkinPackageError.notInstalled(id) }
            applySkin(try skinPackages.installedSkin(id: id))
        } catch {
            loadBundledSkin(.studioGraphite)
        }
    }

    private func applySkin(_ skin: ResolvedSkin) {
        activeSkin = skin
        playerWindows?.applySkin(skin)
        if let coordinator { Task { await coordinator.updatePresentationState(skinID: skin.manifest.id) } }
    }

    private func handleOpenURLs(_ urls: [URL], coordinator: ProductionPlaybackCoordinator) {
        let packages = urls.filter(SkinPackageManager.isSupportedPackage)
        let playable = urls.filter { !SkinPackageManager.isSupportedPackage($0) }
        for package in packages { importSkinPackage(package) }
        if !playable.isEmpty { Task { await coordinator.send(.open(playable)) } }
    }

    @objc private func importSkin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SkinPackageManager.packageExtension, SkinPackageManager.legacyPackageExtension]
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importSkinPackage(url)
        }
    }

    private func importSkinPackage(_ url: URL) {
        guard let manager = skinPackages else { return }
        Task {
            do {
                let preview = try await Task.detached { try manager.preview(packageURL: url) }.value
                let alert = NSAlert()
                alert.messageText = "Install \(preview.skin.manifest.name)?"
                alert.informativeText = "By \(preview.skin.manifest.author) · version \(preview.skin.manifest.version)"
                alert.addButton(withTitle: "Install & Apply")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let installed = try await Task.detached { try manager.install(packageURL: url) }.value
                applySkin(installed)
            } catch { showError("Couldn’t import skin", error) }
        }
    }

    @objc private func exportCurrentSkin() {
        guard let manager = skinPackages, let skin = activeSkin else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: SkinPackageManager.packageExtension)!]
        panel.nameFieldStringValue = "\(skin.manifest.id).\(SkinPackageManager.packageExtension)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { try await Task.detached { try manager.export(directory: skin.rootURL, to: url) }.value }
                catch { self?.showError("Couldn’t export skin", error) }
            }
        }
    }

    @objc private func exportCreatorStarter() {
        guard let manager = skinPackages,
              let directory = Bundle.main.resourceURL?.appendingPathComponent("Skins/CreatorExample", isDirectory: true) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: SkinPackageManager.packageExtension)!]
        panel.nameFieldStringValue = "MacAmp-Creator-Starter.\(SkinPackageManager.packageExtension)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { try await Task.detached { try manager.export(directory: directory, to: url) }.value }
                catch { self?.showError("Couldn’t export creator starter", error) }
            }
        }
    }

    @objc private func removeCurrentSkin() {
        guard let manager = skinPackages, let skin = activeSkin else { return }
        let installedRoot = manager.installedSkinsURL.standardizedFileURL.path + "/"
        guard skin.rootURL.standardizedFileURL.path.hasPrefix(installedRoot) else {
            showError("Bundled skins can’t be removed", SkinPackageError.notInstalled(skin.manifest.id)); return
        }
        do {
            try manager.remove(id: skin.manifest.id)
            loadBundledSkin(.studioGraphite)
        } catch { showError("Couldn’t remove skin", error) }
    }

    private func saveAccent(_ variation: SkinAccentVariation) {
        guard let manager = skinPackages, let skin = activeSkin else { return }
        do { applySkin(try manager.save(variation: variation, basedOn: skin)) }
        catch { showError("Couldn’t save accent variation", error) }
    }

    @objc private func accentElectricBlue() { saveAccent(.graphiteElectricBlue) }
    @objc private func accentPlum() { saveAccent(.paperPlum) }
    @objc private func accentAmber() { saveAccent(.terminalAmber) }

    @objc private func exportPlaylist() {
        guard let coordinator else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
        panel.nameFieldStringValue = "MacAmp Playlist.m3u8"
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                let queue = await coordinator.queueSnapshot()
                let urls = queue.entries.compactMap { queue.tracks[$0.trackID]?.lastKnownURL }
                do { try PortablePlaylistCodec().exportM3U(urls: urls, to: destination) }
                catch { self?.showError("Couldn’t export playlist", error) }
            }
        }
    }

    @objc private func saveNamedPlaylist() {
        guard let coordinator, let store = savedPlaylists else { return }
        let field = NSTextField(string: "")
        field.placeholderString = "Playlist name"
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = "Save Current Queue"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                _ = try await store.save(name: field.stringValue, queue: coordinator.queueSnapshot())
                refreshSavedPlaylistsMenu()
            } catch { showError("Couldn’t save playlist", error) }
        }
    }

    @objc private func openSavedPlaylist(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let uuid = UUID(uuidString: raw), let store = savedPlaylists, let coordinator else { return }
        Task {
            do {
                guard let playlist = try await store.all().first(where: { $0.id.rawValue == uuid }) else { return }
                await coordinator.openTracks(playlist.tracks)
            } catch { showError("Couldn’t open playlist", error) }
        }
    }

    private func refreshSavedPlaylistsMenu() {
        guard let menu = savedPlaylistsMenu, let store = savedPlaylists else { return }
        Task {
            do {
                let playlists = try await store.all()
                menu.removeAllItems()
                if playlists.isEmpty {
                    let empty = menu.addItem(withTitle: "No Saved Playlists", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                }
                for playlist in playlists {
                    let item = menu.addItem(withTitle: playlist.name, action: #selector(openSavedPlaylist(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = playlist.id.rawValue.uuidString
                }
            } catch { showError("Couldn’t load saved playlists", error) }
        }
    }

    @objc private func locateSelectedFile() {
        guard let coordinator else { return }
        Task {
            let queue = await coordinator.queueSnapshot()
            let entryID = queue.selectedEntryID ?? queue.playingEntryID ?? queue.entries.first?.id
            guard let entryID, let trackID = queue.entries.first(where: { $0.id == entryID })?.trackID else { return }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Choose the file for this playlist entry"
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                Task {
                    do { try await coordinator.reauthorize(trackID: trackID, at: url) }
                    catch { self?.showError("Couldn’t authorize file", error) }
                }
            }
        }
    }

    @objc private func revealSelectedFile() {
        guard let coordinator else { return }
        Task {
            let queue = await coordinator.queueSnapshot()
            let entryID = queue.selectedEntryID ?? queue.playingEntryID
            guard let entryID, let trackID = queue.entries.first(where: { $0.id == entryID })?.trackID,
                  let url = queue.tracks[trackID]?.lastKnownURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }

    private func showNotice(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MacAmp Notice"
        alert.informativeText = message
        alert.runModal()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MacAmp")
        appMenu.addItem(withTitle: "About MacAmp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MacAmp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit MacAmp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(openFiles), keyEquivalent: "o")
        openItem.target = self
        let addItem = fileMenu.addItem(withTitle: "Add to Playlist…", action: #selector(addFiles), keyEquivalent: "o")
        addItem.keyEquivalentModifierMask = [.command, .shift]
        addItem.target = self
        fileMenu.addItem(.separator())
        let saveNamed = fileMenu.addItem(withTitle: "Save Current Queue…", action: #selector(saveNamedPlaylist), keyEquivalent: "s")
        saveNamed.target = self
        let savedItem = NSMenuItem(title: "Open Saved Playlist", action: nil, keyEquivalent: "")
        let savedMenu = NSMenu(title: "Open Saved Playlist")
        savedItem.submenu = savedMenu
        savedPlaylistsMenu = savedMenu
        fileMenu.addItem(savedItem)
        let exportPlaylistItem = fileMenu.addItem(withTitle: "Export Playlist…", action: #selector(exportPlaylist), keyEquivalent: "e")
        exportPlaylistItem.target = self
        fileMenu.addItem(.separator())
        let locate = fileMenu.addItem(withTitle: "Locate Selected File…", action: #selector(locateSelectedFile), keyEquivalent: "l")
        locate.target = self
        let reveal = fileMenu.addItem(withTitle: "Reveal Selected File in Finder", action: #selector(revealSelectedFile), keyEquivalent: "r")
        reveal.keyEquivalentModifierMask = [.command, .shift]
        reveal.target = self
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undoItem = editMenu.addItem(withTitle: "Undo Playlist Change", action: #selector(undoQueueMutation), keyEquivalent: "z")
        undoItem.target = self
        let clearItem = editMenu.addItem(withTitle: "Clear Playlist", action: #selector(clearPlaylist), keyEquivalent: "")
        clearItem.target = self
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(withTitle: "Find in Playlist", action: #selector(focusPlaylistSearch), keyEquivalent: "f")
        findItem.target = self
        let revealPlaying = editMenu.addItem(withTitle: "Reveal Playing Track", action: #selector(revealPlayingTrack), keyEquivalent: "j")
        revealPlaying.keyEquivalentModifierMask = [.command, .shift]
        revealPlaying.target = self
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let playbackItem = NSMenuItem()
        let playbackMenu = NSMenu(title: "Playback")
        let playPauseItem = playbackMenu.addItem(withTitle: "Play", action: #selector(playPause), keyEquivalent: " ")
        playPauseItem.keyEquivalentModifierMask = []
        playPauseItem.target = self
        playPauseMenuItem = playPauseItem
        let stopItem = playbackMenu.addItem(withTitle: "Stop", action: #selector(stopPlayback), keyEquivalent: ".")
        stopItem.target = self
        playbackMenu.addItem(.separator())
        let previousItem = playbackMenu.addItem(withTitle: "Previous Track", action: #selector(previousTrack), keyEquivalent: "[")
        previousItem.target = self
        let nextItem = playbackMenu.addItem(withTitle: "Next Track", action: #selector(nextTrack), keyEquivalent: "]")
        nextItem.target = self
        playbackItem.submenu = playbackMenu
        mainMenu.addItem(playbackItem)

        let eqItem = NSMenuItem()
        let eqMenu = NSMenu(title: "Equalizer")
        for (title, action) in [
            ("Flat", #selector(useFlatEQ)), ("Rock", #selector(useRockEQ)),
            ("Pop", #selector(usePopEQ)), ("Jazz", #selector(useJazzEQ)),
            ("Classical", #selector(useClassicalEQ)), ("Bass Boost", #selector(useBassBoostEQ)),
        ] {
            let item = eqMenu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        eqItem.submenu = eqMenu
        mainMenu.addItem(eqItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let equalizerItem = windowMenu.addItem(withTitle: "Show Equalizer", action: #selector(showEqualizer), keyEquivalent: "g")
        equalizerItem.target = self
        let playlistItem = windowMenu.addItem(withTitle: "Show Playlist", action: #selector(showPlaylist), keyEquivalent: "p")
        playlistItem.target = self
        let compactItem = windowMenu.addItem(withTitle: "Compact Player", action: #selector(toggleCompactMode), keyEquivalent: "w")
        compactItem.target = self
        windowMenu.addItem(.separator())
        let resetItem = windowMenu.addItem(withTitle: "Reset Layout", action: #selector(resetLayout), keyEquivalent: "0")
        resetItem.target = self
        let scaleItem = NSMenuItem(title: "Interface Scale", action: nil, keyEquivalent: "")
        let scaleMenu = NSMenu(title: "Interface Scale")
        for (title, action) in [("100%", #selector(scale100)), ("125%", #selector(scale125)), ("150%", #selector(scale150))] {
            let item = scaleMenu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        scaleItem.submenu = scaleMenu
        windowMenu.addItem(scaleItem)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let skinsItem = NSMenuItem()
        let skinsMenu = NSMenu(title: "Skins")
        let graphiteItem = skinsMenu.addItem(withTitle: "Studio Graphite", action: #selector(useGraphiteSkin), keyEquivalent: "1")
        graphiteItem.target = self
        let paperItem = skinsMenu.addItem(withTitle: "Paper", action: #selector(usePaperSkin), keyEquivalent: "2")
        paperItem.target = self
        let terminalItem = skinsMenu.addItem(withTitle: "Terminal", action: #selector(useTerminalSkin), keyEquivalent: "3")
        terminalItem.target = self
        skinsMenu.addItem(.separator())
        let accentsItem = NSMenuItem(title: "Save Accent Variation", action: nil, keyEquivalent: "")
        let accentsMenu = NSMenu(title: "Save Accent Variation")
        for (title, action) in [("Electric Blue", #selector(accentElectricBlue)), ("Plum", #selector(accentPlum)), ("Amber", #selector(accentAmber))] {
            let item = accentsMenu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        accentsItem.submenu = accentsMenu
        skinsMenu.addItem(accentsItem)
        skinsMenu.addItem(.separator())
        let importSkinItem = skinsMenu.addItem(withTitle: "Import Skin…", action: #selector(importSkin), keyEquivalent: "i")
        importSkinItem.target = self
        let exportSkinItem = skinsMenu.addItem(withTitle: "Export Current Skin…", action: #selector(exportCurrentSkin), keyEquivalent: "e")
        exportSkinItem.target = self
        let exportStarterItem = skinsMenu.addItem(withTitle: "Export Creator Starter…", action: #selector(exportCreatorStarter), keyEquivalent: "")
        exportStarterItem.target = self
        let removeSkinItem = skinsMenu.addItem(withTitle: "Remove Current Skin", action: #selector(removeCurrentSkin), keyEquivalent: "")
        removeSkinItem.target = self
        skinsItem.submenu = skinsMenu
        mainMenu.addItem(skinsItem)

        NSApp.mainMenu = mainMenu
    }
}

@main
enum MacAmpMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MacAmpApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
