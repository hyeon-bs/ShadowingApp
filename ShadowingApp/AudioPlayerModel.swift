import Foundation
import AVFoundation
import Combine

// MARK: - Track Item
struct TrackItem: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    var duration: Double
    
    var url: URL {
        PersistenceManager.audioURL(trackID: id, fileName: name)
    }
    
    init(id: UUID = UUID(), name: String, duration: Double) {
        self.id = id
        self.name = name
        self.duration = duration
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TrackItem, rhs: TrackItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sentence Segment
struct SentenceSegment: Identifiable, Codable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var text: String
    
    init(id: UUID = UUID(), text: String, startTime: Double, endTime: Double) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
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
    
    @Published var playlist: [TrackItem] = []
    @Published var currentTrackIndex: Int = -1
    @Published var selectedTrackIndices: Set<Int> = []
    
    @Published var loopSectionEnabled: Bool = false
    @Published var isWaveformLoopSelection: Bool = false
    @Published var loopAllEnabled: Bool = false
    @Published var loopStart: Double = 0
    @Published var loopEnd: Double = 10
    @Published var loopCount: Int = 3
    
    // MARK: - Private
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var currentLoopRepeat: Int = 0
    private var playStartDate: Date = .now
    private var playStartOffset: Double = 0
    private var waveformTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    
    // MARK: - Playlist 관리
    func addTrack(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        let trackID = UUID()
        let fileName = url.lastPathComponent
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + fileName)
        try? FileManager.default.copyItem(at: url, to: tempURL)
        
        let quickDur: Double = (try? AVAudioPlayer(contentsOf: tempURL))?.duration ?? 0
        
        guard let _ = PersistenceManager.copyAudioToPermanentStorage(
            from: tempURL, trackID: trackID, fileName: fileName
        ) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        try? FileManager.default.removeItem(at: tempURL)
        
        let track = TrackItem(id: trackID, name: fileName, duration: quickDur)
        playlist.append(track)
        PersistenceManager.savePlaylist(playlist)
        
        let permanentURL = track.url
        let insertedIndex = playlist.count - 1
        Task.detached(priority: .userInitiated) {
            let decoded = Self.decodedDuration(url: permanentURL)
            guard decoded > 0 else { return }
            await MainActor.run {
                guard insertedIndex < self.playlist.count,
                      self.playlist[insertedIndex].id == trackID else { return }
                self.playlist[insertedIndex].duration = decoded
                PersistenceManager.savePlaylist(self.playlist)
            }
        }
    }
    
    func removeTrack(at index: Int) {
        guard index < playlist.count else { return }
        let track = playlist[index]
        playlist.remove(at: index)
        
        PersistenceManager.deleteAudio(trackID: track.id, fileName: track.name)
        PersistenceManager.deleteSentences(forTrackID: track.id)
        PersistenceManager.savePlaylist(playlist)
        
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
    
    func loadPersistedPlaylist() {
        guard playlist.isEmpty else { return }
        playlist = PersistenceManager.loadPlaylist()
        
        let trackSnapshots = playlist.map { (id: $0.id, url: $0.url, duration: $0.duration) }
        Task.detached(priority: .utility) {
            var updates: [(Int, Double)] = []
            for i in trackSnapshots.indices {
                let real = Self.decodedDuration(url: trackSnapshots[i].url)
                if real > 0, abs(real - trackSnapshots[i].duration) > 0.5 {
                    updates.append((i, real))
                }
            }
            guard !updates.isEmpty else { return }
            await MainActor.run {
                for (i, dur) in updates {
                    guard i < self.playlist.count,
                          self.playlist[i].id == trackSnapshots[i].id else { continue }
                    self.playlist[i].duration = dur
                }
                PersistenceManager.savePlaylist(self.playlist)
            }
        }
    }
    
    func selectTrack(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        currentTrackIndex = index
        loadAudio(url: playlist[index].url)
    }
    
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        stopSectionRepeat()
        
        if currentTrackIndex == index {
            seek(to: 0)
            if !isPlaying { togglePlay() }
            return
        }
        
        currentTrackIndex = index
        loadAudio(url: playlist[index].url)
        togglePlay()
    }
    
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
    
    func toggleTrackSelection(at index: Int) {
        if selectedTrackIndices.contains(index) {
            selectedTrackIndices.remove(index)
        } else {
            selectedTrackIndices.insert(index)
        }
    }
    
    func playSelectedTracks() {
        let sorted = selectedTrackIndices.sorted()
        guard let first = sorted.first else { return }
        loopAllEnabled = true
        playTrack(at: first)
    }
    
    func stop() {
        player?.stop()
        stopTimer()
        isPlaying = false
        currentTime = 0
    }
    
    // MARK: - Playback
    func togglePlay() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            playStartOffset = player.currentTime
            playStartDate = Date()
            player.play()
            startTimer()
            isPlaying = true
        }
    }

    func seek(to time: Double) {
        let clamped = max(0, min(duration, time))
        player?.currentTime = clamped
        currentTime = clamped
        playStartOffset = clamped
        playStartDate = Date()
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
    
    func stopSectionRepeat() {
        loopSectionEnabled = false
        currentLoopRepeat = 0
    }
    
    func updatePlaybackRate(_ rate: Float) {
        if let player = player {
            playStartOffset = player.currentTime
            playStartDate = Date()
        }
        playbackRate = rate
        player?.rate = rate
    }
    
    // MARK: - Timer
    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let player = self.player else { return }

                let elapsed = Date().timeIntervalSince(self.playStartDate)
                var computed = self.playStartOffset + elapsed * Double(player.rate)

                let actual = player.currentTime
                if player.isPlaying, actual > 0, abs(computed - actual) > 0.3 {
                    self.playStartOffset = actual
                    self.playStartDate = Date()
                    computed = actual
                }

                self.currentTime = min(computed, self.duration)

                if self.loopSectionEnabled {
                    self.currentTime = min(self.currentTime, self.loopEnd)
                }

                if self.loopSectionEnabled, self.currentTime >= self.loopEnd {
                    if self.currentLoopRepeat < max(0, self.loopCount - 1) {
                        self.currentLoopRepeat += 1
                        self.seek(to: self.loopStart)
                    } else {
                        self.seek(to: self.loopStart)
                        self.player?.stop()
                        self.stopTimer()
                        self.isPlaying = false
                        self.currentLoopRepeat = 0
                    }
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Waveform
    private func generateWaveform(url: URL) {
        waveformTask?.cancel()
        waveformTask = Task.detached(priority: .utility) {
            let bars = await Self.computeWaveform(url: url, targetBars: 60)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.audioURL == url else { return }
                self.waveformData = bars
            }
        }
    }
    
    nonisolated static func decodedDuration(url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return 0 }

        let chunkSize: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return 0 }

        var totalDecodedFrames: Int64 = 0
        while true {
            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: chunkSize)
            } catch {
                break
            }
            let read = Int64(buffer.frameLength)
            if read <= 0 { break }
            totalDecodedFrames += read
        }
        return Double(totalDecodedFrames) / sampleRate
    }
    
    private nonisolated static func computeWaveform(url: URL, targetBars: Int) async -> [Float] {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let channelCount = Int(format.channelCount)
            
            let chunkSize: AVAudioFrameCount = 8192
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                return Array(repeating: 0.05, count: targetBars)
            }
            
            var barSumSquares = [Double](repeating: 0, count: targetBars)
            var barSampleCounts = [Int](repeating: 0, count: targetBars)
            
            // Pass 1: 총 디코딩 프레임 수 계산
            var totalDecodedFrames: Int64 = 0
            while true {
                buffer.frameLength = 0
                do { try file.read(into: buffer, frameCount: chunkSize) } catch { break }
                let read = Int64(buffer.frameLength)
                if read <= 0 { break }
                totalDecodedFrames += read
            }
            
            guard totalDecodedFrames > 0 else {
                return Array(repeating: 0.05, count: targetBars)
            }
            
            // Pass 2: RMS 에너지를 바별로 누적
            let file2 = try AVAudioFile(forReading: url)
            let format2 = file2.processingFormat
            guard let buffer2 = AVAudioPCMBuffer(pcmFormat: format2, frameCapacity: chunkSize) else {
                return Array(repeating: 0.05, count: targetBars)
            }
            
            let framesPerBar = Double(totalDecodedFrames) / Double(targetBars)
            var globalFrameOffset: Int64 = 0
            
            while true {
                buffer2.frameLength = 0
                do { try file2.read(into: buffer2, frameCount: chunkSize) } catch { break }
                let readFrames = Int(buffer2.frameLength)
                if readFrames <= 0 { break }
                
                guard let floatChannels = buffer2.floatChannelData else { break }
                
                for j in 0..<readFrames {
                    let globalFrame = globalFrameOffset + Int64(j)
                    let barIndex = min(Int(Double(globalFrame) / framesPerBar), targetBars - 1)
                    
                    var sampleSum: Float = 0
                    for ch in 0..<channelCount {
                        sampleSum += floatChannels[ch][j]
                    }
                    let avg = Double(sampleSum / Float(channelCount))
                    barSumSquares[barIndex] += avg * avg
                    barSampleCounts[barIndex] += 1
                }
                
                globalFrameOffset += Int64(readFrames)
            }
            
            var bars = [Float](repeating: 0, count: targetBars)
            for i in 0..<targetBars {
                let count = barSampleCounts[i]
                if count > 0 {
                    bars[i] = Float(sqrt(barSumSquares[i] / Double(count)))
                }
            }
            
            let rawMax = bars.max() ?? 1.0
            if rawMax > 0 {
                for i in 0..<targetBars {
                    bars[i] = max(0.05, powf(bars[i] / rawMax, 0.7))
                }
            } else {
                bars = Array(repeating: 0.05, count: targetBars)
            }
            
            return bars
        } catch {
            return Array(repeating: 0.05, count: targetBars)
        }
    }
    
    // MARK: - Load Audio
    func loadAudio(url: URL) {
        stopPlayback()
        waveformTask?.cancel()
        durationTask?.cancel()
        
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.enableRate = true
            player?.rate = playbackRate
            player?.prepareToPlay()
            
            audioURL = url
            trackName = url.lastPathComponent
            duration = player?.duration ?? 0
            loopStart = 0
            loopEnd = min(10, duration)
            currentTime = 0

            generateWaveform(url: url)

            let capturedURL = url
            durationTask = Task.detached(priority: .userInitiated) {
                let decoded = Self.decodedDuration(url: capturedURL)
                guard decoded > 0, !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.audioURL == capturedURL else { return }
                    self.duration = decoded
                    self.loopEnd = min(self.loopEnd, decoded)

                    if self.currentTrackIndex >= 0,
                       self.currentTrackIndex < self.playlist.count {
                        self.playlist[self.currentTrackIndex].duration = decoded
                        PersistenceManager.savePlaylist(self.playlist)
                    }
                }
            }
        } catch {
            print("오디오 로드 실패: \(error)")
        }
    }
    
    func stopLoopAll() {
        loopAllEnabled = false
        stopPlayback()
    }
    
    // MARK: - 트랙 이동
    func playNextTrack() {
        guard !playlist.isEmpty else { return }
        
        if loopAllEnabled && !selectedTrackIndices.isEmpty {
            let sorted = selectedTrackIndices.sorted()
            if let nextIdx = sorted.first(where: { $0 > currentTrackIndex }) {
                playTrack(at: nextIdx)
            } else {
                playTrack(at: sorted[0])
            }
        } else {
            let nextIndex = currentTrackIndex + 1
            if nextIndex < playlist.count {
                playTrack(at: nextIndex)
            } else if currentTrackIndex >= 0 && currentTrackIndex < playlist.count {
                playTrack(at: currentTrackIndex)
            }
        }
    }
    
    func playPreviousTrack() {
        guard !playlist.isEmpty else { return }
        
        if loopAllEnabled && !selectedTrackIndices.isEmpty {
            let sorted = selectedTrackIndices.sorted()
            if let prevIdx = sorted.last(where: { $0 < currentTrackIndex }) {
                playTrack(at: prevIdx)
            } else {
                playTrack(at: sorted.last ?? currentTrackIndex)
            }
        } else {
            let prevIndex = currentTrackIndex - 1
            if prevIndex >= 0 {
                playTrack(at: prevIndex)
            } else {
                seek(to: 0)
                if !isPlaying { togglePlay() }
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
            
            guard !self.loopSectionEnabled else { return }
            
            let finishedURL = self.audioURL
            self.currentTime = self.duration
            
            try? await Task.sleep(for: .milliseconds(300))
            
            guard self.audioURL == finishedURL, self.player != nil else { return }
            
            if self.loopAllEnabled {
                self.playNextTrack()
            } else {
                self.seek(to: 0)
                self.togglePlay()
            }
        }
    }
}
