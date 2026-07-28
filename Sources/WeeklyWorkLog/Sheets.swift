import AppKit
import SwiftUI

struct EditEntryView: View {
    @EnvironmentObject private var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkEntry

    init(entry: WorkEntry) {
        _draft = State(initialValue: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("编辑工作记录")
                .font(.title2.bold())

            DatePicker("日期", selection: $draft.date, displayedComponents: .date)

            TextField("项目 / 分类", text: $draft.project)

            VStack(alignment: .leading, spacing: 6) {
                Text("工作内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.content)
                    .padding(8)
                    .frame(height: 120)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Picker("状态", selection: $draft.status) {
                ForEach(WorkStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    store.update(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct SettingsView: View {
    private enum ClearAction: String, Identifiable {
        case reports
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .reports: "确认清除所有周报？"
            case .all: "确认清除全部记录？"
            }
        }

        var message: String {
            switch self {
            case .reports:
                "所有已生成和手动编辑的周报缓存都会被删除，每天记录的工作内容将继续保留。此操作无法撤销。"
            case .all:
                "所有周报缓存和每天记录的工作内容都会被永久删除。应用设置和本地保存的 API 密钥会保留。此操作无法撤销。"
            }
        }

        var confirmationLabel: String {
            switch self {
            case .reports: "清除周报"
            case .all: "清除全部"
            }
        }
    }

    @EnvironmentObject private var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var statusMessage = ""
    @State private var pendingClearAction: ClearAction?
    @State private var modelOptions: [String] = []
    @State private var modelStatusMessage = ""
    @State private var isLoadingModels = false
    @State private var modelLoadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("周报设置")
                    .font(.title2.bold())
                Text("配置基本信息与自定义第三方 AI 服务。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("基本信息") {
                    TextField("姓名", text: $store.settings.authorName)
                    TextField("团队 / 部门", text: $store.settings.teamName)
                    Picker("本地汇总方式", selection: $store.settings.reportStyle) {
                        ForEach(ReportStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }

                Section("自定义 AI 接口") {
                    TextField(
                        "完整 API 地址",
                        text: $store.settings.customAPIEndpoint,
                        prompt: Text("https://api.example.com/v1/chat/completions")
                    )
                    LabeledContent("模型名称") {
                        HStack(spacing: 8) {
                            EditableModelComboBox(
                                text: $store.settings.customModel,
                                items: modelOptions,
                                placeholder: "选择或输入模型"
                            )
                            .frame(minWidth: 280, minHeight: 24)

                            Button {
                                modelLoadTask?.cancel()
                                modelLoadTask = Task { await loadModels() }
                            } label: {
                                if isLoadingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.borderless)
                            .hoverHighlight(cornerRadius: 6)
                            .disabled(
                                isLoadingModels
                                    || store.settings.customAPIEndpoint
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty
                            )
                            .help("从接口刷新模型列表")
                        }
                    }
                    if !modelStatusMessage.isEmpty {
                        Text(modelStatusMessage)
                            .font(.caption)
                            .foregroundStyle(
                                modelStatusMessage.contains("失败")
                                    ? WorkStatus.blocked.color
                                    : .secondary
                            )
                    }
                    if isGeminiEndpoint, !isGeminiCompatibleChatEndpoint {
                        HStack {
                            Text("检测到 Gemini。生成周报需要使用其 Chat Completions 兼容地址。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("使用推荐地址") {
                                applyGeminiCompatibleEndpoint()
                            }
                        }
                    }
                    Picker("接口格式", selection: $store.settings.customAPIFormat) {
                        ForEach(CustomAPIFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    Picker("认证方式", selection: $store.settings.customAuthentication) {
                        ForEach(CustomAuthentication.allCases) { authentication in
                            Text(authentication.title).tag(authentication)
                        }
                    }

                    if store.settings.customAuthentication != .none {
                        HStack {
                            SecureField(
                                hasStoredAPIKey ? "已保存在本地；输入新密钥可替换" : "API 密钥",
                                text: $apiKey
                            )
                            Button(hasStoredAPIKey ? "更新密钥" : "保存密钥") {
                                saveAPIKey()
                            }
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if hasStoredAPIKey {
                                Button("删除", role: .destructive) {
                                    deleteAPIKey()
                                }
                            }
                        }
                        Text("密钥保存在本机 worklog.json 中，不使用 Apple 钥匙串；该文件未加密，请注意设备与文件权限安全。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("建议使用 HTTPS；HTTP 仅适合可信的本地或内网服务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("智能写作") {
                    Picker("报告语气", selection: $store.settings.reportTone) {
                        ForEach(AIReportTone.allCases) { tone in
                            Text(tone.title).tag(tone)
                        }
                    }
                    TextField(
                        "额外要求",
                        text: $store.settings.customAIInstructions,
                        prompt: Text("例如：重点突出跨团队协作")
                    )
                }

                Section("数据管理") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("已生成周报")
                            Text("删除周报缓存，保留每天的工作记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("清除周报", role: .destructive) {
                            pendingClearAction = .reports
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("全部记录")
                            Text("删除所有周报及每天记录的工作内容")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("清除全部", role: .destructive) {
                            pendingClearAction = .all
                        }
                    }

                    Text("系统会自动保留最近 4 周的周报，以及最近 10 周的工作记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 8) {
                Image(systemName: "signature")
                    .foregroundStyle(AppTheme.accent)
                Text("创作者：Matthias Cheng")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("版本 \(AppInfo.version) · \(AppInfo.releaseDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            HStack {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusMessage.contains("失败") ? WorkStatus.blocked.color : WorkStatus.completed.color)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 760)
        .onAppear {
            apiKey = store.settings.customAPIKey
            scheduleModelRefresh()
        }
        .onDisappear {
            modelLoadTask?.cancel()
        }
        .onChange(of: store.settings.customAPIEndpoint) { _ in
            scheduleModelRefresh()
        }
        .onChange(of: store.settings.customAuthentication) { _ in
            scheduleModelRefresh()
        }
        .alert(item: $pendingClearAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.confirmationLabel)) {
                    performClear(action)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func saveAPIKey() {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return }
        store.settings.customAPIKey = cleanKey
        apiKey = cleanKey
        statusMessage = "密钥已保存在本地，不会请求系统钥匙串授权"
        modelLoadTask?.cancel()
        modelLoadTask = Task { await loadModels() }
    }

    private func deleteAPIKey() {
        store.settings.customAPIKey = ""
        apiKey = ""
        statusMessage = "本地保存的密钥已删除"
        scheduleModelRefresh()
    }

    private func performClear(_ action: ClearAction) {
        switch action {
        case .reports:
            store.clearReports()
            statusMessage = "已清除所有周报缓存"
        case .all:
            store.clearAllContent()
            statusMessage = "已清除所有周报及工作记录"
        }
    }

    private var isGeminiEndpoint: Bool {
        !AIModelDiscoveryService.suggestedModels(
            for: store.settings.customAPIEndpoint
        ).isEmpty
    }

    private var hasStoredAPIKey: Bool {
        !store.settings.customAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var isGeminiCompatibleChatEndpoint: Bool {
        guard let url = URL(string: store.settings.customAPIEndpoint) else { return false }
        return url.path.lowercased().hasSuffix("/v1beta/openai/chat/completions")
    }

    private func applyGeminiCompatibleEndpoint() {
        store.settings.customAPIEndpoint =
            "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        store.settings.customAPIFormat = .chatCompletions
        store.settings.customAuthentication = .bearer
        scheduleModelRefresh()
    }

    private func scheduleModelRefresh() {
        modelLoadTask?.cancel()
        let suggestions = AIModelDiscoveryService.suggestedModels(
            for: store.settings.customAPIEndpoint
        )
        modelOptions = suggestions

        let endpoint = store.settings.customAPIEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            modelStatusMessage = ""
            return
        }

        if !suggestions.isEmpty {
            modelStatusMessage = hasStoredAPIKey
                ? "已识别 Gemini，正在获取账号可用模型…"
                : "已识别 Gemini；保存密钥后可刷新账号可用模型。"
        } else {
            modelStatusMessage = hasStoredAPIKey || store.settings.customAuthentication == .none
                ? "可点击刷新按钮，从兼容接口获取模型列表。"
                : "保存密钥后可从兼容接口获取模型列表。"
        }

        guard hasStoredAPIKey || store.settings.customAuthentication == .none else { return }
        modelLoadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await loadModels()
        }
    }

    @MainActor
    private func loadModels() async {
        let endpoint = store.settings.customAPIEndpoint
        let authentication = store.settings.customAuthentication
        let key = store.settings.customAPIKey

        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await AIModelDiscoveryService().discover(
                endpointText: endpoint,
                authentication: authentication,
                apiKey: key
            )
            guard !Task.isCancelled else { return }
            modelOptions = models
            modelStatusMessage = "已获取 \(models.count) 个可用模型，可展开选择或继续手动输入。"
            if store.settings.customModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
               let firstModel = models.first {
                store.settings.customModel = firstModel
            }
        } catch {
            guard !Task.isCancelled else { return }
            let suggestions = AIModelDiscoveryService.suggestedModels(for: endpoint)
            if !suggestions.isEmpty {
                modelOptions = suggestions
            }
            modelStatusMessage = error.localizedDescription
        }
    }
}

private struct EditableModelComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.delegate = context.coordinator
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.hasVerticalScroller = true
        comboBox.numberOfVisibleItems = 10
        comboBox.placeholderString = placeholder
        comboBox.addItems(withObjectValues: items)
        comboBox.stringValue = text
        comboBox.setAccessibilityLabel("模型名称")
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self
        let currentItems = comboBox.objectValues.compactMap { $0 as? String }
        if currentItems != items {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: items)
        }
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        comboBox.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: EditableModelComboBox

        init(parent: EditableModelComboBox) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            if parent.text != comboBox.stringValue {
                parent.text = comboBox.stringValue
            }
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard
                let comboBox = notification.object as? NSComboBox,
                let selected = comboBox.objectValueOfSelectedItem as? String
            else {
                return
            }
            if parent.text != selected {
                parent.text = selected
            }
        }
    }
}

struct ReportView: View {
    @EnvironmentObject private var store: WorkStore
    @Environment(\.dismiss) private var dismiss
    let weekDate: Date
    @State private var reportText = ""
    @State private var copied = false
    @State private var isGenerating = false
    @State private var generatedByAI = false
    @State private var generationError: String?
    @State private var didLoadReport = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本周周报")
                        .font(.title2.bold())
                    Text(WeekCalendar.displayTitle(for: weekDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 12)
            }
            .padding(22)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(AppTheme.accent)
                        Text("智能润色")
                            .font(.headline)
                    }
                    Text(apiConfigurationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await generateWithAI() }
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "正在整理…" : "生成自然周报")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(isGenerating || store.entries(inWeekContaining: weekDate).isEmpty)

                    Button("恢复本地汇总", systemImage: "arrow.counterclockwise") {
                        generatedByAI = false
                        regenerate()
                    }
                    .buttonStyle(.borderless)
                    .hoverHighlight(cornerRadius: 6)

                    if let generationError {
                        Text(generationError)
                            .font(.caption)
                            .foregroundStyle(WorkStatus.blocked.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    Text("下周计划")
                        .font(.headline)
                    Text("可选。支持 Markdown 格式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.settings.nextWeekPlan)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Picker("汇总方式", selection: $store.settings.reportStyle) {
                        ForEach(ReportStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if generatedByAI {
                        Label("当前内容由第三方 AI 生成，可继续手动编辑", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(WorkStatus.completed.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(width: 260)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("预览与编辑")
                        .font(.headline)
                    TextEditor(text: $reportText)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Text("Markdown 格式，可直接粘贴到邮件或文档中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reportText, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    exportReport()
                } label: {
                    Label("导出文件", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(18)
        }
        .frame(width: 860, height: 650)
        .onAppear(perform: loadReport)
        .onChange(of: store.settings.nextWeekPlan) { _ in
            if !generatedByAI { regenerate() }
        }
        .onChange(of: store.settings.reportStyle) { _ in
            if !generatedByAI { regenerate() }
        }
        .onChange(of: reportText) { newValue in
            guard didLoadReport else { return }
            store.cacheReport(
                newValue,
                for: weekDate,
                source: generatedByAI ? .ai : .local
            )
        }
    }

    private func loadReport() {
        if let cachedReport = store.cachedReport(for: weekDate) {
            generatedByAI = cachedReport.source == .ai
            reportText = cachedReport.content
        } else {
            generatedByAI = false
            reportText = store.report(for: weekDate)
            store.cacheReport(reportText, for: weekDate, source: .local)
        }
        didLoadReport = true
    }

    private func regenerate() {
        generatedByAI = false
        reportText = store.report(for: weekDate)
        store.cacheReport(reportText, for: weekDate, source: .local)
    }

    private var apiConfigurationSummary: String {
        let endpoint = store.settings.customAPIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = store.settings.customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isEmpty || model.isEmpty {
            return "请先在“周报设置”中填写第三方 API 地址和模型。"
        }
        return "\(model) · \(store.settings.customAPIFormat.title)"
    }

    @MainActor
    private func generateWithAI() async {
        generationError = nil
        let key = store.settings.customAPIKey
        if store.settings.customAuthentication != .none && key.isEmpty {
            generationError = "尚未保存 API 密钥，请先打开“周报设置”完成配置。"
            return
        }

        isGenerating = true
        defer { isGenerating = false }
        do {
            let generatedReport = try await CustomAIReportService().generate(
                entries: store.entries,
                weekDate: weekDate,
                settings: store.settings,
                apiKey: key
            )
            generatedByAI = true
            reportText = generatedReport
            store.cacheReport(generatedReport, for: weekDate, source: .ai)
        } catch {
            generationError = error.localizedDescription
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "工作周报-\(fileDateString()).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try reportText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法导出周报"
            alert.runModal()
        }
    }

    private func fileDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: WeekCalendar.startOfWeek(containing: weekDate))
    }
}
