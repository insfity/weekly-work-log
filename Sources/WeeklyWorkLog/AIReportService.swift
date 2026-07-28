import Foundation

struct CustomAIReportService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(
        entries: [WorkEntry],
        weekDate: Date,
        settings: AppSettings,
        apiKey: String
    ) async throws -> String {
        let weeklyEntries = entries.filter {
            WeekCalendar.isDate($0.date, inWeekContaining: weekDate)
        }
        guard !weeklyEntries.isEmpty else {
            throw AIReportError.noEntries
        }

        let endpointText = settings.customAPIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: endpointText),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw AIReportError.invalidEndpoint
        }
        let model = settings.customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIReportError.missingModel
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        switch settings.customAuthentication {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKey:
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        case .xAPIKey:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        case .none:
            break
        }

        let instructions = AIReportPromptBuilder.instructions(settings: settings)
        let input = AIReportPromptBuilder.input(
            entries: weeklyEntries,
            weekDate: weekDate,
            settings: settings
        )
        switch settings.customAPIFormat {
        case .chatCompletions:
            request.httpBody = try JSONEncoder().encode(
                ChatCompletionsRequest(
                    model: model,
                    messages: [
                        .init(role: "system", content: instructions),
                        .init(role: "user", content: input)
                    ],
                    stream: false
                )
            )
        case .responses:
            request.httpBody = try JSONEncoder().encode(
                ResponsesRequest(
                    model: model,
                    instructions: instructions,
                    input: input,
                    store: false
                )
            )
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIReportError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIReportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw AIReportError.api(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message
            )
        }

        let text = Self.extractText(from: data)
        guard !text.isEmpty else {
            throw AIReportError.emptyResponse
        }
        return text + "\n"
    }

    private static func extractText(from data: Data) -> String {
        if let chat = try? JSONDecoder().decode(ChatCompletionsResponse.self, from: data) {
            let content = chat.choices
                .compactMap(\.message.content)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                return content
            }
        }

        if let responses = try? JSONDecoder().decode(ResponsesResponse.self, from: data) {
            return responses.output
                .flatMap(\.content)
                .filter { $0.type == "output_text" }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

}

enum AIReportPromptBuilder {
    static func instructions(settings: AppSettings) -> String {
        var instructions = """
        你是一名严谨的中文工作周报编辑。用户会提供一周内零散、简短、可能只有几个词的工作记录。
        请理解这些记录之间的关联，将它们自然扩写成一份简短周报，而不是逐条机械拼接。

        输出要求：
        - 使用 Markdown，包含标题“# 工作周报”和 2 至 4 个简短段落。
        - 用连续、自然的文字概括本周重点、推进情况、进行中事项或阻塞；必要时使用简短小标题。
        - 保留原始记录中的项目名、状态和事实，不遗漏重要事项。
        - 可以补充自然的连接词和工作目的层面的概括，但绝对不要虚构数字、完成效果、业务结果、时间、人物、决策或原记录未提供的事实。
        - 对语义不明确的关键词采用保守表达，不擅自猜测具体含义。
        - 如果用户提供了下周计划，必须在周报末尾加入“## 下周计划”小标题，并将计划自然整理成一个简短段落；不得遗漏、改变原意或虚构额外计划。
        - 如果用户没有提供下周计划，不要生成“下周计划”章节，也不要自行补充计划。
        - 不要解释写作过程，不要输出免责声明。
        - \(settings.reportTone.promptDescription)
        """

        let custom = settings.customAIInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            instructions += "\n- 用户的额外写作要求：\(custom)"
        }
        return instructions
    }

    static func input(entries: [WorkEntry], weekDate: Date, settings: AppSettings) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "M月d日 EEEE"

        let sorted = entries.sorted {
            if WeekCalendar.calendar.isDate($0.date, inSameDayAs: $1.date) {
                return $0.createdAt < $1.createdAt
            }
            return $0.date < $1.date
        }
        let records = sorted.map { entry in
            let project = entry.project.isEmpty ? "未分类" : entry.project
            return "- \(dateFormatter.string(from: entry.date))｜\(project)｜\(entry.status.title)：\(entry.content)"
        }.joined(separator: "\n")

        let author = settings.authorName.isEmpty ? "未填写" : settings.authorName
        let team = settings.teamName.isEmpty ? "未填写" : settings.teamName
        let plan = settings.nextWeekPlan.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        周期：\(WeekCalendar.displayTitle(for: weekDate))
        姓名：\(author)
        团队：\(team)

        原始工作记录：
        \(records)

        下周计划：
        \(plan.isEmpty ? "未提供" : plan)
        """
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let store: Bool
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct ResponsesResponse: Decodable {
    let output: [OutputItem]

    struct OutputItem: Decodable {
        let content: [ContentItem]

        private enum CodingKeys: String, CodingKey {
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            content = try container.decodeIfPresent([ContentItem].self, forKey: .content) ?? []
        }
    }

    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

enum AIReportError: LocalizedError {
    case noEntries
    case invalidEndpoint
    case missingModel
    case network(String)
    case invalidResponse
    case api(statusCode: Int, message: String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noEntries:
            return "本周还没有工作记录，无法生成智能周报。"
        case .invalidEndpoint:
            return "请填写以 https:// 或 http:// 开头的完整 API 地址。"
        case .missingModel:
            return "请填写第三方服务使用的模型名称。"
        case .network(let detail):
            return "网络连接失败：\(detail)"
        case .invalidResponse:
            return "服务返回了无法识别的响应。"
        case .api(let statusCode, let message):
            if statusCode == 401 {
                return "API 密钥无效或认证方式不正确，请检查“周报设置”。"
            }
            if statusCode == 429 {
                return "请求过于频繁或账户额度不足，请稍后再试。"
            }
            return message.map { "生成失败（\(statusCode)）：\($0)" }
                ?? "生成失败，服务返回状态码 \(statusCode)。"
        case .emptyResponse:
            return "模型没有返回可用的周报内容，请重试。"
        }
    }
}
