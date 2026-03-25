import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - Track Item
struct TrackItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    var duration: Double

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrackItem, rhs: TrackItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sentence Segment
struct SentenceSegment: Identifiable {
    let id = UUID()
    let text: String
    let startTime: Double
    let endTime: Double
}

// MARK: - Audio Player Model
class AudioPlayerModel: NSObject, ObservableObject {

    // MARK: - Published
    @Published var audioURL: URL?
    @Published var trackName: String = ""
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var waveformData: [Float] = []

    // 플레이리스트
    @Published var playlist: [TrackItem] = []
    @Published var currentTrackIndex: Int = -1

    // 반복
    @Published var loopSectionEnabled: Bool = false
    @Published var loopAllEnabled: Bool = false
    @Published var loopStart: Double = 0
    @Published var loopEnd: Double = 10
    @Published var loopCount: Int = 3

    // 스크립트
    @Published var sentences: [SentenceSegment] = []
    @Published var isAnalyzing: Bool = false

    // MARK: - Private
    private var player: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var recordingPlayers: [AVAudioPlayer] = []
    private var recordingURLs: [URL] = []
    private var timer: Timer?
    private var currentLoopRepeat: Int = 0

    // MARK: - Playlist 관리
    func addTrack(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: tempURL)

        var duration = 0.0
        if let p = try? AVAudioPlayer(contentsOf: tempURL) {
            duration = p.duration
        }

        let track = TrackItem(url: tempURL, name: url.lastPathComponent, duration: duration)
        DispatchQueue.main.async {
            self.playlist.append(track)
        }
    }

    func removeTrack(at index: Int) {
        guard index < playlist.count else { return }
        playlist.remove(at: index)

        if currentTrackIndex == index {
            stopPlayback()
            if !playlist.isEmpty {
                let newIndex = min(index, playlist.count - 1)
                playTrack(at: newIndex)
            } else {
                audioURL = nil
                currentTrackIndex = -1
            }
        } else if currentTrackIndex > index {
            currentTrackIndex -= 1
        }
    }

    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        currentTrackIndex = index
        loadAudio(url: playlist[index].url)
        togglePlay()
    }

    private func stopPlayback() {
        player?.stop()
        stopTimer()
        isPlaying = false
        currentTime = 0
    }

    // MARK: - 다음 트랙으로
    func playNextTrack() {
        guard !playlist.isEmpty else { return }
        
        let nextIndex = currentTrackIndex + 1
        
        if nextIndex < playlist.count {
            // 다음 파일이 있으면 재생
            playTrack(at: nextIndex)
        } else if loopAllEnabled {
            // 마지막 파일인데 전체 반복이 켜져 있으면 다시 첫 번째 파일로
            playTrack(at: 0)
        } else {
            // 반복 안 켜져 있으면 정지
            stopPlayback()
        }
    }

    // MARK: - Load Audio
    func loadAudio(url: URL) {
        stopPlayback()
        sentences = []

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.enableRate = true
            player?.rate = playbackRate

            audioURL = url
            trackName = url.lastPathComponent
            duration = player?.duration ?? 0
            loopEnd = min(10, duration)
            currentTime = 0

            generateWaveform(url: url)
            analyzeAudio(url: url)
        } catch {
            print("오디오 로드 실패: \(error)")
        }
    }

    // MARK: - Playback
    func togglePlay() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            player.play()
            startTimer()
            isPlaying = true
        }
    }

    func seek(to time: Double) {
        let clamped = max(0, min(duration, time))
        player?.currentTime = clamped
        currentTime = clamped
    }

    func updatePlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    // MARK: - Timer
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            self.currentTime = player.currentTime

            // 1. 구간 반복(Loop Section)이 켜져 있을 때
            if self.loopSectionEnabled {
                if player.currentTime >= self.loopEnd {
                    self.currentLoopRepeat += 1
                    
                    if self.currentLoopRepeat < self.loopCount {
                        // 아직 지정된 횟수만큼 반복 전이면 다시 시작점으로
                        self.seek(to: self.loopStart)
                    } else {
                        // 반복 횟수를 다 채웠다면?
                        self.currentLoopRepeat = 0
                        
                        if self.loopAllEnabled {
                            // 전체 반복이 켜져 있으면 다음 트랙으로 넘기거나 처음부터 재생
                            self.playNextTrack()
                        } else {
                            // 꺼져 있으면 여기서 정지
                            player.pause()
                            self.isPlaying = false
                            self.stopTimer()
                        }
                    }
                }
            }
            // 2. 구간 반복은 꺼져 있고 전체 반복(Loop All)만 켜져 있을 때
            else if self.loopAllEnabled {
                if player.currentTime >= self.duration - 0.1 {
                    self.playNextTrack()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Waveform
    private func generateWaveform(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let frameCount = AVAudioFrameCount(file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
                try file.read(into: buffer)
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                let samplesPerBar = max(1, frameLength / 60)
                var bars: [Float] = []
                for i in 0..<60 {
                    let start = i * samplesPerBar
                    let end = min(start + samplesPerBar, frameLength)
                    var sum: Float = 0
                    for j in start..<end { sum += abs(channelData[j]) }
                    bars.append(sum / Float(end - start))
                }
                let maxVal = bars.max() ?? 1.0
                let normalized = maxVal > 0 ? bars.map { $0 / maxVal } : bars
                DispatchQueue.main.async { self.waveformData = normalized }
            } catch {
                DispatchQueue.main.async {
                    self.waveformData = (0..<60).map { _ in Float.random(in: 0.2...1.0) }
                }
            }
        }
    }

    // MARK: - Speech Analysis
    func analyzeAudio(url: URL) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self = self else { return }
            DispatchQueue.main.async { self.isAnalyzing = true }

            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self, let result = result, result.isFinal else { return }

                var segments: [SentenceSegment] = []
                var sentenceStart: Double = 0
                var sentenceWords: [String] = []

                for segment in result.bestTranscription.segments {
                    sentenceWords.append(segment.substring)
                    let isPunctuation = segment.substring.hasSuffix(".") ||
                                       segment.substring.hasSuffix("?") ||
                                       segment.substring.hasSuffix("!")
                    if isPunctuation || segment === result.bestTranscription.segments.last {
                        let endTime = segment.timestamp + segment.duration
                        segments.append(SentenceSegment(
                            text: sentenceWords.joined(separator: " "),
                            startTime: sentenceStart,
                            endTime: endTime + 0.3
                        ))
                        sentenceStart = endTime
                        sentenceWords = []
                    }
                }

                DispatchQueue.main.async {
                    self.sentences = segments
                    self.isAnalyzing = false
                }
            }
        }
    }

    // MARK: - Recording
    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            guard granted, let self = self else { return }
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
                try session.setActive(true)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("rec_\(Date().timeIntervalSince1970).m4a")
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                self.recorder = try AVAudioRecorder(url: url, settings: settings)
                self.recorder?.record()
                self.recordingURLs.append(url)
            } catch {
                print("녹음 실패: \(error)")
            }
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    func playRecording(index: Int) {
        guard index < recordingURLs.count else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: recordingURLs[index])
            p.play()
            if recordingPlayers.count > index {
                recordingPlayers[index] = p
            } else {
                recordingPlayers.append(p)
            }
        } catch {
            print("녹음 재생 실패: \(error)")
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlayerModel: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stopTimer()
            self.isPlaying = false
            self.currentTime = 0
            // 다음 트랙 자동 재생
            self.playNextTrack()
        }
    }
}

