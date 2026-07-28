import Foundation
import SwiftUI

@MainActor
final class WorkStore: ObservableObject {
    @Published private(set) var entries: [WorkEntry] = []
    @Published private(set) var cachedReports: [CachedWeeklyReport] = []
    @Published var settings = AppSettings() {
        didSet { save() }
    }

    private let storageURL: URL
    private var hasLoaded = false

    private struct SavedData: Codable {
        var entries: [WorkEntry]
        var cachedReports: [CachedWeeklyReport]
        var settings: AppSettings

        private enum CodingKeys: String, CodingKey {
            case entries
            case cachedReports
            case settings
        }

        init(
            entries: [WorkEntry],
            cachedReports: [CachedWeeklyReport],
            settings: AppSettings
        ) {
            self.entries = entries
            self.cachedReports = cachedReports
            self.settings = settings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entries = try container.decodeIfPresent([WorkEntry].self, forKey: .entries) ?? []
            cachedReports = try container.decodeIfPresent(
                [CachedWeeklyReport].self,
                forKey: .cachedReports
            ) ?? []
            settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings)
                ?? AppSettings()
        }
    }

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
        hasLoaded = true
        cleanupExpiredContent()
    }

    func add(date: Date, project: String, content: String, status: WorkStatus) {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return }
        entries.append(
            WorkEntry(
                date: WeekCalendar.calendar.startOfDay(for: date),
                project: project.trimmingCharacters(in: .whitespacesAndNewlines),
                content: cleanContent,
                status: status
            )
        )
        sortEntries()
        save()
    }

    func update(_ entry: WorkEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.content = updated.content.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.project = updated.project.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.date = WeekCalendar.calendar.startOfDay(for: updated.date)
        updated.updatedAt = .now
        guard !updated.content.isEmpty else { return }
        entries[index] = updated
        sortEntries()
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func entries(on date: Date) -> [WorkEntry] {
        entries.filter { WeekCalendar.calendar.isDate($0.date, inSameDayAs: date) }
    }

    func entries(inWeekContaining date: Date) -> [WorkEntry] {
        entries.filter { WeekCalendar.isDate($0.date, inWeekContaining: date) }
    }

    func report(for weekDate: Date) -> String {
        WeeklyReportGenerator.generate(entries: entries, weekContaining: weekDate, settings: settings)
    }

    func cachedReport(for weekDate: Date) -> CachedWeeklyReport? {
        let weekStart = WeekCalendar.startOfWeek(containing: weekDate)
        return cachedReports.first { $0.weekStart == weekStart }
    }

    func cacheReport(
        _ content: String,
        for weekDate: Date,
        source: CachedReportSource
    ) {
        let weekStart = WeekCalendar.startOfWeek(containing: weekDate)
        if let index = cachedReports.firstIndex(where: { $0.weekStart == weekStart }) {
            cachedReports[index].content = content
            cachedReports[index].source = source
            cachedReports[index].updatedAt = .now
        } else {
            cachedReports.append(
                CachedWeeklyReport(
                    weekStart: weekStart,
                    content: content,
                    source: source
                )
            )
        }
        sortCachedReports()
        save()
    }

    func clearReports() {
        guard !cachedReports.isEmpty else { return }
        cachedReports.removeAll()
        save()
    }

    func clearAllContent() {
        guard !entries.isEmpty || !cachedReports.isEmpty else { return }
        entries.removeAll()
        cachedReports.removeAll()
        save()
    }

    func cleanupExpiredContent(referenceDate: Date = .now) {
        let currentWeek = WeekCalendar.startOfWeek(containing: referenceDate)
        guard
            let reportCutoff = WeekCalendar.calendar.date(
                byAdding: .weekOfYear,
                value: -3,
                to: currentWeek
            ),
            let entryCutoff = WeekCalendar.calendar.date(
                byAdding: .weekOfYear,
                value: -9,
                to: currentWeek
            )
        else {
            return
        }

        let entryCount = entries.count
        let reportCount = cachedReports.count
        entries.removeAll { $0.date < entryCutoff }
        cachedReports.removeAll { $0.weekStart < reportCutoff }

        if entries.count != entryCount || cachedReports.count != reportCount {
            save()
        }
    }

    private func sortEntries() {
        entries.sort {
            if WeekCalendar.calendar.isDate($0.date, inSameDayAs: $1.date) {
                return $0.createdAt < $1.createdAt
            }
            return $0.date > $1.date
        }
    }

    private func sortCachedReports() {
        cachedReports.sort { $0.weekStart > $1.weekStart }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let saved = try JSONDecoder.iso8601.decode(SavedData.self, from: data)
            entries = saved.entries
            cachedReports = saved.cachedReports.map {
                CachedWeeklyReport(
                    id: $0.id,
                    weekStart: $0.weekStart,
                    content: $0.content,
                    source: $0.source,
                    updatedAt: $0.updatedAt
                )
            }
            settings = saved.settings
            sortEntries()
            sortCachedReports()
        } catch {
            NSLog("无法读取工作记录：\(error.localizedDescription)")
        }
    }

    private func save() {
        guard hasLoaded else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.prettyPrinted.encode(
                SavedData(
                    entries: entries,
                    cachedReports: cachedReports,
                    settings: settings
                )
            )
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("无法保存工作记录：\(error.localizedDescription)")
        }
    }

    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("WeeklyWorkLog", isDirectory: true)
            .appendingPathComponent("worklog.json")
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
