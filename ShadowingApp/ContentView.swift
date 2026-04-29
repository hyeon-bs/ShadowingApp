import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Content View (목록 화면)
struct ContentView: View {
    @StateObject var player = AudioPlayerModel()
    @StateObject var analyzer = ScriptAnalyzer()
    @State private var showFilePicker = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        PlaylistView(player: player) { index in
                            navigationPath.append(index)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("쉐도잉 챌린지")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilePicker = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls { player.addTrack(url: url) }
                }
            }
            .navigationDestination(for: Int.self) { index in
                TrackDetailView(
                    player: player,
                    analyzer: analyzer,
                    trackIndex: index
                )
            }
        }
    }
}

// MARK: - Playlist View (목록)
struct PlaylistView: View {
    @ObservedObject var player: AudioPlayerModel
    @State private var isSelectionMode = false
    var onTapTrack: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("재생 목록")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                Spacer()
                if isSelectionMode {
                    Button {
                        player.selectedTrackIndices.removeAll()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            isSelectionMode = false
                        }
                    } label: {
                        Text("취소")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 4)

            if player.playlist.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundStyle(.green.opacity(0.5))
                    Text("+ 버튼을 눌러 파일을 추가해주세요")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(player.playlist.enumerated()), id: \.element.id) { index, track in
                        Button {
                            if isSelectionMode {
                                player.toggleTrackSelection(at: index)
                                if player.selectedTrackIndices.isEmpty {
                                    isSelectionMode = false
                                }
                            } else {
                                onTapTrack(index)
                            }
                        } label: {
                            PlaylistRowView(
                                track: track,
                                index: index,
                                isPlaying: player.currentTrackIndex == index && player.isPlaying,
                                isCurrent: player.currentTrackIndex == index,
                                isSelected: player.selectedTrackIndices.contains(index)
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    if !isSelectionMode {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            isSelectionMode = true
                                            player.toggleTrackSelection(at: index)
                                        }
                                    }
                                }
                        )
                        
                        if index < player.playlist.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // 선택 모드 하단 바
                if isSelectionMode {
                    HStack(spacing: 12) {
                        Button {
                            if player.selectedTrackIndices.count == player.playlist.count {
                                player.selectedTrackIndices.removeAll()
                            } else {
                                player.selectedTrackIndices = Set(0..<player.playlist.count)
                            }
                        } label: {
                            Text(player.selectedTrackIndices.count == player.playlist.count ? "전체해제" : "전체선택")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.12))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Button {
                            player.playSelectedTracks()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                Text("반복재생")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(player.selectedTrackIndices.isEmpty ? Color.gray.opacity(0.12) : Color.green)
                            .foregroundColor(
                                player.selectedTrackIndices.isEmpty ? .secondary : .white
                            )
                            .clipShape(Capsule())
                        }
                        .disabled(player.selectedTrackIndices.isEmpty)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - Track Detail View (상세/재생 화면)
struct TrackDetailView: View {
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var analyzer: ScriptAnalyzer
    let trackIndex: Int
    @State private var showScript = true

    var body: some View {
        VStack {
            if trackIndex >= 0 && trackIndex < player.playlist.count {
                if player.duration > 0 {
                    ScrollView {
                        VStack(spacing: 20) {
                            WaveformView(
                                player: player,
                                analyzer: analyzer
                            )
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                            PlaybackControlsView(player: player)
                            SpeedControlView(player: player)
                            
                            ScriptView(player: player, analyzer: analyzer)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.green)
                        Text("파일을 분석하고 있습니다...")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(trackIndex < player.playlist.count ? player.playlist[trackIndex].name : "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            player.selectTrack(at: trackIndex)
        }
        .onDisappear { player.stopAndDeselect() }
    }
}

// MARK: - Playlist Row
struct PlaylistRowView: View {
    let track: TrackItem
    let index: Int
    let isPlaying: Bool
    let isCurrent: Bool
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 30, height: 30)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else if isPlaying {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .frame(width: 30, height: 30)
                    Text("\(index + 1)")
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(isCurrent ? .green : .secondary)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? .green : Color.primary)
                Text(track.duration > 0 ? formatTime(track.duration) : "—")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isCurrent && !isSelected {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    func formatTime(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Waveform
struct WaveformView: View {
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var analyzer: ScriptAnalyzer
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let totalDuration = max(0.1, player.duration)
            let loopStartPct = player.loopStart / totalDuration
            let loopEndPct = player.loopEnd / totalDuration

            ZStack(alignment: .leading) {
                if player.loopSectionEnabled && player.duration > 0 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: geo.size.width * CGFloat(loopEndPct - loopStartPct))
                        .offset(x: geo.size.width * CGFloat(loopStartPct))
                }

                HStack(spacing: 2.5) {
                    ForEach(0..<60, id: \.self) { i in
                        let barPos = Double(i) / 60.0
                        
                        let h: CGFloat = {
                            if i < player.waveformData.count {
                                return CGFloat(player.waveformData[i])
                            } else {
                                return 0.2
                            }
                        }()
                        
                        let progress = player.currentTime / totalDuration
                        let isInLoop = player.loopSectionEnabled
                        let inLoopRange = isInLoop && barPos >= loopStartPct && barPos < loopEndPct
                        let showGreen: Bool = isInLoop ? (inLoopRange && barPos < progress) : (barPos < progress)

                        Capsule()
                            .fill(showGreen ? Color.green : Color.secondary.opacity(0.25))
                            .frame(height: geo.size.height * max(0.1, h))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        guard player.duration > 0 else { return }
                        let w = geo.size.width
                        if dragStart == nil {
                            let pct = max(0, min(1, Double(v.startLocation.x / w)))
                            dragStart = pct * player.duration
                        }
                        let currentPct = max(0, min(1, Double(v.location.x / w)))
                        let currentTime = currentPct * player.duration
                        player.loopStart = min(dragStart!, currentTime)
                        player.loopEnd = max(dragStart!, currentTime)
                        player.loopSectionEnabled = true
                    }
                    .onEnded { _ in
                        dragStart = nil
                        player.seek(to: player.loopStart)
                        if !player.isPlaying { player.togglePlay() }
                    }
            )
            .onTapGesture { location in
                guard player.duration > 0 else { return }
                let pct = Double(location.x / geo.size.width)
                player.loopSectionEnabled = false
                player.seek(to: pct * player.duration)
            }
        }
    }
}

// MARK: - Playback Controls
struct PlaybackControlsView: View {
    @ObservedObject var player: AudioPlayerModel

    var body: some View {
        HStack(spacing: 28) {
            Button { player.seek(to: player.currentTime - 5) } label: {
                Image(systemName: "gobackward.5")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Circle())
            }

            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.green)
                    .clipShape(Circle())
                    .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
            }

            Button { player.seek(to: player.currentTime + 5) } label: {
                Image(systemName: "goforward.5")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Speed Control
struct SpeedControlView: View {
    @ObservedObject var player: AudioPlayerModel
    let speeds: [Float] = [0.5, 0.75, 1.0, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("재생 속도")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                Spacer()
                Text(String(format: "%.2g×", player.playbackRate))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
            HStack(spacing: 8) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        player.playbackRate = speed
                        player.updatePlaybackRate(speed)
                    } label: {
                        Text(String(format: "%.2g×", speed))
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(abs(player.playbackRate - speed) < 0.01 ? Color.green : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle(abs(player.playbackRate - speed) < 0.01 ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Script View
struct ScriptView: View {
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var analyzer: ScriptAnalyzer
    @State private var isVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 헤더 영역 (제목 & 토글 버튼)
            HStack {
                Text("스크립트")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { isVisible.toggle() }
                } label: {
                    Label(isVisible ? "숨기기" : "보이기",
                          systemImage: isVisible ? "eye.slash" : "eye")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if analyzer.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.green)
                        .scaleEffect(0.8)
                    Text("음성 분석 중...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if analyzer.sentences.isEmpty {
                Button {
                    if let url = player.audioURL {
                        analyzer.analyze(
                            url: url,
                            duration: player.duration
                        )
                    }
                } label: {
                    Label("음성 분석 시작", systemImage: "waveform.badge.magnifyingglass")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(analyzer.sentences) { sentence in
                            sentenceRow(sentence)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // 개별 문장 행 뷰
    @ViewBuilder
    private func sentenceRow(_ sentence: SentenceSegment) -> some View {
        let isActive = player.loopSectionEnabled &&
            abs(player.loopStart - sentence.startTime) < 0.1 &&
            abs(player.loopEnd - sentence.endTime) < 0.1
        
        let isCurrentlyPlaying = player.currentTime >= sentence.startTime &&
            player.currentTime < sentence.endTime

        Button {
            handleSentenceTap(sentence, isActive: isActive)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // 상태 아이콘
                ZStack {
                    Circle()
                        .fill(isActive ? Color.green : (isCurrentlyPlaying ? Color.green.opacity(0.15) : Color(.tertiarySystemGroupedBackground)))
                        .frame(width: 28, height: 28)
                    Image(systemName: isActive ? "repeat" : (isCurrentlyPlaying ? "play.fill" : "play"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isActive ? .white : (isCurrentlyPlaying ? .green : .secondary))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(isVisible ? sentence.text : String(repeating: "● ", count: min(8, max(1, sentence.text.count / 3))))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(isCurrentlyPlaying ? .semibold : .regular)
                        .foregroundColor(isCurrentlyPlaying ? Color.primary : Color.primary.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(formatTime(sentence.startTime)) - \(formatTime(sentence.endTime))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.green.opacity(0.12) :
                          (isCurrentlyPlaying ? Color.green.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
    }

    // 문장 클릭 핸들러
    private func handleSentenceTap(_ sentence: SentenceSegment, isActive: Bool) {
        if isActive {
            player.loopSectionEnabled = false
        } else {
            player.loopStart = sentence.startTime
            player.loopEnd = sentence.endTime
            player.loopSectionEnabled = true
            player.seek(to: sentence.startTime)
            if !player.isPlaying { player.togglePlay() }
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func formatTime(_ t: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}



// MARK: - Recording View
struct RecordingView: View {
    @ObservedObject var player: AudioPlayerModel
    @State private var isRecording = false
    @State private var recordings: [String] = []
    @State private var recordingSeconds = 0
    @State private var recTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("내 발음 녹음")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.bold)
            HStack(spacing: 12) {
                Button { toggleRecording() } label: {
                    ZStack {
                        Circle().strokeBorder(Color.red.opacity(0.6), lineWidth: 2).frame(width: 48, height: 48)
                        if isRecording {
                            RoundedRectangle(cornerRadius: 5).fill(Color.red).frame(width: 16, height: 16)
                        } else {
                            Circle().fill(Color.red).frame(width: 22, height: 22)
                        }
                    }
                }
                if isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text(formatRecTime(recordingSeconds))
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                            .monospacedDigit()
                    }
                } else {
                    Text("버튼을 눌러 녹음 시작")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !recordings.isEmpty {
                Divider()
                ForEach(recordings.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(.green)
                        Text("녹음 #\(i + 1)")
                            .font(.system(.subheadline, design: .rounded))
                        Text("— \(recordings[i])")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { player.playRecording(index: i) } label: {
                            Text("비교 재생")
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.12))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func toggleRecording() {
        if isRecording {
            isRecording = false
            recTimer?.invalidate()
            recordings.append(formatRecTime(recordingSeconds))
            player.stopRecording()
            recordingSeconds = 0
        } else {
            isRecording = true
            recordingSeconds = 0
            player.startRecording()
            recTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    self.recordingSeconds += 1
                }
            }
        }
    }

    func formatRecTime(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

#Preview {
    ContentView()
}
