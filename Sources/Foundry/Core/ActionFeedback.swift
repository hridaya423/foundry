import Foundation

enum ActionFeedback: Equatable, Sendable {
    case info(String)
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case let .info(message), let .success(message), let .failure(message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    var displayDuration: Duration {
        switch self {
        case .failure:
            .seconds(5)
        case .info, .success:
            .seconds(2.2)
        }
    }
}
