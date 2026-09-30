import AppKit
import Contracts
import Visualizations

final class VisualizationViewController: ThemedViewController {
    private let canvas = MetalVisualizationView()
    private var settings: VisualizationSettings
    private let settingsChanged: (VisualizationSettings) -> Void
    private let presets = BuiltInVisualizationCatalog.presets
    private weak var presetPopup: NSPopUpButton?
    private weak var favoriteButton: NSButton?
    private weak var lockButton: NSButton?
    private weak var cycleButton: NSButton?
    private weak var startMotionButton: NSButton?
    private var lastCycleAudioTime: Double?
    private var presetHistory: [String] = []

    init(theme: PlayerUITheme, settings: VisualizationSettings, settingsChanged: @escaping (VisualizationSettings) -> Void) {
        self.settings = settings; self.settingsChanged = settingsChanged
        super.init(theme: theme)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        super.loadView()
        let previous = button("◀", label: "Previous visualization", action: { [weak self] in self?.goBack() })
        let next = button("▶", label: "Next visualization", action: { [weak self] in self?.step(1) })
        let popup = NSPopUpButton(); popup.addItems(withTitles: presets.map(\.name)); popup.target = self; popup.action = #selector(selectPreset)
        stylePopUp(popup)
        popup.selectItem(at: presets.firstIndex(where: { $0.id == settings.presetID }) ?? 0); popup.setAccessibilityLabel("Visualization preset")
        let favorite = button(settings.favoritePresetIDs.contains(settings.presetID) ? "★" : "☆", label: "Favorite visualization", action: { [weak self] in self?.toggleFavorite() })
        let lock = button(settings.isLocked ? "LOCK" : "UNLOCK", label: "Lock visualization", action: { [weak self] in self?.toggleLock() })
        let cycle = button(settings.isCycling ? "CYCLE ON" : "CYCLE", label: "Automatically cycle visualizations", action: { [weak self] in self?.toggleCycle() })
        let fullScreen = button("⛶", label: "Enter full screen", action: { [weak self] in self?.view.window?.toggleFullScreen(nil) })
        let startMotion = button("START", label: "Start visualization animation for this session", action: { [weak self] in self?.enableMotion() })
        startMotion.isHidden = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || settings.reduceMotionSessionOverride
        let mini = NSPopUpButton(); mini.addItems(withTitles: ["Mini: Spectrum", "Mini: Scope", "Mini: Off"]); mini.selectItem(at: settings.miniMode == .spectrum ? 0 : settings.miniMode == .oscilloscope ? 1 : 2)
        stylePopUp(mini)
        mini.target = self; mini.action = #selector(selectMiniMode); mini.setAccessibilityLabel("Mini visualization mode")
        let filter = NSPopUpButton(); filter.addItems(withTitles: ["All Presets", "Favorites"]); filter.selectItem(at: settings.filter == .all ? 0 : 1)
        stylePopUp(filter); filter.target = self; filter.action = #selector(selectFilter); filter.setAccessibilityLabel("Preset filter")
        let toolbar = NSStackView(views: [previous, next, popup, favorite, lock, cycle, startMotion, fullScreen]); toolbar.spacing = scaled(6)
        let sensitivity = CommandSlider(value: settings.sensitivity, minValue: 0.25, maxValue: 4) { [weak self] slider in self?.setSensitivity(slider.doubleValue) }
        sensitivity.setAccessibilityLabel("Visualization sensitivity")
        let options = NSStackView(views: [mini, filter, label("SENSITIVITY", size: 9, bold: true, color: theme.secondaryText), sensitivity]); options.spacing = scaled(7)
        canvas.isAnimationSuppressed = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !settings.reduceMotionSessionOverride
        canvas.transitionDuration = canvas.isAnimationSuppressed ? 0 : settings.transitionSeconds; canvas.presetID = settings.presetID; canvas.sensitivity = Float(settings.sensitivity)
        [toolbar, options, canvas].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(10)), toolbar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -scaled(10)), toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: scaled(8)), toolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: scaled(28)),
            options.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(10)), options.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(10)), options.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: scaled(5)), options.heightAnchor.constraint(equalToConstant: scaled(24)), sensitivity.widthAnchor.constraint(greaterThanOrEqualToConstant: scaled(100)),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: scaled(8)), canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -scaled(8)), canvas.topAnchor.constraint(equalTo: options.bottomAnchor, constant: scaled(7)), canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -scaled(8)),
        ])
        presetPopup = popup; favoriteButton = favorite; lockButton = lock; cycleButton = cycle; startMotionButton = startMotion
        refreshPresetPopup()
        setKeyViewLoop([previous, next, popup, favorite, lock, cycle, startMotion, fullScreen, mini, filter, sensitivity])
    }

    func update(_ features: VisualizationFeatures?) {
        guard let features else { canvas.clearVisualization(); lastCycleAudioTime = nil; return }
        canvas.update(features: features)
        let audioTime = Double(features.sampleTime) / max(1, features.sampleRate)
        if let last = lastCycleAudioTime, audioTime < last { lastCycleAudioTime = audioTime }
        if lastCycleAudioTime == nil { lastCycleAudioTime = audioTime }
        if !canvas.isAnimationSuppressed, settings.isCycling, !settings.isLocked, audioTime - (lastCycleAudioTime ?? audioTime) >= settings.dwellSeconds {
            lastCycleAudioTime = audioTime; step(1)
        }
    }
    private var availablePresets: [VisualizationPresetDescriptor] {
        settings.filter == .favorites ? presets.filter { settings.favoritePresetIDs.contains($0.id) } : presets
    }
    private func applyPreset(_ id: String, recordingHistory: Bool = true) {
        guard presets.contains(where: { $0.id == id }), id != settings.presetID else { return }
        if recordingHistory { presetHistory.append(settings.presetID); if presetHistory.count > 50 { presetHistory.removeFirst() } }
        settings.presetID = id; canvas.presetID = id; refreshPresetPopup(); settingsChanged(settings)
    }
    private func step(_ amount: Int) {
        let choices = availablePresets; guard !choices.isEmpty else { return }
        let current = choices.firstIndex(where: { $0.id == settings.presetID }) ?? (amount > 0 ? -1 : 0)
        let normalized = (current + amount + choices.count) % choices.count
        applyPreset(choices[normalized].id)
    }
    private func goBack() { guard let id = presetHistory.popLast() else { return }; applyPreset(id, recordingHistory: false) }
    @objc private func selectPreset() {
        let choices = availablePresets; guard let index = presetPopup?.indexOfSelectedItem, choices.indices.contains(index) else { return }
        applyPreset(choices[index].id)
    }
    private func refreshPresetPopup() {
        guard let popup = presetPopup else { return }; let choices = availablePresets
        popup.removeAllItems(); popup.addItems(withTitles: choices.isEmpty ? ["No Favorites"] : choices.map(\.name))
        popup.isEnabled = !choices.isEmpty
        if let index = choices.firstIndex(where: { $0.id == settings.presetID }) { popup.selectItem(at: index) }
    }
    private func toggleFavorite() {
        if settings.favoritePresetIDs.contains(settings.presetID) { settings.favoritePresetIDs.remove(settings.presetID) } else { settings.favoritePresetIDs.insert(settings.presetID) }
        styleButtonTitle(favoriteButton, title: settings.favoritePresetIDs.contains(settings.presetID) ? "★" : "☆"); refreshPresetPopup(); settingsChanged(settings)
    }
    private func toggleLock() { settings.isLocked.toggle(); styleButtonTitle(lockButton, title: settings.isLocked ? "LOCK" : "UNLOCK"); settingsChanged(settings) }
    private func toggleCycle() { settings.isCycling.toggle(); lastCycleAudioTime = nil; styleButtonTitle(cycleButton, title: settings.isCycling ? "CYCLE ON" : "CYCLE"); settingsChanged(settings) }
    private func setSensitivity(_ value: Double) { settings.sensitivity = min(4, max(0.25, value)); canvas.sensitivity = Float(settings.sensitivity); settingsChanged(settings) }
    private func enableMotion() { settings.reduceMotionSessionOverride = true; canvas.isAnimationSuppressed = false; canvas.transitionDuration = settings.transitionSeconds; startMotionButton?.isHidden = true; settingsChanged(settings) }
    @objc private func selectMiniMode(_ sender: NSPopUpButton) {
        settings.miniMode = sender.indexOfSelectedItem == 0 ? .spectrum : sender.indexOfSelectedItem == 1 ? .oscilloscope : .off
        settingsChanged(settings)
    }
    @objc private func selectFilter(_ sender: NSPopUpButton) {
        settings.filter = sender.indexOfSelectedItem == 0 ? .all : .favorites
        refreshPresetPopup(); settingsChanged(settings)
    }
}
