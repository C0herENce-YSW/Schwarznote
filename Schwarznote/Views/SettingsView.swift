//
//  SettingsView.swift
//  Schwarznote
//

import SwiftUI

/// 设置. Sections sit in a chip bar; 快捷键 is the first (and so far only) one.
struct SettingsView: View {
    enum Section: String, CaseIterable, Hashable {
        case shortcuts = "快捷键"
    }

    @State private var section = Section.shortcuts
    @FocusState private var focusedSection: Section?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ChipBar(items: Section.allCases, title: \.rawValue, selection: $section, focus: $focusedSection)
                switch section {
                case .shortcuts: ShortcutSettings()
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
    }
}

/// Select a row, then press the key you want for that action.
struct ShortcutSettings: View {
    @Environment(ShortcutCenter.self) private var shortcuts

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("在笔记详情页使用。选中一项后按下想要的按键即可修改；方向键、确认键和返回键用于导航，不能设为快捷键。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            ForEach(ShortcutAction.allCases) { action in
                row(for: action)
            }

            Button("恢复默认") {
                shortcuts.recording = nil
                shortcuts.resetToDefaults()
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: 1100, alignment: .leading)
        .fullScreenCover(item: Binding(get: { shortcuts.recording }, set: { shortcuts.recording = $0 })) { action in
            KeyRecordingPrompt(action: action) { shortcuts.recording = nil }
        }
    }

    private func row(for action: ShortcutAction) -> some View {
        HStack(spacing: 20) {
            Button {
                if action.isEditable { shortcuts.recording = action }
            } label: {
                HStack {
                    Text(action.title)
                    Spacer()
                    Text(keyLabel(for: action))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
            .buttonStyle(RowStyle())
            .frame(maxWidth: .infinity)

            if action.isEditable, shortcuts.bindings[action] != nil {
                Button("清除") { shortcuts.clear(action) }
            }
        }
    }

    private func keyLabel(for action: ShortcutAction) -> String {
        if !action.isEditable { return "返回键（不可修改）" }
        return shortcuts.bindings[action]?.name ?? "未设置"
    }
}

/// Full-screen "press the new key" prompt. Closes by itself once a key is captured;
/// 取消 or the back button closes it without changing anything.
struct KeyRecordingPrompt: View {
    let action: ShortcutAction
    let cancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 36) {
                Image(systemName: "keyboard")
                    .font(.system(size: 120))
                Text("请按下新的按键")
                    .font(.system(size: 76, weight: .bold))
                Text("作为“\(action.title)”的快捷键")
                    .font(.title2)
                Text("方向键、确认键和返回键不能使用")
                    .font(.callout)
                    .opacity(0.6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: cancel) {
                Label("取消", systemImage: "chevron.left")
            }
            .padding(60)
        }
        .onExitCommand(perform: cancel)
    }
}
