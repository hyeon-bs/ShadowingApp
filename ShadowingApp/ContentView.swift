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
            analyzer.reset()
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
                    let loopColor: Color = .green
                    
                    let dotHeight = max(18, geo.size.height - 20)
                    let dotCount = max(4, Int(dotHeight / 8))
                    
                    // Removed A handle UI block
                    
                    // Removed B handle UI block
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
    @State private var popupSentenceID: UUID? = nil
    @State private var popupText: String = ""
    @State private var popupStartText: String = ""
    @State private var popupEndText: String = ""
    @State private var showEditSheet: Bool = false
    @State private var isEditingMode: Bool = false
    
    @State private var showQuickEdit = false
    @State private var quickEditSentenceID: UUID?
    @State private var quickEditText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 헤더 영역 (제목 & 토글 버튼)
            HStack {
                Text("스크립트")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    // 새 문장 삽입: 현재 재생 위치 기준 기본 범위 2초
                    let start = max(0, player.currentTime)
                    let end = min(player.duration, start + 2.0)
                    let new = SentenceSegment(text: "새 문장", startTime: start, endTime: end)
                    analyzer.sentences.append(new)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                }
                
                HStack(spacing: 8) {
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
                        .background(player.audioURL == nil ? Color.gray.opacity(0.35) : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(player.audioURL == nil)
            } else {
                ZStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(analyzer.sentences.enumerated()), id: \.element.id) { index, sentence in
                                sentenceRow(sentence, index: index)
                            }
                        }
                    }
                    .frame(maxHeight: 240)

                    if !isVisible {
                        // Blur overlay layer
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
        .sheet(isPresented: $showEditSheet) {
        }
        .sheet(isPresented: $showQuickEdit) {
            NavigationStack {
                VStack(spacing: 16) {
                    // Mini rounded waveform with draggable range selection
                    GeometryReader { geo in
                        let bars = player.waveformData
                        let count = max(1, bars.count)
                        let width = geo.size.width
                        let height = geo.size.height
                        let barSpacing: CGFloat = 2
                        let barWidth = max(1, (width - CGFloat(count - 1) * barSpacing) / CGFloat(count))

                        // Compute current sentence range in pixels
                        let (a, b): (Double, Double) = {
                            if let id = quickEditSentenceID, let idx = analyzer.sentences.firstIndex(where: { $0.id == id }) {
                                return (analyzer.sentences[idx].startTime, analyzer.sentences[idx].endTime)
                            }
                            return (0, 0)
                        }()
                        let total = max(0.0001, player.duration)
                        let aX = CGFloat(a / total) * width
                        let bX = CGFloat(b / total) * width
                        let rangeMinX = min(aX, bX)
                        let rangeMaxX = max(aX, bX)

                        ZStack(alignment: .leading) {
                            // Bars
                            HStack(spacing: barSpacing) {
                                ForEach(0..<count, id: \.self) { i in
                                    let h = max(0.1, Double(bars[i]))
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.35))
                                        .frame(width: barWidth, height: height * h)
                                }
                            }
                            // Green highlighted current range
                            Rectangle()
                                .fill(Color.green.opacity(0.25))
                                .frame(width: max(0, rangeMaxX - rangeMinX))
                                .offset(x: rangeMinX)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let clampedX = max(0, min(width, value.location.x))
                                    let time = Double(clampedX / width) * total
                                    if let id = quickEditSentenceID, let idx = analyzer.sentences.firstIndex(where: { $0.id == id }) {
                                        // If drag just began, set start to current and end to same; otherwise extend end
                                        if value.startLocation == value.location {
                                            analyzer.sentences[idx].startTime = time
                                            analyzer.sentences[idx].endTime = time
                                        } else {
                                            analyzer.sentences[idx].endTime = time
                                        }
                                    }
                                }
                        )
                    }
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Text editor for sentence content
                    TextEditor(text: $quickEditText)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .frame(maxHeight: 200)
                    
                    Spacer()
                    
                    Button {
                        guard let id = quickEditSentenceID,
                              let idx = analyzer.sentences.firstIndex(where: { $0.id == id })
                        else { showQuickEdit = false; return }
                        analyzer.updateSentenceText(at: idx, newText: quickEditText)
                        // Range already updated via drag; ensure it is within duration
                        analyzer.sentences[idx].startTime = max(0, min(player.duration, analyzer.sentences[idx].startTime))
                        analyzer.sentences[idx].endTime = max(0, min(player.duration, analyzer.sentences[idx].endTime))
                        showQuickEdit = false
                    } label: {
                        Text("저장")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal)
                }
                .padding()
                .navigationTitle("편집")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("취소") { showQuickEdit = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            if let id = quickEditSentenceID, let idx = analyzer.sentences.firstIndex(where: { $0.id == id }) {
                                analyzer.sentences.remove(at: idx)
                            }
                            showQuickEdit = false
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
    }
    
    // 개별 문장 행 뷰
    @ViewBuilder
    private func sentenceRow(_ sentence: SentenceSegment, index: Int) -> some View {
        let isCurrentlyPlaying = player.currentTime >= sentence.startTime &&
        player.currentTime < sentence.endTime
        
        HStack(alignment: .top, spacing: 12) {
            Button {
                if isEditingMode {
                    popupSentenceID = sentence.id
                    popupText = sentence.text
                    popupStartText = String(format: "%.2f", sentence.startTime)
                    popupEndText = String(format: "%.2f", sentence.endTime)
                    showEditSheet = true
                } else {
                    player.loopSectionEnabled = false
                    player.seek(to: sentence.startTime)
                    if !player.isPlaying { player.togglePlay() }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isEditingMode ? Color.green.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                        .frame(width: 28, height: 28)
                    Image(systemName: isCurrentlyPlaying ? "play.fill" : "play")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isEditingMode ? .green : .secondary)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("위로 이동") {
                    if let i = analyzer.sentences.firstIndex(where: { $0.id == sentence.id }), i > 0 {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            let moved = analyzer.sentences.remove(at: i)
                            analyzer.sentences.insert(moved, at: i - 1)
                        }
                    }
                }
                Button("아래로 이동") {
                    if let i = analyzer.sentences.firstIndex(where: { $0.id == sentence.id }), i < analyzer.sentences.count - 1 {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            let moved = analyzer.sentences.remove(at: i)
                            analyzer.sentences.insert(moved, at: i + 1)
                        }
                    }
                }
                Button(role: .destructive) {
                    if let idx = analyzer.sentences.firstIndex(where: { $0.id == sentence.id }) {
                        analyzer.sentences.remove(at: idx)
                    }
                } label: { Label("삭제", systemImage: "trash") }
            }
            .onDrag {
                draggedSentenceID = sentence.id
                let provider = NSItemProvider(object: sentence.id.uuidString as NSString)
                provider.suggestedName = sentence.text
                return provider
            }
            .onDrop(of: [.text, .sentenceReorder], delegate: SentenceDropDelegate(
                targetID: sentence.id,
                sentences: $analyzer.sentences,
                draggedID: $draggedSentenceID,
                isEnabled: !analyzer.isAnalyzing
            ))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence.text)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(isCurrentlyPlaying ? .semibold : .regular)
                    .foregroundColor(isCurrentlyPlaying ? Color.primary : Color.primary.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 8) {
                    Text("\(formatTime(sentence.startTime)) - \(formatTime(sentence.endTime))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    quickEditSentenceID = sentence.id
                    quickEditText = sentence.text
                    showQuickEdit = true
                }
        )
    }
    
    private func formatTime(_ t: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    @State private var draggedSentenceID: UUID?
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

