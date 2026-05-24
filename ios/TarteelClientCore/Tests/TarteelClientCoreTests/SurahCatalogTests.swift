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
}
