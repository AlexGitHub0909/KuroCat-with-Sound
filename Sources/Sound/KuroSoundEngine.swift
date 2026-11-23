import Foundation
import AVFAudio
import AudioToolbox
import AppKit

// MARK: - Sound category (ported from KeyFoley)
enum SoundCategory: String, CaseIterable, Hashable {
    case standard
    case space
    case enter
    case delete
    case escape
    case arrow
    case modifier
}

// MARK: - Theme model (simplified from KeyFoley SoundTheme)
private struct SoundThemeManifest: Decodable {
    let schemaVersion: Int
    let id: String
    let displayName: String
    let categories: [String: [String]]
}

private struct SoundTheme {
    let id: String
    let displayName: String
    let sampleURLs: [SoundCategory: [URL]]
}

// MARK: - Peak limiter (ported from KeyFoley)
private enum SoundPeakLimiter {
    static func makeNode() -> AVAudioUnitEffect {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.024, 0)
        return limiter
    }

    static func setPreGain(_ db: Float, on limiter: AVAudioUnitEffect) {
        limiter.bypass = db <= 0
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, db, 0)
    }
}

// MARK: - Settings persistence
private enum SoundPrefs {
    static let enabledKey = "kurocat.sound.enabled"
    static let themeKey = "kurocat.sound.theme"
    static let volumeKey = "kurocat.sound.volume"
    static let defaults = UserDefaults.standard

    static var enabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }
    static var themeID: String {
        get { defaults.string(forKey: themeKey) ?? "scissor" }
        set { defaults.set(newValue, forKey: themeKey) }
    }
    static var volume: Double {
        get { defaults.object(forKey: volumeKey) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: volumeKey) }
    }
}

// MARK: - KuroSoundEngine
/// Self-contained keyboard sound engine for KuroCat, ported from KeyFoley.
/// Plays preloaded samples on key-down with a round-robin player pool and peak limiter.
final class KuroSoundEngine {
    static let shared = KuroSoundEngine()

    private let engine = AVAudioEngine()
    private let playerNodes: [AVAudioPlayerNode]
    private let limiter: AVAudioUnitEffect
    private var buffers: [SoundCategory: [AVAudioPCMBuffer]] = [:]
    private var nextPlayerIndex = 0
    private var isRunning = false

    private(set) var themes: [(id: String, name: String)] = []
    private(set) var currentThemeName = ""
    private(set) var loadError: String?

    var enabled: Bool {
        get { SoundPrefs.enabled }
        set {
            SoundPrefs.enabled = newValue
            if newValue { start() } else { stop() }
        }
    }
    var volume: Double {
        get { SoundPrefs.volume }
        set { SoundPrefs.volume = min(max(newValue, 0), 4); applyVolume() }
    }
    var themeID: String {
        get { SoundPrefs.themeID }
        set { SoundPrefs.themeID = newValue; loadTheme(id: newValue); if enabled { start() } }
    }

    private init() {
        playerNodes = (0..<12).map { _ in AVAudioPlayerNode() }
        limiter = SoundPeakLimiter.makeNode()
        for node in playerNodes { engine.attach(node) }
        engine.attach(limiter)
        applyVolume()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    func setup() {
        discoverThemes()
        loadTheme(id: themeID)
        if enabled { start() }
    }

    // MARK: Theme discovery
    private func discoverThemes() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("SoundThemes") else {
            loadError = "找不到音效资源目录"
            return
        }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("catalog.json")),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            loadError = "无法读取音效主题目录"
            return
        }
        var found: [(String, String)] = []
        for dir in catalog.themeDirectories {
            guard let mData = try? Data(contentsOf: root.appendingPathComponent(dir).appendingPathComponent("theme.json")),
                  let m = try? JSONDecoder().decode(SoundThemeManifest.self, from: mData) else { continue }
            found.append((m.id, m.displayName))
        }
        themes = found
    }

    private struct Catalog: Decodable {
        let defaultThemeID: String
        let themeDirectories: [String]
    }

    private func loadTheme(id: String) {
        stop()
        buffers = [:]
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("SoundThemes"),
              let mData = try? Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("theme.json")),
              let manifest = try? JSONDecoder().decode(SoundThemeManifest.self, from: mData) else {
            loadError = "找不到音效主题：\(id)"
            return
        }

        let themeDir = root.appendingPathComponent(id)
        var loaded: [SoundCategory: [AVAudioPCMBuffer]] = [:]
        var format: AVAudioFormat?

        for (catName, paths) in manifest.categories {
            guard let cat = SoundCategory(rawValue: catName) else { continue }
            var arr: [AVAudioPCMBuffer] = []
            for path in paths {
                guard let file = try? AVAudioFile(forReading: themeDir.appendingPathComponent(path)),
                      let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
                try? file.read(into: buf)
                arr.append(buf)
                if format == nil { format = file.processingFormat }
            }
            if !arr.isEmpty { loaded[cat] = arr }
        }

        guard let fmt = format, loaded[.standard] != nil else {
            loadError = "音效主题没有可播放样本"
            return
        }
        configureGraph(format: fmt)
        buffers = loaded
        currentThemeName = manifest.displayName
        loadError = nil
    }

    private func configureGraph(format: AVAudioFormat) {
        for node in playerNodes {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.disconnectNodeOutput(limiter)
        engine.connect(engine.mainMixerNode, to: limiter, format: nil)
        engine.connect(limiter, to: engine.outputNode, format: nil)
    }

    // MARK: Lifecycle
    func start() {
        guard enabled, !buffers.isEmpty else { return }
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        isRunning = engine.isRunning
        applyVolume()
    }

    func stop() {
        for node in playerNodes { node.stop() }
        engine.stop()
        isRunning = false
    }

    private func applyVolume() {
        let v = Float(volume)
        engine.mainMixerNode.outputVolume = min(max(v, 0), 1)
        let db: Float = v > 1 ? 20 * log10(v) : 0
        SoundPeakLimiter.setPreGain(db, on: limiter)
    }

    // MARK: Playback
    func play(category: SoundCategory) {
        guard enabled, isRunning, engine.isRunning else { return }
        let candidates = buffers[category] ?? buffers[.standard] ?? []
        guard let buffer = candidates.randomElement() else { return }
        let node = playerNodes[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % playerNodes.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: [])
        node.play()
    }

    /// Map KuroCat's PhysicalKey to a sound category.
    func category(for key: PhysicalKey) -> SoundCategory {
        switch key {
        case .space: return .space
        case .enter: return .enter
        case .backspace, .forwardDelete: return .delete
        case .escape: return .escape
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight: return .arrow
        case .leftShift, .rightShift, .leftControl, .rightControl,
             .leftOption, .rightOption, .leftCommand, .rightCommand,
             .capsLock, .fn: return .modifier
        default: return .standard
        }
    }

    @objc private func handleConfigChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled else { return }
            self.stop()
            self.start()
        }
    }
}
