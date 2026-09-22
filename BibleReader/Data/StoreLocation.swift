import Foundation

enum StoreLocation {
    static func open() async throws -> BibleStore {
        try await Task.detached(priority: .userInitiated) {
            guard let corpus = Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite") else {
                throw StorageIssue.incompatibleCorpus
            }
            var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("ReaderData", isDirectory: true)
            #if DEBUG
            // Dedicated isolated test stores; never reset or delete the real user database.
            if let token = ProcessInfo.processInfo.environment["BIBLE_TEST_STORE"], let uuid = UUID(uuidString: token) {
                directory = directory.appendingPathComponent("Tests/\(uuid.uuidString)", isDirectory: true)
            }
            #endif
            return try BibleStore(corpusURL: corpus, userURL: directory.appendingPathComponent("User.sqlite"))
        }.value
    }
}
