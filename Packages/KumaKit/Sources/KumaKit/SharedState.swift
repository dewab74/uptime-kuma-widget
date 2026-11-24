import Foundation

/// What the menu bar app last learned, handed to the widget through a file in
/// the shared App Group container.
public struct SharedState: Codable, Sendable, Equatable {
    /// The last successful fetch. Kept through errors, so the widget can keep
    /// showing it (marked stale) while the server is unreachable.
    public var snapshot: StatusSnapshot?
    /// Why the latest attempt failed, or nil after a success.
    public var lastError: String?
    public var lastAttempt: Date?

    public init(snapshot: StatusSnapshot? = nil, lastError: String? = nil, lastAttempt: Date? = nil) {
        self.snapshot = snapshot
        self.lastError = lastError
        self.lastAttempt = lastAttempt
    }

    /// True when the snapshot is older than `limit` or the last attempt failed.
    public func isStale(at date: Date, limit: TimeInterval) -> Bool {
        guard let snapshot else { return true }
        return lastError != nil || date.timeIntervalSince(snapshot.fetchedAt) > limit
    }

    /// Whether the widget needs a redraw to show `self` instead of `old`.
    public func differsVisibly(from old: SharedState?) -> Bool {
        guard let old else { return true }
        return snapshot?.statusSignature != old.snapshot?.statusSignature
            || snapshot?.title != old.snapshot?.title
            || snapshot?.incident != old.snapshot?.incident
            || snapshot?.maintenance != old.snapshot?.maintenance
            || (lastError == nil) != (old.lastError == nil)
    }
}

/// Reads and writes `SharedState` as JSON in a directory both the app and the
/// widget can reach. Writes are atomic, so a reader never sees half a file.
public struct SharedStateStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appending(path: "state.json", directoryHint: .notDirectory)
    }

    /// The App Group container, or nil when the process is not entitled to it
    /// (an unsigned build).
    public init?(appGroup: String) {
        guard !appGroup.isEmpty,
            let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        self.init(directory: directory)
    }

    public func load() -> SharedState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(SharedState.self, from: data)
    }

    public func save(_ state: SharedState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
