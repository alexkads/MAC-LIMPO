// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import SwiftUI

/// Faixa de atualização no topo do popover (todos os temas). Não é um alerta:
/// interromper ensina a dispensar sem ler. Some quando não há nada a dizer.
struct UpdateBanner: View {
    @ObservedObject var updater: UpdateChecker
    @State private var showsNotes = false

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var content: AnyView? {
        switch updater.state {
        case let .available(manifest) where manifest.version != updater.dismissedVersion:
            AnyView(available(manifest))
        case let .installing(manifest, step):
            AnyView(installing(manifest, step: step))
        case let .failed(manifest, reason, log):
            AnyView(failed(manifest, reason: reason, log: log))
        case let .upToDate(version):
            AnyView(message(
                icon: "checkmark.circle.fill", tint: .green,
                text: String(localized: "You're on the latest version (\(version)).")
            ))
        case let .unreachable(reason):
            AnyView(VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Couldn't check for a new version: \(reason)").fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                }
                HStack {
                    Button("Try Again") { updater.check(manual: true) }
                    Spacer()
                    Button("Close") { updater.dismiss() }
                }
                .controlSize(.small)
            })
        case .checking(manual: true):
            AnyView(HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for a new version…").foregroundStyle(.secondary)
            })
        default:
            nil
        }
    }

    // MARK: - Estados

    private func available(_ manifest: UpdateManifest) -> some View {
        let notes = manifest.localizedNotes()
        let important = manifest.important == true
        return VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(important
                        ? String(localized: "Important update: version \(manifest.version)")
                        : String(localized: "Version \(manifest.version) available"))
                        .font(.headline)
                        .foregroundStyle(important ? .red : .primary)
                    if let title = notes?.title {
                        Text(title).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(important ? .red : .accentColor)
                    .font(.title2)
            }

            if showsNotes, let notes {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notes.changes, id: \.self) { change in
                        Text("• \(change)").font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    if let why = notes.why, !why.isEmpty {
                        Text(why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .padding(.leading, 30)
            }

            Text(UpdateChecker.canBuildFromSource
                ? String(localized: "Builds on this Mac in the background (2–5 minutes). MAC-LIMPO reopens by itself when it's done.")
                : String(localized: "Opens the download page for the new version."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Update") { updater.install() }
                    .buttonStyle(.borderedProminent)
                if notes?.changes.isEmpty == false {
                    Button(showsNotes ? "Hide What's New" : "What's New") {
                        withAnimation { showsNotes.toggle() }
                    }
                }
                Spacer()
                Button("Later") { updater.dismiss() }
            }
            .controlSize(.small)
        }
    }

    private func installing(_ manifest: UpdateManifest, step: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Updating to version \(manifest.version) — \(step)").font(.callout.weight(.semibold))
                Text("You can keep using MAC-LIMPO. It closes and reopens by itself when the new version is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func failed(_ manifest: UpdateManifest, reason: String, log: URL?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("The update didn't work, and version \(UpdateChecker.currentVersion ?? "?") keeps working. \(reason)")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack {
                Button("Try Again") { updater.install() }
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("curl -fsSL \(UpdateChecker.installScriptURL.absoluteString) | sh", forType: .string)
                }
                .help("Paste it in Terminal to update by hand")
                if let log {
                    Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                }
                Spacer()
                Button("Close") { updater.dismiss() }
            }
            .controlSize(.small)
        }
    }

    private func message(icon: String, tint: Color, text: String) -> some View {
        HStack {
            Label {
                Text(text)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            Spacer()
            Button("Close") { updater.dismiss() }.controlSize(.small)
        }
    }
}
