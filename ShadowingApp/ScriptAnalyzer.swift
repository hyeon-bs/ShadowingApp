import Foundation
import Speech
import Combine

@MainActor
final class ScriptAnalyzer: ObservableObject {

    @Published var sentences: [SentenceSegment] = []
    @Published var isAnalyzing = false
    @Published var failed = false

    private var recognitionTask: SFSpeechRecognitionTask?

    func analyze(url: URL, duration: Double) {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        failed = false
        sentences.removeAll()

        recognitionTask?.cancel()
        recognitionTask = nil

        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.isAnalyzing = false
                    self.failed = true
                    return
                }

                let localeID = Locale.preferredLanguages.first ?? "en-US"
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
                    self.isAnalyzing = false
                    self.failed = true
                    return
                }

                let request = SFSpeechURLRecognitionRequest(url: url)
                request.shouldReportPartialResults = false

                self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                    Task { @MainActor in
                        if let error {
                            print("Speech recognition error: \(error.localizedDescription)")
                            self.isAnalyzing = false
                            self.failed = true
                            self.recognitionTask = nil
                            return
                        }

                        if let result, result.isFinal {
                            self.sentences = self.makeSentences(from: result, duration: duration)
                            self.isAnalyzing = false
                            self.failed = false
                            self.recognitionTask = nil
                        }
                    }
                }
            }
        }
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

            if gap > 0.7 && !words.isEmpty {
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
                || words.count >= 12
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
