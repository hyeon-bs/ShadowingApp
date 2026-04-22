import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Content View (목록 화면)
struct ContentView: View {
    @StateObject private var player = AudioPlayerModel()
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
            .navigationTitle("쉐도잉")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Int.self) { index in
                TrackDetailView(player: player, trackIndex: index)
            }
            .onDisappear {
                player.stop()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilePicker = true } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        player.addTrack(url: url)
                    }
                }
            }
            .navigationDestination(for: Int.self) { index in
                TrackDetailView(player: player, trackIndex: index)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("재생 목록")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if isSelectionMode {
                    Button {
                        player.stop()
                        player.selectedTrackIndices.removeAll()
                        withAnimation {
                            isSelectionMode = false
                        }
                    } label: {
                        Text("취소")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.horizontal, 4)

            if player.playlist.isEmpty {
                Text("+ 버튼을 눌러 파일을 추가해주세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(player.playlist.enumerated()), id: \.element.id) { index, track in
                        Button {
                            // 일반 탭 처리
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
                                    // 꾹 누르는 제스쳐에 따라서 선택모드
                                    if !isSelectionMode {
                                        isSelectionMode = true
                                        player.toggleTrackSelection(at: index)
                                    }
                                }
                        )
                        if index < player.playlist.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // 선택 모드 하단 바
                if isSelectionMode {
                    HStack {
                        Button {
                            if player.selectedTrackIndices.count == player.playlist.count {
                                player.selectedTrackIndices.removeAll()
                            } else {
                                player.selectedTrackIndices = Set(0..<player.playlist.count)
                            }
                        } label: {
                            Text(player.selectedTrackIndices.count == player.playlist.count ? "전체해제" : "전체선택")
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                        }
                        Spacer()
                        Button {
                            player.playSelectedTracks()
                        } label: {
                            Text("반복재생")
                                .font(.subheadline)
                                .foregroundColor(player.selectedTrackIndices.isEmpty ? .secondary : .accentColor)
                        }
                        .disabled(player.selectedTrackIndices.isEmpty)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Track Detail View (상세/재생 화면)
struct TrackDetailView: View {
    @ObservedObject var player: AudioPlayerModel
    let trackIndex: Int
    @State private var showScript = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 웨이브폼
                WaveformView(player: player)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // 시간 표시 + 구간 안내
                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    if player.loopSectionEnabled {
                        Button {
                            player.loopSectionEnabled = false
                        } label: {
                            Label("구간 해제", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.30))
                                .clipShape(Capsule())
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text("웨이브폼을 드래그하여 구간 반복")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(formatTime(player.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                // 재생 컨트롤
                PlaybackControlsView(player: player)

                // 속도 조절
                SpeedControlView(player: player)

                // 스크립트
                ScriptView(player: player, isVisible: $showScript)

                // 녹음
                RecordingView(player: player)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(trackIndex < player.playlist.count ? player.playlist[trackIndex].name : "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            player.selectTrack(at: trackIndex)
        }
        .onDisappear {
            player.stopAndDeselect()
        }
        .onDisappear {
            player.stop()
        }
    }

    func formatTime(_ time: Double) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                } else if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundStyle(.tint)
                } else {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .medium : .regular)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                Text(track.duration > 0 ? formatTime(track.duration) : "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    func formatTime(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Waveform
struct WaveformView: View {
    @ObservedObject var player: AudioPlayerModel
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let loopStartPct = player.duration > 0 ? player.loopStart / player.duration : 0
            let loopEndPct = player.duration > 0 ? player.loopEnd / player.duration : 0

            ZStack(alignment: .leading) {
                // 구간 반복 배경 (회색 10%)
                if player.loopSectionEnabled && player.duration > 0 {
                    Color.gray.opacity(0.30)
                        .frame(width: geo.size.width * CGFloat(loopEndPct - loopStartPct))
                        .offset(x: geo.size.width * CGFloat(loopStartPct))
                }

                // 웨이브폼 바
                HStack(spacing: 2) {
                    ForEach(0..<60, id: \.self) { i in
                        let barPos = Double(i) / 60.0
                        let h = player.waveformData.isEmpty ? 0.3 :
                            CGFloat(player.waveformData[min(i, player.waveformData.count - 1)])
                        let progress = player.duration > 0 ? player.currentTime / player.duration : 0

                        let isInLoop = player.loopSectionEnabled && player.duration > 0
                        let inLoopRange = isInLoop && barPos >= loopStartPct && barPos < loopEndPct

                        // 파란색: 구간 반복 시 구간 내 재생 위치까지 / 일반 재생 시 재생 위치까지
                        let showBlue: Bool = isInLoop
                            ? (inLoopRange && barPos < progress)
                            : (barPos < progress)

                        let barColor: Color = showBlue
                            ? Color.accentColor
                            : Color.secondary.opacity(0.3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor)
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
                            // 드래그 시작 지점
                            let pct = max(0, min(1, Double(v.startLocation.x / w)))
                            dragStart = pct * player.duration
                        }

                        // 현재 드래그 위치
                        let currentPct = max(0, min(1, Double(v.location.x / w)))
                        let currentTime = currentPct * player.duration

                        let start = min(dragStart!, currentTime)
                        let end = max(dragStart!, currentTime)

                        player.loopStart = start
                        player.loopEnd = end
                        player.loopSectionEnabled = true
                    }
                    .onEnded { _ in
                        dragStart = nil
                        // 구간 설정 후 해당 구간 시작점으로 이동 및 재생
                        player.seek(to: player.loopStart)
                        if !player.isPlaying { player.togglePlay() }
                    }
            )
            .onTapGesture { location in
                // 탭하면 해당 위치로 이동 (구간 반복 해제)
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
        HStack(spacing: 20) {
            Button { player.seek(to: player.currentTime - 5) } label: {
                Image(systemName: "gobackward.5").font(.system(size: 22))
            }.foregroundStyle(.primary)

            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
            }

            Button { player.seek(to: player.currentTime + 5) } label: {
                Image(systemName: "goforward.5").font(.system(size: 22))
            }.foregroundStyle(.primary)
        }
    }
}

// MARK: - Speed Control
struct SpeedControlView: View {
    @ObservedObject var player: AudioPlayerModel
    let speeds: [Float] = [0.5, 0.75, 1.0, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("재생 속도").font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(String(format: "%.2g×", player.playbackRate))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.tint)
            }
            HStack(spacing: 8) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        player.playbackRate = speed
                        player.updatePlaybackRate(speed)
                    } label: {
                        Text(String(format: "%.2g×", speed))
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(abs(player.playbackRate - speed) < 0.01 ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle(abs(player.playbackRate - speed) < 0.01 ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Script View
struct ScriptView: View {
    @ObservedObject var player: AudioPlayerModel
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("스크립트").font(.subheadline).fontWeight(.medium)
                Spacer()
                Button {
                    withAnimation { isVisible.toggle() }
                } label: {
                    Label(isVisible ? "숨기기" : "보이기",
                          systemImage: isVisible ? "eye.slash" : "eye")
                        .font(.caption)
                }
            }

            if player.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("음성 분석 중...").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if player.sentences.isEmpty {
                Button {
                    if let url = player.audioURL {
                        player.analyzeAudio(url: url)
                    }
                } label: {
                    Label("음성 분석 시작", systemImage: "waveform.badge.magnifyingglass")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(player.sentences) { sentence in
                            let isActive = player.loopSectionEnabled &&
                                abs(player.loopStart - sentence.startTime) < 0.1 &&
                                abs(player.loopEnd - sentence.endTime) < 0.1
                            let isCurrentlyPlaying = player.currentTime >= sentence.startTime &&
                                player.currentTime < sentence.endTime

                            Button {
                                if isActive {
                                    // 이미 반복 중인 문장을 다시 누르면 해제
                                    player.loopSectionEnabled = false
                                } else {
                                    player.loopStart = sentence.startTime
                                    player.loopEnd = sentence.endTime
                                    player.loopSectionEnabled = true
                                    player.seek(to: sentence.startTime)
                                    if !player.isPlaying { player.togglePlay() }
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: isActive ? "repeat.circle.fill" : "play.circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isVisible ? sentence.text : String(repeating: "■ ", count: max(1, sentence.text.count / 4)))
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(formatTime(sentence.startTime) + " - " + formatTime(sentence.endTime))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    isActive ? Color.accentColor.opacity(0.12) :
                                    isCurrentlyPlaying ? Color.accentColor.opacity(0.05) : Color.clear
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func formatTime(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
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
            Text("내 발음 녹음").font(.subheadline).fontWeight(.medium)
            HStack(spacing: 12) {
                Button { toggleRecording() } label: {
                    ZStack {
                        Circle().strokeBorder(Color.red.opacity(0.6), lineWidth: 2).frame(width: 44, height: 44)
                        if isRecording {
                            RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 16, height: 16)
                        } else {
                            Circle().fill(Color.red).frame(width: 20, height: 20)
                        }
                    }
                }
                if isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text(formatRecTime(recordingSeconds))
                            .font(.subheadline).fontWeight(.medium).foregroundStyle(.red).monospacedDigit()
                    }
                } else {
                    Text("버튼을 눌러 녹음 시작").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !recordings.isEmpty {
                Divider()
                ForEach(recordings.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(.tint)
                        Text("녹음 #\(i + 1)").font(.subheadline)
                        Text("— \(recordings[i])").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button { player.playRecording(index: i) } label: {
                            Text("비교 재생")
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(.tint)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
