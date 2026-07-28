import Foundation

enum WeeklyReportGenerator {
    static func generate(
        entries: [WorkEntry],
        weekContaining date: Date,
        settings: AppSettings
    ) -> String {
        let weeklyEntries = entries
            .filter { WeekCalendar.isDate($0.date, inWeekContaining: date) }
            .sorted {
                if WeekCalendar.calendar.isDate($0.date, inSameDayAs: $1.date) {
                    return $0.createdAt < $1.createdAt
                }
                return $0.date < $1.date
            }

        let title = "# 工作周报（\(WeekCalendar.displayTitle(for: date))）"
        var sections = [title]

        let identity = [settings.authorName, settings.teamName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !identity.isEmpty {
            sections.append(identity)
        }

        sections.append(reportBody(entries: weeklyEntries, style: settings.reportStyle))
        sections.append(progressSummary(entries: weeklyEntries))

        let nextPlan = settings.nextWeekPlan.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nextPlan.isEmpty {
            sections.append("## 下周计划\n\n\(nextPlan)")
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func reportBody(entries: [WorkEntry], style: ReportStyle) -> String {
        guard !entries.isEmpty else {
            return "## 本周工作\n\n本周暂无工作记录。"
        }

        switch style {
        case .concise:
            return groupedByProject(entries)
        case .byDay:
            return groupedByDay(entries)
        }
    }

    private static func groupedByProject(_ entries: [WorkEntry]) -> String {
        let grouped = Dictionary(grouping: entries) {
            let project = $0.project.trimmingCharacters(in: .whitespacesAndNewlines)
            return project.isEmpty ? "其他工作" : project
        }
        let orderedProjects = grouped.keys.sorted { lhs, rhs in
            if lhs == "其他工作" { return false }
            if rhs == "其他工作" { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        let body = orderedProjects.map { project in
            let rows = (grouped[project] ?? []).map { "- \(statusPrefix($0.status))\($0.content)" }
            return "### \(project)\n\n\(rows.joined(separator: "\n"))"
        }.joined(separator: "\n\n")
        return "## 本周工作\n\n\(body)"
    }

    private static func groupedByDay(_ entries: [WorkEntry]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"

        let grouped = Dictionary(grouping: entries) { WeekCalendar.calendar.startOfDay(for: $0.date) }
        let body = grouped.keys.sorted().map { day in
            let rows = (grouped[day] ?? []).map { entry in
                let project = entry.project.trimmingCharacters(in: .whitespacesAndNewlines)
                let projectPrefix = project.isEmpty ? "" : "【\(project)】"
                return "- \(statusPrefix(entry.status))\(projectPrefix)\(entry.content)"
            }
            return "### \(formatter.string(from: day))\n\n\(rows.joined(separator: "\n"))"
        }.joined(separator: "\n\n")
        return "## 本周工作\n\n\(body)"
    }

    private static func progressSummary(entries: [WorkEntry]) -> String {
        let completed = entries.count { $0.status == .completed }
        let inProgress = entries.count { $0.status == .inProgress }
        let blocked = entries.count { $0.status == .blocked }
        return """
        ## 进度概览

        - 已完成：\(completed) 项
        - 进行中：\(inProgress) 项
        - 有阻塞：\(blocked) 项
        """
    }

    private static func statusPrefix(_ status: WorkStatus) -> String {
        switch status {
        case .completed: "✅ "
        case .inProgress: "⏳ "
        case .blocked: "⚠️ "
        }
    }
}
