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
@MainActor
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
    @Published var selectedTrackIndices: Set<Int> = []  // 꾹 눌러 선택한 트랙

    // 반복
    @Published var loopSectionEnabled: Bool = false
    @Published var loopAllEnabled: Bool = false  // 선택된 트랙 전체 반복
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
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Playlist 관리
    func addTrack(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: tempURL)

        var dur = 0.0
        if let p = try? AVAudioPlayer(contentsOf: tempURL) {
            dur = p.duration
        }

        let track = TrackItem(url: tempURL, name: url.lastPathComponent, duration: dur)
        playlist.append(track)
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

    /// 트랙 선택만 (재생 안 함) — 탭 시 사용
    func selectTrack(at index: Int) {
        // 1. 인덱스 범위 확인 (가장 중요!)
        guard index >= 0 && index < playlist.count else { return }
        
        let track = playlist[index]
        self.currentTrackIndex = index
        
        // 2. 새로운 곡을 로드하기 전에 기존 상태 초기화
        self.stop()
        self.waveformData = [] // 혹은 초기값 세팅
        
        // 3. 오디오 로드 및 설정
        loadAudio(url: track.url)
    }

    /// 트랙 선택 + 바로 재생 — 꾹 누르기 시 사용
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }

        if currentTrackIndex == index {
            // 이미 선택된 트랙이면 처음부터 재생
            seek(to: 0)
            if !isPlaying { togglePlay() }
            return
        }

        currentTrackIndex = index
        loadAudio(url: playlist[index].url)
        togglePlay()
    }

    /// 트랙 선택 해제 + 정지
    func stopAndDeselect() {
        stopPlayback()
        audioURL = nil
        currentTrackIndex = -1
        sentences = []
        waveformData = []
    }

    private func stopPlayback() {
        player?.stop()
        stopTimer()
        isPlaying = false
        currentTime = 0
    }

    /// 선택 트랙 토글 (꾹 눌러 선택/해제)
    func toggleTrackSelection(at index: Int) {
        if selectedTrackIndices.contains(index) {
            selectedTrackIndices.remove(index)
        } else {
            selectedTrackIndices.insert(index)
        }
    }

    /// 선택된 트랙들 전체 반복 재생 시작
    func playSelectedTracks() {
        let sorted = selectedTrackIndices.sorted()
        guard let first = sorted.first else { return }
        loopAllEnabled = true
        playTrack(at: first)
    }
    
    func stop() {
        self.player?.stop()
        for p in recordingPlayers {
            p.stop()
        }
        self.isPlaying = false
        self.timer?.invalidate()
        self.timer = nil
    }

    // MARK: - 다음 트랙으로
    func playNextTrack() {
        guard !playlist.isEmpty else { return }

        if loopAllEnabled && !selectedTrackIndices.isEmpty {
            // 선택된 트랙들만 순회
            let sorted = selectedTrackIndices.sorted()
            if let nextIdx = sorted.first(where: { $0 > currentTrackIndex }) {
                playTrack(at: nextIdx)
            } else {
                // 마지막이면 다시 첫 번째 선택 트랙으로
                playTrack(at: sorted[0])
            }
        } else {
            let nextIndex = currentTrackIndex + 1
            if nextIndex < playlist.count {
                playTrack(at: nextIndex)
            } else {
                stopPlayback()
            }
        }
    }

    // MARK: - Load Audio
    func loadAudio(url: URL) {
        stopPlayback()
        sentences = []

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("파일이 존재하지 않음: \(url.path)")
            return
        }

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
            MainActor.assumeIsolated {
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime

                // 구간 반복이 켜져 있으면 끝에 도달 시 시작점으로 되돌림 (무한 반복)
                if self.loopSectionEnabled {
                    if player.currentTime >= self.loopEnd {
                        self.seek(to: self.loopStart)
                    }
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
        Task {
            let bars = await Self.computeWaveform(url: url)
            self.waveformData = bars
        }
    }

    private nonisolated static func computeWaveform(url: URL) async -> [Float] {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return (0..<60).map { _ in Float.random(in: 0.2...1.0) }
            }
            try file.read(into: buffer)
            guard let channelData = buffer.floatChannelData?[0] else {
                return (0..<60).map { _ in Float.random(in: 0.2...1.0) }
            }
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
            return maxVal > 0 ? bars.map { $0 / maxVal } : bars
        } catch {
            return (0..<60).map { _ in Float.random(in: 0.2...1.0) }
        }
    }

    // MARK: - Speech Analysis
    func analyzeAudio(url: URL) {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        sentences.removeAll()
        recognitionTask?.cancel()
        recognitionTask = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if status != .authorized {
                    self.isAnalyzing = false
                    return
                }

                let preferredLocaleId = Locale.preferredLanguages.first ?? "en-US"
                let locale = Locale(identifier: preferredLocaleId)

                guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
                    self.isAnalyzing = false
                    return
                }
                self.speechRecognizer = recognizer

                let request = SFSpeechURLRecognitionRequest(url: url)
                request.shouldReportPartialResults = false

                self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }

                        if let result = result, result.isFinal {
                            self.sentences = self.buildSentenceSegments(from: result)
                            self.isAnalyzing = false
                            self.recognitionTask = nil
                        } else if let error = error {
                            print("분석 에러: \(error)")
                            self.isAnalyzing = false
                            self.recognitionTask = nil
                        }
                    }
                }
            }
        }
    }

    private func buildSentenceSegments(from result: SFSpeechRecognitionResult) -> [SentenceSegment] {
        let segments = result.bestTranscription.segments
        guard !segments.isEmpty else {
            let fallbackText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallbackText.isEmpty else { return [] }
            return [SentenceSegment(
                text: fallbackText,
                startTime: 0,
                endTime: max(duration, 0.5)
            )]
        }

        var grouped: [SentenceSegment] = []
        var words: [String] = []
        var sentenceStart = segments[0].timestamp
        var lastSegmentEnd = sentenceStart

        let pauseThreshold = 0.7
        let maxWordsPerSentence = 14

        for (i, seg) in segments.enumerated() {
            let currentStart = seg.timestamp
            let currentEnd = seg.timestamp + seg.duration
            let gap = currentStart - lastSegmentEnd
            let isLast = i == segments.count - 1

            if !words.isEmpty && gap >= pauseThreshold {
                grouped.append(SentenceSegment(
                    text: words.joined(separator: " "),
                    startTime: sentenceStart,
                    endTime: lastSegmentEnd + 0.2
                ))
                words.removeAll()
                sentenceStart = currentStart
            }

            if words.isEmpty {
                sentenceStart = currentStart
            }
            words.append(seg.substring)

            let token = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            let isPunctuation = token.hasSuffix(".") || token.hasSuffix("?") || token.hasSuffix("!")
            let isLongChunk = words.count >= maxWordsPerSentence

            if isPunctuation || isLongChunk || isLast {
                grouped.append(SentenceSegment(
                    text: words.joined(separator: " "),
                    startTime: sentenceStart,
                    endTime: currentEnd + 0.2
                ))
                words.removeAll()
            }

            lastSegmentEnd = currentEnd
        }

        return grouped
    }

    // MARK: - Recording
    func startRecording() {
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else { return }
            do {
                let session = AVAudioSession.sharedInstance()
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
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopTimer()
            self.isPlaying = false
            self.currentTime = 0
            self.playNextTrack()
        }
    }
}
