import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Content View (목록 화면)
struct ContentView: View {
    @StateObject private var player = AudioPlayerModel()
    @State private var showFilePicker = false
    @State private var selectedTrackIndex: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        PlaylistView(
                            player: player,
                            selectedTrackIndex: $selectedTrackIndex
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle("쉐도잉")
            .navigationBarTitleDisplayMode(.large)
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
            .navigationDestination(item: $selectedTrackIndex) { index in
                TrackDetailView(player: player, trackIndex: index)
            }
        }
    }
}

// MARK: - Playlist View (목록)
struct PlaylistView: View {
    @ObservedObject var player: AudioPlayerModel
    @Binding var selectedTrackIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("재생 목록")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
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
                        PlaylistItemView(
                            track: track,
                            index: index,
                            isPlaying: player.currentTrackIndex == index && player.isPlaying,
                            isCurrent: player.currentTrackIndex == index
                        ) {
                            player.selectTrack(at: index)
                            selectedTrackIndex = index
                        } onDelete: {
                            player.removeTrack(at: index)
                        }
                        if index < player.playlist.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // 시간 표시
                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    if player.loopSectionEnabled {
                        Text("핸들 드래그로 구간 설정")
                            .font(.caption)
                            .foregroundStyle(.tint)
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

                // 반복 횟수
                if player.loopSectionEnabled {
                    LoopCountView(player: player)
                }

                // 스크립트
                ScriptView(player: player, isVisible: $showScript)

                // 녹음
                RecordingView(player: player)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(player.trackName)
        .navigationBarTitleDisplayMode(.inline)
    }

    func formatTime(_ time: Double) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

// MARK: - Playlist Item
struct PlaylistItemView: View {
    let track: TrackItem
    let index: Int
    let isPlaying: Bool
    let isCurrent: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isPlaying {
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    func formatTime(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Waveform
struct WaveformView: View {
    @ObservedObject var player: AudioPlayerModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(0..<60, id: \.self) { i in
                        let h = player.waveformData.isEmpty ? 0.3 :
                            CGFloat(player.waveformData[min(i, player.waveformData.count - 1)])
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: geo.size.height * max(0.1, h))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)

                HStack(spacing: 2) {
                    ForEach(0..<60, id: \.self) { i in
                        let progress = player.duration > 0 ? player.currentTime / player.duration : 0
                        let h = player.waveformData.isEmpty ? 0.3 :
                            CGFloat(player.waveformData[min(i, player.waveformData.count - 1)])
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(height: geo.size.height * max(0.1, h))
                            .opacity(Double(i) / 60.0 < progress ? 1.0 : 0.0)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)

                if player.loopSectionEnabled && player.duration > 0 {
                    let sx = geo.size.width * CGFloat(player.loopStart / player.duration)
                    let ex = geo.size.width * CGFloat(player.loopEnd / player.duration)

                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                        .frame(width: max(0, ex - sx))
                        .offset(x: sx)

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 4)
                        .offset(x: sx)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let pct = max(0.0, min(Double(player.loopEnd / player.duration) - 0.02, Double(v.location.x / geo.size.width)))
                            player.loopStart = pct * player.duration
                        })

                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 4)
                        .offset(x: ex - 4)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let pct = max(Double(player.loopStart / player.duration) + 0.02, min(1.0, Double(v.location.x / geo.size.width)))
                            player.loopEnd = pct * player.duration
                        })
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                if !player.loopSectionEnabled {
                    let p = Double(v.location.x / geo.size.width)
                    player.seek(to: p * player.duration)
                }
            })
        }
    }
}

// MARK: - Playback Controls
struct PlaybackControlsView: View {
    @ObservedObject var player: AudioPlayerModel

    var body: some View {
        HStack(spacing: 20) {
            ctrlButton(icon: "repeat.1", label: "구간", active: player.loopSectionEnabled) {
                player.loopSectionEnabled.toggle()
            }
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

            ctrlButton(icon: "repeat", label: "전체", active: player.loopAllEnabled) {
                player.loopAllEnabled.toggle()
            }
        }
    }

    @ViewBuilder
    func ctrlButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18))
                Text(label).font(.caption2)
            }
            .foregroundStyle(active ? .white : .primary)
            .frame(width: 56, height: 48)
            .background(active ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Loop Count View
struct LoopCountView: View {
    @ObservedObject var player: AudioPlayerModel

    var body: some View {
        HStack {
            Text("반복 횟수")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Slider(
                value: Binding<Double>(
                    get: { Double(player.loopCount) },
                    set: { player.loopCount = Int($0) }
                ),
                in: 1...20,
                step: 1
            )
            .frame(maxWidth: 160)
            Text("\(player.loopCount)회")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .frame(width: 36)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Speed Control
struct SpeedControlView: View {
    @ObservedObject var player: AudioPlayerModel
    let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("재생 속도").font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(String(format: "%.2g×", player.playbackRate))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.tint)
            }
            Slider(value: $player.playbackRate, in: 0.5...1.5, step: 0.05)
                .onChange(of: player.playbackRate) { _, v in player.updatePlaybackRate(v) }
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
                Text("음성 분석 결과가 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(player.sentences) { sentence in
                            Button {
                                player.loopStart = sentence.startTime
                                player.loopEnd = sentence.endTime
                                player.loopSectionEnabled = true
                                player.loopCount = 3
                                player.seek(to: sentence.startTime)
                                if !player.isPlaying { player.togglePlay() }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(formatTime(sentence.startTime))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.tint)
                                        .frame(width: 36)
                                    Text(isVisible ? sentence.text : String(repeating: "■ ", count: max(1, sentence.text.count / 4)))
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    player.currentTime >= sentence.startTime &&
                                    player.currentTime < sentence.endTime
                                    ? Color.accentColor.opacity(0.1) : Color.clear
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 46)
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
