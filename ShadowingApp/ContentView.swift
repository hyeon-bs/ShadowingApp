import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit

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
                    Task { @MainActor in
                        for url in urls {
                            player.addTrack(url: url)
                        }
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
                            .foregroundStyle(player.selectedTrackIndices.isEmpty ? Color.secondary : Color.white)
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
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var player: AudioPlayerModel
    let trackIndex: Int
    @State private var showScript = true
    
    var body: some View {
        VStack {
            if trackIndex >= 0 && trackIndex < player.playlist.count {
                if player.duration > 0 {
                    ScrollView {
                        VStack(spacing: 20) {
                            WaveformView(player: player)
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            
                            PlaybackControlsView(player: player)
                            SpeedControlView(player: player)
                            
                            // 🔍 자동 분석된 문장 리스트가 보일 곳
                            ScriptView(player: player, isVisible: $showScript)
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle((trackIndex >= 0 && trackIndex < player.playlist.count) ? player.playlist[trackIndex].name : "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            player.selectTrack(at: trackIndex)

            try? await Task.sleep(for: .seconds(1.0))

            if player.duration > 0 {
                player.autoAnalyzeCurrentTrackIfNeeded()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    player.stopAndDeselect()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
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
                        .foregroundStyle(isCurrent ? Color.green : Color.secondary)
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
                    
                    let count = max(player.waveformData.count, 1)
                    
                    ForEach(player.waveformData.indices, id:\.self) { i in
                        
                        let barPos = Double(i) / Double(count)
                        let h = CGFloat(player.waveformData[i])
                        
                        let progress = player.currentTime / totalDuration
                        let isInLoop = player.loopSectionEnabled
                        let inLoopRange = isInLoop && barPos >= loopStartPct && barPos < loopEndPct
                        let showGreen = isInLoop ? (inLoopRange && barPos < progress) : (barPos < progress)
                        
                        Capsule()
                            .fill(showGreen ? Color.green : Color.secondary.opacity(0.25))
                            .frame(height: geo.size.height * max(0.08, h))
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
                        guard let start = dragStart else { return }
                        player.loopStart = min(start, currentTime)
                        player.loopEnd = max(start, currentTime)
                        player.loopSectionEnabled = true
                    }
                    .onEnded { _ in
                        dragStart = nil
                        player.seek(to: player.loopStart)
                        if !player.isPlaying { player.togglePlay() }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard player.duration > 0 else { return }
                        let pct = Double(value.location.x / geo.size.width)
                        player.loopSectionEnabled = false
                        player.seek(to: pct * player.duration)
                    }
            )
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
                            .foregroundStyle(abs(player.playbackRate - speed) < 0.01 ? Color.white : Color.primary)
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
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // HEADER
            HStack {
                Text("스크립트")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isVisible.toggle()
                    }
                } label: {
                    Label(
                        isVisible ? "숨기기" : "보이기",
                        systemImage: isVisible ? "eye.slash.fill" : "eye.fill"
                    )
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.12))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                }
            }
            
            // 분석중
            if player.isAnalyzing {
                
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.green)
                        .scaleEffect(1.2)
                    
                    Text("파일을 분석하고 있습니다...")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                    
                    Text("문장을 분리하고 있어요.\n최대 1분 정도 걸릴 수 있습니다.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
            
            // 비어있음 = 자동 재시도 UI
            else if player.sentences.isEmpty {
                
                VStack(spacing: 14) {
                    
                    if player.analysisTimedOut {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 26))
                            .foregroundStyle(.orange)
                        
                        Text("분석이 지연되고 있습니다.")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                        
                        Text("자동으로 다시 시도 중입니다.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .tint(.green)
                        
                        Text("스크립트를 준비 중입니다...")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            }
            
            // 문장 리스트
            else {
                
                ScrollViewReader { proxy in
                    
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            
                            ForEach(player.sentences) { sentence in
                                sentenceRow(sentence)
                                    .id(sentence.id)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    
                    // 현재 재생 문장 자동 스크롤
                    .onChange(of: currentSentence()?.id) { _, newID in
                        guard let id = newID else { return }

                        let exists = player.sentences.contains { $0.id == id }
                        guard exists else { return }

                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.25), value: player.isAnalyzing)
        .animation(.easeInOut(duration: 0.25), value: player.sentences.count)
    }
    
    // MARK: Sentence Row
    @ViewBuilder
    private func sentenceRow(_ sentence: SentenceSegment) -> some View {
        
        let isActive =
        player.loopSectionEnabled &&
        abs(player.loopStart - sentence.startTime) < 0.3 &&
        abs(player.loopEnd - sentence.endTime) < 0.3
        
        let isPlaying =
        player.currentTime >= sentence.startTime &&
        player.currentTime < sentence.endTime
        
        Button {
            handleSentenceTap(sentence, isActive: isActive)
        } label: {
            
            HStack(alignment: .top, spacing: 14) {
                
                // 상태 아이콘
                ZStack {
                    Circle()
                        .fill(
                            isActive ? Color.green :
                                isPlaying ? Color.green.opacity(0.15) :
                                Color(.tertiarySystemGroupedBackground)
                        )
                        .frame(width: 34, height: 34)
                    
                    Image(systemName:
                            isActive ? "repeat" :
                            isPlaying ? "speaker.wave.2.fill" :
                            "play.fill"
                    )
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(
                        isActive ? .white :
                            isPlaying ? .green :
                                .secondary
                    )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    
                    // 쉐도잉 모드
                    if isVisible {
                        Text(sentence.text)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(isPlaying ? .semibold : .regular)
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                    } else {
                        Text(masked(sentence.text))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(formatTime(sentence.startTime)) ~ \(formatTime(sentence.endTime))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(isPlaying ? .green : .secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isActive ? Color.green.opacity(0.14) :
                            isPlaying ? Color.green.opacity(0.08) :
                            Color(.tertiarySystemGroupedBackground)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: Shadowing Tap Action
    private func handleSentenceTap(_ sentence: SentenceSegment, isActive: Bool) {
        
        if isActive {
            player.loopSectionEnabled = false
        } else {
            player.loopStart = sentence.startTime
            player.loopEnd = sentence.endTime
            player.loopSectionEnabled = true
            player.seek(to: sentence.startTime)
            
            if !player.isPlaying {
                player.togglePlay()
            }
        }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    // 현재 문장 찾기
    private func currentSentence() -> SentenceSegment? {
        player.sentences.first {
            player.currentTime >= $0.startTime &&
            player.currentTime < $0.endTime
        }
    }
    
    // 가리기 (쉐도잉용)
    private func masked(_ text: String) -> String {
        String(repeating: "● ", count: max(1, min(10, text.count / 3)))
    }
    
    private func formatTime(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}



//// MARK: - Recording View
//struct RecordingView: View {
//    @ObservedObject var player: AudioPlayerModel
//    @State private var isRecording = false
//    @State private var recordings: [String] = []
//    @State private var recordingSeconds = 0
//    @State private var recTimer: Timer?
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text("내 발음 녹음")
//                .font(.system(.subheadline, design: .rounded))
//                .fontWeight(.bold)
//            HStack(spacing: 12) {
//                Button { toggleRecording() } label: {
//                    ZStack {
//                        Circle().strokeBorder(Color.red.opacity(0.6), lineWidth: 2).frame(width: 48, height: 48)
//                        if isRecording {
//                            RoundedRectangle(cornerRadius: 5).fill(Color.red).frame(width: 16, height: 16)
//                        } else {
//                            Circle().fill(Color.red).frame(width: 22, height: 22)
//                        }
//                    }
//                }
//                if isRecording {
//                    HStack(spacing: 6) {
//                        Circle().fill(Color.red).frame(width: 8, height: 8)
//                        Text(formatRecTime(recordingSeconds))
//                            .font(.system(.subheadline, design: .rounded))
//                            .fontWeight(.semibold)
//                            .foregroundStyle(.red)
//                            .monospacedDigit()
//                    }
//                } else {
//                    Text("버튼을 눌러 녹음 시작")
//                        .font(.system(.subheadline, design: .rounded))
//                        .foregroundStyle(.secondary)
//                }
//                Spacer()
//            }
//            if !recordings.isEmpty {
//                Divider()
//                ForEach(recordings.indices, id: \.self) { i in
//                    HStack {
//                        Image(systemName: "waveform").foregroundStyle(.green)
//                        Text("녹음 #\(i + 1)")
//                            .font(.system(.subheadline, design: .rounded))
//                        Text("— \(recordings[i])")
//                            .font(.system(.subheadline, design: .rounded))
//                            .foregroundStyle(.secondary)
//                        Spacer()
//                        Button { player.playRecording(index: i) } label: {
//                            Text("비교 재생")
//                                .font(.system(.caption, design: .rounded))
//                                .fontWeight(.semibold)
//                                .padding(.horizontal, 12)
//                                .padding(.vertical, 6)
//                                .background(Color.green.opacity(0.12))
//                                .foregroundStyle(.green)
//                                .clipShape(Capsule())
//                        }
//                    }
//                }
//            }
//        }
//        .padding(18)
//        .background(Color(.secondarySystemGroupedBackground))
//        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
//    }
//
//    func toggleRecording() {
//        if isRecording {
//            isRecording = false
//            recTimer?.invalidate()
//            recordings.append(formatRecTime(recordingSeconds))
//            player.stopRecording()
//            recordingSeconds = 0
//        } else {
//            isRecording = true
//            recordingSeconds = 0
//            player.startRecording()
//            recTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//                Task { @MainActor in
//                    self.recordingSeconds += 1
//                }
//            }
//        }
//    }
//
//    func formatRecTime(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
//}

#Preview {
    ContentView()
}
