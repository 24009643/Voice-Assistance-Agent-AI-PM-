import XCTest
@testable import ParaformerProbe

final class OnlineRecognizerStateTests: XCTestCase {
    func testChangedPartialsAreEmittedInOrder() {
        var state = OnlineRecognizerState()

        XCTAssertEqual(state.partial("你"), [.partial("你")])
        XCTAssertEqual(state.partial("你"), [])
        XCTAssertEqual(state.partial("你好"), [.partial("你好")])
    }

    func testEndpointFinalizesAndResetsBeforeNextUtterance() {
        var state = OnlineRecognizerState()

        XCTAssertEqual(state.partial("第一"), [.partial("第一")])
        XCTAssertEqual(state.endpoint("第一句"), [.final("第一句")])
        XCTAssertEqual(state.partial("第二"), [.partial("第二")])
    }

    func testFinishKeepsTheFinalTail() {
        var state = OnlineRecognizerState()

        XCTAssertEqual(state.partial("开始"), [.partial("开始")])
        XCTAssertEqual(state.finish("开始尾声"), [.final("开始尾声")])
    }

    func testCancelResetsThePreviousUtterance() {
        var state = OnlineRecognizerState()

        XCTAssertEqual(state.partial("旧会话"), [.partial("旧会话")])
        state.cancel()
        XCTAssertEqual(state.partial("新会话"), [.partial("新会话")])
    }

    func testEmptyInputDoesNotEmitAResult() {
        var state = OnlineRecognizerState()

        XCTAssertEqual(state.partial(""), [])
        XCTAssertEqual(state.endpoint(""), [])
        XCTAssertEqual(state.finish(""), [])
    }
}
