import AVFoundation

/// The three-note chime the web app played when rest ran out, built in
/// memory so the app ships no sound files.
@MainActor
enum Chime {
    private static var player: AVAudioPlayer?
    private static let sound = makeSound()

    static func play() {
        // Ambient mixes with the person's music and respects the silent switch.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(true)
        player = try? AVAudioPlayer(data: sound, fileTypeHint: AVFileType.wav.rawValue)
        player?.play()
    }

    /// 880 Hz, 880 Hz, 1320 Hz, a quarter second apart, as 16-bit mono WAV.
    private static func makeSound() -> Data {
        let rate = 44_100
        let notes: [(start: Double, frequency: Double)] = [(0, 880), (0.25, 880), (0.5, 1320)]
        let noteLength = 0.25
        var samples = [Int16](repeating: 0, count: Int(0.75 * Double(rate)))

        for note in notes {
            let first = Int(note.start * Double(rate))
            for i in 0..<Int(noteLength * Double(rate)) where first + i < samples.count {
                let t = Double(i) / Double(rate)
                // Quick attack, then an exponential fade over 0.2 s.
                let gain = t < 0.02 ? 0.4 * t / 0.02 : 0.4 * pow(0.0001 / 0.4, min(1, (t - 0.02) / 0.2))
                let value = sin(2 * Double.pi * note.frequency * t) * gain
                samples[first + i] = Int16(max(-1, min(1, value)) * Double(Int16.max))
            }
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))          // fmt chunk size
        append(UInt16(1))           // PCM
        append(UInt16(1))           // mono
        append(UInt32(rate))
        append(UInt32(rate * 2))    // bytes per second
        append(UInt16(2))           // bytes per frame
        append(UInt16(16))          // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        for sample in samples {
            append(sample)
        }
        return data
    }
}
