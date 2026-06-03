import Foundation

public struct SurahMetadata: Identifiable, Hashable, Sendable {
    public let id: Int
    public let nameSimple: String
    public let nameArabic: String
    public let versesCount: Int

    public var displayName: String {
        "\(id). \(nameArabic) - \(nameSimple)"
    }

    public init(id: Int, nameSimple: String, nameArabic: String, versesCount: Int) {
        self.id = id
        self.nameSimple = nameSimple
        self.nameArabic = nameArabic
        self.versesCount = versesCount
    }
}

public enum SurahCatalog {
    public static let all: [SurahMetadata] = [
        SurahMetadata(id: 1, nameSimple: "Al-Fatihah", nameArabic: "الفاتحة", versesCount: 7),
        SurahMetadata(id: 2, nameSimple: "Al-Baqarah", nameArabic: "البقرة", versesCount: 286),
        SurahMetadata(id: 3, nameSimple: "Ali 'Imran", nameArabic: "آل عمران", versesCount: 200),
        SurahMetadata(id: 4, nameSimple: "An-Nisa", nameArabic: "النساء", versesCount: 176),
        SurahMetadata(id: 5, nameSimple: "Al-Ma'idah", nameArabic: "المائدة", versesCount: 120),
        SurahMetadata(id: 6, nameSimple: "Al-An'am", nameArabic: "الأنعام", versesCount: 165),
        SurahMetadata(id: 7, nameSimple: "Al-A'raf", nameArabic: "الأعراف", versesCount: 206),
        SurahMetadata(id: 8, nameSimple: "Al-Anfal", nameArabic: "الأنفال", versesCount: 75),
        SurahMetadata(id: 9, nameSimple: "At-Tawbah", nameArabic: "التوبة", versesCount: 129),
        SurahMetadata(id: 10, nameSimple: "Yunus", nameArabic: "يونس", versesCount: 109),
        SurahMetadata(id: 11, nameSimple: "Hud", nameArabic: "هود", versesCount: 123),
        SurahMetadata(id: 12, nameSimple: "Yusuf", nameArabic: "يوسف", versesCount: 111),
        SurahMetadata(id: 13, nameSimple: "Ar-Ra'd", nameArabic: "الرعد", versesCount: 43),
        SurahMetadata(id: 14, nameSimple: "Ibrahim", nameArabic: "ابراهيم", versesCount: 52),
        SurahMetadata(id: 15, nameSimple: "Al-Hijr", nameArabic: "الحجر", versesCount: 99),
        SurahMetadata(id: 16, nameSimple: "An-Nahl", nameArabic: "النحل", versesCount: 128),
        SurahMetadata(id: 17, nameSimple: "Al-Isra", nameArabic: "الإسراء", versesCount: 111),
        SurahMetadata(id: 18, nameSimple: "Al-Kahf", nameArabic: "الكهف", versesCount: 110),
        SurahMetadata(id: 19, nameSimple: "Maryam", nameArabic: "مريم", versesCount: 98),
        SurahMetadata(id: 20, nameSimple: "Taha", nameArabic: "طه", versesCount: 135),
        SurahMetadata(id: 21, nameSimple: "Al-Anbya", nameArabic: "الأنبياء", versesCount: 112),
        SurahMetadata(id: 22, nameSimple: "Al-Hajj", nameArabic: "الحج", versesCount: 78),
        SurahMetadata(id: 23, nameSimple: "Al-Mu'minun", nameArabic: "المؤمنون", versesCount: 118),
        SurahMetadata(id: 24, nameSimple: "An-Nur", nameArabic: "النور", versesCount: 64),
        SurahMetadata(id: 25, nameSimple: "Al-Furqan", nameArabic: "الفرقان", versesCount: 77),
        SurahMetadata(id: 26, nameSimple: "Ash-Shu'ara", nameArabic: "الشعراء", versesCount: 227),
        SurahMetadata(id: 27, nameSimple: "An-Naml", nameArabic: "النمل", versesCount: 93),
        SurahMetadata(id: 28, nameSimple: "Al-Qasas", nameArabic: "القصص", versesCount: 88),
        SurahMetadata(id: 29, nameSimple: "Al-'Ankabut", nameArabic: "العنكبوت", versesCount: 69),
        SurahMetadata(id: 30, nameSimple: "Ar-Rum", nameArabic: "الروم", versesCount: 60),
        SurahMetadata(id: 31, nameSimple: "Luqman", nameArabic: "لقمان", versesCount: 34),
        SurahMetadata(id: 32, nameSimple: "As-Sajdah", nameArabic: "السجدة", versesCount: 30),
        SurahMetadata(id: 33, nameSimple: "Al-Ahzab", nameArabic: "الأحزاب", versesCount: 73),
        SurahMetadata(id: 34, nameSimple: "Saba", nameArabic: "سبإ", versesCount: 54),
        SurahMetadata(id: 35, nameSimple: "Fatir", nameArabic: "فاطر", versesCount: 45),
        SurahMetadata(id: 36, nameSimple: "Ya-Sin", nameArabic: "يس", versesCount: 83),
        SurahMetadata(id: 37, nameSimple: "As-Saffat", nameArabic: "الصافات", versesCount: 182),
        SurahMetadata(id: 38, nameSimple: "Sad", nameArabic: "ص", versesCount: 88),
        SurahMetadata(id: 39, nameSimple: "Az-Zumar", nameArabic: "الزمر", versesCount: 75),
        SurahMetadata(id: 40, nameSimple: "Ghafir", nameArabic: "غافر", versesCount: 85),
        SurahMetadata(id: 41, nameSimple: "Fussilat", nameArabic: "فصلت", versesCount: 54),
        SurahMetadata(id: 42, nameSimple: "Ash-Shuraa", nameArabic: "الشورى", versesCount: 53),
        SurahMetadata(id: 43, nameSimple: "Az-Zukhruf", nameArabic: "الزخرف", versesCount: 89),
        SurahMetadata(id: 44, nameSimple: "Ad-Dukhan", nameArabic: "الدخان", versesCount: 59),
        SurahMetadata(id: 45, nameSimple: "Al-Jathiyah", nameArabic: "الجاثية", versesCount: 37),
        SurahMetadata(id: 46, nameSimple: "Al-Ahqaf", nameArabic: "الأحقاف", versesCount: 35),
        SurahMetadata(id: 47, nameSimple: "Muhammad", nameArabic: "محمد", versesCount: 38),
        SurahMetadata(id: 48, nameSimple: "Al-Fath", nameArabic: "الفتح", versesCount: 29),
        SurahMetadata(id: 49, nameSimple: "Al-Hujurat", nameArabic: "الحجرات", versesCount: 18),
        SurahMetadata(id: 50, nameSimple: "Qaf", nameArabic: "ق", versesCount: 45),
        SurahMetadata(id: 51, nameSimple: "Adh-Dhariyat", nameArabic: "الذاريات", versesCount: 60),
        SurahMetadata(id: 52, nameSimple: "At-Tur", nameArabic: "الطور", versesCount: 49),
        SurahMetadata(id: 53, nameSimple: "An-Najm", nameArabic: "النجم", versesCount: 62),
        SurahMetadata(id: 54, nameSimple: "Al-Qamar", nameArabic: "القمر", versesCount: 55),
        SurahMetadata(id: 55, nameSimple: "Ar-Rahman", nameArabic: "الرحمن", versesCount: 78),
        SurahMetadata(id: 56, nameSimple: "Al-Waqi'ah", nameArabic: "الواقعة", versesCount: 96),
        SurahMetadata(id: 57, nameSimple: "Al-Hadid", nameArabic: "الحديد", versesCount: 29),
        SurahMetadata(id: 58, nameSimple: "Al-Mujadila", nameArabic: "المجادلة", versesCount: 22),
        SurahMetadata(id: 59, nameSimple: "Al-Hashr", nameArabic: "الحشر", versesCount: 24),
        SurahMetadata(id: 60, nameSimple: "Al-Mumtahanah", nameArabic: "الممتحنة", versesCount: 13),
        SurahMetadata(id: 61, nameSimple: "As-Saf", nameArabic: "الصف", versesCount: 14),
        SurahMetadata(id: 62, nameSimple: "Al-Jumu'ah", nameArabic: "الجمعة", versesCount: 11),
        SurahMetadata(id: 63, nameSimple: "Al-Munafiqun", nameArabic: "المنافقون", versesCount: 11),
        SurahMetadata(id: 64, nameSimple: "At-Taghabun", nameArabic: "التغابن", versesCount: 18),
        SurahMetadata(id: 65, nameSimple: "At-Talaq", nameArabic: "الطلاق", versesCount: 12),
        SurahMetadata(id: 66, nameSimple: "At-Tahrim", nameArabic: "التحريم", versesCount: 12),
        SurahMetadata(id: 67, nameSimple: "Al-Mulk", nameArabic: "الملك", versesCount: 30),
        SurahMetadata(id: 68, nameSimple: "Al-Qalam", nameArabic: "القلم", versesCount: 52),
        SurahMetadata(id: 69, nameSimple: "Al-Haqqah", nameArabic: "الحاقة", versesCount: 52),
        SurahMetadata(id: 70, nameSimple: "Al-Ma'arij", nameArabic: "المعارج", versesCount: 44),
        SurahMetadata(id: 71, nameSimple: "Nuh", nameArabic: "نوح", versesCount: 28),
        SurahMetadata(id: 72, nameSimple: "Al-Jinn", nameArabic: "الجن", versesCount: 28),
        SurahMetadata(id: 73, nameSimple: "Al-Muzzammil", nameArabic: "المزمل", versesCount: 20),
        SurahMetadata(id: 74, nameSimple: "Al-Muddaththir", nameArabic: "المدثر", versesCount: 56),
        SurahMetadata(id: 75, nameSimple: "Al-Qiyamah", nameArabic: "القيامة", versesCount: 40),
        SurahMetadata(id: 76, nameSimple: "Al-Insan", nameArabic: "الانسان", versesCount: 31),
        SurahMetadata(id: 77, nameSimple: "Al-Mursalat", nameArabic: "المرسلات", versesCount: 50),
        SurahMetadata(id: 78, nameSimple: "An-Naba", nameArabic: "النبإ", versesCount: 40),
        SurahMetadata(id: 79, nameSimple: "An-Nazi'at", nameArabic: "النازعات", versesCount: 46),
        SurahMetadata(id: 80, nameSimple: "'Abasa", nameArabic: "عبس", versesCount: 42),
        SurahMetadata(id: 81, nameSimple: "At-Takwir", nameArabic: "التكوير", versesCount: 29),
        SurahMetadata(id: 82, nameSimple: "Al-Infitar", nameArabic: "الإنفطار", versesCount: 19),
        SurahMetadata(id: 83, nameSimple: "Al-Mutaffifin", nameArabic: "المطففين", versesCount: 36),
        SurahMetadata(id: 84, nameSimple: "Al-Inshiqaq", nameArabic: "الإنشقاق", versesCount: 25),
        SurahMetadata(id: 85, nameSimple: "Al-Buruj", nameArabic: "البروج", versesCount: 22),
        SurahMetadata(id: 86, nameSimple: "At-Tariq", nameArabic: "الطارق", versesCount: 17),
        SurahMetadata(id: 87, nameSimple: "Al-A'la", nameArabic: "الأعلى", versesCount: 19),
        SurahMetadata(id: 88, nameSimple: "Al-Ghashiyah", nameArabic: "الغاشية", versesCount: 26),
        SurahMetadata(id: 89, nameSimple: "Al-Fajr", nameArabic: "الفجر", versesCount: 30),
        SurahMetadata(id: 90, nameSimple: "Al-Balad", nameArabic: "البلد", versesCount: 20),
        SurahMetadata(id: 91, nameSimple: "Ash-Shams", nameArabic: "الشمس", versesCount: 15),
        SurahMetadata(id: 92, nameSimple: "Al-Layl", nameArabic: "الليل", versesCount: 21),
        SurahMetadata(id: 93, nameSimple: "Ad-Duhaa", nameArabic: "الضحى", versesCount: 11),
        SurahMetadata(id: 94, nameSimple: "Ash-Sharh", nameArabic: "الشرح", versesCount: 8),
        SurahMetadata(id: 95, nameSimple: "At-Tin", nameArabic: "التين", versesCount: 8),
        SurahMetadata(id: 96, nameSimple: "Al-'Alaq", nameArabic: "العلق", versesCount: 19),
        SurahMetadata(id: 97, nameSimple: "Al-Qadr", nameArabic: "القدر", versesCount: 5),
        SurahMetadata(id: 98, nameSimple: "Al-Bayyinah", nameArabic: "البينة", versesCount: 8),
        SurahMetadata(id: 99, nameSimple: "Az-Zalzalah", nameArabic: "الزلزلة", versesCount: 8),
        SurahMetadata(id: 100, nameSimple: "Al-'Adiyat", nameArabic: "العاديات", versesCount: 11),
        SurahMetadata(id: 101, nameSimple: "Al-Qari'ah", nameArabic: "القارعة", versesCount: 11),
        SurahMetadata(id: 102, nameSimple: "At-Takathur", nameArabic: "التكاثر", versesCount: 8),
        SurahMetadata(id: 103, nameSimple: "Al-'Asr", nameArabic: "العصر", versesCount: 3),
        SurahMetadata(id: 104, nameSimple: "Al-Humazah", nameArabic: "الهمزة", versesCount: 9),
        SurahMetadata(id: 105, nameSimple: "Al-Fil", nameArabic: "الفيل", versesCount: 5),
        SurahMetadata(id: 106, nameSimple: "Quraysh", nameArabic: "قريش", versesCount: 4),
        SurahMetadata(id: 107, nameSimple: "Al-Ma'un", nameArabic: "الماعون", versesCount: 7),
        SurahMetadata(id: 108, nameSimple: "Al-Kawthar", nameArabic: "الكوثر", versesCount: 3),
        SurahMetadata(id: 109, nameSimple: "Al-Kafirun", nameArabic: "الكافرون", versesCount: 6),
        SurahMetadata(id: 110, nameSimple: "An-Nasr", nameArabic: "النصر", versesCount: 3),
        SurahMetadata(id: 111, nameSimple: "Al-Masad", nameArabic: "المسد", versesCount: 5),
        SurahMetadata(id: 112, nameSimple: "Al-Ikhlas", nameArabic: "الإخلاص", versesCount: 4),
        SurahMetadata(id: 113, nameSimple: "Al-Falaq", nameArabic: "الفلق", versesCount: 5),
        SurahMetadata(id: 114, nameSimple: "An-Nas", nameArabic: "الناس", versesCount: 6)
    ]

    public static func surah(id: Int) -> SurahMetadata? {
        all.first { $0.id == id }
    }

    public static func matchingSurahs(for query: String) -> [SurahMetadata] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return all }

        if let id = Int(normalizedQuery) {
            return all.filter { $0.id == id }
        }

        return all.filter { surah in
            surah.nameSimple.localizedCaseInsensitiveContains(normalizedQuery)
                || surah.nameArabic.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public static func exactSelectionID(for query: String) -> Int? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return nil }

        if let id = Int(normalizedQuery), surah(id: id) != nil {
            return id
        }

        let exactMatches = all.filter { surah in
            surah.nameSimple.compare(
                normalizedQuery,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
                || surah.nameArabic == normalizedQuery
                || surah.displayName.compare(
                    normalizedQuery,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
        }
        return exactMatches.count == 1 ? exactMatches[0].id : nil
    }

    public static func selectionID(for query: String) -> Int? {
        if let exactSelectionID = exactSelectionID(for: query) {
            return exactSelectionID
        }

        let matches = matchingSurahs(for: query)
        return matches.count == 1 ? matches[0].id : nil
    }
}
