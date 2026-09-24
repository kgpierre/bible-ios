import Foundation

/// The installed corpus identity format is edition:book:chapter:verse.
/// Preserve unknown components; callers validate availability separately.
enum ScriptureID {
    static func chapter(containing verseID: String) -> String {
        verseID.split(separator: ":").dropLast().joined(separator: ":")
    }
}
