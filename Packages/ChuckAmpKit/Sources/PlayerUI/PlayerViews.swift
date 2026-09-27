import AppKit
import Contracts
import Skins

struct PlayerUIActions {
    var send: (PlayerCommand) -> Void
    var compact: () -> Void; var showEqualizer: () -> Void; var showPlaylist: () -> Void
    var importFiles: (Bool) -> Void
    var receiveFiles: ([URL], Bool) -> Void
    var search: (String) -> Void
}

struct PlayerUITheme {
    let background: NSColor; let panel: NSColor; let text: NSColor
    let secondaryText: NSColor; let accent: NSColor; let border: NSColor
    let trackFont: NSFont; let technicalFont: NSFont; let controlFont: NSFont
    let images: [SkinAssetKey: NSImage]
    let scale: CGFloat
    init(_ preview: PlayerUISkinPreview, scale: CGFloat = 1) {
        self.scale = scale
        switch preview {
        case .graphite:
            background = NSColor(deviceWhite: 0.105, alpha: 1); panel = NSColor(deviceWhite: 0.15, alpha: 1)
            text = NSColor(deviceRed: 1, green: 0.82, blue: 0.34, alpha: 1); secondaryText = NSColor(deviceWhite: 0.76, alpha: 1)
            accent = NSColor(deviceRed: 1, green: 0.56, blue: 0.12, alpha: 1); border = NSColor(deviceWhite: 0.34, alpha: 1)
        case .paper:
            background = NSColor(deviceRed: 0.93, green: 0.91, blue: 0.86, alpha: 1); panel = NSColor(deviceRed: 0.985, green: 0.975, blue: 0.945, alpha: 1)
            text = NSColor(deviceRed: 0.12, green: 0.16, blue: 0.18, alpha: 1); secondaryText = NSColor(deviceRed: 0.3, green: 0.32, blue: 0.32, alpha: 1)
            accent = NSColor(deviceRed: 0.04, green: 0.43, blue: 0.48, alpha: 1); border = NSColor(deviceRed: 0.58, green: 0.55, blue: 0.49, alpha: 1)
        }
        trackFont = .systemFont(ofSize: 11 * scale); technicalFont = .monospacedSystemFont(ofSize: 10 * scale, weight: .regular); controlFont = .systemFont(ofSize: 11 * scale, weight: .semibold); images = [:]
    }
    init(_ skin: ResolvedSkin, scale: CGFloat = 1) {
        self.scale = scale
        background = NSColor(hex: skin.color(.windowBackground)) ?? .windowBackgroundColor
        panel = NSColor(hex: skin.color(.displayBackground)) ?? .controlBackgroundColor
        text = NSColor(hex: skin.color(.textPrimary)) ?? .labelColor
        secondaryText = NSColor(hex: skin.color(.textSecondary)) ?? .secondaryLabelColor
        accent = NSColor(hex: skin.color(.accent)) ?? .controlAccentColor
        border = NSColor(hex: skin.color(.border)) ?? .separatorColor
        trackFont = Self.font(skin.font(.track), size: 11 * scale); technicalFont = Self.font(skin.font(.technical), size: 10 * scale); controlFont = Self.font(skin.font(.controls), size: 11 * scale)
        images = Dictionary(uniqueKeysWithValues: SkinAssetKey.allCases.compactMap { key in skin.asset(key).flatMap(NSImage.init(contentsOf:)).map { (key, $0) } })
    }
    private static func font(_ value: SkinFontValue, size: CGFloat) -> NSFont {
        switch value { case .system, .systemRounded: .systemFont(ofSize: size); case .systemMonospaced: .monospacedSystemFont(ofSize: size, weight: .regular) }
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")); guard value.count == 6 || value.count == 8, let raw = UInt64(value, radix: 16) else { return nil }
        let shift = value.count == 8 ? 8 : 0
        self.init(deviceRed: CGFloat((raw >> (16 + shift)) & 0xff) / 255, green: CGFloat((raw >> (8 + shift)) & 0xff) / 255, blue: CGFloat((raw >> shift) & 0xff) / 255, alpha: value.count == 8 ? CGFloat(raw & 0xff) / 255 : 1)
    }
}

class ThemedViewController: NSViewController {
    let theme: PlayerUITheme
    init(theme: PlayerUITheme) { self.theme = theme; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = AudioDropView(); view.wantsLayer = true; view.layer?.backgroundColor = theme.background.cgColor
        view.layer?.borderColor = theme.border.cgColor; view.layer?.borderWidth = 1
        if let frame = theme.images[.windowFrame] { view.layer?.contents = frame; view.layer?.contentsGravity = .resizeAspectFill }
    }
    func scaled(_ value: CGFloat) -> CGFloat { value * theme.scale }
    func scaleControl(_ control: NSControl) {
        control.controlSize = theme.scale > 1 ? .large : .regular
    }
    func label(_ text: String, size: CGFloat = 11, bold: Bool = false, color: NSColor? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.font = bold ? .boldSystemFont(ofSize: scaled(size)) : .systemFont(ofSize: scaled(size))
        label.textColor = color ?? theme.text; label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func button(_ title: String, label: String, image: NSImage? = nil, action: @escaping () -> Void) -> NSButton {
        let button = ActionButton(title: title, action: action)
        scaleControl(button)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = theme.panel.cgColor
        button.layer?.borderColor = theme.border.cgColor
        button.layer?.borderWidth = scaled(1)
        button.layer?.cornerRadius = scaled(5)
        button.contentTintColor = theme.accent
        styleButtonTitle(button, title: title)
        if let image { button.image = image; button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown }
        button.font = theme.controlFont; button.setAccessibilityLabel(label); button.toolTip = label; return button
    }
    func styleButtonTitle(_ button: NSButton?, title: String) {
        button?.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: theme.text, .font: theme.controlFont]
        )
    }
}

final class ActionButton: NSButton {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) { handler = action; super.init(frame: .zero); self.title = title; target = self; self.action = #selector(performAction) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performAction() { handler() }
}

final class AudioDropView: NSView {
    var onDrop: (([URL]) -> Void)? { didSet { registerForDraggedTypes([.fileURL]) } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }; onDrop?(urls); return true
    }
}

final class PlayerViewController: ThemedViewController {
    private var model: PlayerUIStateModel; private let actions: PlayerUIActions
    private weak var elapsedLabel: NSTextField?; private weak var titleLabel: NSTextField?; private weak var statusLabel: NSTextField?
    private weak var progressSlider: NSSlider?; private weak var volumeSlider: NSSlider?; private weak var playButton: NSButton?
    init(theme: PlayerUITheme, model: PlayerUIStateModel, actions: PlayerUIActions) { self.model = model; self.actions = actions; super.init(theme: theme) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        super.loadView()
        let model = self.model; let actions = self.actions
        (view as? AudioDropView)?.onDrop = { actions.receiveFiles($0, model.rows.isEmpty) }
        let display = NSView(); display.wantsLayer = true; display.layer?.backgroundColor = theme.panel.cgColor; display.layer?.cornerRadius = 4
        let time = label(Self.clock(model.playback.position), size: 24, bold: true); time.font = .monospacedDigitSystemFont(ofSize: scaled(24), weight: .bold)
        time.setAccessibilityLabel("Elapsed time"); time.setAccessibilityValue(Self.clock(model.playback.position))
        let title = label("\(model.artist) — \(model.title)", size: 12, bold: true); title.font = theme.trackFont; title.setAccessibilityLabel("Now playing, \(model.title) by \(model.artist)")
        let detail = [model.statusText, model.technicalText].compactMap { $0 }.joined(separator: " · ")
        let format = label(detail, size: 10, color: model.playback.state.isFailure ? .systemRed : theme.secondaryText)
        let progress = CommandSlider(value: model.playback.position, minValue: 0, maxValue: max(model.playback.duration ?? 1, 1)) { [weak self, actions] slider in
            guard let duration = self?.model.playback.duration, duration > 0 else { return }; actions.send(.seek(to: slider.doubleValue / slider.maxValue * duration))
        }; scaleControl(progress); progress.isEnabled = model.playback.duration != nil; progress.setAccessibilityLabel("Playback position")
        let playImage = theme.images[model.playback.state.isPlaying ? .pause : .play]
        let controls = NSStackView(views: [button("◀◀", label: "Previous track", image: theme.images[.previous], action: { actions.send(.previous) }), button(model.playback.state.isPlaying ? "Ⅱ" : "▶︎", label: "Play or pause", image: playImage, action: { [weak self, actions] in if let command = self?.model.playPauseCommand { actions.send(command) } }), button("■", label: "Stop", image: theme.images[.stop], action: { actions.send(.stop) }), button("▶▶", label: "Next track", image: theme.images[.next], action: { actions.send(.next) })])
        playButton = controls.views[1] as? NSButton; elapsedLabel = time; titleLabel = title; statusLabel = format; progressSlider = progress
        controls.spacing = scaled(5); controls.distribution = .fillEqually
        controls.views.forEach { $0.widthAnchor.constraint(greaterThanOrEqualToConstant: scaled(34)).isActive = true; $0.heightAnchor.constraint(greaterThanOrEqualToConstant: scaled(28)).isActive = true }
        let volume = CommandSlider(value: model.playback.volume, minValue: 0, maxValue: 1) { [weak self, actions] in if let command = self?.model.volumeCommand($0.doubleValue) { actions.send(command) } }; scaleControl(volume); volume.setAccessibilityLabel("Volume")
        volumeSlider = volume
        let volumeRow = NSStackView(views: [label("VOL", size: 9, bold: true, color: theme.secondaryText), volume]); volumeRow.spacing = scaled(7)
        let utilities = NSStackView(views: [button("OPEN", label: "Open audio", action: { actions.importFiles(true) }), button("EQ", label: "Show equalizer", action: actions.showEqualizer), button("LIST", label: "Show playlist", action: actions.showPlaylist), button("▔", label: "Compact player", action: actions.compact)]); utilities.spacing = scaled(4)
        [display, time, title, format, progress, controls, volumeRow, utilities].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(display); [time, title, format].forEach(display.addSubview); [progress, controls, volumeRow, utilities].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            display.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(10)), display.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(10)), display.topAnchor.constraint(equalTo: view.topAnchor, constant: scaled(7)), display.heightAnchor.constraint(equalToConstant: scaled(48)),
            time.leadingAnchor.constraint(equalTo: display.leadingAnchor, constant: scaled(8)), time.centerYAnchor.constraint(equalTo: display.centerYAnchor), time.widthAnchor.constraint(equalToConstant: scaled(76)),
            title.leadingAnchor.constraint(equalTo: time.trailingAnchor, constant: scaled(8)), title.trailingAnchor.constraint(equalTo: display.trailingAnchor, constant: -scaled(8)), title.topAnchor.constraint(equalTo: display.topAnchor, constant: scaled(8)),
            format.leadingAnchor.constraint(equalTo: title.leadingAnchor), format.trailingAnchor.constraint(equalTo: title.trailingAnchor), format.topAnchor.constraint(equalTo: title.bottomAnchor, constant: scaled(3)),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(12)), progress.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(12)), progress.topAnchor.constraint(equalTo: display.bottomAnchor, constant: scaled(4)),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(10)), controls.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: scaled(3)), controls.heightAnchor.constraint(equalToConstant: scaled(29)),
            volumeRow.leadingAnchor.constraint(equalTo: controls.trailingAnchor, constant: scaled(10)), volumeRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(10)), volumeRow.centerYAnchor.constraint(equalTo: controls.centerYAnchor), volumeRow.widthAnchor.constraint(greaterThanOrEqualToConstant: scaled(112)),
            utilities.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(10)), utilities.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: scaled(2)), utilities.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -scaled(4)),
        ])
    }
    func update(_ model: PlayerUIStateModel) {
        self.model = model
        elapsedLabel?.stringValue = Self.clock(model.playback.position); elapsedLabel?.setAccessibilityValue(Self.clock(model.playback.position))
        titleLabel?.stringValue = "\(model.artist) — \(model.title)"; titleLabel?.setAccessibilityLabel("Now playing, \(model.title) by \(model.artist)")
        statusLabel?.stringValue = [model.statusText, model.technicalText].compactMap { $0 }.joined(separator: " · ")
        statusLabel?.textColor = model.playback.state.isFailure ? .systemRed : theme.secondaryText
        progressSlider?.maxValue = max(model.playback.duration ?? 1, 1); progressSlider?.doubleValue = model.playback.position; progressSlider?.isEnabled = model.playback.duration != nil
        volumeSlider?.doubleValue = model.playback.volume
        styleButtonTitle(playButton, title: model.playback.state.isPlaying ? "Ⅱ" : "▶︎")
        playButton?.image = theme.images[model.playback.state.isPlaying ? .pause : .play]
    }
    private static func clock(_ seconds: TimeInterval) -> String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

private extension PlaybackState {
    var isPlaying: Bool { if case .playing = self { true } else { false } }
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

final class CommandSlider: NSSlider {
    private let handler: (NSSlider) -> Void
    init(value: Double, minValue: Double, maxValue: Double, handler: @escaping (NSSlider) -> Void) {
        self.handler = handler; super.init(frame: .zero); self.minValue = minValue; self.maxValue = maxValue; self.doubleValue = value
        target = self; action = #selector(change)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func change() { handler(self) }
}

final class CommandSearchField: NSSearchField {
    private let handler: (String) -> Void
    init(value: String, handler: @escaping (String) -> Void) { self.handler = handler; super.init(frame: .zero); stringValue = value; target = self; action = #selector(change) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func change() { handler(stringValue) }
}

final class PlaylistTableView: NSTableView {
    var activateSelection: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { activateSelection?() } else { super.keyDown(with: event) }
    }
}

final class CompactPlayerViewController: ThemedViewController {
    private var model: PlayerUIStateModel; private let actions: PlayerUIActions
    private weak var playButton: NSButton?; private weak var titleLabel: NSTextField?; private weak var elapsedLabel: NSTextField?
    init(theme: PlayerUITheme, model: PlayerUIStateModel, actions: PlayerUIActions) { self.model = model; self.actions = actions; super.init(theme: theme) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        super.loadView()
        let model = self.model; let actions = self.actions
        (view as? AudioDropView)?.onDrop = { actions.receiveFiles($0, model.rows.isEmpty) }
        let play = button(model.playback.state.isPlaying ? "Ⅱ" : "▶︎", label: "Play or pause", image: theme.images[model.playback.state.isPlaying ? .pause : .play], action: { [weak self, actions] in if let command = self?.model.playPauseCommand { actions.send(command) } })
        let title = label("\(model.artist) — \(model.title)", size: 11, bold: true); title.setAccessibilityLabel("Now playing, \(model.title) by \(model.artist)")
        let time = label(String(format: "%02d:%02d", Int(model.playback.position) / 60, Int(model.playback.position) % 60), size: 11, bold: true); time.font = .monospacedDigitSystemFont(ofSize: scaled(11), weight: .semibold)
        playButton = play; titleLabel = title; elapsedLabel = time
        let expand = button("▁", label: "Expand player", action: actions.compact)
        let row = NSStackView(views: [play, title, time, expand]); row.spacing = scaled(7); row.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(row)
        play.widthAnchor.constraint(equalToConstant: scaled(32)).isActive = true; expand.widthAnchor.constraint(equalToConstant: scaled(32)).isActive = true
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(5)), row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(5)), row.topAnchor.constraint(equalTo: view.topAnchor, constant: scaled(4)), row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -scaled(4))])
    }
    func update(_ model: PlayerUIStateModel) {
        self.model = model
        styleButtonTitle(playButton, title: model.playback.state.isPlaying ? "Ⅱ" : "▶︎")
        playButton?.image = theme.images[model.playback.state.isPlaying ? .pause : .play]
        titleLabel?.stringValue = "\(model.artist) — \(model.title)"; titleLabel?.setAccessibilityLabel("Now playing, \(model.title) by \(model.artist)")
        elapsedLabel?.stringValue = String(format: "%02d:%02d", Int(model.playback.position) / 60, Int(model.playback.position) % 60)
    }
}

final class EqualizerViewController: ThemedViewController {
    private let model: PlayerUIStateModel; private let actions: PlayerUIActions
    init(theme: PlayerUITheme, model: PlayerUIStateModel, actions: PlayerUIActions) { self.model = model; self.actions = actions; super.init(theme: theme) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        super.loadView()
        let model = self.model; let actions = self.actions
        let heading = label("10-BAND EQUALIZER", size: 11, bold: true)
        let highestGain = model.playback.equalizer.bandGains.max() ?? 0
        let protectionActive = !model.playback.equalizer.isBypassed && model.playback.equalizer.preampGain + highestGain > 0
        let protection = label(protectionActive ? "LIMIT" : "SAFE", size: 9, bold: true, color: protectionActive ? .systemOrange : theme.secondaryText)
        protection.setAccessibilityLabel(protectionActive ? "Output protection may be reducing gain" : "Output protection ready")
        protection.toolTip = "A peak limiter protects the output when EQ boost could clip. Reduce preamp gain for more headroom."
        let bypass = ActionButton(title: "Bypass", action: { [model, actions] in actions.send(model.toggleBypassCommand) }); scaleControl(bypass); bypass.font = theme.controlFont; bypass.setButtonType(.switch); bypass.state = model.playback.equalizer.isBypassed ? .on : .off; bypass.setAccessibilityLabel("Bypass equalizer")
        let reset = button("RESET", label: "Reset equalizer", action: { [model, actions] in actions.send(model.resetEqualizerCommand) })
        let header = NSStackView(views: [heading, NSView(), protection, bypass, reset]); header.spacing = scaled(8)
        let frequencies = ["PRE", "31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        let sliders = NSStackView(); sliders.orientation = .horizontal; sliders.distribution = .fillEqually; sliders.spacing = scaled(3)
        for (index, frequency) in frequencies.enumerated() {
            let value = index == 0 ? model.playback.equalizer.preampGain : model.playback.equalizer.bandGains[index - 1]
            let slider = CommandSlider(value: value, minValue: -12, maxValue: 12) { [model, actions] slider in
                if index == 0 { actions.send(model.preampCommand(slider.doubleValue)) }
                else if let command = model.equalizerCommand(band: index - 1, gain: slider.doubleValue) { actions.send(command) }
            }; scaleControl(slider); slider.isVertical = true
            slider.setAccessibilityLabel(frequency == "PRE" ? "Preamp gain" : "\(frequency) hertz gain"); slider.setAccessibilityValue("\(value) decibels")
            let caption = label(frequency, size: 8, bold: frequency == "PRE", color: theme.secondaryText); caption.alignment = .center
            let column = NSStackView(views: [slider, caption]); column.orientation = .vertical; column.spacing = scaled(2); sliders.addArrangedSubview(column)
        }
        [header, sliders].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(10)), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(10)), header.topAnchor.constraint(equalTo: view.topAnchor, constant: scaled(8)), header.heightAnchor.constraint(equalToConstant: scaled(28)), sliders.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(8)), sliders.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(8)), sliders.topAnchor.constraint(equalTo: header.bottomAnchor, constant: scaled(2)), sliders.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -scaled(7))])
    }
}

final class PlaylistViewController: ThemedViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: PlayerUIStateModel; private let actions: PlayerUIActions
    private weak var tableView: NSTableView?
    private weak var searchField: NSSearchField?
    private var isRestoringSelection = false
    init(theme: PlayerUITheme, model: PlayerUIStateModel, actions: PlayerUIActions) { self.model = model; self.actions = actions; super.init(theme: theme) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        super.loadView()
        let model = self.model; let actions = self.actions
        (view as? AudioDropView)?.onDrop = { actions.receiveFiles($0, false) }
        let heading = label("PLAYLIST", size: 11, bold: true); let search = CommandSearchField(value: model.filterText, handler: actions.search); scaleControl(search); search.font = theme.controlFont; search.placeholderString = "Search"; search.setAccessibilityLabel("Search playlist"); search.isEnabled = !model.queue.entries.isEmpty; searchField = search
        let header = NSStackView(views: [heading, NSView(), search]); header.spacing = scaled(8)
        let table = PlaylistTableView(); table.headerView = nil; table.backgroundColor = theme.panel; table.rowHeight = scaled(28); table.delegate = self; table.dataSource = self; table.allowsMultipleSelection = false
        table.target = self; table.doubleAction = #selector(activateSelection); table.activateSelection = { [weak self] in self?.activateSelection() }; tableView = table
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track")); column.resizingMask = .autoresizingMask; table.addTableColumn(column); table.setAccessibilityLabel("Playlist tracks")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let add = button("+ ADD", label: "Add audio to playlist", action: { actions.importFiles(false) })
        let shuffle = button(model.queue.isShuffled ? "SHF✓" : "SHF", label: "Toggle shuffle", action: { actions.send(.setShuffle(!model.queue.isShuffled)) })
        let repeatButton = button("R:\(model.queue.repeatMode.rawValue.uppercased())", label: "Change repeat mode", action: { actions.send(.setRepeat(model.nextRepeatMode)) })
        let remove = button("−", label: "Remove selected tracks", action: { if let id = model.queue.selectedEntryID { actions.send(.remove([id])) } })
        let clear = button("CLR", label: "Clear playlist", action: { actions.send(.remove(model.queue.entries.map(\.id))) })
        let moveUp = button("↑", label: "Move selected track up", action: { if let id = model.queue.selectedEntryID, let index = model.queue.entries.firstIndex(where: { $0.id == id }), index > 0 { actions.send(.move(entries: [id], before: model.queue.entries[index - 1].id)) } })
        let moveDown = button("↓", label: "Move selected track down", action: { if let id = model.queue.selectedEntryID, let index = model.queue.entries.firstIndex(where: { $0.id == id }) { let before = index + 2 < model.queue.entries.count ? model.queue.entries[index + 2].id : nil; actions.send(.move(entries: [id], before: before)) } })
        let footer = NSStackView(views: [add, remove, clear, moveUp, moveDown, shuffle, repeatButton, NSView(), label("\(model.rows.count) TRACKS", size: 9, bold: true, color: theme.secondaryText)]); footer.spacing = scaled(4)
        [header, scroll, footer].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(10)), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(10)), header.topAnchor.constraint(equalTo: view.topAnchor, constant: scaled(8)), header.heightAnchor.constraint(equalToConstant: scaled(26)), search.widthAnchor.constraint(equalToConstant: scaled(150)), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(8)), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(8)), scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: scaled(5)), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -scaled(5)), footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(10)), footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(10)), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -scaled(7)), footer.heightAnchor.constraint(equalToConstant: scaled(28))])
        if let selected = model.rows.firstIndex(where: \.isSelected) { isRestoringSelection = true; table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false); isRestoringSelection = false }
        if model.rows.isEmpty {
            let empty = label("Drop audio here or choose + Add", size: 12, color: theme.secondaryText); empty.alignment = .center; empty.setAccessibilityLabel("Playlist is empty. Drop audio here or choose Add.")
            empty.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(empty)
            NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)])
        }
    }
    func focusSearch() { view.window?.makeFirstResponder(searchField) }
    func revealPlaying() {
        guard let row = model.rows.firstIndex(where: \.isPlaying) else { return }
        tableView?.scrollRowToVisible(row)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { model.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = model.rows[row]; let marker = item.isPlaying ? "▶" : (item.isUnavailable ? "!" : " ")
        let subtitle = item.detail.map { " — \($0)" } ?? ""
        let cell = NSTableCellView(); let text = label("\(marker)  \(String(format: "%02d", row + 1))  \(item.title)\(subtitle)", size: 11, bold: item.isPlaying, color: item.isUnavailable ? .systemRed : (item.isPlaying ? theme.accent : theme.text))
        text.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(text); cell.textField = text
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: scaled(6)), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -scaled(6)), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        let states = [item.isPlaying ? "Playing" : nil, item.isSelected ? "Selected" : nil, item.isUnavailable ? "Unavailable" : nil].compactMap { $0 }.joined(separator: ", ")
        text.setAccessibilityLabel(states.isEmpty ? item.title : "\(states), \(item.title)"); return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isRestoringSelection, let table = notification.object as? NSTableView else { return }
        actions.send(.select(table.selectedRow >= 0 ? model.rows[table.selectedRow].id : nil))
    }
    @objc private func activateSelection() {
        guard let row = tableView?.selectedRow, row >= 0, model.rows.indices.contains(row) else { return }
        actions.send(.select(model.rows[row].id)); actions.send(.play)
    }
}
