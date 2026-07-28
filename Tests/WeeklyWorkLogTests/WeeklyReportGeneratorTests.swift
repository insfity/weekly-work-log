import Foundation
import Testing
@testable import WeeklyWorkLog

struct WeeklyReportGeneratorTests {
    private let monday = makeDate(2026, 7, 20)

    @Test func filtersEntriesOutsideSelectedWeek() {
        let entries = [
            WorkEntry(date: makeDate(2026, 7, 20), project: "客户端", content: "完成登录页", status: .completed),
            WorkEntry(date: makeDate(2026, 7, 26), project: "客户端", content: "修复崩溃", status: .blocked),
            WorkEntry(date: makeDate(2026, 7, 27), project: "下周", content: "不应出现", status: .inProgress)
        ]

        let report = WeeklyReportGenerator.generate(
            entries: entries,
            weekContaining: monday,
            settings: AppSettings()
        )

        #expect(report.contains("完成登录页"))
        #expect(report.contains("修复崩溃"))
        #expect(!report.contains("不应出现"))
        #expect(report.contains("已完成：1 项"))
        #expect(report.contains("有阻塞：1 项"))
    }

    @Test func groupsConciseReportByProject() {
        let entries = [
            WorkEntry(date: monday, project: "网站", content: "实现首页"),
            WorkEntry(date: monday, project: "", content: "参加例会")
        ]
        var settings = AppSettings()
        settings.authorName = "小林"
        settings.teamName = "产品研发"

        let report = WeeklyReportGenerator.generate(
            entries: entries,
            weekContaining: monday,
            settings: settings
        )

        #expect(report.contains("小林 · 产品研发"))
        #expect(report.contains("### 网站"))
        #expect(report.contains("### 其他工作"))
    }

    @Test func canGroupReportByDay() {
        var settings = AppSettings()
        settings.reportStyle = .byDay
        let report = WeeklyReportGenerator.generate(
            entries: [WorkEntry(date: monday, project: "API", content: "完成接口")],
            weekContaining: monday,
            settings: settings
        )

        #expect(report.contains("7月20日"))
        #expect(report.contains("【API】完成接口"))
    }

    @Test func smartPromptPreservesRawKeywordsAndPreventsFabrication() {
        var settings = AppSettings()
        settings.reportTone = .natural
        settings.customAIInstructions = "突出协作"
        settings.nextWeekPlan = "完成客户端验收，并整理上线清单"
        let entries = [
            WorkEntry(date: monday, project: "客户端", content: "登录页 联调 修复")
        ]

        let instructions = AIReportPromptBuilder.instructions(settings: settings)
        let input = AIReportPromptBuilder.input(
            entries: entries,
            weekDate: monday,
            settings: settings
        )

        #expect(instructions.contains("绝对不要虚构"))
        #expect(instructions.contains("突出协作"))
        #expect(instructions.contains("必须在周报末尾加入“## 下周计划”"))
        #expect(input.contains("客户端"))
        #expect(input.contains("登录页 联调 修复"))
        #expect(input.contains("完成客户端验收，并整理上线清单"))
    }

    @Test func smartPromptOmitsEmptyNextWeekPlan() {
        let settings = AppSettings()
        let input = AIReportPromptBuilder.input(
            entries: [WorkEntry(date: monday, content: "整理需求")],
            weekDate: monday,
            settings: settings
        )

        #expect(input.contains("下周计划：\n未提供"))
        #expect(AIReportPromptBuilder.instructions(settings: settings).contains("不要生成“下周计划”章节"))
    }

    @Test func settingsDecodeOlderDataWithoutCustomAPIFields() throws {
        let oldJSON = """
        {
          "authorName": "小林",
          "teamName": "研发",
          "nextWeekPlan": "",
          "reportStyle": "concise"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(oldJSON.utf8))

        #expect(settings.authorName == "小林")
        #expect(settings.customAPIEndpoint.isEmpty)
        #expect(settings.customAPIKey.isEmpty)
        #expect(settings.customAPIFormat == .chatCompletions)
    }

    @Test func locallyStoredAPIKeyRoundTripsWithSettings() throws {
        var settings = AppSettings()
        settings.customAPIKey = "local-test-key"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.customAPIKey == "local-test-key")
    }

    @Test func customChatCompletionsEndpointIsCalledAndParsed() async throws {
        var settings = AppSettings()
        settings.customAPIEndpoint = "http://localhost/v1/chat/completions"
        settings.customModel = "third-party-model"
        settings.customAPIFormat = .chatCompletions
        settings.customAuthentication = .bearer

        URLProtocolStub.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                """
                {"choices":[{"message":{"content":"# 工作周报\\n\\n本周完成了客户端联调工作。"}}]}
                """.utf8
            )
            return (response, data)
        }
        defer { URLProtocolStub.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let service = CustomAIReportService(session: URLSession(configuration: configuration))
        let result = try await service.generate(
            entries: [WorkEntry(date: monday, project: "客户端", content: "联调")],
            weekDate: monday,
            settings: settings,
            apiKey: "test-key"
        )

        #expect(result.contains("本周完成了客户端联调工作"))
    }

    @Test @MainActor func clearReportsPreservesEntriesAndClearAllPreservesSettings() {
        let storageURL = temporaryStorageURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }

        let store = WorkStore(storageURL: storageURL)
        store.settings.authorName = "Matthias"
        store.add(
            date: makeDate(2026, 7, 28),
            project: "客户端",
            content: "完成清理功能",
            status: .completed
        )
        store.cacheReport("本周完成了清理功能。", for: makeDate(2026, 7, 28), source: .ai)

        store.clearReports()

        #expect(store.entries.count == 1)
        #expect(store.cachedReports.isEmpty)

        store.cacheReport("重新生成的周报", for: makeDate(2026, 7, 28), source: .local)
        store.clearAllContent()

        #expect(store.entries.isEmpty)
        #expect(store.cachedReports.isEmpty)
        #expect(store.settings.authorName == "Matthias")
    }

    @Test @MainActor func cleanupKeepsFourReportWeeksAndTenEntryWeeks() {
        let storageURL = temporaryStorageURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }

        let store = WorkStore(storageURL: storageURL)
        let currentWeek = WeekCalendar.startOfWeek(containing: makeDate(2026, 7, 28))
        let entryKeepDate = WeekCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: -9,
            to: currentWeek
        )!
        let entryDeleteDate = WeekCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: -10,
            to: currentWeek
        )!
        let reportKeepDate = WeekCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: -3,
            to: currentWeek
        )!
        let reportDeleteDate = WeekCalendar.calendar.date(
            byAdding: .weekOfYear,
            value: -4,
            to: currentWeek
        )!

        store.add(date: entryKeepDate, project: "", content: "应保留的工作记录", status: .completed)
        store.add(date: entryDeleteDate, project: "", content: "应删除的工作记录", status: .completed)
        store.cacheReport("应保留的周报", for: reportKeepDate, source: .local)
        store.cacheReport("应删除的周报", for: reportDeleteDate, source: .ai)

        store.cleanupExpiredContent(referenceDate: currentWeek)

        #expect(store.entries.map(\.content) == ["应保留的工作记录"])
        #expect(store.cachedReports.map(\.content) == ["应保留的周报"])
    }

    @Test @MainActor func cachedReportPersistsAcrossStoreInstances() {
        let storageURL = temporaryStorageURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }

        let week = makeDate(2026, 7, 28)
        let firstStore = WorkStore(storageURL: storageURL)
        firstStore.cacheReport("已编辑的周报内容", for: week, source: .ai)

        let reloadedStore = WorkStore(storageURL: storageURL)
        let report = reloadedStore.cachedReport(for: week)

        #expect(report?.content == "已编辑的周报内容")
        #expect(report?.source == .ai)
    }

    @Test func derivesModelsEndpointFromChatCompletionsAddress() throws {
        let endpoint = try #require(URL(string: "https://example.com/v1/chat/completions"))
        let modelsEndpoint = AIModelDiscoveryService.modelsEndpoint(from: endpoint)

        #expect(modelsEndpoint?.absoluteString == "https://example.com/v1/models")
    }

    @Test func geminiModelsCanBeDiscoveredAndFiltered() async throws {
        ModelURLProtocolStub.requestHandler = { request in
            #expect(request.url?.path == "/v1beta/models")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")

            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                """
                {
                  "models": [
                    {
                      "name": "models/gemini-test-flash-001",
                      "baseModelId": "gemini-test-flash",
                      "supportedGenerationMethods": ["generateContent"]
                    },
                    {
                      "name": "models/text-embedding-test",
                      "baseModelId": "text-embedding-test",
                      "supportedGenerationMethods": ["embedContent"]
                    }
                  ]
                }
                """.utf8
            )
            return (response, data)
        }
        defer { ModelURLProtocolStub.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelURLProtocolStub.self]
        let service = AIModelDiscoveryService(session: URLSession(configuration: configuration))
        let models = try await service.discover(
            endpointText: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            authentication: .bearer,
            apiKey: "gemini-key"
        )

        #expect(models == ["gemini-test-flash"])
    }
}

private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.calendar = WeekCalendar.calendar
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    return components.date!
}

private func temporaryStorageURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeeklyWorkLogTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("worklog.json")
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ModelURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
