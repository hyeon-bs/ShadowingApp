# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS shadowing (language learning) app where users import audio files, view auto-generated sentence-level scripts, and practice speaking by looping specific sentences. Built with SwiftUI, AVFoundation, and the Speech framework.

## Building and Running

This is a standard Xcode project with no external dependencies (no SPM, no CocoaPods).

```bash
open ShadowingApp.xcodeproj   # Open in Xcode
# Cmd+B to build, Cmd+R to run
```

- **Minimum deployment target:** iOS 26.2
- **Required permissions:** Microphone (`NSMicrophoneUsageDescription`), Speech Recognition
- No automated test suite; testing is manual on simulator or device.

To run on a real device, a valid development team (`8Q6TBKHQD5`) and code signing must be configured in Xcode.

## Architecture

Three core files carry all the logic:

### `AudioPlayerModel.swift`
`@MainActor ObservableObject` that owns all audio state. Key responsibilities:
- Playlist management (`tracks: [TrackItem]`)
- `AVAudioPlayer` playback with rate control (0.5x–2.0x)
- Section repeat (A-B loop): `loopStart`, `loopEnd`, `startSectionRepeat()`
- Waveform generation: reads PCM samples in background, publishes `waveformBars: [Float]` (60 bars)
- 50 ms `Timer` drives `currentTime` updates and loop boundary checks

### `ScriptAnalyzer.swift`
`@MainActor ObservableObject` that wraps `SFSpeechRecognizer` (en-US). Key responsibilities:
- `analyze(url:duration:)` — async, returns `[SentenceSegment]`
- Segmentation heuristics: 0.7s silence gap, punctuation boundaries, max 12 words/segment, min 0.25s/segment
- Text normalization: contraction correction, capitalization
- Segment editing: `splitSentence()`, `mergeWithNext()`, `updateSentenceText/Start/End()`

### `ContentView.swift`
All UI lives here (no separate view files). Four major views:

| View | Role |
|---|---|
| `ContentView` | Root; holds `@StateObject` for both models; owns navigation |
| `PlaylistView` | Track list; long-press for multi-select; bulk delete/repeat |
| `TrackDetailView` | Waveform + playback controls + speed selector; triggers `ScriptAnalyzer.analyze()` |
| `ScriptView` | Sentence list; tap row = toggle section repeat; edit mode for reorder/merge/split |

`ScriptAnalyzer` is instantiated inside `TrackDetailView` as `@StateObject`, so a fresh analyzer is created per track. `AudioPlayerModel` is created once in `ContentView` and passed down.

## Key Data Flow

```
File picker → AudioPlayerModel.addTrack()
    → TrackDetailView appears → ScriptAnalyzer.analyze() fires
    → SentenceSegment array published
    → ScriptView lists sentences
    → User taps sentence → AudioPlayerModel.startSectionRepeat(start:end:)
    → Timer fires every 50ms → currentTime published → sentence row highlighted green
```

## Conventions

- All published state mutations happen on `@MainActor`. Background work (waveform PCM, speech recognition callbacks) uses `Task { await MainActor.run { } }`.
- `SentenceSegment` is the shared model type between `ScriptAnalyzer` and `ScriptView` — changes to its shape affect both.
- The waveform is computed once per track selection and cached in `AudioPlayerModel.waveformBars`. It is not recomputed unless the track changes.
- There is no data persistence yet. All playlist and script data is in-memory only and lost on app restart.
