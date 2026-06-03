import Testing
@testable import TarteelClientCore

struct SurahCatalogTests {
    @Test func catalogIncludesEverySurahInQuranOrder() {
        #expect(SurahCatalog.all.count == 114)
        #expect(SurahCatalog.all.first?.id == 1)
        #expect(SurahCatalog.all.last?.id == 114)
    }

    @Test func catalogIncludesNamesAndVerseCountsForSelector() throws {
        let anNisa = try #require(SurahCatalog.surah(id: 4))
        #expect(anNisa.nameSimple == "An-Nisa")
        #expect(anNisa.nameArabic == "النساء")
        #expect(anNisa.versesCount == 176)

        let alKawthar = try #require(SurahCatalog.surah(id: 108))
        #expect(alKawthar.nameSimple == "Al-Kawthar")
        #expect(alKawthar.nameArabic == "الكوثر")
        #expect(alKawthar.versesCount == 3)
        #expect(alKawthar.displayName == "108. الكوثر - Al-Kawthar")
    }

    @Test func searchMatchesSurahNamesAndExactSelections() {
        #expect(SurahCatalog.matchingSurahs(for: "kawthar").map(\.id) == [108])
        #expect(SurahCatalog.matchingSurahs(for: "الكوثر").map(\.id) == [108])
        #expect(SurahCatalog.matchingSurahs(for: "108").map(\.id) == [108])
        #expect(SurahCatalog.matchingSurahs(for: "missing").isEmpty)

        #expect(SurahCatalog.exactSelectionID(for: "108") == 108)
        #expect(SurahCatalog.exactSelectionID(for: "Al-Kawthar") == 108)
        #expect(SurahCatalog.exactSelectionID(for: "الكوثر") == 108)
        #expect(SurahCatalog.exactSelectionID(for: "Al") == nil)
        #expect(SurahCatalog.selectionID(for: "kawthar") == 108)
        #expect(SurahCatalog.selectionID(for: "Al") == nil)
    }
}
