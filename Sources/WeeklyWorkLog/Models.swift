import Foundation

enum WorkStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case completed
    case inProgress
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completed: "已完成"
        case .inProgress: "进行中"
        case .blocked: "有阻塞"
        }
    }

    var symbolName: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .inProgress: "clock.fill"
        case .blocked: "exclamationmark.triangle.fill"
        }
    }
}

struct WorkEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var project: String
    var content: String
    var status: WorkStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        project: String = "",
        content: String,
        status: WorkStatus = .completed,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.project = project
        self.content = content
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum CachedReportSource: String, Codable, Sendable {
    case local
    case ai
}

struct CachedWeeklyReport: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var weekStart: Date
    var content: String
    var source: CachedReportSource
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        weekStart: Date,
        content: String,
        source: CachedReportSource,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.weekStart = WeekCalendar.startOfWeek(containing: weekStart)
        self.content = content
        self.source = source
        self.updatedAt = updatedAt
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var authorName = ""
    var teamName = ""
    var nextWeekPlan = ""
    var reportStyle: ReportStyle = .concise
    var customAPIEndpoint = ""
    var customModel = ""
    var customAPIKey = ""
    var customAPIFormat: CustomAPIFormat = .chatCompletions
    var customAuthentication: CustomAuthentication = .bearer
    var reportTone: AIReportTone = .professional
    var customAIInstructions = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case authorName
        case teamName
        case nextWeekPlan
        case reportStyle
        case customAPIEndpoint
        case customModel
        case customAPIKey
        case customAPIFormat
        case customAuthentication
        case reportTone
        case customAIInstructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        nextWeekPlan = try container.decodeIfPresent(String.self, forKey: .nextWeekPlan) ?? ""
        reportStyle = try container.decodeIfPresent(ReportStyle.self, forKey: .reportStyle) ?? .concise
        customAPIEndpoint = try container.decodeIfPresent(String.self, forKey: .customAPIEndpoint) ?? ""
        customModel = try container.decodeIfPresent(String.self, forKey: .customModel) ?? ""
        customAPIKey = try container.decodeIfPresent(String.self, forKey: .customAPIKey) ?? ""
        customAPIFormat = try container.decodeIfPresent(CustomAPIFormat.self, forKey: .customAPIFormat) ?? .chatCompletions
        customAuthentication = try container.decodeIfPresent(CustomAuthentication.self, forKey: .customAuthentication) ?? .bearer
        reportTone = try container.decodeIfPresent(AIReportTone.self, forKey: .reportTone) ?? .professional
        customAIInstructions = try container.decodeIfPresent(String.self, forKey: .customAIInstructions) ?? ""
    }
}

enum ReportStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case concise
    case byDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concise: "按项目汇总"
        case .byDay: "按日期汇总"
        }
    }
}

enum CustomAPIFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatCompletions
    case responses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatCompletions: "Chat Completions 兼容"
        case .responses: "Responses 兼容"
        }
    }
}

enum CustomAuthentication: String, Codable, CaseIterable, Identifiable, Sendable {
    case bearer
    case apiKey
    case xAPIKey
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bearer: "Authorization: Bearer"
        case .apiKey: "api-key"
        case .xAPIKey: "x-api-key"
        case .none: "无需认证"
        }
    }
}

enum AIReportTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case professional
    case resultsFocused
    case natural

    var id: String { rawValue }

    var title: String {
        switch self {
        case .professional: "专业简洁"
        case .resultsFocused: "突出成果"
        case .natural: "自然口吻"
        }
    }

    var promptDescription: String {
        switch self {
        case .professional:
            "使用专业、克制的书面表达，句子简洁，适合直接发给管理者。"
        case .resultsFocused:
            "优先突出已完成事项、产生的推进作用和后续动作，但不得杜撰成果数据。"
        case .natural:
            "使用自然流畅的第一人称工作总结语气，避免官话和机械罗列。"
        }
    }
}

enum WeekCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func startOfWeek(containing date: Date) -> Date {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return calendar.startOfDay(for: start)
    }

    static func endOfWeek(containing date: Date) -> Date {
        calendar.date(byAdding: .day, value: 6, to: startOfWeek(containing: date)) ?? date
    }

    static func days(inWeekContaining date: Date) -> [Date] {
        let start = startOfWeek(containing: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func isDate(_ date: Date, inWeekContaining weekDate: Date) -> Bool {
        guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek(containing: weekDate)) else {
            return false
        }
        let start = startOfWeek(containing: weekDate)
        return date >= start && date < nextWeek
    }

    static func displayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: startOfWeek(containing: date))) – \(formatter.string(from: endOfWeek(containing: date)))"
    }
}
