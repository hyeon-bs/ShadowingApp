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
    private enum ActiveHandle {
        case a
        case b
    }

    @ObservedObject var player: AudioPlayerModel
    @ObservedObject var analyzer: ScriptAnalyzer
    @State private var dragStart: Double?
    @State private var activeHandle: ActiveHandle?
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
                        .fill((analyzer.isRangeEditing ? Color.orange : Color.green).opacity(0.18))
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
                        let activeColor: Color = analyzer.isRangeEditing ? .orange : .green

                        Capsule()
                            .fill(showGreen ? activeColor : Color.secondary.opacity(0.25))
                            .frame(height: geo.size.height * max(0.1, h))
                    }
                }
                .padding(.horizontal, waveformInset)
                .frame(maxHeight: .infinity, alignment: .center)

                if player.duration > 0 {
                    let loopColor: Color = analyzer.isRangeEditing ? .orange : .green

                    let dotHeight = max(18, geo.size.height - 20)
                    let dotCount = max(4, Int(dotHeight / 8))

                    // A handle (start)
                    VStack(spacing: 3) {
                        Text("A")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(loopColor)
                        VStack(spacing: 4) {
                            ForEach(0..<dotCount, id: \.self) { _ in
                                Circle()
                                    .fill(loopColor)
                                    .frame(width: 3.6, height: 3.6)
                            }
                        }
                    }
                    .position(
                        x: max(waveformInset, min(geo.size.width - waveformInset, waveformInset + (usableWidth * CGFloat(loopStartPct)))),
                        y: geo.size.height / 2
                    )
                    .frame(width: 28, height: geo.size.height)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                activeHandle = .a
                                let clampedX = max(waveformInset, min(geo.size.width - waveformInset, value.location.x))
                                let pct = max(0, min(1, Double((clampedX - waveformInset) / usableWidth)))
                                let newStart = min(pct * player.duration, player.loopEnd - 0.05)
                                player.loopStart = max(0, newStart)
                                player.loopSectionEnabled = true
                                if analyzer.isRangeEditing,
                                   let editingID = analyzer.editingSentenceID,
                                   let index = analyzer.sentences.firstIndex(where: { $0.id == editingID }) {
                                    analyzer.updateSentenceRange(
                                        at: index,
                                        start: player.loopStart,
                                        end: player.loopEnd
                                    )
                                }
                            }
                            .onEnded { _ in
                                activeHandle = nil
                            }
                    )

                    // B handle (end)
                    VStack(spacing: 3) {
                        Text("B")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(loopColor)
                        VStack(spacing: 4) {
                            ForEach(0..<dotCount, id: \.self) { _ in
                                Circle()
                                    .fill(loopColor)
                                    .frame(width: 3.6, height: 3.6)
                            }
                        }
                    }
                    .position(
                        x: max(waveformInset, min(geo.size.width - waveformInset, waveformInset + (usableWidth * CGFloat(loopEndPct)))),
                        y: geo.size.height / 2
                    )
                    .frame(width: 28, height: geo.size.height)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                activeHandle = .b
                                let clampedX = max(waveformInset, min(geo.size.width - waveformInset, value.location.x))
                                let pct = max(0, min(1, Double((clampedX - waveformInset) / usableWidth)))
                                let newEnd = max(pct * player.duration, player.loopStart + 0.05)
                                player.loopEnd = min(player.duration, newEnd)
                                player.loopSectionEnabled = true
                                if analyzer.isRangeEditing,
                                   let editingID = analyzer.editingSentenceID,
                                   let index = analyzer.sentences.firstIndex(where: { $0.id == editingID }) {
                                    analyzer.updateSentenceRange(
                                        at: index,
                                        start: player.loopStart,
                                        end: player.loopEnd
                                    )
                                }
                            }
                            .onEnded { _ in
                                activeHandle = nil
                            }
                    )
                }
            }
            .background(analyzer.isRangeEditing ? Color(.systemGray6) : Color(.secondarySystemGroupedBackground))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        guard player.duration > 0 else { return }
                        guard !analyzer.isRangeEditing else { return }
                        guard activeHandle == nil else { return }
                        let w = usableWidth
                        if dragStart == nil {
                            let startX = max(waveformInset, min(geo.size.width - waveformInset, v.startLocation.x))
                            let pct = max(0, min(1, Double((startX - waveformInset) / w)))
                            dragStart = pct * player.duration
                        }
                        let currentX = max(waveformInset, min(geo.size.width - waveformInset, v.location.x))
                        let currentPct = max(0, min(1, Double((currentX - waveformInset) / w)))
                        let currentTime = currentPct * player.duration
                        player.loopStart = min(dragStart!, currentTime)
                        player.loopEnd = max(dragStart!, currentTime)
                        player.loopSectionEnabled = true
                        player.isWaveformLoopSelection = !analyzer.isRangeEditing

                        if analyzer.isRangeEditing,
                           let editingID = analyzer.editingSentenceID,
                           let index = analyzer.sentences.firstIndex(where: { $0.id == editingID }) {
                            analyzer.updateSentenceRange(
                                at: index,
                                start: player.loopStart,
                                end: player.loopEnd
                            )
                        }
                    }
                    .onEnded { _ in
                        guard !analyzer.isRangeEditing else { return }
                        guard activeHandle == nil else { return }
                        dragStart = nil
                        if analyzer.isRangeEditing {
                            player.seek(to: player.loopStart)
                        } else {
                            player.seek(to: player.loopStart)
                            if !player.isPlaying { player.togglePlay() }
                        }
                    }
            )
            .onTapGesture { location in
                guard player.duration > 0 else { return }
                let clampedX = max(waveformInset, min(geo.size.width - waveformInset, location.x))
                let pct = max(0, min(1, Double((clampedX - waveformInset) / usableWidth)))
                if !analyzer.isRangeEditing {
                    player.loopSectionEnabled = false
                    player.isWaveformLoopSelection = false
                }
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
    @State private var editingSentenceID: UUID?
    @State private var activeEditingTargetID: UUID?
    @State private var draftSentenceText = ""
    @State private var draggedSentenceID: UUID?
    @State private var rangeEditingSentenceID: UUID?
    @State private var rangeStartText = ""
    @State private var rangeEndText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 헤더 영역 (제목 & 토글 버튼)
            HStack {
                Text("스크립트")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                
                Spacer()

                if let editingID = editingSentenceID {
                    HStack(spacing: 6) {
                        Button("저장") {
                            let targetID = activeEditingTargetID ?? editingID
                            if let index = analyzer.sentences.firstIndex(where: { $0.id == targetID }) {
                                // 1. 현재 플레이어의 수정된 시간 확정
                                let finalizedStart = player.loopStart
                                let finalizedEnd = player.loopEnd
                                
                                // 2. 데이터 저장
                                analyzer.updateSentenceRange(at: index, start: finalizedStart, end: finalizedEnd)
                                analyzer.updateSentenceText(at: index, newText: draftSentenceText)
                                
                                // 3. ⭐ 핵심: 저장된 데이터를 플레이어에 즉시 다시 주입
                                // 이렇게 해야 위에 있는 isActive 조건이 True가 되어 하이라이트가 유지됩니다.
                                player.loopStart = finalizedStart
                                player.loopEnd = finalizedEnd
                                player.loopSectionEnabled = true
                            }
                            
                            // 4. 상태 초기화
                            editingSentenceID = nil
                            activeEditingTargetID = nil
                            analyzer.isRangeEditing = false
                            analyzer.editingSentenceID = nil
                        }
                    }
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }

                if editingSentenceID == nil {
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(analyzer.sentences.enumerated()), id: \.element.id) { index, sentence in
                            sentenceRow(sentence, index: index)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(18)
        .background(editingSentenceID != nil ? Color(.systemGray6) : Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .alert("시간 범위 직접 수정", isPresented: Binding(
            get: { rangeEditingSentenceID != nil },
            set: { if !$0 { rangeEditingSentenceID = nil } }
        )) {
            TextField("시작시간 A (초)", text: $rangeStartText)
                .keyboardType(.decimalPad)
            TextField("종료시간 B (초)", text: $rangeEndText)
                .keyboardType(.decimalPad)
            Button("취소", role: .cancel) {
                rangeEditingSentenceID = nil
            }
            Button("적용") {
                guard let targetID = rangeEditingSentenceID,
                      let index = analyzer.sentences.firstIndex(where: { $0.id == targetID }),
                      let start = Double(rangeStartText),
                      let end = Double(rangeEndText) else {
                    rangeEditingSentenceID = nil
                    return
                }
                analyzer.updateSentenceRange(at: index, start: start, end: end)
                if analyzer.sentences.indices.contains(index) {
                    let updated = analyzer.sentences[index]
                    player.loopStart = updated.startTime
                    player.loopEnd = updated.endTime
                    player.loopSectionEnabled = true
                }
                rangeEditingSentenceID = nil
            }
        } message: {
            Text("예: A=12.3, B=15.8")
        }
        .onChange(of: editingSentenceID) { _, newValue in
            // 편집 대상이 없으면 반드시 일반 모드 상태로 복귀
            if newValue == nil {
                activeEditingTargetID = nil
                analyzer.isRangeEditing = false
                analyzer.editingSentenceID = nil
            }
        }
    }

    // 개별 문장 행 뷰
    @ViewBuilder
    private func sentenceRow(_ sentence: SentenceSegment, index: Int) -> some View {
        let isEditingMode = analyzer.isRangeEditing && editingSentenceID != nil
        let isActive = player.loopSectionEnabled &&
            abs(player.loopStart - sentence.startTime) < 0.1 &&
            abs(player.loopEnd - sentence.endTime) < 0.1

        let isCurrentlyPlaying = player.currentTime >= sentence.startTime &&
            player.currentTime < sentence.endTime

        HStack(alignment: .top, spacing: 12) {
            Button {
                handleSentenceIconTap(sentence, isEditingMode: isEditingMode)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isEditingMode
                            ? Color.orange.opacity(0.18)
                            : (isActive ? Color.green : (isCurrentlyPlaying ? Color.green.opacity(0.15) : Color(.tertiarySystemGroupedBackground)))
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: isEditingMode ? "checkmark.circle.fill" : (isActive ? "repeat" : (isCurrentlyPlaying ? "play.fill" : "play")))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            isEditingMode
                            ? .orange
                            : (isActive ? .white : (isCurrentlyPlaying ? .green : .secondary))
                        )
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                if editingSentenceID == sentence.id {
                    TextField("문장 입력", text: $draftSentenceText)
                        .textFieldStyle(.plain)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.primary)
                } else {
                    Text(isVisible ? sentence.text : mosaicText(sentence.text))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(isCurrentlyPlaying ? .semibold : .regular)
                        .foregroundColor(isCurrentlyPlaying ? Color.primary : Color.primary.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // sentenceRow 함수 내부의 시간 표시 부분
                HStack(spacing: 8) {
                    if editingSentenceID == sentence.id {
                        // 편집 중일 때는 드래그 중인 플레이어의 시간을 실시간으로 표시
                        Text("\(formatTime(player.loopStart)) - \(formatTime(player.loopEnd))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.orange) // 편집 중임을 알리는 색상
                            .fontWeight(.bold)
                    } else {
                        // 평상시에는 저장된 문장 데이터의 시간 표시
                        Text("\(formatTime(sentence.startTime)) - \(formatTime(sentence.endTime))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                handleSentenceContentTap(sentence, isEditingMode: isEditingMode)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isEditingMode
                    ? Color.clear
                    : (isActive ? Color.green.opacity(0.12) :
                        (isCurrentlyPlaying ? Color.green.opacity(0.06) : Color.clear))
                )
        )
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    if !isEditingMode {
                        startSentenceEditing(sentence, index: index)
                    }
                }
        )
        .onDrag {
            guard !isEditingMode else {
                return NSItemProvider()
            }
            draggedSentenceID = sentence.id
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.sentenceReorder.identifier, visibility: .all) { completion in
                completion(Data(), nil)
                return nil
            }
            return provider
        }
        .onDrop(
            of: [UTType.sentenceReorder],
            delegate: SentenceDropDelegate(
                targetID: sentence.id,
                sentences: $analyzer.sentences,
                draggedID: $draggedSentenceID,
                isEnabled: !isEditingMode
            )
        )
        .contextMenu {
            if !isEditingMode {
                Button("A~B 시간 직접 입력") {
                    rangeStartText = String(format: "%.2f", sentence.startTime)
                    rangeEndText = String(format: "%.2f", sentence.endTime)
                    rangeEditingSentenceID = sentence.id
                }
                Button("현재 재생 위치에서 분할") {
                    let split = min(max(player.currentTime, sentence.startTime), sentence.endTime)
                    analyzer.splitSentence(at: index, splitTime: split)
                }
                Button("다음 문장과 병합") {
                    analyzer.mergeWithNext(at: index)
                }
                Button("이 문장 앞에 구간 추가") {
                    analyzer.insertSentence(before: index)
                }
                Button("이 문장 뒤에 구간 추가") {
                    analyzer.insertSentence(after: index)
                }
            }
        }
    }

    private func handleSentenceIconTap(_ sentence: SentenceSegment, isEditingMode: Bool) {
        if isEditingMode {
            // 편집 모드일 때 아이콘(트레이 모양)을 누르면 현재 player의 범위를 문장에 저장
            saveEditedRangeOnEditingMode(for: sentence)
            
            // 저장이 완료되었음을 알리는 피드백 (선택 사항)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // 편집 모드를 종료하고 싶다면 아래 주석을 해제하세요
            // analyzer.isRangeEditing = false
            // editingSentenceID = nil
        } else {
            // 일반 모드일 때는 기존처럼 구간 반복 재생
            playSentenceLoopInNormalMode(sentence)
        }
    }

    private func handleSentenceContentTap(_ sentence: SentenceSegment, isEditingMode: Bool) {
        if isEditingMode {
            selectSentenceForEditing(sentence)
        } else {
            playSentenceLoopInNormalMode(sentence)
        }
    }

    private func selectSentenceForEditing(_ sentence: SentenceSegment) {
        editingSentenceID = sentence.id
        activeEditingTargetID = sentence.id
        analyzer.editingSentenceID = sentence.id
        draftSentenceText = sentence.text
        player.loopStart = sentence.startTime
        player.loopEnd = sentence.endTime
        player.loopSectionEnabled = true
        player.isWaveformLoopSelection = false
        player.seek(to: sentence.startTime)
    }

    private func saveEditedRangeOnEditingMode(for sentence: SentenceSegment) {
        // 1. analyzer의 문장 배열에서 수정하려는 문장의 인덱스를 찾음
        guard let targetIndex = analyzer.sentences.firstIndex(where: { $0.id == sentence.id }) else { return }
        
        // 2. 모델이 'var'로 되어 있다면 이제 아래와 같이 직접 할당이 가능합니다.
        analyzer.sentences[targetIndex].startTime = player.loopStart
        analyzer.sentences[targetIndex].endTime = player.loopEnd
        analyzer.sentences[targetIndex].text = draftSentenceText // 여기서 에러가 났던 것이 해결됩니다.
        
        // 3. UI 업데이트를 위해 ID 및 상태 동기화
        editingSentenceID = sentence.id
        analyzer.editingSentenceID = sentence.id
        
        // 4. 저장 완료 피드백 (햅틱)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func playSentenceLoopInNormalMode(_ sentence: SentenceSegment) {
        player.loopStart = sentence.startTime
        player.loopEnd = sentence.endTime
        player.startSectionRepeat(repeatCount: 10)

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func startSentenceEditing(_ sentence: SentenceSegment, index: Int) {
        draftSentenceText = sentence.text
        editingSentenceID = sentence.id
        activeEditingTargetID = sentence.id
        player.loopStart = sentence.startTime
        player.loopEnd = sentence.endTime
        player.loopSectionEnabled = true
        analyzer.isRangeEditing = true
        analyzer.editingSentenceID = sentence.id
        player.seek(to: sentence.startTime)
    }

    // 문장 클릭 핸들러
    private func handleSentenceTap(_ sentence: SentenceSegment) {
        // 이전 호출부 호환용
        if analyzer.isRangeEditing, editingSentenceID != nil {
            saveEditedRangeOnEditingMode(for: sentence)
        } else {
            playSentenceLoopInNormalMode(sentence)
        }
    }

    private func saveEditedRangeForSentence(at index: Int) {
        analyzer.updateSentenceRange(
            at: index,
            start: player.loopStart,
            end: player.loopEnd
        )
    }

    private func formatTime(_ t: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func mosaicText(_ text: String) -> String {
        String(text.map { $0.isWhitespace ? $0 : "█" })
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



#Preview {
    ContentView()
}
