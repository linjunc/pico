import AppKit
import SwiftUI

struct PicoMainView: View {
    @EnvironmentObject private var state: PicoAppState
    @State private var showSettings = false
    var body: some View {
        ZStack { Color(red: 0.025, green: 0.035, blue: 0.05).ignoresSafeArea(); VStack(spacing: 0) { header; Divider().overlay(Color.white.opacity(0.08)); HStack(spacing: 0) { groupsRail; Divider().overlay(Color.white.opacity(0.08)); entryGrid } } .overlay(alignment: .top) { TranslationIslandView().padding(.top, 12) } }.preferredColorScheme(.dark).toolbar(.hidden, for: .windowToolbar).sheet(isPresented: $showSettings) { PicoSettingsView().environmentObject(state) }.onReceive(NotificationCenter.default.publisher(for: .picoTranslateEntry)) { notification in if let entry = notification.object as? ClipboardEntry { TranslationCoordinator.shared.translate(entry: entry) } }.onKeyPress(.leftArrow) { state.selectRelative(-1); return .handled }.onKeyPress(.rightArrow) { state.selectRelative(1); return .handled }.onKeyPress(.escape) { NSApp.keyWindow?.orderOut(nil); return .handled }.onKeyPress(.return) { pasteSelected(plainText: false); return .handled }.onKeyPress(characters: CharacterSet(charactersIn: "Tt"), phases: .down) { _ in translateSelected(); return .handled }
    }
    private var header: some View { HStack(spacing: 10) { Image(systemName: "doc.on.clipboard.fill").foregroundStyle(.cyan); Text("Pico").font(.system(size: 15, weight: .semibold)); Spacer(); Picker("布局", selection: $state.selectedLayout) { Text("横向").tag("横向"); Text("纵向").tag("纵向"); Text("紧凑").tag("紧凑") }.pickerStyle(.segmented).frame(width: 180); TextField("搜索历史、OCR 或来源应用", text: $state.query).textFieldStyle(.roundedBorder).frame(width: 240); Button { showSettings = true } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless).foregroundStyle(.secondary) }.padding(.horizontal, 18).padding(.vertical, 13) }
    private var groupsRail: some View { VStack(alignment: .leading, spacing: 7) { Text("分组").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10); GroupButton(title: "全部", icon: "circle.grid.2x2", count: state.repository.entries.count, active: true); GroupButton(title: "收藏", icon: "star", count: state.repository.entries.filter(\.isFavorite).count, active: false); ForEach(state.repository.groups) { group in GroupButton(title: group.name, icon: group.iconName, count: nil, active: false) }; Spacer(); Button { state.repository.addGroup(name: "新分组") } label: { Label("新建分组", systemImage: "plus") }.buttonStyle(.borderless).foregroundStyle(.cyan).padding(.horizontal, 10) }.padding(.vertical, 14).frame(width: 155).background(Color.white.opacity(0.025)) }
    private var entryGrid: some View { ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: state.selectedLayout == "紧凑" ? 2 : 3), spacing: 10) { ForEach(state.filteredEntries) { entry in ClipboardCard(entry: entry, selected: entry.id == state.selectedEntry?.id, onSelect: { state.selectedID = entry.id }, onPaste: { pasteSelected(entry, plainText: false) }, onTranslate: { translate(entry) }, onFavorite: { state.repository.toggleFavorite(entry) }, onDelete: { state.repository.delete(entry) }) } }.padding(15) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    private func pasteSelected(_ entry: ClipboardEntry? = nil, plainText: Bool) { guard let entry = entry ?? state.selectedEntry else { return }; PasteService.shared.paste(entry, plainText: plainText) { NSApp.keyWindow?.orderOut(nil) } }
    private func translateSelected() { if let entry = state.selectedEntry { translate(entry) } }
    private func translate(_ entry: ClipboardEntry) { NotificationCenter.default.post(name: .picoTranslateEntry, object: entry) }
}

private struct TranslationIslandView: View {
    @State private var result: TranslationResult?
    @State private var failure: TranslationFailure?
    @State private var expanded = false
    @State private var copied = false
    var body: some View {
        Group {
            if let result {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { Text("译").font(.caption.bold()).frame(width: 26, height: 26).background(.cyan, in: Circle()).foregroundStyle(.black); VStack(alignment: .leading, spacing: 2) { Text("翻译完成 · \(result.direction == .english ? "英文 → 简体中文" : "中文 → 英文")").font(.caption).foregroundStyle(.cyan); Text(result.translated).lineLimit(expanded ? nil : 1).font(.callout) }; Spacer(); Button(copied ? "已复制" : "复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.translated, forType: .string); copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.result = nil } }.buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black) }.contentShape(Rectangle()).onTapGesture { expanded.toggle() }; if expanded { Divider().overlay(Color.white.opacity(0.1)); HStack(alignment: .top) { Text(result.source).foregroundStyle(.secondary); Spacer(); Text(result.translated) } .font(.caption) }
                }.padding(12).frame(width: expanded ? 460 : 340).background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.cyan.opacity(0.3))).shadow(radius: 20)
            } else if let failure {
                HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(failure.message).font(.caption); Spacer(); Button("重试") { self.failure = nil }.buttonStyle(.bordered) }.padding(12).frame(width: 340).background(.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.orange.opacity(0.35)))
            }
        }.onReceive(NotificationCenter.default.publisher(for: .picoTranslationSucceeded)) { note in result = note.object as? TranslationResult; failure = nil; copied = false; expanded = false }.onReceive(NotificationCenter.default.publisher(for: .picoTranslationFailed)) { note in failure = note.object as? TranslationFailure; result = nil }
    }
}

private struct GroupButton: View { let title: String; let icon: String; let count: Int?; let active: Bool; var body: some View { Button {} label: { HStack { Image(systemName: icon).frame(width: 18); Text(title); Spacer(); if let count { Text("\(count)").foregroundStyle(.secondary) } } }.buttonStyle(.borderless).padding(.vertical, 7).padding(.horizontal, 10).background(active ? Color.cyan.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(active ? .cyan : .secondary) } }

private struct ClipboardCard: View {
    let entry: ClipboardEntry; let selected: Bool; let onSelect: () -> Void; let onPaste: () -> Void; let onTranslate: () -> Void; let onFavorite: () -> Void; let onDelete: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 9) { HStack { Image(systemName: icon).foregroundStyle(.cyan); Text(entry.contentType.rawValue).font(.caption2).foregroundStyle(.secondary); Spacer(); if entry.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) } }; Text(entry.customTitle ?? entry.text ?? "图片内容").font(.system(size: 12)).foregroundStyle(.primary).lineLimit(5).frame(maxWidth: .infinity, alignment: .leading); Spacer(minLength: 0); HStack { Text(entry.sourceAppName ?? "未知应用").font(.caption2).foregroundStyle(.secondary); Spacer(); Text(entry.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary) } }.padding(12).frame(minHeight: 130).background(Color.white.opacity(selected ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(selected ? Color.cyan.opacity(0.75) : Color.white.opacity(0.08), lineWidth: 1)).contentShape(Rectangle()).onTapGesture(perform: onSelect).contextMenu { Button("粘贴") { onPaste() }; Button("粘贴为纯文本") { onPaste() }; Button("翻译") { onTranslate() }; Button(entry.isFavorite ? "取消收藏" : "加入收藏") { onFavorite() }; Divider(); Button("删除", role: .destructive) { onDelete() } } }
    private var icon: String { switch entry.contentType { case .link: "link"; case .code: "chevron.left.forwardslash.chevron.right"; case .image: "photo"; case .fileURL: "doc"; default: "text.alignleft" } }
}
