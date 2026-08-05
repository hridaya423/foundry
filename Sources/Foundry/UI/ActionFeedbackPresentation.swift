import Foundation
import FoundryDomain

extension ActionFeedback {
    var symbolName: String {
        switch self {
        case .info:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .failure:
            "exclamationmark.triangle.fill"
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
