import Foundation

enum PersistenceManager {

    // MARK: - Directories

    private static var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowingApp", isDirectory: true)
    }

    static var audioDir: URL {
        appSupportDir.appendingPathComponent("audio", isDirectory: true)
    }

    private static var scriptsDir: URL {
        appSupportDir.appendingPathComponent("scripts", isDirectory: true)
    }

    static func ensureDirectoriesExist() {
        let fm = FileManager.default
        for dir in [appSupportDir, audioDir, scriptsDir] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Audio Files

    static func copyAudioToPermanentStorage(from sourceURL: URL, trackID: UUID, fileName: String) -> URL? {
        ensureDirectoriesExist()
        let dest = audioDir.appendingPathComponent("\(trackID.uuidString)_\(fileName)")
        try? FileManager.default.copyItem(at: sourceURL, to: dest)
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    static func deleteAudio(trackID: UUID, fileName: String) {
        let path = audioDir.appendingPathComponent("\(trackID.uuidString)_\(fileName)")
        try? FileManager.default.removeItem(at: path)
    }

    static func audioURL(trackID: UUID, fileName: String) -> URL {
        audioDir.appendingPathComponent("\(trackID.uuidString)_\(fileName)")
    }

    // MARK: - Playlist

    private static var playlistURL: URL {
        appSupportDir.appendingPathComponent("playlist.json")
    }

    static func savePlaylist(_ tracks: [TrackItem]) {
        ensureDirectoriesExist()
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: playlistURL, options: .atomic)
    }

    static func loadPlaylist() -> [TrackItem] {
        guard let data = try? Data(contentsOf: playlistURL),
              let tracks = try? JSONDecoder().decode([TrackItem].self, from: data) else {
            return []
        }
        // 오디오 파일이 실제로 존재하는 트랙만 반환
        return tracks.filter { track in
            let url = audioURL(trackID: track.id, fileName: track.name)
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    // MARK: - Scripts (per-track)

    static func saveSentences(_ sentences: [SentenceSegment], forTrackID trackID: UUID) {
        ensureDirectoriesExist()
        let url = scriptsDir.appendingPathComponent("\(trackID.uuidString).json")
        guard let data = try? JSONEncoder().encode(sentences) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadSentences(forTrackID trackID: UUID) -> [SentenceSegment]? {
        let url = scriptsDir.appendingPathComponent("\(trackID.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let sentences = try? JSONDecoder().decode([SentenceSegment].self, from: data) else {
            return nil
        }
        return sentences.isEmpty ? nil : sentences
    }

    static func deleteSentences(forTrackID trackID: UUID) {
        let url = scriptsDir.appendingPathComponent("\(trackID.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
