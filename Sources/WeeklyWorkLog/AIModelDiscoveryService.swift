import Foundation

struct AIModelDiscoveryService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func suggestedModels(for endpointText: String) -> [String] {
        guard isGeminiEndpoint(endpointText) else { return [] }
        return [
            "gemini-3.6-flash",
            "gemini-3.5-flash-lite",
            "gemini-2.5-flash",
            "gemini-2.5-pro"
        ]
    }

    func discover(
        endpointText: String,
        authentication: CustomAuthentication,
        apiKey: String
    ) async throws -> [String] {
        let cleanEndpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: cleanEndpoint),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw ModelDiscoveryError.invalidEndpoint
        }

        let isGemini = Self.isGeminiEndpoint(cleanEndpoint)
        guard let modelsEndpoint = Self.modelsEndpoint(from: endpoint, isGemini: isGemini) else {
            throw ModelDiscoveryError.invalidEndpoint
        }

        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if isGemini {
            guard !apiKey.isEmpty else { throw ModelDiscoveryError.missingAPIKey }
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        } else {
            Self.applyAuthentication(authentication, apiKey: apiKey, to: &request)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ModelDiscoveryError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelDiscoveryError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(ModelAPIErrorEnvelope.self, from: data)
            throw ModelDiscoveryError.api(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message
            )
        }

        let models: [String]
        if isGemini, let response = try? JSONDecoder().decode(GeminiModelList.self, from: data) {
            models = response.models
                .filter {
                    $0.supportedGenerationMethods.isEmpty
                        || $0.supportedGenerationMethods.contains("generateContent")
                }
                .map { model in
                    let baseModelID = model.baseModelId?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let baseModelID, !baseModelID.isEmpty {
                        return baseModelID
                    }
                    return model.name.replacingOccurrences(of: "models/", with: "")
                }
        } else if let response = try? JSONDecoder().decode(OpenAIModelList.self, from: data) {
            models = response.data.map(\.id)
        } else {
            throw ModelDiscoveryError.invalidResponse
        }

        let uniqueModels = Array(
            Set(models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        )
        .filter { !$0.isEmpty }
        .sorted()

        guard !uniqueModels.isEmpty else {
            throw ModelDiscoveryError.noModels
        }
        return uniqueModels
    }

    static func modelsEndpoint(from endpoint: URL, isGemini: Bool? = nil) -> URL? {
        let gemini = isGemini ?? isGeminiEndpoint(endpoint.absoluteString)
        if gemini {
            var components = URLComponents()
            components.scheme = endpoint.scheme
            components.host = endpoint.host
            components.port = endpoint.port
            components.path = "/v1beta/models"
            components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            return components.url
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var pathParts = components.path.split(separator: "/").map(String.init)
        if pathParts.last == "completions", pathParts.dropLast().last == "chat" {
            pathParts.removeLast(2)
        } else if pathParts.last == "responses" || pathParts.last == "models" {
            pathParts.removeLast()
        }
        pathParts.append("models")
        components.path = "/" + pathParts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func isGeminiEndpoint(_ endpointText: String) -> Bool {
        guard let url = URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return url.host?.lowercased() == "generativelanguage.googleapis.com"
    }

    private static func applyAuthentication(
        _ authentication: CustomAuthentication,
        apiKey: String,
        to request: inout URLRequest
    ) {
        switch authentication {
        case .bearer where !apiKey.isEmpty:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKey where !apiKey.isEmpty:
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        case .xAPIKey where !apiKey.isEmpty:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        case .none, .bearer, .apiKey, .xAPIKey:
            break
        }
    }
}

private struct OpenAIModelList: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private struct GeminiModelList: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
        let baseModelId: String?
        let supportedGenerationMethods: [String]

        private enum CodingKeys: String, CodingKey {
            case name
            case baseModelId
            case supportedGenerationMethods
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            baseModelId = try container.decodeIfPresent(String.self, forKey: .baseModelId)
            supportedGenerationMethods = try container.decodeIfPresent(
                [String].self,
                forKey: .supportedGenerationMethods
            ) ?? []
        }
    }
}

private struct ModelAPIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

enum ModelDiscoveryError: LocalizedError {
    case invalidEndpoint
    case missingAPIKey
    case network(String)
    case invalidResponse
    case api(statusCode: Int, message: String?)
    case noModels

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "无法根据当前地址找到模型列表接口。"
        case .missingAPIKey:
            "保存 API 密钥后即可获取账号可用的模型。"
        case .network(let detail):
            "获取模型失败：\(detail)"
        case .invalidResponse:
            "模型列表接口返回了无法识别的数据。"
        case .api(let statusCode, let message):
            message.map { "获取模型失败（\(statusCode)）：\($0)" }
                ?? "获取模型失败，服务返回状态码 \(statusCode)。"
        case .noModels:
            "接口没有返回可用于生成内容的模型。"
        }
    }
}
