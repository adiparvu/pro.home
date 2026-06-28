import XCTest
@testable import PRVIO

final class PollTallyTests: XCTestCase {

    private func vote(_ user: UUID, _ option: Int) -> PollVote {
        PollVote(id: UUID(), messageId: UUID(), userId: user, voterName: "x", optionIndex: option)
    }

    func testCountsAndTotalVoters() {
        let u1 = UUID(), u2 = UUID(), u3 = UUID()
        // u1 -> 0 and 1 (multi), u2 -> 1, u3 -> 1
        let votes = [vote(u1, 0), vote(u2, 1), vote(u3, 1), vote(u1, 1)]

        XCTAssertEqual(PollTally.totalVoters(votes), 3)
        XCTAssertEqual(PollTally.count(votes, option: 0), 1)
        XCTAssertEqual(PollTally.count(votes, option: 1), 3)
        XCTAssertEqual(PollTally.count(votes, option: 2), 0)
    }

    func testDidVote() {
        let u1 = UUID(), u2 = UUID()
        let votes = [vote(u1, 0), vote(u2, 1)]
        XCTAssertTrue(PollTally.didVote(votes, option: 0, userId: u1))
        XCTAssertFalse(PollTally.didVote(votes, option: 1, userId: u1))
        XCTAssertFalse(PollTally.didVote(votes, option: 0, userId: nil))
    }

    func testFraction() {
        let u1 = UUID(), u2 = UUID()
        let votes = [vote(u1, 0), vote(u2, 1)]
        XCTAssertEqual(PollTally.fraction(votes, option: 0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PollTally.fraction(votes, option: 1), 0.5, accuracy: 0.0001)
    }

    func testEmpty() {
        XCTAssertEqual(PollTally.totalVoters([]), 0)
        XCTAssertEqual(PollTally.count([], option: 0), 0)
        XCTAssertEqual(PollTally.fraction([], option: 0), 0, accuracy: 0.0001)
        XCTAssertFalse(PollTally.didVote([], option: 0, userId: UUID()))
    }
}
