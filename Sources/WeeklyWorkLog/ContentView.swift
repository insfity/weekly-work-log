import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WorkStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var selectedWeek = WeekCalendar.startOfWeek(containing: .now)
    @State private var showingReport = false
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                selectedWeek: $selectedWeek,
                selectedDate: $selectedDate,
                showingSettings: $showingSettings
            )
            .frame(width: 225)

            Divider()

            VStack(spacing: 0) {
                Header(
                    week: $selectedWeek,
                    selectedDate: $selectedDate,
                    showingReport: $showingReport
                )
                Divider()
                dashboard
            }
            .background(AppTheme.canvas)
        }
        .sheet(isPresented: $showingReport) {
            ReportView(weekDate: selectedWeek)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .onChange(of: selectedWeek) { newWeek in
            if !WeekCalendar.isDate(selectedDate, inWeekContaining: newWeek) {
                selectedDate = newWeek
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                store.cleanupExpiredContent()
            }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DayStrip(selectedDate: $selectedDate, weekDate: selectedWeek)
                SummaryCards(entries: store.entries(inWeekContaining: selectedWeek))

                DashboardColumns(spacing: 20, leftColumnFraction: 1.0 / 3.0) {
                    DayEntriesView(date: selectedDate)
                        .environmentObject(store)

                    QuickAddView(date: selectedDate)
                        .environmentObject(store)
                }
            }
            .padding(28)
        }
    }
}

private struct DashboardColumns: Layout {
    let spacing: CGFloat
    let leftColumnFraction: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let totalWidth = proposal.width ?? 800
        let availableWidth = max(0, totalWidth - spacing)
        let leftWidth = availableWidth * leftColumnFraction
        let rightWidth = availableWidth - leftWidth
        let leftSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: leftWidth, height: proposal.height)
        )
        let rightSize = subviews[1].sizeThatFits(
            ProposedViewSize(width: rightWidth, height: proposal.height)
        )
        return CGSize(width: totalWidth, height: max(leftSize.height, rightSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        let availableWidth = max(0, bounds.width - spacing)
        let leftWidth = availableWidth * leftColumnFraction
        let rightWidth = availableWidth - leftWidth

        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: leftWidth, height: proposal.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leftWidth + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: rightWidth, height: proposal.height)
        )
    }
}

private struct Sidebar: View {
    @Binding var selectedWeek: Date
    @Binding var selectedDate: Date
    @Binding var showingSettings: Bool

    private let recentWeeks: [Date] = {
        let current = WeekCalendar.startOfWeek(containing: .now)
        return (0..<10).compactMap {
            WeekCalendar.calendar.date(byAdding: .weekOfYear, value: -$0, to: current)
        }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.gradient)
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("工作周记")
                        .font(.system(size: 16, weight: .bold))
                    Text("For Sunnyqin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 26)

            Button {
                let today = Date()
                selectedDate = today
                selectedWeek = WeekCalendar.startOfWeek(containing: today)
            } label: {
                Label("回到今天", systemImage: "sun.max.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.accentSoft)
                    .foregroundStyle(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 9)
            .padding(.horizontal, 12)

            Text("最近几周")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 8)

            VStack(spacing: 3) {
                ForEach(recentWeeks, id: \.self) { week in
                    weekButton(week)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Label("周报设置", systemImage: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 50)
                    .padding(.horizontal, 14)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 10)
            .padding(12)
        }
        .background(AppTheme.sidebar)
    }

    private func weekButton(_ week: Date) -> some View {
        let isSelected = WeekCalendar.calendar.isDate(
            selectedWeek,
            equalTo: week,
            toGranularity: .weekOfYear
        )
        return Button {
            selectedWeek = week
            selectedDate = week
        } label: {
            HStack {
                Image(systemName: isSelected ? "calendar.circle.fill" : "calendar")
                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                Text(WeekCalendar.displayTitle(for: week))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.accent.opacity(0.1) : Color.clear)
            .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 8)
    }
}

private struct Header: View {
    @Binding var week: Date
    @Binding var selectedDate: Date
    @Binding var showingReport: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Text("本周工作")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(WeekCalendar.displayTitle(for: week))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    weekNavigationButton(
                        systemName: "chevron.left",
                        offset: -1,
                        accessibilityLabel: "上一周"
                    )
                    weekNavigationButton(
                        systemName: "chevron.right",
                        offset: 1,
                        accessibilityLabel: "下一周"
                    )
                }
            }

            Spacer()

            Button {
                showingReport = true
            } label: {
                Label("生成周报", systemImage: "sparkles")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 28)
        .frame(height: 82)
        .background(.bar)
    }

    private func weekNavigationButton(
        systemName: String,
        offset: Int,
        accessibilityLabel: String
    ) -> some View {
        Button {
            if let newWeek = WeekCalendar.calendar.date(byAdding: .weekOfYear, value: offset, to: week) {
                week = newWeek
                selectedDate = newWeek
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 10)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct DayStrip: View {
    @Binding var selectedDate: Date
    let weekDate: Date

    private let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d"
        return formatter
    }()

    var body: some View {
        let days = WeekCalendar.days(inWeekContaining: weekDate)
        ResponsiveWeekLayout(minimumCardWidth: 66, minimumSpacing: 10) {
            ForEach(days, id: \.self) { day in
                let selected = WeekCalendar.calendar.isDate(day, inSameDayAs: selectedDate)
                let today = WeekCalendar.calendar.isDateInToday(day)
                Button {
                    selectedDate = day
                } label: {
                    VStack(spacing: 7) {
                        Text(weekdayFormatter.string(from: day))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                        Text(dayFormatter.string(from: day))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? .white : Color.primary)
                        Circle()
                            .fill(today ? (selected ? Color.white : AppTheme.accent) : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(minWidth: 66, maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(selected ? AppTheme.accent : AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? Color.clear : AppTheme.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 12)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ResponsiveWeekLayout: Layout {
    let minimumCardWidth: CGFloat
    let minimumSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let proposedWidth = proposal.width
            ?? CGFloat(subviews.count) * minimumCardWidth
                + CGFloat(max(0, subviews.count - 1)) * minimumSpacing
        let metrics = layoutMetrics(totalWidth: proposedWidth, itemCount: subviews.count)
        let height = subviews.map {
            $0.sizeThatFits(
                ProposedViewSize(width: metrics.cardWidth, height: proposal.height)
            ).height
        }.max() ?? 0
        return CGSize(width: proposedWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let metrics = layoutMetrics(totalWidth: bounds.width, itemCount: subviews.count)
        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: metrics.cardWidth,
                    height: proposal.height
                )
            )
            x += metrics.cardWidth + metrics.spacing
        }
    }

    private func layoutMetrics(
        totalWidth: CGFloat,
        itemCount: Int
    ) -> (cardWidth: CGFloat, spacing: CGFloat) {
        let gapCount = max(0, itemCount - 1)
        let baseWidth = CGFloat(itemCount) * minimumCardWidth
            + CGFloat(gapCount) * minimumSpacing

        guard totalWidth > baseWidth, gapCount > 0 else {
            let availableCardWidth = max(
                44,
                (totalWidth - CGFloat(gapCount) * minimumSpacing)
                    / CGFloat(itemCount)
            )
            return (availableCardWidth, minimumSpacing)
        }

        let extraWidth = totalWidth - baseWidth
        let cardGrowth = extraWidth * 0.85
        let spacingGrowth = extraWidth - cardGrowth
        return (
            minimumCardWidth + cardGrowth / CGFloat(itemCount),
            minimumSpacing + spacingGrowth / CGFloat(gapCount)
        )
    }
}

private struct SummaryCards: View {
    let entries: [WorkEntry]

    var body: some View {
        AdaptiveSummaryLayout(breakpoint: 720, spacing: 12) {
            summaryCard(
                title: "本周记录",
                count: entries.count,
                symbol: "square.and.pencil",
                color: AppTheme.accent
            )
            summaryCard(
                title: "已完成",
                count: entries.count { $0.status == .completed },
                symbol: WorkStatus.completed.symbolName,
                color: WorkStatus.completed.color
            )
            summaryCard(
                title: "进行中",
                count: entries.count { $0.status == .inProgress },
                symbol: WorkStatus.inProgress.symbolName,
                color: WorkStatus.inProgress.color
            )
            summaryCard(
                title: "有阻塞",
                count: entries.count { $0.status == .blocked },
                symbol: WorkStatus.blocked.symbolName,
                color: WorkStatus.blocked.color
            )
        }
    }

    private func summaryCard(title: String, count: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .appCard()
    }
}

private struct AdaptiveSummaryLayout: Layout {
    let breakpoint: CGFloat
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? breakpoint
        let columns = columnCount(for: width, itemCount: subviews.count)
        let itemWidth = widthForItem(totalWidth: width, columns: columns)
        let rowHeights = measuredRowHeights(
            subviews: subviews,
            columns: columns,
            itemWidth: itemWidth,
            proposedHeight: proposal.height
        )
        return CGSize(
            width: width,
            height: rowHeights.reduce(0, +)
                + CGFloat(max(0, rowHeights.count - 1)) * spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let columns = columnCount(for: bounds.width, itemCount: subviews.count)
        let itemWidth = widthForItem(totalWidth: bounds.width, columns: columns)
        let rowHeights = measuredRowHeights(
            subviews: subviews,
            columns: columns,
            itemWidth: itemWidth,
            proposedHeight: proposal.height
        )

        var rowOrigins: [CGFloat] = []
        var currentY = bounds.minY
        for height in rowHeights {
            rowOrigins.append(currentY)
            currentY += height + spacing
        }

        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let column = index % columns
            let x = bounds.minX + CGFloat(column) * (itemWidth + spacing)
            subview.place(
                at: CGPoint(x: x, y: rowOrigins[row]),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: itemWidth,
                    height: rowHeights[row]
                )
            )
        }
    }

    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        min(itemCount, width < breakpoint ? 2 : 4)
    }

    private func widthForItem(totalWidth: CGFloat, columns: Int) -> CGFloat {
        max(
            0,
            (totalWidth - CGFloat(max(0, columns - 1)) * spacing)
                / CGFloat(columns)
        )
    }

    private func measuredRowHeights(
        subviews: Subviews,
        columns: Int,
        itemWidth: CGFloat,
        proposedHeight: CGFloat?
    ) -> [CGFloat] {
        let rowCount = (subviews.count + columns - 1) / columns
        return (0..<rowCount).map { row in
            let start = row * columns
            let end = min(start + columns, subviews.count)
            return subviews[start..<end].map {
                $0.sizeThatFits(
                    ProposedViewSize(width: itemWidth, height: proposedHeight)
                ).height
            }.max() ?? 0
        }
    }
}

private struct DayEntriesView: View {
    @EnvironmentObject private var store: WorkStore
    let date: Date
    @State private var editingEntry: WorkEntry?

    private var entries: [WorkEntry] { store.entries(on: date) }

    private let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleFormatter.string(from: date))
                        .font(.headline)
                    Text(entries.isEmpty ? "还没有记录，写下今天完成的事情吧" : "\(entries.count) 条工作记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("今天的工作记录会显示在这里")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry) {
                            editingEntry = entry
                        } onDelete: {
                            store.delete(id: entry.id)
                        }
                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
        }
        .appCard()
        .sheet(item: $editingEntry) { entry in
            EditEntryView(entry: entry)
                .environmentObject(store)
        }
    }
}

private struct EntryRow: View {
    let entry: WorkEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: entry.status.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(entry.status.color)
                .frame(width: 28, height: 28)
                .background(entry.status.color.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    if !entry.project.isEmpty {
                        Text(entry.project)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent.opacity(0.09))
                            .clipShape(Capsule())
                    }
                    Text(entry.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Menu {
                Button("编辑", systemImage: "pencil", action: onEdit)
                Divider()
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverHighlight(cornerRadius: 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }
}

private struct QuickAddView: View {
    @EnvironmentObject private var store: WorkStore
    let date: Date
    @State private var project = ""
    @State private var content = ""
    @State private var status: WorkStatus = .completed
    @FocusState private var contentFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                Text("添加工作记录")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("项目 / 分类")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("例如：移动端改版", text: $project)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("工作内容")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 110)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                    .focused($contentFocused)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("当前状态")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("当前状态", selection: $status) {
                    ForEach(WorkStatus.allCases) { status in
                        Label(status.title, systemImage: status.symbolName)
                            .tag(status)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Button {
                store.add(date: date, project: project, content: content, status: status)
                content = ""
                contentFocused = true
            } label: {
                Text("保存记录")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])

            Text("⌘ ↩ 快速保存")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .appCard()
    }
}
