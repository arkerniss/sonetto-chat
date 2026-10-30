import SwiftUI

/// 助手编辑页。包含 5 个标签:基础设置、提示词、记忆、正则、快捷短语。
/// 任何字段改动都会立即写回 AssistantStore(无保存按钮),与 kelivo 一致。
struct AssistantEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var assistants: AssistantStore

    let assistantID: UUID

    @State private var draft: Assistant?
    @State private var selectedTab: AssistantEditTab = .basic

    var body: some View {
        ZStack {
            ChatChrome.canvas
                .ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: 0) {
                header
                tabBar

                if let binding = draftBinding {
                    TabView(selection: $selectedTab) {
                        AssistantBasicTab(assistant: binding)
                            .tag(AssistantEditTab.basic)
                        AssistantPromptTab(assistant: binding)
                            .tag(AssistantEditTab.prompt)
                        AssistantMemoryTab(assistant: binding)
                            .tag(AssistantEditTab.memory)
                        AssistantRegexTab(assistant: binding)
                            .tag(AssistantEditTab.regex)
                        AssistantQuickPhraseTab(assistant: binding)
                            .tag(AssistantEditTab.quickPhrase)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if draft == nil {
                draft = assistants.assistant(withID: assistantID)
            }
        }
        .onChange(of: draft) { _, newValue in
            guard let newValue else { return }
            assistants.update(newValue)
        }
    }

    /// 把本地 draft 暴露成非可选 Binding,供各标签使用。
    private var draftBinding: Binding<Assistant>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft ?? assistants.currentAssistant },
            set: { draft = $0 }
        )
    }

    private var header: some View {
        SettingsHeaderBar(
            title: draft?.name.isEmpty == false ? draft!.name : "助手设置",
            subtitle: "改动会自动保存",
            backSymbol: "chevron.left",
            backLabel: "返回助手列表"
        ) {
            dismiss()
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AssistantEditTab.allCases) { tab in
                    tabChip(tab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func tabChip(_ tab: AssistantEditTab) -> some View {
        let isSelected = tab == selectedTab

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .liquidGlass(
                shape: Capsule(style: .continuous),
                tint: isSelected ? .accent : .none,
                interactive: true,
                fallbackFill: isSelected ? Color.accentColor.opacity(0.12) : ChatChrome.field,
                shadowRadius: 0,
                shadowY: 0
            )
        }
        .buttonStyle(.plain)
    }
}

enum AssistantEditTab: String, CaseIterable, Identifiable {
    case basic, prompt, memory, regex, quickPhrase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "基础"
        case .prompt: return "提示词"
        case .memory: return "记忆"
        case .regex: return "正则"
        case .quickPhrase: return "快捷短语"
        }
    }

    var symbol: String {
        switch self {
        case .basic: return "slider.horizontal.3"
        case .prompt: return "text.alignleft"
        case .memory: return "brain"
        case .regex: return "textformat.abc"
        case .quickPhrase: return "bolt"
        }
    }
}
