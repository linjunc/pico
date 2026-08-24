import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PicoMainView: View {
    @EnvironmentObject private var state: PicoAppState
    /// 分组命名弹窗：新建 / 重命名共用一个 alert
    @State private var groupDialog: GroupDialog?
    @State private var groupDialogText = ""
    /// 辅助功能未授权时显示引导条
    @State private var showAXHint = false

    enum GroupDialog: Identifiable {
        case create
        case rename(ClipboardGroup)
        var id: String {
            switch self {
            case .create: return "create"
            case .rename(let g): return g.id.uuidString
            }
        }
        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }
        var title: String {
            isCreate ? "新建分组" : "重命名分组"
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.05).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if showAXHint { axHintBar }
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 0) {
                    groupsRail
                    Divider().overlay(Color.white.opacity(0.08))
                    entryGrid
                }
            }

            // 翻译灵动岛
            VStack { TranslationIslandView().padding(.top, 12); Spacer() }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: .picoTranslateEntry)) { notification in
            if let entry = notification.object as? ClipboardEntry {
                TranslationCoordinator.shared.translate(entry: entry)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .picoPasteNeedsAccessibility)) { _ in
            showAXHint = true
            // 8 秒后自动收起
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { showAXHint = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .picoPasteFailed)) { _ in
            showAXHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { showAXHint = false }
        }
        .onAppear {
            // 面板是 .nonactivatingPanel：可收键盘但绝不 activate 抢焦点。
            // 这里只需要确保 SwiftUI 没把焦点自动塞给搜索框。
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        // 新建分组 / 重命名分组 共用一个命名弹窗
        .alert(
            groupDialog?.title ?? "",
            isPresented: Binding(
                get: { groupDialog != nil },
                set: { if !$0 { groupDialog = nil } }
            ),
            presenting: groupDialog
        ) { dialog in
            TextField("分组名称", text: $groupDialogText)
            Button(dialog.isCreate ? "创建" : "确定") {
                let trimmed = groupDialogText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    switch dialog {
                    case .create:
                        state.repository.addGroup(name: trimmed)
                    case .rename(let group):
                        state.repository.renameGroup(group, to: trimmed)
                    }
                }
                groupDialog = nil
            }
            Button("取消", role: .cancel) { groupDialog = nil }
        } message: { dialog in
            Text(dialog.isCreate ? "为剪贴板分组起个名字" : "输入新的分组名称")
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }


    // MARK: - 辅助权限提示条
    private var axHintBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("粘贴需要「辅助功能」权限：请在 系统设置 → 隐私与安全性 → 辅助功能 中勾选 Pico 后重试")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("打开系统设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button { showAXHint = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - 头部
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill").foregroundStyle(.cyan)
            Text("Pico").font(.system(size: 15, weight: .semibold))
            Spacer()
            Picker("布局", selection: $state.selectedLayout) {
                Text("横条").tag("横条")
                Text("纵向").tag("纵向")
                Text("紧凑").tag("紧凑")
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            TextField("搜索历史、OCR 或来源应用", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                // 搜索完按回车：交还焦点，下一次回车直接粘贴选中条目
                .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
            Button {
                // 即选即用即关闭：打开设置的同时收起面板
                PicoPanelController.shared.hide(restoreFocus: false)
                PicoSettingsWindowController.shared.show(state: state)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("设置")
            // 关闭按钮：即用即关
            Button {
                PicoPanelController.shared.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.borderless)
            .help("关闭（Esc）")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - 分组栏
    private var groupsRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("分组").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)

            GroupButton(title: "全部", icon: "circle.grid.2x2",
                        count: state.repository.entries.count,
                        active: state.selection == .all) {
                state.selection = .all; state.selectedID = nil
            }

            GroupButton(title: "收藏", icon: "star",
                        count: state.repository.favoriteEntries.count,
                        active: state.selection == .favorites) {
                state.selection = .favorites; state.selectedID = nil
            }

            ForEach(state.repository.groups) { group in
                let groupID = group.id
                GroupButton(
                    title: group.name,
                    icon: group.iconName,
                    count: state.repository.membershipsByGroup[group.id]?.count ?? 0,
                    active: state.selection == .group(group.id)
                ) {
                    state.selection = .group(group.id); state.selectedID = nil
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let raw = object as? String, let entryID = UUID(uuidString: raw) else { return }
                        Task { @MainActor in
                            if let entry = state.repository.entries.first(where: { $0.id == entryID }),
                               let destination = state.repository.groups.first(where: { $0.id == groupID }) {
                                state.repository.add(entry, to: destination)
                            }
                        }
                    }
                    return true
                }
                .contextMenu {
                    Button("重命名…") {
                        groupDialogText = group.name
                        groupDialog = .rename(group)
                    }
                    Button("删除分组", role: .destructive) {
                        state.repository.deleteGroup(group)
                        if state.selection == .group(group.id) { state.selection = .all; state.selectedID = nil }
                    }
                }
            }

            Spacer()
            Button {
                groupDialogText = ""
                groupDialog = .create
            } label: {
                Label("新建分组", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.cyan)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
        .frame(width: 168)
        .background(Color.white.opacity(0.025))
    }

    // MARK: - 条目网格
    private var entryGrid: some View {
        let columns: Int = {
            switch state.selectedLayout {
            case "紧凑": return 5
            case "纵向": return 2
            default: return 4
            }
        }()
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                    spacing: 10
                ) {
                    ForEach(state.filteredEntries) { entry in
                        ClipboardCard(
                            entry: entry,
                            selected: entry.id == state.selectedEntry?.id,
                            onSelect: { state.selectedID = entry.id },
                            onPaste: {
                                // 先选中当前卡，再粘贴（避免操作到旧选中条目）
                                state.selectedID = entry.id
                                state.pasteSelected(plainText: false)
                            },
                            onPastePlainText: {
                                state.selectedID = entry.id
                                state.pasteSelected(plainText: true)
                            },
                            onTranslate: {
                                state.selectedID = entry.id
                                state.translateSelected()
                            },
                            onFavorite: { state.repository.toggleFavorite(entry) },
                            onDelete: { state.repository.delete(entry) }
                        )
                        .id(entry.id)
                        .onDrag {
                            NSItemProvider(object: entry.id.uuidString as NSString)
                        }
                    }
                }
                .padding(18)
            }
            // 选中变化时让卡片滚到可视区域中心，避免上下键选出视口
            .onChange(of: state.selectedID) { _, newID in
                guard let newID else { return }
                proxy.scrollTo(newID, anchor: .center)
            }
            // 切换分组也滚到顶
            .onChange(of: state.selection) { _, _ in
                guard let first = state.filteredEntries.first?.id else { return }
                proxy.scrollTo(first, anchor: .top)
            }
            // 布局切换也滚到顶
            .onChange(of: state.selectedLayout) { _, _ in
                guard let first = state.filteredEntries.first?.id else { return }
                proxy.scrollTo(first, anchor: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 点击网格空白处时把焦点从搜索框收回到窗口，方向键恢复可用
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        .overlay {
            if state.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("没有匹配的历史条目")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 灵动岛

private struct TranslationIslandView: View {
    @State private var result: TranslationResult?
    @State private var failure: TranslationFailure?
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        Group {
            if let result {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("译").font(.caption.bold())
                            .frame(width: 26, height: 26)
                            .background(.cyan, in: Circle())
                            .foregroundStyle(.black)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("翻译完成 · \(result.direction == .english ? "英文 → 简体中文" : "中文 → 英文")")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                            Text(result.translated)
                                .lineLimit(expanded ? nil : 1)
                                .font(.callout)
                        }
                        Spacer()
                        Button(copied ? "已复制" : "复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result.translated, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.result = nil }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .foregroundStyle(.black)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { expanded.toggle() }
                    if expanded {
                        Divider().overlay(Color.white.opacity(0.1))
                        HStack(alignment: .top) {
                            Text(result.source).foregroundStyle(.secondary)
                            Spacer()
                            Text(result.translated)
                        }
                        .font(.caption)
                    }
                }
                .padding(12)
                .frame(width: expanded ? 460 : 340)
                .background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.cyan.opacity(0.3)))
                .shadow(radius: 20)
            } else if let failure {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(failure.message).font(.caption)
                    Spacer()
                    Button("重试") { self.failure = nil }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .frame(width: 340)
                .background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.orange.opacity(0.35)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .picoTranslationSucceeded)) { note in
            result = note.object as? TranslationResult
            failure = nil; copied = false; expanded = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .picoTranslationFailed)) { note in
            failure = note.object as? TranslationFailure
            result = nil
        }
    }
}

// MARK: - 分组按钮

private struct GroupButton: View {
    let title: String
    let icon: String
    let count: Int?
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 18)
                Text(title).lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(active ? .cyan.opacity(0.9) : .secondary)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                active ? Color.cyan.opacity(0.18)
                       : (hovering ? Color.white.opacity(0.06) : .clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(active ? .cyan : (hovering ? .white.opacity(0.85) : .secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - 条目卡片

private struct ClipboardCard: View {
    let entry: ClipboardEntry
    let selected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onTranslate: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                Text(entry.contentType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                // 翻译：直接放在卡片上，免去右键
                Button(action: onTranslate) {
                    Image(systemName: "translate")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.85))
                }
                .buttonStyle(.borderless)
                .help("翻译（T）")
                // 收藏：直接放在卡片上，免去右键
                Button(action: onFavorite) {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(entry.isFavorite ? .yellow : .secondary.opacity(0.85))
                }
                .buttonStyle(.borderless)
                .help(entry.isFavorite ? "取消收藏" : "加入收藏")
            }

            thumbnail

            if entry.contentType != .image {
                Text(displayText)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack {
                Text(entry.sourceAppName ?? "未知应用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(self.formattedTime(entry.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(minHeight: entry.contentType == .image ? 150 : 156)
        .background(
            LinearGradient(
                colors: selected
                    ? [Color.cyan.opacity(0.13), Color.blue.opacity(0.06)]
                    : [Color.white.opacity(0.048), Color.white.opacity(0.018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Color.cyan.opacity(0.82) : Color.white.opacity(0.045), lineWidth: selected ? 1.2 : 0.6)
        )
        .shadow(color: selected ? Color.cyan.opacity(0.12) : .clear, radius: 14, y: 5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onPaste)
        .contextMenu {
            Button("粘贴") { onPaste() }
            Button("粘贴为纯文本") { onPastePlainText() }
            Button("翻译") { onTranslate() }
            Button(entry.isFavorite ? "取消收藏" : "加入收藏") { onFavorite() }
            Divider()
            Button("删除", role: .destructive) { onDelete() }
        }
    }

    private var displayText: String {
        if let custom = entry.customTitle, !custom.isEmpty { return custom }
        if let t = entry.text, !t.isEmpty { return t }
        if entry.contentType == .image { return entry.ocrText ?? "图片" }
        return "图片"
    }

    private var icon: String {
        switch entry.contentType {
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .fileURL: return "doc"
        case .color: return "paintpalette"
        case .richText: return "text.justify.leading"
        default: return "text.alignleft"
        }
    }

    /// 卡片右下角的绝对时间显示：今天 `HH:mm`、昨天 `昨天 HH:mm`、更早 `MM-dd HH:mm`
    private func formattedTime(_ date: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if cal.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨天 " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if entry.contentType == .image, let data = entry.imageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            EmptyView()
        }
    }
}
