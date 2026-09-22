import Foundation

enum PrototypeLibrary {
    static func load() async throws -> [ChapterDocument] {
        #if DEBUG
        return try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "PrototypeChapters", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try JSONDecoder().decode([ChapterDocument].self, from: Data(contentsOf: url))
        }.value
        #else
        throw CocoaError(.fileNoSuchFile)
        #endif
    }
}
