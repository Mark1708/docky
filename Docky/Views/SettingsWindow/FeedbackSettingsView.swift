//
//  FeedbackSettingsView.swift
//  Docky
//
//  Lets the user prepare a textual report and self-contained diagnostic zip.
//  The zip bundles every `docky.*` UserDefaults key, the live
//  `com.apple.dock` plist, basic system specs, and an optional user-picked
//  asset. Docky reveals the archive in Finder and opens a prefilled issue in
//  the fork's GitHub repository; the user reviews the report and attaches the
//  archive manually.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let feedbackIssueURL = URL(string: "https://github.com/Mark1708/docky/issues/new")!

struct FeedbackSettingsView: View {
    @State private var feedbackText: String = ""
    @State private var attachmentURL: URL?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("What's going on?") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe the issue, idea, or feedback. Docky creates a diagnostic bundle and reveals it in Finder so you can attach it to the GitHub issue.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $feedbackText)
                        .font(.body)
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if feedbackText.isEmpty {
                                Text("Describe the steps to reproduce, or what you'd like to see…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }
                .padding(.vertical, 4)
            }

            Section("Attachment (optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Choose Screenshot / Video…") { chooseAttachment() }
                        if attachmentURL != nil {
                            Button("Clear") { attachmentURL = nil }
                        }
                        Spacer()
                    }
                    if let attachmentURL {
                        Text(attachmentURL.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Text("Optional, a screen recording or screenshot helps explain UI issues. Images and videos are supported.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("What the diagnostic bundle contains") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Your message", systemImage: "text.alignleft")
                    Label("Docky preferences (every `docky.*` UserDefaults key)", systemImage: "doc.text")
                    Label("Live macOS Dock prefs (`com.apple.dock`)", systemImage: "dock.rectangle")
                    Label("Basic system info (macOS version, screens, Docky build)", systemImage: "info.circle")
                    if attachmentURL != nil {
                        Label("Your attachment", systemImage: "paperclip")
                    }
                }
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.vertical, 4)
            }

            Section {
                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Open GitHub Issue") { sendFeedback() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isPreparing || feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "Attach")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attachmentURL = url
    }

    private func sendFeedback() {
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }

        do {
            let bundleURL = try FeedbackBundle.build(
                feedbackText: feedbackText,
                attachmentURL: attachmentURL
            )
            openIssue(bundleURL: bundleURL)
        } catch {
            errorMessage = "Could not build feedback bundle: \(error.localizedDescription)"
        }
    }

    private func openIssue(bundleURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])

        let subject = "Docky feedback (v\(Bundle.main.shortVersion))"
        let body = """
        ### Description
        \(feedbackText)

        ### Diagnostics
        Attach `\(bundleURL.lastPathComponent)` from the Finder window opened by Docky.
        """
        var components = URLComponents(url: feedbackIssueURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let issueURL = components?.url, NSWorkspace.shared.open(issueURL) else {
            errorMessage = String(localized: "Could not open GitHub. The diagnostic bundle is available in Finder for manual attachment.")
            return
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}

/// Standalone helper so the build step is testable on its own and
/// nothing in the view code needs to know about plist serialization,
/// zipping, etc.
private enum FeedbackBundle {
    static func build(feedbackText: String, attachmentURL: URL?) throws -> URL {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let stagingRoot = fileManager.temporaryDirectory
            .appending(path: "docky-feedback-\(timestamp)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        // 1. docky-defaults.plist, filtered to our namespace so we
        //    don't leak unrelated UserDefaults from other domains.
        let allDefaults = UserDefaults.standard.dictionaryRepresentation()
        let dockyDefaults = allDefaults.filter { $0.key.hasPrefix("docky.") }
        try writePlist(dockyDefaults, to: stagingRoot.appending(path: "docky-defaults.plist"))

        // 2. com.apple.dock plist, exact snapshot of system dock prefs.
        if let dockPlist = DockPlistReader.read() {
            try writePlist(dockPlist, to: stagingRoot.appending(path: "com.apple.dock.plist"))
        }

        // 3. system.json, Mac specs (kept minimal: no usernames or
        //    paths). Enough to tell apart "M1 Air on macOS 14" vs
        //    "Mac Pro on macOS 26".
        let system = systemSnapshot()
        try writeJSON(system, to: stagingRoot.appending(path: "system.json"))

        // 4. feedback.txt, verbatim user message.
        try feedbackText
            .write(to: stagingRoot.appending(path: "feedback.txt"), atomically: true, encoding: .utf8)

        // 5. Optional asset, copied alongside (preserves original name).
        if let attachmentURL {
            let dest = stagingRoot.appending(path: attachmentURL.lastPathComponent)
            try fileManager.copyItem(at: attachmentURL, to: dest)
        }

        // Zip the staging directory in place so the share sheet has
        // one cohesive attachment rather than a directory tree.
        let zipURL = stagingRoot.deletingLastPathComponent()
            .appending(path: stagingRoot.lastPathComponent + ".zip")
        try fileManager.removeItemIfExists(at: zipURL)
        try ditto(source: stagingRoot, destination: zipURL)
        return zipURL
    }

    private static func writePlist(_ value: Any, to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private static func writeJSON(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private static func systemSnapshot() -> [String: Any] {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        var screens: [[String: Any]] = []
        for screen in NSScreen.screens {
            screens.append([
                "frame": NSStringFromRect(screen.frame),
                "visibleFrame": NSStringFromRect(screen.visibleFrame),
                "backingScaleFactor": screen.backingScaleFactor,
                "localizedName": screen.localizedName
            ])
        }
        return [
            "dockyVersion": Bundle.main.shortVersion,
            "dockyBuild": (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?",
            "macosVersion": "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            "macosVersionString": processInfo.operatingSystemVersionString,
            "processorCount": processInfo.processorCount,
            "physicalMemoryBytes": processInfo.physicalMemory,
            "locale": Locale.current.identifier,
            "screens": screens
        ]
    }

    /// Use `/usr/bin/ditto` for archiving, it produces a real macOS
    /// zip (preserves resource forks / extended attrs, deterministic,
    /// no third-party deps).
    private static func ditto(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "FeedbackBundle", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "ditto exited with status \(process.terminationStatus)"
            ])
        }
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
