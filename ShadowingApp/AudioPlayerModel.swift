import Foundation
import AVFoundation
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
    let id: UUID
    var startTime: Double // 이미 var일 확률이 높지만 확인해 보세요.
    var endTime: Double
    var text: String      // 이 부분을 'let'에서 'var'로 변경!

    init(id: UUID = UUID(), startTime: Double, endTime: Double, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }

    init(text: String, startTime: Double, endTime: Double) {
        self.init(id: UUID(), startTime: startTime, endTime: endTime, text: text)
    }
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

    // 반복 (재생 모드용 섹션 반복) - 편집 모드 A/B와 별개
    @Published var loopSectionEnabled: Bool = false
    @Published var isWaveformLoopSelection: Bool = false
    @Published var loopAllEnabled: Bool = false  // 선택된 트랙 전체 반복
    @Published var loopStart: Double = 0
    @Published var loopEnd: Double = 10
    @Published var loopCount: Int = 3

    // MARK: - Private
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var currentLoopRepeat: Int = 0

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
        
        // 3. 오디오 로드 및 설정
        loadAudio(url: track.url)
    }

    /// 트랙 선택 + 바로 재생 — 꾹 누르기 시 사용
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        
        // 트랙 재생 시 구간 반복 해제 (전체 재생)
        stopSectionRepeat()

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
        waveformData = []
        isWaveformLoopSelection = false
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
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
        self.isPlaying = false
        self.timer?.invalidate()
        self.timer = nil
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

    func startSectionRepeat(repeatCount: Int = 10) {
        guard duration > 0 else { return }
        loopSectionEnabled = true
        isWaveformLoopSelection = false
        loopCount = max(1, repeatCount)
        currentLoopRepeat = 0
        seek(to: loopStart)
        if !isPlaying {
            togglePlay()
        }
    }

    /// 구간 반복 해제 (전체 재생으로 복귀)
    func stopSectionRepeat() {
        loopSectionEnabled = false
        currentLoopRepeat = 0
    }

    func updatePlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    // MARK: - Timer
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let player = self.player else { return }
                self.currentTime = player.currentTime

                // 구간 반복: 설정된 횟수만큼 반복 후 자동 종료
                if self.loopSectionEnabled, player.currentTime >= self.loopEnd {
                    if self.currentLoopRepeat < max(0, self.loopCount - 1) {
                        self.currentLoopRepeat += 1
                        self.seek(to: self.loopStart)
                    } else {
                        self.seek(to: self.loopStart)
                        player.pause()
                        self.stopTimer()
                        self.isPlaying = false
                        self.currentLoopRepeat = 0
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
        Task.detached(priority: .utility) {
            let bars = await Self.computeWaveform(url: url)

            await MainActor.run {
                self.waveformData = bars
            }
        }
    }

    private nonisolated static func computeWaveform(url: URL) async -> [Float] {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let totalFrames = max(1, Int(file.length))
            let targetBars = 60
            let framesPerBar = max(1, totalFrames / targetBars)
            let chunkSize = min(4096, max(512, framesPerBar))

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(chunkSize)
            ) else {
                return (0..<60).map { _ in Float.random(in: 0.2...1.0) }
            }

            var bars = Array(repeating: Float(0), count: targetBars)
            var counts = Array(repeating: 0, count: targetBars)
            var globalFrame = 0

            while globalFrame < totalFrames {
                buffer.frameLength = 0
                try file.read(into: buffer, frameCount: AVAudioFrameCount(chunkSize))
                let readFrames = Int(buffer.frameLength)
                if readFrames <= 0 { break }
                guard let channelData = buffer.floatChannelData?[0] else { break }

                for i in 0..<readFrames {
                    let absoluteFrame = globalFrame + i
                    let barIndex = min(targetBars - 1, absoluteFrame / framesPerBar)
                    bars[barIndex] += abs(channelData[i])
                    counts[barIndex] += 1
                }
                globalFrame += readFrames
            }

            for i in 0..<targetBars {
                if counts[i] > 0 {
                    bars[i] /= Float(counts[i])
                }
            }

            let maxVal = bars.max() ?? 1.0
            return maxVal > 0 ? bars.map { $0 / maxVal } : bars
        } catch {
            return (0..<60).map { _ in Float.random(in: 0.2...1.0) }
        }
    }

    // MARK: - Load Audio
    func loadAudio(url: URL) {
        stopPlayback()

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
            
            currentTime = 0

            generateWaveform(url: url)
        } catch {
            print("오디오 로드 실패: \(error)")
        }
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
            } else if currentTrackIndex >= 0 && currentTrackIndex < playlist.count {
                // 단일 트랙 재생 완료 시 현재 트랙을 다시 시작
                playTrack(at: currentTrackIndex)
            } else {
                stopPlayback()
            }
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
