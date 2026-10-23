import AVFoundation

/// The web app's two sounds, synthesized in memory: a rising chime when the
/// timer runs out, and Sleep groaning when bedtime gets pushed.
@MainActor
enum Sounds {
    private static var player: AVAudioPlayer?
    private static let rate = 44_100.0
    private static let chimeData = WAV.make(samples: makeChime(), rate: Int(rate))

    static func chime() {
        play(chimeData)
    }

    /// Longer and lower the further bedtime moved.
    static func groan(push: Double) {
        play(WAV.make(samples: makeGroan(severity: min(2, max(0.3, push / 60))), rate: Int(rate)))
    }

    private static func play(_ data: Data) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(true)
        player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        player?.play()
    }

    private static var alarmPlayer: AVAudioPlayer?

    /// The alarm, over and over, while the scanner waits. It plays even with
    /// the silent switch on, like the Clock app's alarms.
    static func startAlarm() {
        guard alarmPlayer == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)
        alarmPlayer = try? AVAudioPlayer(data: WAV.make(samples: makeAlarm(), rate: Int(rate)), fileTypeHint: AVFileType.wav.rawValue)
        alarmPlayer?.numberOfLoops = -1
        alarmPlayer?.volume = 1
        alarmPlayer?.play()
    }

    static func stopAlarm() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    /// Four quick beeps, alternating 880 and 1175 Hz, then a pause.
    private static func makeAlarm() -> [Float] {
        var samples = [Float](repeating: 0, count: Int(1.6 * rate))
        for beep in 0..<4 {
            let first = Int(Double(beep) * 0.22 * rate)
            let frequency = beep % 2 == 0 ? 880.0 : 1175.0
            for n in 0..<Int(0.15 * rate) where first + n < samples.count {
                let t = Double(n) / rate
                let edge = min(1, min(t, 0.15 - t) / 0.01)
                samples[first + n] = Float(sin(2 * Double.pi * frequency * t) * 0.6 * edge)
            }
        }
        return samples
    }

    /// 660, 880 and 1320 Hz, 0.17 s apart, each fading over half a second.
    private static func makeChime() -> [Float] {
        var samples = [Float](repeating: 0, count: Int(0.9 * rate))
        for (i, frequency) in [660.0, 880.0, 1320.0].enumerated() {
            let first = Int(Double(i) * 0.17 * rate)
            for n in 0..<Int(0.55 * rate) where first + n < samples.count {
                let t = Double(n) / rate
                let gain = t < 0.02 ? 0.16 * t / 0.02 : 0.16 * pow(0.0001 / 0.16, min(1, (t - 0.02) / 0.48))
                samples[first + n] += Float(sin(2 * Double.pi * frequency * t) * gain)
            }
        }
        return samples
    }

    /// A falling sawtooth with a wobble, through a low-pass filter.
    private static func makeGroan(severity: Double) -> [Float] {
        let length = 1 + 0.3 * severity
        let sweep = 0.5 + 0.25 * severity
        let fadeEnd = 0.7 + 0.3 * severity
        let alpha = 1 - exp(-2 * Double.pi * 700 / rate)
        var samples = [Float](repeating: 0, count: Int(length * rate))
        var phase = 0.0, filtered = 0.0
        for n in 0..<samples.count {
            let t = Double(n) / rate
            let base = 210 * pow(95.0 / 210.0, min(1, t / sweep))
            let frequency = base + 10 * sin(2 * Double.pi * 7 * t)
            phase += frequency / rate
            let saw = 2 * (phase - (phase + 0.5).rounded(.down))
            filtered += alpha * (saw - filtered)
            let gain: Double
            if t < 0.06 {
                gain = 0.0001 * pow(0.12 / 0.0001, t / 0.06)
            } else {
                gain = 0.12 * pow(0.0001 / 0.12, min(1, (t - 0.06) / (fadeEnd - 0.06)))
            }
            samples[n] = Float(filtered * gain)
        }
        return samples
    }
}

enum WAV {
    /// 16-bit mono PCM.
    static func make(samples: [Float], rate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
