// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import SwiftUI

/// Popover do tema Liquid Glass: só componentes nativos do sistema — List,
/// Section, Gauge, LabeledContent, Picker, Toggle, ProgressView, NSSearchField —
/// e o vidro nativo (`glassEffect`, botões `.glass`/`.glassProminent`) nos
/// controles e painéis flutuantes. Usa o mesmo view model e as mesmas ações do
/// popover dos outros temas.
struct NativeMenuBarContent: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @ObservedObject var cleaningOptions: CleaningOptions
    @ObservedObject var themeManager: ThemeManager
    @Binding var searchText: String
    let insight: String?
    let insightStatus: AppleIntelligenceAvailability?
    let isGeneratingInsight: Bool
    let generateInsight: () -> Void
    let onOpenDiskXRay: () -> Void
    let version: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            NativeSearchField(text: $searchText, prompt: "Search cleaning categories")
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            List {
                storageSection
                intelligenceSection
                categorySections
                settingsSection
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            cleanAllBar
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("MAC-LIMPO").font(.title2.weight(.bold))
                Text("System Cleaner").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button(action: onOpenDiskXRay) {
                        Image(systemName: "rays")
                    }
                    .help("Disk X-Ray")
                    .accessibilityLabel("Open Disk X-Ray")

                    Button {
                        viewModel.refreshDiskStats()
                        viewModel.scanAllCategories()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh scan")
                    .accessibilityLabel("Refresh scan")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Armazenamento

    private var storageSection: some View {
        let total = Double(max(1, viewModel.totalDiskSpace))
        let used = Double(max(0, viewModel.usedDiskSpace))
        let fraction = min(1, used / total)
        return Section("Storage") {
            HStack(spacing: 16) {
                Gauge(value: fraction) {
                    Text("Used")
                } currentValueLabel: {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.accentColor)
                .accessibilityLabel("Disk used")
                .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))

                VStack(spacing: 4) {
                    LabeledContent("Used", value: bytes(viewModel.usedDiskSpace))
                    LabeledContent("Free", value: bytes(viewModel.totalDiskSpace - viewModel.usedDiskSpace))
                    LabeledContent("Total", value: bytes(viewModel.totalDiskSpace))
                }
                .monospacedDigit()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Apple Intelligence

    private var intelligenceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(insight ?? insightStatus?.message ?? "Generate a private, on-device storage recommendation.")
                    .font(.callout)
                    .foregroundStyle(insight == nil ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: generateInsight) {
                    if isGeneratingInsight {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(insight == nil ? "Analyze" : "Refresh", systemImage: "apple.intelligence")
                    }
                }
                .buttonStyle(.glass)
                .disabled(isGeneratingInsight)
                .accessibilityLabel(isGeneratingInsight ? "Generating recommendation" : "Generate storage recommendation")
            }
            .padding(.vertical, 2)
        } header: {
            Label("Apple Intelligence", systemImage: "apple.intelligence")
        }
    }

    // MARK: - Categorias

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func categories(in group: CleaningGroup) -> [CleaningCategory] {
        viewModel.services.keys
            .filter { category in
                guard category.group == group else { return false }
                guard !query.isEmpty else { return true }
                return category.rawValue.localizedCaseInsensitiveContains(query)
                    || category.description.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.rawValue < $1.rawValue }
    }

    @ViewBuilder
    private var categorySections: some View {
        let groups = CleaningGroup.allCases.map { ($0, categories(in: $0)) }.filter { !$0.1.isEmpty }
        if groups.isEmpty {
            Section {
                ContentUnavailableView.search(text: query)
            }
        }
        ForEach(groups, id: \.0) { group, categories in
            Section {
                ForEach(categories) { category in
                    categoryRow(category)
                }
            } header: {
                HStack {
                    Label(group.rawValue, systemImage: group.icon)
                    Spacer()
                    Text("\(categories.count)").monospacedDigit()
                }
            }
        }
    }

    private func categoryRow(_ category: CleaningCategory) -> some View {
        let isCleaning = viewModel.cleaningCategories.contains(category)
        let isScanning = viewModel.isScanning[category] ?? false
        let size = viewModel.scanResults[category]?.formattedSize ?? "…"
        return Button {
            viewModel.cleanCategory(category)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(category.color)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.rawValue)
                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isCleaning || isScanning {
                    if let status = isCleaning ? "Cleaning…" : viewModel.scanningStatus[category] {
                        Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ProgressView().controlSize(.small)
                } else {
                    Text(size).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCleaning)
        .help(category.description)
        .accessibilityLabel("\(category.rawValue), \(isCleaning ? "cleaning" : isScanning ? "scanning" : size)")
        .accessibilityHint("Cleans \(category.rawValue)")
    }

    // MARK: - Ajustes

    private var settingsSection: some View {
        Section("Settings") {
            Picker("Theme", selection: $themeManager.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)
            Toggle(isOn: $cleaningOptions.aggressiveMode) {
                Text("Aggressive cleaning")
                Text("Also clears large regenerable caches (Chrome AI models, all unused Docker images)")
            }
            Toggle(isOn: $cleaningOptions.dockerFullCleanup) {
                Text("Docker full cleanup")
                Text("Stops all containers and deletes every container, image and volume — databases included")
            }
            HStack {
                Button("Quit MAC-LIMPO", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.glass)
                Spacer()
                if let version {
                    Text(version).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Clean All

    private var cleanAllBar: some View {
        Button {
            viewModel.cleanAll()
        } label: {
            Label("Clean All", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }
}

// MARK: - Painéis (confirmação, progresso, resultado)

/// Painel flutuante sobre o conteúdo do popover: vidro nativo, com fundo opaco
/// quando Reduzir Transparência está ligado.
private struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            Group {
                if reduceTransparency {
                    content.padding(20)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
                } else {
                    content.padding(20)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                }
            }
            .padding(24)
        }
    }
}

struct NativeConfirmationPanel: View {
    let request: ConfirmationRequest
    let onConfirm: (_ dontAskAgain: Bool) -> Void
    let onCancel: () -> Void
    @State private var dontAskAgain = false

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(request.title, systemImage: "sparkles").font(.headline)
                Text(request.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Don't ask again this session", isOn: $dontAskAgain)
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Clean") { onConfirm(dontAskAgain) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
    }
}

struct NativeProgressPanel: View {
    let category: CleaningCategory
    @Binding var isShowing: Bool
    let progress: Double
    let currentOperation: String

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(category.rawValue, systemImage: category.icon).font(.headline)
                    Spacer()
                    Button {
                        isShowing = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.glass)
                    .help("Hide")
                    .accessibilityLabel("Hide progress")
                }
                ProgressView(value: progress) {
                    Text(currentOperation.isEmpty ? "Cleaning…" : currentOperation).lineLimit(1)
                } currentValueLabel: {
                    Text(progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
            }
        }
    }
}

struct NativeResultsPanel: View {
    let result: CleaningResult
    @Binding var isShowing: Bool

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    result.success ? "Cleaning Complete" : "Cleaning Finished with Errors",
                    systemImage: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(result.success ? .green : .orange)

                VStack(spacing: 4) {
                    LabeledContent("Space Freed", value: result.formattedSize)
                    LabeledContent("Files Removed", value: result.filesRemoved.formatted())
                    LabeledContent("Time Taken", value: result.executionTime.formatted(.number.precision(.fractionLength(1))) + " s")
                }
                .monospacedDigit()

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.errors.prefix(3), id: \.self) { error in
                            Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Done") { isShowing = false }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

// MARK: - Busca nativa

/// O NSSearchField do AppKit (lupa, botão de limpar, foco e acessibilidade do
/// sistema). O `.searchable` do SwiftUI precisa de uma barra de navegação, que
/// o popover não tem.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.controlSize = .large
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
