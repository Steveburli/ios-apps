import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Speaks stories aloud, or plays a recorded clip when the stop has one. It ducks music
/// and podcasts while talking, then hands the audio back.
@MainActor
@Observable
final class Narrator: NSObject {
    enum State: Equatable { case idle, speaking, paused }

    private(set) var state: State = .idle
    /// What's on right now (or paused).
    private(set) var current: Narration?

    /// Words per minute feel: 0.4…0.6 of AVSpeechUtterance's range.
    var rate: Float = 0.5
    var voiceIdentifier: String?

    /// Called on the main actor when a narration ends on its own (not when stopped).
    var onFinish: ((Narration) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    /// The utterance or clip now playing, so a late callback from an old one is ignored.
    private var playingID: ObjectIdentifier?

    struct Narration: Equatable, Identifiable {
        let id = UUID()
        var stopID: String
        var title: String
        var script: String
        var audioFile: String?
        var isTeaser: Bool
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        setUpRemoteCommands()
    }

    /// Screenshots only: shows a story as paused without making a sound.
    func showForScreenshot(_ narration: Narration) {
        current = narration
        state = .paused
    }

    var isBusy: Bool { state != .idle }

    func play(_ narration: Narration) {
        stopAll(notify: false)
        current = narration
        activateSession()
        if let file = narration.audioFile, let url = Self.bundledAudio(file),
           let player = try? AVAudioPlayer(contentsOf: url) {
            self.player = player
            player.delegate = self
            playingID = ObjectIdentifier(player)
            player.play()
        } else {
            let utterance = AVSpeechUtterance(string: narration.script)
            utterance.rate = rate
            utterance.prefersAssistiveTechnologySettings = false
            utterance.postUtteranceDelay = 0.4
            if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            } else {
                utterance.voice = Self.bestDefaultVoice
            }
            playingID = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
        state = .speaking
        updateNowPlaying()
    }

    func togglePause() {
        switch state {
        case .speaking:
            if let player { player.pause() } else { synthesizer.pauseSpeaking(at: .word) }
            state = .paused
            updateNowPlaying()
        case .paused:
            if let player { player.play() } else { synthesizer.continueSpeaking() }
            state = .speaking
            updateNowPlaying()
        case .idle:
            break
        }
    }

    /// Stops without counting as finished.
    func stop() {
        stopAll(notify: false)
    }

    private func stopAll(notify: Bool) {
        let ending = current
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        current = nil
        playingID = nil
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateSession()
        if notify, let ending { onFinish?(ending) }
    }

    fileprivate func finishedNaturally(_ id: ObjectIdentifier) {
        guard id == playingID else { return }
        stopAll(notify: true)
    }

    // MARK: - Audio session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc nonisolated private func audioInterrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            if type == .began, self.state == .speaking { self.togglePause() }
        }
    }

    // MARK: - Lock Screen and car controls

    private func updateNowPlaying() {
        guard let current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: "Fishers Guide",
            MPNowPlayingInfoPropertyPlaybackRate: state == .speaking ? 1.0 : 0.0,
        ]
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.state != .idle else { return .noActionableNowPlayingItem }
            self.togglePause()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.state == .speaking else { return .commandFailed }
            self.togglePause()
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.state == .paused else { return .commandFailed }
            self.togglePause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.state != .idle else { return .commandFailed }
            self.onSkipRequest?()
            return .success
        }
    }

    /// The car's or headphones' "next" button: the model decides what comes after.
    var onSkipRequest: (() -> Void)?

    // MARK: - Voices

    static func bundledAudio(_ name: String) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext.isEmpty ? nil : ext)
    }

    /// The nicest installed US English voice: premium, then enhanced, then default.
    static var bestDefaultVoice: AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }
}

extension Narrator: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finishedNaturally(id) }
    }
}

extension Narrator: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finishedNaturally(id) }
    }
}
