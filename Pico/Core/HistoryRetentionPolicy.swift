import Foundation

public enum HistoryRetentionPolicy: String, Codable, CaseIterable, Sendable {
    case week
    case month
    case threeMonths
    case year
    case forever

    public func shouldDelete(createdAt: Date, isFavorite: Bool, now: Date = .now) -> Bool {
        guard !isFavorite, self != .forever else { return false }
        let days: Double = switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .year: 365
        case .forever: .infinity
        }
        return now.timeIntervalSince(createdAt) >= days * 86_400
    }
}

