import AVFoundation
import Combine
import PineappleCore

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var errorMessage: String?
    override init() { super.init(); synthesizer.delegate = self }
    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.caseInsensitiveCompare("en-GB") == .orderedSame }
    }
    var isAvailable: Bool { !availableVoices.isEmpty || AVSpeechSynthesisVoice(language: "en-GB") != nil }
    func resolvedVoice(gender: VoiceGender) -> AVSpeechSynthesisVoice? {
        let preferred: AVSpeechSynthesisVoiceGender = gender == .female ? .female : .male
        let voices = availableVoices.sorted { $0.quality.rawValue > $1.quality.rawValue }
        return voices.first { $0.gender == preferred } ?? voices.first ?? AVSpeechSynthesisVoice(language: "en-GB")
    }
    func description(gender: VoiceGender) -> String {
        guard let voice = resolvedVoice(gender: gender) else { return "未安装英式英语语音" }
        let preferred: AVSpeechSynthesisVoiceGender = gender == .female ? .female : .male
        return voice.gender == preferred ? "\(voice.name) · en-GB" : "\(voice.name) · en-GB（当前可用声音）"
    }
    func speak(_ text: String, gender: VoiceGender) {
        guard !text.isEmpty else { return }
        guard let voice = resolvedVoice(gender: gender) else {
            errorMessage = "设备没有可用的 en-GB 语音。请在系统设置的辅助功能中下载英语（英国）朗读声音。"; return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            synthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.86
            synthesizer.speak(utterance)
        } catch { errorMessage = "暂时无法播放发音：\(error.localizedDescription)" }
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard self?.synthesizer.isSpeaking == false else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
