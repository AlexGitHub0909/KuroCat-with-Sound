import Foundation
import CoreAudio
import AppKit

/// Real-time system-audio pulse via Core Audio Process Taps (macOS 14.2+).
///
/// No ScreenCaptureKit and no screen-recording permission are used. A private
/// global tap is attached to a private aggregate device and read from an IOProc.
/// All audio is analysed in memory only — nothing is stored or transmitted.
final class MusicPulse: NSObject {
    static let shared = MusicPulse()

    // MARK: - Public state (read from the 60 fps render loop)
    private(set) var level: CGFloat = 0       // smoothed overall loudness
    private(set) var bass: CGFloat = 0        // smoothed low-frequency energy
    private(set) var beat: CGFloat = 0        // transient beat envelope 0...1
    private(set) var isPlaying = false
    private(set) var lastError: String?
    /// Live 6-band spectrum, normalized 0...1 — drives the little microphone bars.
    private(set) var bands: [CGFloat] = Array(repeating: 0, count: PulseMetrics.bandCount)
    /// Slow-falling peak markers, one per band — gives the bars a visible bounce.
    private(set) var bandPeaks: [CGFloat] = Array(repeating: 0, count: PulseMetrics.bandCount)

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "KuroCat.MusicMode") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "KuroCat.MusicMode")
            if newValue { start() } else { stop() }
        }
    }

    // MARK: - Capture resources
    private let captureQueue = DispatchQueue(label: "com.chanke.kurocat.music.capture", qos: .userInitiated)
    private let metrics = PulseMetrics()

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var procID: AudioDeviceIOProcID?
    private var pollTimer: DispatchSourceTimer?
    private var starting = false

    // MARK: - DSP state (main thread)
    private var smoothedLevel: Float = 0
    private var smoothedBass: Float = 0
    private var runningBassAverage: Float = 0
    private var lastLoudTime: CFTimeInterval = 0
    private var lastBeatTime: CFTimeInterval = 0
    private var beatEnvelope: CGFloat = 0
    private var lastCallbackCount: UInt64 = 0
    private var startCheckTime: CFTimeInterval = 0

    private override init() { super.init() }

    func setup() {
        if enabled { start() }
    }

    /// Opens the narrow "System Audio Recording Only" privacy pane (not screen recording).
    static func openSystemAudioSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { break }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard tapID == kAudioObjectUnknown, !starting else { return }
        starting = true
        lastError = nil
        captureQueue.async { [weak self] in
            guard let self else { return }
            if #available(macOS 14.2, *) {
                self.buildCaptureChain()
            } else {
                self.fail("音乐律动需要 macOS 14.2 或更高版本")
            }
            self.starting = false
        }
    }

    @available(macOS 14.2, *)
    private func buildCaptureChain() {
        // Translate our PID to a Core Audio process object so our own key clicks
        // are excluded from the tap (no feedback loop into the sound engine).
        var selfProcess = AudioObjectID(kAudioObjectUnknown)
        var translateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        var pidSize = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = withUnsafeMutablePointer(to: &pid) { p in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &translateAddr,
                                       UInt32(MemoryLayout<pid_t>.size), p, &pidSize, &selfProcess)
        }
        let excluded: [AudioObjectID] = selfProcess == kAudioObjectUnknown ? [] : [selfProcess]

        // The empty CATapDescription() initializer silently yields tapID = 0.
        // The global-mixdown initializer configures isMixdown/isExclusive correctly.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        desc.name = "KuroCat Pulse"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            fail("无法创建系统音频分接 (status \(tapStatus))")
            return
        }

        var tapUID: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { p in
            AudioObjectGetPropertyData(newTapID, &uidAddr, 0, nil, &uidSize, p)
        }
        guard uidStatus == noErr else {
            _ = AudioHardwareDestroyProcessTap(newTapID)
            fail("无法读取音频分接标识 (status \(uidStatus))")
            return
        }

        let subTap: [String: Any] = [
            kAudioSubTapUIDKey as String: tapUID,
            kAudioSubTapDriftCompensationKey as String: true
        ]
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "KuroCat Pulse Capture",
            kAudioAggregateDeviceUIDKey as String: "com.chanke.kurocat.pulse.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceSubDeviceListKey as String: [],
            kAudioAggregateDeviceTapListKey as String: [subTap]
        ]
        var newDeviceID = AudioDeviceID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &newDeviceID)
        guard aggStatus == noErr, newDeviceID != kAudioObjectUnknown else {
            _ = AudioHardwareDestroyProcessTap(newTapID)
            fail("无法创建音频采集设备 (status \(aggStatus))")
            return
        }

        let m = metrics
        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, newDeviceID, nil) {
            _, inputData, _, _, _ in
            // Real-time thread: numeric work only, no allocation and no ARC traffic.
            let list = inputData
            let count = Int(list.pointee.mNumberBuffers)
            guard count > 0 else { return }
            var header = list.pointee
            let buffers = withUnsafePointer(to: &header.mBuffers) { p in
                p.withMemoryRebound(to: AudioBuffer.self, capacity: count) {
                    UnsafeBufferPointer(start: $0, count: count)
                }
            }
            var sumSquares: Float = 0
            var bassSquares: Float = 0
            var frames = 0
            for i in 0..<PulseMetrics.bandCount { m.bandEnergy[i] = 0 }

            for b in buffers {
                guard let data = b.mData else { continue }
                let n = Int(b.mDataByteSize) / MemoryLayout<Float32>.size
                let samples = data.assumingMemoryBound(to: Float32.self)
                for i in 0..<n {
                    let x = samples[i]
                    sumSquares += x * x
                    m.lowPass += 0.045 * (x - m.lowPass)
                    bassSquares += m.lowPass * m.lowPass

                    // Cascaded one-pole low-passes; differences between adjacent
                    // stages approximate a 6-band spectrum without any allocation.
                    var prev: Float = 0
                    for k in 0..<PulseMetrics.bandCount {
                        m.lowpasses[k] += PulseMetrics.bandAlphas[k] * (x - m.lowpasses[k])
                        let e = m.lowpasses[k] - prev
                        m.bandEnergy[k] += e * e
                        prev = m.lowpasses[k]
                    }
                }
                frames += n
            }
            if frames > 0 {
                m.rms = sqrt(sumSquares / Float(frames))
                m.bass = sqrt(bassSquares / Float(frames))
                for k in 0..<PulseMetrics.bandCount {
                    m.bandEnergy[k] = sqrt(m.bandEnergy[k] / Float(frames))
                }
            }
            m.callbacks &+= 1
        }
        guard procStatus == noErr, newProcID != nil else {
            AudioHardwareDestroyAggregateDevice(newDeviceID)
            _ = AudioHardwareDestroyProcessTap(newTapID)
            fail("无法注册音频回调 (status \(procStatus))")
            return
        }

        let startStatus = AudioDeviceStart(newDeviceID, newProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(newDeviceID, newProcID!)
            AudioHardwareDestroyAggregateDevice(newDeviceID)
            _ = AudioHardwareDestroyProcessTap(newTapID)
            fail("无法开始采集系统音频 (status \(startStatus))。请允许「系统音频录制」权限。")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // If a previous teardown completed late, release it before adopting new IDs.
            self.tapID = newTapID
            self.deviceID = newDeviceID
            self.procID = newProcID
            self.lastError = nil
            self.startCheckTime = CACurrentMediaTime()
            self.startPolling()
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = message
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.stopPollingOnMain()
            let device = self.deviceID
            let tap = self.tapID
            if device != kAudioObjectUnknown, let proc = self.procID {
                AudioDeviceStop(device, proc)
                AudioDeviceDestroyIOProcID(device, proc)
            }
            if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
            if #available(macOS 14.2, *) {
                if tap != kAudioObjectUnknown { _ = AudioHardwareDestroyProcessTap(tap) }
            }
            self.procID = nil
            self.deviceID = kAudioObjectUnknown
            self.tapID = kAudioObjectUnknown

            DispatchQueue.main.async {
                self.level = 0
                self.bass = 0
                self.beat = 0
                self.isPlaying = false
                self.smoothedLevel = 0
                self.smoothedBass = 0
                self.runningBassAverage = 0
                self.beatEnvelope = 0
                self.lastLoudTime = 0
                self.lastCallbackCount = 0
                self.metrics.rms = 0
                self.metrics.bass = 0
                self.bands = Array(repeating: 0, count: PulseMetrics.bandCount)
                self.bandPeaks = Array(repeating: 0, count: PulseMetrics.bandCount)
                for k in 0..<PulseMetrics.bandCount { self.metrics.bandEnergy[k] = 0 }
            }
        }
    }

    // MARK: - Polling / DSP

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func stopPollingOnMain() {
        DispatchQueue.main.sync { [weak self] in self?.stopPolling() }
    }

    private func poll() {
        let now = CACurrentMediaTime()
        let rms = metrics.rms
        let low = metrics.bass
        let callbacks = metrics.callbacks

        // Permission can be granted silently; detect a tap that never delivers.
        if callbacks == 0, now - startCheckTime > 3.0, lastError == nil {
            lastError = "未收到系统音频，请允许「系统音频录制」权限"
        }

        let fresh = callbacks != lastCallbackCount
        lastCallbackCount = callbacks

        if rms > 0.004 { lastLoudTime = now }
        let playing = fresh && (now - lastLoudTime) < 1.2

        if playing {
            let target = min(Float(1), rms * 3.4)
            smoothedLevel += (target - smoothedLevel) * (target > smoothedLevel ? 0.35 : 0.06)

            let bassTarget = min(Float(1), low * 5.5)
            smoothedBass += (bassTarget - smoothedBass) * (bassTarget > smoothedBass ? 0.40 : 0.07)
            runningBassAverage += (low - runningBassAverage) * 0.015

            if low > runningBassAverage * 1.45 && low > 0.012 && now - lastBeatTime > 0.20 {
                beatEnvelope = 1
                lastBeatTime = now
            }
            if lastError != nil { lastError = nil }
        } else {
            smoothedLevel += (0 - smoothedLevel) * 0.08
            smoothedBass += (0 - smoothedBass) * 0.08
        }
        beatEnvelope *= 0.82

        level = playing ? CGFloat(smoothedLevel) : 0
        bass = playing ? CGFloat(smoothedBass) : 0
        beat = playing ? beatEnvelope : 0
        isPlaying = playing

        // Snappy attack with a quick but not instant release, so bars visibly dance.
        for k in 0..<PulseMetrics.bandCount {
            let g = PulseMetrics.bandGains[k]
            let target = playing ? min(CGFloat(1), CGFloat(metrics.bandEnergy[k]) * g) : 0
            let rate: CGFloat = target > bands[k] ? 0.85 : 0.26
            bands[k] += (target - bands[k]) * rate
            // Peak marker jumps up with the band, then eases back down.
            if bands[k] >= bandPeaks[k] {
                bandPeaks[k] = bands[k]
            } else {
                bandPeaks[k] = max(bands[k], bandPeaks[k] - 0.055)
            }
        }
    }
}

/// Numeric scratch shared with the Core Audio real-time callback.
private final class PulseMetrics {
    static let bandCount = 6

    /// Cutoff coefficients from deep bass upward. Cascaded low-pass differences
    /// give six cheap, allocation-free frequency bands.
    static let bandAlphas: [Float] = [0.012, 0.028, 0.065, 0.14, 0.30, 0.62]
    /// Higher bands carry less energy, so they need more gain to read visually.
    static let bandGains: [CGFloat] = [3.2, 3.6, 4.4, 5.4, 6.8, 8.5]

    var rms: Float = 0
    var bass: Float = 0
    var lowPass: Float = 0
    var callbacks: UInt64 = 0

    var bandEnergy = [Float](repeating: 0, count: bandCount)
    var lowpasses = [Float](repeating: 0, count: bandCount)
}
