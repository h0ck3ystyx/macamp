import AppKit
import Contracts
import Library
import MacIntegration
import PlayerUI
import Skins

@MainActor
final class ApplicationCommandRouter: PlayerUICommandRouting {
    var coordinator: ProductionPlaybackCoordinator?

    func send(_ command: PlayerCommand) {
        guard let coordinator else { return }
        Task { await coordinator.send(command) }
    }
}

@MainActor
final class ChuckAmpApplicationDelegate: NSObject, NSApplicationDelegate {
    private var playerWindows: PlayerUIWindowController?
    private let commandRouter = ApplicationCommandRouter()
    private var coordinator: ProductionPlaybackCoordinator?
    private var observationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let playerWindows = PlayerUIWindowController()
        self.playerWindows = playerWindows
        playerWindows.commandRouter = commandRouter
        playerWindows.show()
        loadBundledSkin(.studioGraphite)
        startPlaybackServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { playerWindows?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openFiles() { playerWindows?.openFiles(replacingQueue: true) }
    @objc private func addFiles() { playerWindows?.openFiles(replacingQueue: false) }
    @objc private func showEqualizer() { playerWindows?.setModule(.equalizer, visible: true) }
    @objc private func showPlaylist() { playerWindows?.setModule(.playlist, visible: true) }
    @objc private func toggleCompactMode() { playerWindows?.toggleCompactMode() }
    @objc private func resetLayout() { playerWindows?.resetLayout() }
    @objc private func useGraphiteSkin() { loadBundledSkin(.studioGraphite) }
    @objc private func usePaperSkin() { loadBundledSkin(.paper) }

    private func startPlaybackServices() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fileManager = FileManager.default
                let supportRoot = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                ).appendingPathComponent("ChuckAmp", isDirectory: true)
                try fileManager.createDirectory(at: supportRoot, withIntermediateDirectories: true)
                let sessionStore = AtomicSessionStore(fileURL: supportRoot.appendingPathComponent("session.json"))
                let coordinator = try await ProductionPlaybackCoordinator.makeProduction(sessionStore: sessionStore)
                self.coordinator = coordinator
                self.commandRouter.coordinator = coordinator
                for await snapshot in coordinator.snapshots {
                    guard !Task.isCancelled else { return }
                    let queue = await coordinator.queueSnapshot()
                    self.playerWindows?.update(playback: snapshot, queue: queue)
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
            playerWindows?.applySkin(try SkinResolver().resolve(skin, under: root))
        } catch {
            playerWindows?.applyPreviewSkin(skin == .studioGraphite ? .graphite : .paper)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ChuckAmp")
        appMenu.addItem(withTitle: "About ChuckAmp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ChuckAmp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit ChuckAmp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(openFiles), keyEquivalent: "o")
        openItem.target = self
        let addItem = fileMenu.addItem(withTitle: "Add to Playlist…", action: #selector(addFiles), keyEquivalent: "o")
        addItem.keyEquivalentModifierMask = [.command, .shift]
        addItem.target = self
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

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
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let skinsItem = NSMenuItem()
        let skinsMenu = NSMenu(title: "Skins")
        let graphiteItem = skinsMenu.addItem(withTitle: "Studio Graphite", action: #selector(useGraphiteSkin), keyEquivalent: "1")
        graphiteItem.target = self
        let paperItem = skinsMenu.addItem(withTitle: "Paper", action: #selector(usePaperSkin), keyEquivalent: "2")
        paperItem.target = self
        skinsItem.submenu = skinsMenu
        mainMenu.addItem(skinsItem)

        NSApp.mainMenu = mainMenu
    }
}

@main
enum ChuckAmpMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ChuckAmpApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
