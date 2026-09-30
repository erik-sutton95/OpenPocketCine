import Foundation
import Testing

@testable import OpenPocketCineMacCore

struct MacTileAssignmentTests {
    @Test func addFillsTheFirstEmptySlotAndKeepsThePreviousCamera() {
        let first = UUID()
        let second = UUID()
        let once = MacTileBoard().adding(first)
        let twice = once?.adding(second)
        #expect(once?.cameraIDs == [first, nil, nil, nil])
        #expect(twice?.cameraIDs == [first, second, nil, nil])
    }

    @Test func duplicateIdentityIsRefused() {
        let camera = UUID()
        let once = MacTileBoard().adding(camera)
        #expect(once?.adding(camera) == nil)
        #expect(once?.cameraIDs == [camera, nil, nil, nil])
    }

    @Test func removeClearsOneSlot() {
        let first = UUID()
        let second = UUID()
        let board = MacTileBoard(cameraIDs: [first, second, nil, nil])
        #expect(board.removing(at: 0).cameraIDs == [nil, second, nil, nil])
    }

    @Test func fifthCameraIsRefused() {
        let ids = (0..<4).map { _ in UUID() }
        var board = MacTileBoard()
        for id in ids {
            board = board.adding(id)!
        }
        #expect(board.adding(UUID()) == nil)
        #expect(board.cameraIDs == ids)
    }
}
