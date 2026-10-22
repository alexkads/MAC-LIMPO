import XCTest
@testable import MAC_LIMPO

final class CleaningCategoryTests: XCTestCase {
    /// O Clean All manda itens para a Lixeira; esvaziá-la na mesma passada
    /// apagava de vez o que tinha acabado de chegar.
    func testCleanAllLeavesTheTrashAlone() {
        let excluded = CleaningCategory.allCases.filter { !$0.includedInCleanAll }
        XCTAssertEqual(excluded, [.trash])
    }

    /// Toda categoria tem serviço — senão o card e o Clean All a pulariam em silêncio.
    func testEveryCategoryHasAService() {
        let registered = Set(CleaningServiceRegistry.shared.services.keys)
        XCTAssertEqual(registered, Set(CleaningCategory.allCases))
    }

    // MARK: - Confirmação

    private func message(_ categories: [CleaningCategory], aggressive: Bool = false) -> String {
        CleaningCategory.confirmationMessage(for: categories, sizeText: "1 GB", aggressiveMode: aggressive, dockerWipe: false)
    }

    func testEmptyingTheTrashSaysItIsPermanent() {
        let text = message([.trash])
        XCTAssertTrue(text.contains("for good"))
        XCTAssertFalse(text.contains("can be restored from there"))
    }

    func testCleanAllSaysTheTrashIsLeftForLater() {
        let cleanAll = CleaningCategory.allCases.filter(\.includedInCleanAll)
        XCTAssertTrue(message(cleanAll).contains("The Trash isn't emptied"))
        XCTAssertFalse(message([.docker]).contains("The Trash isn't emptied"))
    }

    func testTimeMachineWarningOnlyWithAggressiveSystemData() {
        XCTAssertTrue(message([.systemData], aggressive: true).contains("Time Machine"))
        XCTAssertFalse(message([.systemData]).contains("Time Machine"))
        XCTAssertFalse(message([.docker], aggressive: true).contains("Time Machine"))
    }
}
