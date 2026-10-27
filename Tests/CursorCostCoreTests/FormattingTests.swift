import CursorCostCore
import Foundation
import Testing

struct FormattingTests {
    @Test
    func dollars_givenFiniteAmount_thenUsesTwoDecimalsAndDollarSuffix() {
        let given = 3.791

        let then = Formatting.dollars(given)

        #expect(then == "3.79 $")
    }

    @Test
    func compactTokens_givenThousandsAndMillions_thenUsesKAndM() {
        let givenThousands = 64_800.0
        let givenMillions = 1_200_000.0

        let thenThousands = Formatting.compactTokens(givenThousands)
        let thenMillions = Formatting.compactTokens(givenMillions)

        #expect(thenThousands == "64.8k")
        #expect(thenMillions == "1.2M")
    }

    @Test
    func kind_givenUsageEventPrefix_thenHumanizesRemainder() {
        let given = "USAGE_EVENT_KIND_INCLUDED_IN_BUSINESS"

        let then = Formatting.kind(given)

        #expect(then == "Included In Business")
    }
}
