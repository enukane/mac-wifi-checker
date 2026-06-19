import Foundation

enum TestItemStatus: Equatable {
    case pending
    case running
    case pass(detail: String? = nil)
    case fail(detail: String? = nil)
    case skip
    case stopped

    var isTerminal: Bool {
        switch self {
        case .pass, .fail, .skip, .stopped: return true
        default: return false
        }
    }

    var displayText: String {
        switch self {
        case .pending:            return "—"
        case .running:            return "…"
        case .pass(let d):        return d ?? "✓"
        case .fail(let d):        return d.map { "✗ \($0)" } ?? "✗"
        case .skip:               return "—"
        case .stopped:            return "■"
        }
    }
}

enum TestStatus: Equatable {
    case idle
    case running(bssid: String, step: String)
    case stopped
    case complete
}
