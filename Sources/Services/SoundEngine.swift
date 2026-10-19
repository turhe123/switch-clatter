import AVFoundation
import AudioToolbox
import CoreAudio

/// The three synthesized switch characters.
enum SwitchProfile: String, CaseIterable, Identifiable {
    case linear, clicky, tactile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: return "Linear thock"
        case .clicky: return "Clicky"
        case .tactile: return "Soft tactile"
        }
    }
}

/// Groups keys that get their own sound.
enum KeyClass: CaseIterable {
    case regular, space, returnKey, delete, modifier

    static func from(_ event: KeyEventInfo) -> KeyClass {
        if event.isModifier { return .modifier }
        switch event.keyCode {
        case 49: return .space
        case 36, 76: return .returnKey
        case 51, 117: return .delete
        default: return .regular
        }
    }
}

/// Parameters for one synthesized keystroke: a decaying sine body, an overtone,
/// a filtered noise burst and an optional delayed second transient (click jacket / stabilizer rattle).
private struct Voice {
    var body: Double, bodyDecay: Double
    var overtone: Double, overtoneDecay: Double, overtoneLevel: Double
    var noiseLevel: Double, noiseDecay: Double, brightness: Double
    var echoDelay: Double, echoLevel: Double
    var gain: Double, duration: Double

    static func base(_ profile: SwitchProfile) -> Voice {
        switch profile {
        case .linear:
            return Voice(body: 150, bodyDecay: 0.030, overtone: 620, overtoneDecay: 0.010, overtoneLevel: 0.35,
                         noiseLevel: 0.35, noiseDecay: 0.006, brightness: 0.25,
                         echoDelay: 0, echoLevel: 0, gain: 0.85, duration: 0.12)
        case .clicky:
            return Voice(body: 1900, bodyDecay: 0.008, overtone: 220, overtoneDecay: 0.015, overtoneLevel: 0.45,
                         noiseLevel: 0.9, noiseDecay: 0.003, brightness: 0.9,
                         echoDelay: 0.007, echoLevel: 0.6, gain: 0.7, duration: 0.08)
        case .tactile:
            return Voice(body: 300, bodyDecay: 0.018, overtone: 1100, overtoneDecay: 0.006, overtoneLevel: 0.3,
                         noiseLevel: 0.25, noiseDecay: 0.005, brightness: 0.4,
                         echoDelay: 0, echoLevel: 0, gain: 0.6, duration: 0.09)
        }
    }

    func shaped(for keyClass: KeyClass, isDown: Bool, pitch: Double) -> Voice {
        var v = self
        switch keyClass {
        case .regular: break
        case .space:
            v.scale(freq: 0.7, decay: 1.6)
            v.echoDelay = 0.012; v.echoLevel = max(v.echoLevel, 0.3)
            v.gain *= 1.1; v.duration *= 1.5
        case .returnKey:
            v.scale(freq: 0.82, decay: 1.3)
            v.echoDelay = 0.010; v.echoLevel = max(v.echoLevel, 0.2)
            v.gain *= 1.05; v.duration *= 1.3
        case .delete:
            v.scale(freq: 0.92, decay: 1.15)
        case .modifier:
            v.scale(freq: 1.08, decay: 1.0)
            v.gain *= 0.8
        }
        if !isDown {
            v.scale(freq: 1.2, decay: 0.7)
            v.noiseLevel *= 0.6; v.echoLevel *= 0.3
            v.gain *= 0.45; v.duration *= 0.8
        }
        v.scale(freq: pitch, decay: 1 / pitch)
        return v
    }

    mutating func scale(freq: Double, decay: Double) {
        body *= freq; overtone *= freq
        bodyDecay *= decay; overtoneDecay *= decay; noiseDecay *= decay
    }
}

/// Generates PCM buffers for every profile/key class and plays them through a pool of
/// `AVAudioPlayerNode`s so rapid, overlapping keystrokes all sound.
final class SoundEngine {
    static let sampleRate: Double = 48_000
    private static let variantCount = 7
    private static let pitchSpread = 0.09
    private static let poolSize = 24

    private struct BankKey: Hashable { let keyClass: KeyClass; let isDown: Bool }

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let format: AVAudioFormat?
    private var players: [AVAudioPlayerNode] = []
    private var busyUntil: [UInt64] = []
    private var bank: [BankKey: [AVAudioPCMBuffer]] = [:]
    private var bankProfile: SwitchProfile?

    private(set) var lastError: String?
    var onStateChange: (() -> Void)?

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Output device changed: the engine has stopped, so bring it back up.
            self?.start()
        }
    }

    var isRunning: Bool { engine.isRunning }

    @discardableResult
    func start() -> Bool {
        guard let format else {
            lastError = "Could not create an audio format."
            onStateChange?()
            return false
        }
        if players.isEmpty {
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            for _ in 0..<Self.poolSize {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: mixer, format: format)
                players.append(player)
            }
        }
        busyUntil = Array(repeating: 0, count: players.count)
        requestSmallIOBuffer()
        engine.prepare()
        do {
            try engine.start()
            players.forEach { $0.play() }
            lastError = nil
        } catch {
            lastError = "Audio engine failed to start: \(error.localizedDescription)"
        }
        onStateChange?()
        return lastError == nil
    }

    /// Asks the output device for a 256-frame IO buffer to keep click latency low. Best-effort.
    private func requestSmallIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames: UInt32 = 256
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                             &frames, UInt32(MemoryLayout<UInt32>.size))
    }

    func prepare(_ profile: SwitchProfile) {
        guard bankProfile != profile, let format else { return }
        var newBank: [BankKey: [AVAudioPCMBuffer]] = [:]
        for keyClass in KeyClass.allCases {
            for isDown in [true, false] {
                newBank[BankKey(keyClass: keyClass, isDown: isDown)] = (0..<Self.variantCount).compactMap { i in
                    let offset = Double(i) / Double(Self.variantCount - 1) * 2 - 1
                    let voice = Voice.base(profile).shaped(for: keyClass, isDown: isDown,
                                                           pitch: 1 + offset * Self.pitchSpread)
                    return Self.render(voice, format: format)
                }
            }
        }
        bank = newBank
        bankProfile = profile
    }

    /// Plays one keystroke. `variance` (0…1) controls pitch randomization, `pan` is -1…1.
    func play(_ keyClass: KeyClass, isDown: Bool, profile: SwitchProfile,
              volume: Double, variance: Double, pan: Double) {
        prepare(profile)
        guard engine.isRunning, !players.isEmpty,
              let variants = bank[BankKey(keyClass: keyClass, isDown: isDown)], !variants.isEmpty else { return }

        let centre = Double(variants.count - 1) / 2
        let pick = centre + Double.random(in: -1...1) * min(max(variance, 0), 1) * centre
        let buffer = variants[min(max(Int(pick.rounded()), 0), variants.count - 1)]

        let now = DispatchTime.now().uptimeNanoseconds
        let index = busyUntil.firstIndex { $0 <= now }
            ?? busyUntil.indices.min { busyUntil[$0] < busyUntil[$1] } ?? 0
        let player = players[index]
        mixer.outputVolume = Float(min(max(volume, 0), 1))
        player.volume = Float.random(in: 0.85...1.0)
        player.pan = Float(min(max(pan, -1), 1))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        busyUntil[index] = now + UInt64(Double(buffer.frameLength) / Self.sampleRate * 1e9) + 5_000_000
    }

    private static func render(_ v: Voice, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let count = Int(v.duration * sampleRate)
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)

        let twoPi = 2 * Double.pi
        let fadeFrames = 0.004 * sampleRate
        let lpCoeff = 0.05 + 0.9 * v.brightness
        var lowpassed = 0.0
        var peak = 1e-9
        var samples = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            lowpassed += lpCoeff * (Double.random(in: -1...1) - lowpassed)
            var s = sin(twoPi * v.body * t) * exp(-t / v.bodyDecay) * min(1, t / 0.0004)
            s += v.overtoneLevel * sin(twoPi * v.overtone * t) * exp(-t / v.overtoneDecay)
            s += v.noiseLevel * lowpassed * exp(-t / v.noiseDecay)
            if v.echoLevel > 0, t >= v.echoDelay {
                let te = t - v.echoDelay
                s += v.echoLevel * lowpassed * exp(-te / 0.0025)
                s += v.echoLevel * 0.5 * sin(twoPi * v.body * 1.3 * te) * exp(-te / (v.bodyDecay * 0.6))
            }
            s *= min(1, Double(count - i) / fadeFrames)
            samples[i] = s
            peak = max(peak, abs(s))
        }
        let scale = v.gain / peak
        for i in 0..<count { out[i] = Float(samples[i] * scale) }
        return buffer
    }
}
