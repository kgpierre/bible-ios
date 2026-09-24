import SwiftUI

/// Editorial navigation metadata, never included in Scripture, search, copy, or sharing.
enum BookDescriptions {
    // Matches the editorial eyebrow metadata in the pinned bundled chapter documents.
    static func eyebrow(for bookID: String) -> String {
        ["MAT", "MRK", "LUK", "JHN"].contains(bookID) ? String(localized: "THE GOSPEL ACCORDING TO") : String(localized: "THE BOOK OF")
    }

    static let values: [String: String] = [
        "GEN": String(localized: "Beginnings, the patriarchs, and God’s covenant."),
        "EXO": String(localized: "Deliverance from Egypt and the covenant at Sinai."),
        "LEV": String(localized: "Worship, holiness, and life under the law."),
        "NUM": String(localized: "Israel’s journey through the wilderness."),
        "DEU": String(localized: "Moses’ final addresses and the renewed covenant."),
        "JOS": String(localized: "Israel enters and settles the promised land."),
        "JDG": String(localized: "Israel’s judges and cycles of deliverance."),
        "RUT": String(localized: "A family story of loyalty and redemption."),
        "1SA": String(localized: "Samuel, Saul, and the rise of David."),
        "2SA": String(localized: "David’s reign and the kingdom of Israel."),
        "1KI": String(localized: "Solomon’s reign and a divided kingdom."),
        "2KI": String(localized: "The kingdoms of Israel and Judah, through exile."),
        "1CH": String(localized: "Israel’s genealogies and the reign of David."),
        "2CH": String(localized: "Judah’s kings and the history of the temple."),
        "EZR": String(localized: "Return from exile and rebuilding the temple."),
        "NEH": String(localized: "Rebuilding Jerusalem and renewing community life."),
        "EST": String(localized: "Esther and the preservation of her people."),
        "JOB": String(localized: "Suffering, faith, and the limits of human wisdom."),
        "PSA": String(localized: "Songs and prayers of praise, lament, and trust."),
        "PRO": String(localized: "Wisdom for daily life and relationships."),
        "ECC": String(localized: "Reflections on life, work, and meaning."),
        "SNG": String(localized: "Poetry celebrating love and longing."),
        "ISA": String(localized: "Prophecy of judgment, comfort, and restoration."),
        "JER": String(localized: "Prophecy to Judah before and during exile."),
        "LAM": String(localized: "Poems mourning the fall of Jerusalem."),
        "EZK": String(localized: "Visions of judgment and restoration in exile."),
        "DAN": String(localized: "Faith in exile and visions of kingdoms."),
        "HOS": String(localized: "Covenant faithfulness, judgment, and mercy."),
        "JOL": String(localized: "A call to repentance and promised restoration."),
        "AMO": String(localized: "Prophecy confronting injustice and empty worship."),
        "OBA": String(localized: "Judgment on Edom and hope for Zion."),
        "JON": String(localized: "A reluctant prophet and mercy for Nineveh."),
        "MIC": String(localized: "Justice, judgment, and hope for restoration."),
        "NAM": String(localized: "Prophecy concerning the fall of Nineveh."),
        "HAB": String(localized: "A prophet’s questions about injustice and faith."),
        "ZEP": String(localized: "The day of the Lord and renewed hope."),
        "HAG": String(localized: "A call to rebuild the temple."),
        "ZEC": String(localized: "Visions of restoration and a coming king."),
        "MAL": String(localized: "A call to faithful worship and covenant life."),
        "MAT": String(localized: "The life and teaching of Jesus, the Messiah."),
        "MRK": String(localized: "Jesus’ ministry, suffering, and resurrection."),
        "LUK": String(localized: "An account of Jesus’ life and saving work."),
        "JHN": String(localized: "Jesus’ signs, teaching, and identity."),
        "ACT": String(localized: "The early church and the spread of the gospel."),
        "ROM": String(localized: "Paul’s letter on faith, grace, and new life."),
        "1CO": String(localized: "A letter on worship, unity, and church life."),
        "2CO": String(localized: "Paul on ministry, reconciliation, and generosity."),
        "GAL": String(localized: "Faith, freedom, and life in the Spirit."),
        "EPH": String(localized: "Unity in Christ and the life of the church."),
        "PHP": String(localized: "Joy, humility, and perseverance in faith."),
        "COL": String(localized: "Christ’s supremacy and life in him."),
        "1TH": String(localized: "Encouragement in faith and hope."),
        "2TH": String(localized: "Steadfastness and the coming of the Lord."),
        "1TI": String(localized: "Guidance for leadership and church life."),
        "2TI": String(localized: "Encouragement to remain faithful in ministry."),
        "TIT": String(localized: "Church leadership and faithful living."),
        "PHM": String(localized: "A personal appeal concerning Onesimus."),
        "HEB": String(localized: "Christ’s priesthood and the call to perseverance."),
        "JAS": String(localized: "Practical wisdom about faith and action."),
        "1PE": String(localized: "Hope and faithful living amid suffering."),
        "2PE": String(localized: "Growth in faith and warnings against false teaching."),
        "1JN": String(localized: "Love, truth, and assurance of life in Christ."),
        "2JN": String(localized: "Walking in truth and love."),
        "3JN": String(localized: "Hospitality and support for fellow believers."),
        "JUD": String(localized: "An appeal to contend for the faith."),
        "REV": String(localized: "Visions of judgment, hope, and a new creation.")
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
