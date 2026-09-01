import Foundation
import Speech
import Combine

@MainActor
final class ScriptAnalyzer: ObservableObject {

    @Published var sentences: [SentenceSegment] = []
    @Published var isAnalyzing = false
    @Published var failed = false
    @Published var isRangeEditing = false
    @Published var editingSentenceID: UUID?

    var currentTrackID: UUID?

    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func reset() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        isAnalyzing = false
        failed = false
        isRangeEditing = false
        editingSentenceID = nil
        currentTrackID = nil
        sentences.removeAll()
    }

    func loadSentences(forTrackID trackID: UUID) -> Bool {
        currentTrackID = trackID
        if let saved = PersistenceManager.loadSentences(forTrackID: trackID) {
            sentences = saved
            failed = false
            return true
        }
        return false
    }

    func saveSentencesIfNeeded() {
        guard let trackID = currentTrackID, !sentences.isEmpty else { return }
        PersistenceManager.saveSentences(sentences, forTrackID: trackID)
    }

    func splitSentence(at index: Int, splitTime: Double) {
        guard sentences.indices.contains(index) else { return }
        let current = sentences[index]
        let minChunk: Double = 0.25
        guard splitTime > current.startTime + minChunk, splitTime < current.endTime - minChunk else { return }

        let words = current.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)

        guard words.count >= 2 else { return }

        let ratio = (splitTime - current.startTime) / max(0.001, current.endTime - current.startTime)
        let rawCut = Int((Double(words.count) * ratio).rounded())
        let cutIndex = max(1, min(words.count - 1, rawCut))

        let leftText = normalizeSentenceText(words[..<cutIndex].joined(separator: " "))
        let rightText = normalizeSentenceText(words[cutIndex...].joined(separator: " "))

        let left = SentenceSegment(text: leftText, startTime: current.startTime, endTime: splitTime)
        let right = SentenceSegment(text: rightText, startTime: splitTime, endTime: current.endTime)

        sentences[index] = left
        sentences.insert(right, at: index + 1)
        saveSentencesIfNeeded()
    }

    func mergeWithNext(at index: Int) {
        guard sentences.indices.contains(index), sentences.indices.contains(index + 1) else { return }
        let first = sentences[index]
        let second = sentences[index + 1]

        let mergedText = normalizeSentenceText(
            first.text.replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
            + " "
            + second.text
        )

        let merged = SentenceSegment(
            text: mergedText,
            startTime: first.startTime,
            endTime: second.endTime
        )

        sentences[index] = merged
        sentences.remove(at: index + 1)
        saveSentencesIfNeeded()
    }

    func updateSentenceText(at index: Int, newText: String) {
        guard sentences.indices.contains(index) else { return }
        let normalized = normalizeSentenceText(newText)
        guard !normalized.isEmpty else { return }
        let current = sentences[index]
        sentences[index] = SentenceSegment(
            text: normalized,
            startTime: current.startTime,
            endTime: current.endTime
        )
        saveSentencesIfNeeded()
    }

    func addSentence(at time: Double, defaultDuration: Double = 1.5) {
        let start = max(0, time)
        let end = start + defaultDuration
        let newSegment = SentenceSegment(text: "New sentence.", startTime: start, endTime: end)

        if let index = sentenceIndex(containing: start) {
            sentences.insert(newSegment, at: index + 1)
        } else if let index = sentences.firstIndex(where: { $0.startTime > start }) {
            sentences.insert(newSegment, at: index)
        } else {
            sentences.append(newSegment)
        }
        saveSentencesIfNeeded()
    }

    func insertSentence(before index: Int, defaultDuration: Double = 1.0) {
        guard sentences.indices.contains(index) else { return }
        let anchor = sentences[index]
        let end = max(0, anchor.startTime)
        let start = max(0, end - defaultDuration)
        let segment = SentenceSegment(text: "New sentence.", startTime: start, endTime: end)
        sentences.insert(segment, at: index)
        saveSentencesIfNeeded()
    }

    func insertSentence(after index: Int, defaultDuration: Double = 1.0) {
        guard sentences.indices.contains(index) else { return }
        let anchor = sentences[index]
        let start = anchor.endTime
        let end = start + defaultDuration
        let segment = SentenceSegment(text: "New sentence.", startTime: start, endTime: end)
        sentences.insert(segment, at: index + 1)
        saveSentencesIfNeeded()
    }

    func updateSentenceStart(at index: Int, newStart: Double) {
        guard sentences.indices.contains(index) else { return }
        let current = sentences[index]
        let minimumDuration: Double = 0.25
        var adjusted = newStart

        if index > 0 {
            adjusted = max(adjusted, sentences[index - 1].endTime)
        } else {
            adjusted = max(0, adjusted)
        }
        adjusted = min(adjusted, current.endTime - minimumDuration)

        guard adjusted != current.startTime else { return }

        sentences[index] = SentenceSegment(
            text: current.text,
            startTime: adjusted,
            endTime: current.endTime
        )
        saveSentencesIfNeeded()
    }

    func updateSentenceEnd(at index: Int, newEnd: Double) {
        guard sentences.indices.contains(index) else { return }
        let current = sentences[index]
        let minimumDuration: Double = 0.25
        var adjusted = newEnd

        if index < sentences.count - 1 {
            adjusted = min(adjusted, sentences[index + 1].startTime)
        }
        adjusted = max(adjusted, current.startTime + minimumDuration)

        guard adjusted != current.endTime else { return }

        sentences[index] = SentenceSegment(
            text: current.text,
            startTime: current.startTime,
            endTime: adjusted
        )
        saveSentencesIfNeeded()
    }

    func sentenceIndex(containing time: Double) -> Int? {
        sentences.firstIndex { segment in
            time >= segment.startTime && time <= segment.endTime
        }
    }

    func updateSentenceRange(at index: Int, start: Double, end: Double) {
        guard sentences.indices.contains(index) else { return }
        let minimumDuration: Double = 0.25
        var newStart = min(start, end)
        var newEnd = max(start, end)

        if index > 0 {
            newStart = max(newStart, sentences[index - 1].endTime)
        } else {
            newStart = max(0, newStart)
        }

        if index < sentences.count - 1 {
            newEnd = min(newEnd, sentences[index + 1].startTime)
        }

        guard newEnd - newStart >= minimumDuration else { return }

        let current = sentences[index]
        sentences[index] = SentenceSegment(text: current.text, startTime: newStart, endTime: newEnd)
        saveSentencesIfNeeded()
    }

    func analyze(url: URL, duration: Double) {
        guard !isAnalyzing else { return }
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            failed = true
            return
        }

        isAnalyzing = true
        failed = false
        sentences.removeAll()

        recognitionTask?.cancel()
        recognitionTask = nil

        let startRecognition: () -> Void = {
            self.recognizer = self.makeAvailableRecognizer()
            guard let recognizer = self.recognizer else {
                self.isAnalyzing = false
                self.failed = true
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.addsPunctuation = true

            self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                Task { @MainActor in
                    if let error {
                        self.isAnalyzing = false
                        self.failed = true
                        self.recognitionTask = nil
                        return
                    }

                    if let result, result.isFinal {
                        let built = self.makeSentences(from: result, duration: duration)
                        self.sentences = built.map { segment in
                            SentenceSegment(
                                text: self.normalizeSentenceText(segment.text),
                                startTime: segment.startTime,
                                endTime: segment.endTime
                            )
                        }
                        self.isAnalyzing = false
                        self.failed = built.isEmpty
                        self.recognitionTask = nil
                        self.saveSentencesIfNeeded()
                    }
                }
            }
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            startRecognition()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    guard status == .authorized else {
                        self.isAnalyzing = false
                        self.failed = true
                        return
                    }
                    startRecognition()
                }
            }
        default:
            isAnalyzing = false
            failed = true
        }
    }

    private func makeAvailableRecognizer() -> SFSpeechRecognizer? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            return nil
        }
        return recognizer
    }

    private func normalizeSentenceText(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        let replacements: [String: String] = [
            " i ": " I ",
            " im ": " I'm ",
            " ive ": " I've ",
            " dont ": " don't ",
            " doesnt ": " doesn't ",
            " didnt ": " didn't ",
            " cant ": " can't ",
            " wont ": " won't ",
            " thats ": " that's ",
            " whats ": " what's ",
            " theres ": " there's ",
            " were ": " we're ",
            " youre ": " you're "
        ]

        text = " \(text) "
        for (wrong, corrected) in replacements {
            text = text.replacingOccurrences(of: wrong, with: corrected, options: [.caseInsensitive])
        }

        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = text.first {
            text.replaceSubrange(text.startIndex...text.startIndex, with: String(first).uppercased())
        }

        if let last = text.last, !".!?".contains(last) {
            text += "."
        }

        return text
    }

    private func makeSentences(
        from result: SFSpeechRecognitionResult,
        duration: Double
    ) -> [SentenceSegment] {

        let segments = result.bestTranscription.segments

        guard !segments.isEmpty else {
            return [
                SentenceSegment(
                    text: result.bestTranscription.formattedString,
                    startTime: 0,
                    endTime: duration
                )
            ]
        }

        var output: [SentenceSegment] = []

        var words: [String] = []
        var start = segments[0].timestamp
        var lastEnd = start

        for (index, seg) in segments.enumerated() {

            let end = seg.timestamp + seg.duration
            let gap = seg.timestamp - lastEnd
            let isLast = index == segments.count - 1

            if gap > 0.4 && !words.isEmpty {
                output.append(
                    SentenceSegment(
                        text: words.joined(separator: " "),
                        startTime: start,
                        endTime: lastEnd
                    )
                )
                words.removeAll()
                start = seg.timestamp
            }

            words.append(seg.substring)

            let token = seg.substring

            if token.hasSuffix(".")
                || token.hasSuffix("?")
                || token.hasSuffix("!")
                || words.count >= 8
                || isLast {

                output.append(
                    SentenceSegment(
                        text: words.joined(separator: " "),
                        startTime: start,
                        endTime: end
                    )
                )

                words.removeAll()
                start = end
            }

            lastEnd = end
        }

        return output
    }
}
