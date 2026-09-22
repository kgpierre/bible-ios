import SwiftUI

/// Editorial navigation metadata, never included in Scripture, search, copy, or sharing.
enum BookDescriptions {
    // Matches the editorial eyebrow metadata in the pinned bundled chapter documents.
    static func eyebrow(for bookID: String) -> String {
        ["MAT", "MRK", "LUK", "JHN"].contains(bookID) ? "THE GOSPEL ACCORDING TO" : "THE BOOK OF"
    }

    static let values: [String: String] = [
        "GEN": "Beginnings, the patriarchs, and God’s covenant.",
        "EXO": "Deliverance from Egypt and the covenant at Sinai.",
        "LEV": "Worship, holiness, and life under the law.",
        "NUM": "Israel’s journey through the wilderness.",
        "DEU": "Moses’ final addresses and the renewed covenant.",
        "JOS": "Israel enters and settles the promised land.",
        "JDG": "Israel’s judges and cycles of deliverance.",
        "RUT": "A family story of loyalty and redemption.",
        "1SA": "Samuel, Saul, and the rise of David.",
        "2SA": "David’s reign and the kingdom of Israel.",
        "1KI": "Solomon’s reign and a divided kingdom.",
        "2KI": "The kingdoms of Israel and Judah, through exile.",
        "1CH": "Israel’s genealogies and the reign of David.",
        "2CH": "Judah’s kings and the history of the temple.",
        "EZR": "Return from exile and rebuilding the temple.",
        "NEH": "Rebuilding Jerusalem and renewing community life.",
        "EST": "Esther and the preservation of her people.",
        "JOB": "Suffering, faith, and the limits of human wisdom.",
        "PSA": "Songs and prayers of praise, lament, and trust.",
        "PRO": "Wisdom for daily life and relationships.",
        "ECC": "Reflections on life, work, and meaning.",
        "SNG": "Poetry celebrating love and longing.",
        "ISA": "Prophecy of judgment, comfort, and restoration.",
        "JER": "Prophecy to Judah before and during exile.",
        "LAM": "Poems mourning the fall of Jerusalem.",
        "EZK": "Visions of judgment and restoration in exile.",
        "DAN": "Faith in exile and visions of kingdoms.",
        "HOS": "Covenant faithfulness, judgment, and mercy.",
        "JOL": "A call to repentance and promised restoration.",
        "AMO": "Prophecy confronting injustice and empty worship.",
        "OBA": "Judgment on Edom and hope for Zion.",
        "JON": "A reluctant prophet and mercy for Nineveh.",
        "MIC": "Justice, judgment, and hope for restoration.",
        "NAM": "Prophecy concerning the fall of Nineveh.",
        "HAB": "A prophet’s questions about injustice and faith.",
        "ZEP": "The day of the Lord and renewed hope.",
        "HAG": "A call to rebuild the temple.",
        "ZEC": "Visions of restoration and a coming king.",
        "MAL": "A call to faithful worship and covenant life.",
        "MAT": "The life and teaching of Jesus, the Messiah.",
        "MRK": "Jesus’ ministry, suffering, and resurrection.",
        "LUK": "An account of Jesus’ life and saving work.",
        "JHN": "Jesus’ signs, teaching, and identity.",
        "ACT": "The early church and the spread of the gospel.",
        "ROM": "Paul’s letter on faith, grace, and new life.",
        "1CO": "A letter on worship, unity, and church life.",
        "2CO": "Paul on ministry, reconciliation, and generosity.",
        "GAL": "Faith, freedom, and life in the Spirit.",
        "EPH": "Unity in Christ and the life of the church.",
        "PHP": "Joy, humility, and perseverance in faith.",
        "COL": "Christ’s supremacy and life in him.",
        "1TH": "Encouragement in faith and hope.",
        "2TH": "Steadfastness and the coming of the Lord.",
        "1TI": "Guidance for leadership and church life.",
        "2TI": "Encouragement to remain faithful in ministry.",
        "TIT": "Church leadership and faithful living.",
        "PHM": "A personal appeal concerning Onesimus.",
        "HEB": "Christ’s priesthood and the call to perseverance.",
        "JAS": "Practical wisdom about faith and action.",
        "1PE": "Hope and faithful living amid suffering.",
        "2PE": "Growth in faith and warnings against false teaching.",
        "1JN": "Love, truth, and assurance of life in Christ.",
        "2JN": "Walking in truth and love.",
        "3JN": "Hospitality and support for fellow believers.",
        "JUD": "An appeal to contend for the faith.",
        "REV": "Visions of judgment, hope, and a new creation."
    ]
}

struct BookRow: View {
    let book: BookSummary
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(book.name).font(.headline).foregroundStyle(Color(.readingPrimary))
                if let description = BookDescriptions.values[book.id] {
                    Text(description).font(.subheadline).foregroundStyle(Color(.readingSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(Color(.accent))
                    .accessibilityLabel("Current book")
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

struct TestamentPicker: View {
    @Binding var newTestament: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu).frame(minHeight: 44)
            } else {
                picker.pickerStyle(.segmented)
            }
        }
        .accessibilityIdentifier("testamentPicker")
    }
    private var picker: some View {
        Picker("Testament", selection: $newTestament) {
            Text("Old Testament").tag(false)
            Text("New Testament").tag(true)
        }
    }
}
