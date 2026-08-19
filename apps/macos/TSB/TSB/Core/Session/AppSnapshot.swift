import Foundation

struct AppSnapshot: Equatable, Sendable {
    let status: SessionStatus
    let elapsedMilliseconds: Int
    let previewText: String
    let message: String?
}
