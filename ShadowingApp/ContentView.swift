import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

private extension UTType {
    static let sentenceReorder = UTType(importedAs: "com.sohyeonbaek.shadowingapp.sentence-reorder")
}

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
                        
                        Button(role: .destructive) {
                            // Delete selected tracks from playlist
                            let indices = player.selectedTrackIndices.sorted(by: >)
                            for i in indices {
                                if i >= 0 && i < player.playlist.count {
                                    player.playlist.remove(at: i)
                                }
                            }
                            player.selectedTrackIndices.removeAll()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                isSelectionMode = false
                            }
                        } label: {
                            Text("삭제")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.12))
                                .foregroundStyle(.red)
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
                            .frame(height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            
                            if player.loopSectionEnabled && player.isWaveformLoopSelection && !analyzer.isRangeEditing {
                                HStack {
                                    Spacer()
                                    Button("구간 취소") {
                                        player.loopSectionEnabled = false
                                        player.isWaveformLoopSelection = false
                                    }
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.green.opacity(0.14))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                                    Spacer()
                                }
                            }
                            
                            PlaybackControlsView(player: player)
                            SpeedControlView(player: player)
                            
                            ScriptView(player: player, analyzer: analyzer)
                        }
                        .padding()
                    }
                    .onTapGesture {
                        if player.loopSectionEnabled {
                            player.stopSectionRepeat()
                        }
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
            if analyzer.sentences.isEmpty {
                    analyzer.reset()
            }
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
    private let waveformInset: CGFloat = 14
    
    var body: some View {
        GeometryReader { geo in
            let totalDuration = max(0.1, player.duration)
            let usableWidth = max(1, geo.size.width - (waveformInset * 2))
            let loopStartPct = player.loopStart / totalDuration
            let loopEndPct = player.loopEnd / totalDuration
            
            ZStack(alignment: .leading) {
                if player.loopSectionEnabled && player.duration > 0 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.green.opacity(0.18))
                        .frame(width: usableWidth * CGFloat(loopEndPct - loopStartPct))
                        .offset(x: waveformInset + (usableWidth * CGFloat(loopStartPct)))
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
                        let activeColor: Color = .green
                        
                        Capsule()
                            .fill(showGreen ? activeColor : Color.secondary.opacity(0.25))
                            .frame(height: geo.size.height * max(0.1, h))
                    }
                }
                .padding(.horizontal, waveformInset)
                .frame(maxHeight: .infinity, alignment: .center)
                
                if player.duration > 0 {
                    // let loopColor: Color = .green
                    
                    // let dotHeight = max(18, geo.size.height - 20)
                    // let dotCount = max(4, Int(dotHeight / 8))
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            // Removed drag gesture for range selection
            
            // Simplified onTapGesture to only seek
            .onTapGesture { location in
                guard player.duration > 0 else { return }
                let clampedX = max(waveformInset, min(geo.size.width - waveformInset, location.x))
                let pct = max(0, min(1, Double((clampedX - waveformInset) / usableWidth)))
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
            
            Button {
                if player.loopSectionEnabled {
                    player.stopSectionRepeat()
                    if !player.isPlaying { player.togglePlay() }
                } else {
                    player.togglePlay()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(player.loopSectionEnabled ? Color.green.opacity(0.55) : Color.green)
                    .clipShape(Circle())
                    .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
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
                    // 값이 바뀔 때 숫자가 부드럽게 변하도록 애니메이션 추가
                    .contentTransition(.numericText())
            }
            
            HStack(spacing: 8) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        // 애니메이션과 함께 속도 변경
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            player.updatePlaybackRate(speed)
                        }
                    } label: {
                        Text(String(format: "%.2g×", speed))
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        // 선택 상태에 따른 색상 변경
                            .background(isCurrentSpeed(speed) ? Color.green : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle(isCurrentSpeed(speed) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain) // 버튼 클릭 시 전체가 깜빡이는 현상 방지
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    // 로직을 별도 함수로 빼면 바디 코드가 더 읽기 쉬워집니다.
    private func isCurrentSpeed(_ speed: Float) -> Bool {
        abs(player.playbackRate - speed) < 0.01
    }
}
// MARK: - Script View
struct ScriptView: View {
    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var analyzer: ScriptAnalyzer
    
    @State private var isVisible = true
    @State private var isEditingMode: Bool = false
    @State private var editMode: EditMode = .inactive
    
    @State private var showQuickEdit = false
    @State private var quickEditSentenceID: UUID?
    @State private var quickEditText: String = ""
    @State private var quickEditStartTime: Double = 0
    @State private var quickEditEndTime: Double = 0
    
    @State private var actionSentenceID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 헤더 영역 (제목 & 토글 버튼)
            HStack(spacing: 12) {
                Text("스크립트")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                
                // 보이기 / 숨기기 버튼 (항상 노출)
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isVisible.toggle()
                    }
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .symbolRenderingMode(.palette) // 🎨 뼈대와 포인트를 다른 색으로 줄 때
                        .foregroundStyle(.gray)  // 슬래시는 빨강, 눈은 회색
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.light)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        //.background(Color.gray.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Spacer()
        
                // 편집 토글 버튼 (우측 상단)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isEditingMode.toggle()
                        editMode = isEditingMode ? .active : .inactive
                    }
                } label: {
                    Text(isEditingMode ? "완료" : "편집")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.light)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isEditingMode ? Color.green : Color.primary.opacity(0.06))
                        .foregroundColor(isEditingMode ? .white : .primary)
                        .clipShape(Capsule())
                }
                // 편집 중일 때만 노출되는 행 추가 버튼
                if isEditingMode {
                    Button {
                        let start = max(0, player.currentTime)
                        let end = min(player.duration, start + 2.0)
                        let new = SentenceSegment(text: "새 문장", startTime: start, endTime: end)
                        withAnimation { analyzer.sentences.append(new) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            
            
            if analyzer.sentences.isEmpty {
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
                } else {
                    if analyzer.failed {
                        Text("인식 실패. 다시 시도해주세요.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                    }
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
                            .background(player.audioURL == nil ? Color.gray.opacity(0.35) : Color.green)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(player.audioURL == nil)
                }
            } else {
                ZStack {
                    List {
                        ForEach(Array(analyzer.sentences.enumerated()), id: \.element.id) { index, sentence in
                            sentenceRow(sentence, index: index)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: isEditingMode ? 2 : 0))
                                .listRowSeparator(.hidden)
                                .moveDisabled(!isEditingMode)
                        }
                        .onMove { source, destination in
                            analyzer.sentences.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, $editMode)
                    .scrollDisabled(true)
                    .frame(height: max(CGFloat(analyzer.sentences.count) * 70, 60))

                    if analyzer.isAnalyzing {
                        VisualEffectBlur()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .allowsHitTesting(true)
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.green)
                            Text("음성 분석 중...")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !isVisible {
                        VisualEffectBlur()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .allowsHitTesting(true)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .confirmationDialog("문장 편집", isPresented: Binding(
            get: { actionSentenceID != nil },
            set: { if !$0 { actionSentenceID = nil } }
        ), titleVisibility: .hidden) {
            Button("편집") {
                if let id = actionSentenceID,
                   let seg = analyzer.sentences.first(where: { $0.id == id }) {
                    quickEditSentenceID = id
                    quickEditText = seg.text
                    quickEditStartTime = seg.startTime
                    quickEditEndTime = seg.endTime
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showQuickEdit = true
                    }
                }
            }
            Button("삭제", role: .destructive) {
                if let id = actionSentenceID {
                    withAnimation {
                        analyzer.sentences.removeAll { $0.id == id }
                    }
                }
            }
            Button("취소", role: .cancel) {}
        }
        .sheet(isPresented: $showQuickEdit) {
            if let id = quickEditSentenceID {
                QuickEditSheet(
                    text: $quickEditText,
                    startTime: $quickEditStartTime,
                    endTime: $quickEditEndTime,
                    duration: player.duration,
                    player: player,
                    onSave: {
                        if let idx = analyzer.sentences.firstIndex(where: { $0.id == id }) {
                            analyzer.sentences[idx].text = quickEditText
                            analyzer.sentences[idx].startTime = quickEditStartTime
                            analyzer.sentences[idx].endTime = quickEditEndTime
                        }
                        player.stopSectionRepeat()
                        showQuickEdit = false
                    },
                    onCancel: {
                        player.stopSectionRepeat()
                        showQuickEdit = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    // MARK: - 개별 문장 행 뷰
    @ViewBuilder
    private func sentenceRow(_ sentence: SentenceSegment, index: Int) -> some View {
        let isCurrentlyPlaying = player.currentTime >= sentence.startTime && player.currentTime < sentence.endTime
        
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isCurrentlyPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .padding(.top, 4)
                } else {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.primary.opacity(0.3))
                }
            }
            .frame(width: 24, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence.text)
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
                .fill((player.loopSectionEnabled && isCurrentlyPlaying) ? Color.green.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditingMode {
                actionSentenceID = sentence.id
            } else {
                if player.loopSectionEnabled
                    && player.loopStart == sentence.startTime
                    && player.loopEnd == sentence.endTime {
                    player.stopSectionRepeat()
                } else {
                    player.loopStart = sentence.startTime
                    player.loopEnd = sentence.endTime
                    player.startSectionRepeat(repeatCount: 9999)
                }
            }
        }
    }
    
    private func formatTime(_ t: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
}

private struct SentenceDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var sentences: [SentenceSegment]
    @Binding var draggedID: UUID?
    let isEnabled: Bool
    
    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        guard let draggedID, draggedID != targetID else { return }
        guard let from = sentences.firstIndex(where: { $0.id == draggedID }),
              let to = sentences.firstIndex(where: { $0.id == targetID }) else { return }
        if from == to { return }
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            let moved = sentences.remove(at: from)
            let destination = to > from ? to : to
            sentences.insert(moved, at: destination)
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
        draggedID = nil
        return true
    }
}


// MARK: - Mini Waveform Editor (드래그로 구간 선택)
struct MiniWaveformEditor: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let waveformData: [Float]
    var currentTime: Double = 0
    
    private let waveformInset: CGFloat = 12
    private let handleWidth: CGFloat = 14
    private let minimumSegmentDuration: Double = 0.25
    
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var startTimeAtDragStart: Double = 0
    @State private var endTimeAtDragStart: Double = 0
    
    var body: some View {
        GeometryReader { geo in
            let usableWidth = max(1, geo.size.width - waveformInset * 2)
            let totalDuration = max(0.1, duration)
            let startPct = CGFloat(startTime / totalDuration)
            let endPct = CGFloat(endTime / totalDuration)
            
            ZStack(alignment: .leading) {
                // 1. 웨이브폼 바
                HStack(spacing: 2) {
                    ForEach(0..<60, id: \.self) { i in
                        let h = i < waveformData.count ? CGFloat(waveformData[i]) : 0.2
                        let barPct = CGFloat(i) / 60.0
                        let inRange = barPct >= startPct && barPct < endPct
                        
                        Capsule()
                            .fill(inRange ? Color.green : Color.secondary.opacity(0.2))
                            .frame(height: geo.size.height * 0.7 * max(0.1, h))
                    }
                }
                .padding(.horizontal, waveformInset)
                .frame(maxHeight: .infinity, alignment: .center)
                
                // 2. 선택 영역 배경
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.green.opacity(0.08))
                    .frame(width: max(0, usableWidth * (endPct - startPct)))
                    .offset(x: waveformInset + usableWidth * startPct)
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
                
                // 3. 플레이헤드
                if currentTime >= startTime && currentTime <= endTime {
                    let playPct = CGFloat(currentTime / totalDuration)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: waveformInset + usableWidth * playPct - 1)
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                
                // 4. 왼쪽 핸들 (시작)
                handleView()
                    .offset(x: waveformInset + usableWidth * startPct - handleWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDraggingStart {
                                    isDraggingStart = true
                                    startTimeAtDragStart = startTime
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                let timeDelta = Double(value.translation.width / usableWidth) * totalDuration
                                let newTime = startTimeAtDragStart + timeDelta
                                startTime = max(0, min(newTime, endTime - minimumSegmentDuration))
                            }
                            .onEnded { _ in isDraggingStart = false }
                    )
                
                // 5. 오른쪽 핸들 (끝)
                handleView()
                    .offset(x: waveformInset + usableWidth * endPct)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDraggingEnd {
                                    isDraggingEnd = true
                                    endTimeAtDragStart = endTime
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                let timeDelta = Double(value.translation.width / usableWidth) * totalDuration
                                let newTime = endTimeAtDragStart + timeDelta
                                endTime = min(totalDuration, max(newTime, startTime + minimumSegmentDuration))
                            }
                            .onEnded { _ in isDraggingEnd = false }
                    )
            }
        }
    }
    
    @ViewBuilder
    private func handleView() -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.green)
            .frame(width: handleWidth)
            .frame(maxHeight: .infinity)
            .overlay(
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 6, height: 1.5)
                    }
                }
            )
            .contentShape(Rectangle().inset(by: -10))
    }
}

// MARK: - Quick Edit Sheet
struct QuickEditSheet: View {
    @Binding var text: String
    @Binding var startTime: Double
    @Binding var endTime: Double
    var duration: Double
    @ObservedObject var player: AudioPlayerModel
    var onSave: () -> Void
    var onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // 1. 문장 텍스트 편집
                VStack(alignment: .leading, spacing: 6) {
                    Text("문장")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .focused($isFocused)
                        .font(.system(.body, design: .rounded))
                        .padding(10)
                        .frame(minHeight: 60)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                // 2. 웨이브폼 구간 선택
                VStack(alignment: .leading, spacing: 6) {
                    Text("구간")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    MiniWaveformEditor(
                        startTime: $startTime,
                        endTime: $endTime,
                        duration: duration,
                        waveformData: player.waveformData,
                        currentTime: player.currentTime
                    )
                    .frame(height: 64)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                // 3. 시간 표시 + 재생 버튼
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("시작")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Text(formatTimeDetailed(startTime))
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("끝")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Text(formatTimeDetailed(endTime))
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    // 미리듣기 버튼
                    Button {
                        if player.isPlaying {
                            player.togglePlay()
                        } else {
                            player.loopStart = startTime
                            player.loopEnd = endTime
                            player.startSectionRepeat(repeatCount: 1)
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("문장 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { onSave() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { isFocused = true }
    }
    
    private func formatTimeDetailed(_ t: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let fraction = Int((t - Double(Int(t))) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }
}

struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterial
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}


#Preview {
    ContentView()
}

