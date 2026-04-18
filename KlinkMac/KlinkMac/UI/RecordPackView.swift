// Record Your Own Pack window: visual keyboard + mic recording per key.
import SwiftUI

struct RecordPackView: View {
    var appState: AppState

    @State private var packName = ""
    @State private var authorName = ""
    @State private var errorMessage: String?
    @State private var savedPack: InstalledPack?
    @Environment(\.klinkTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.klinkSurfaceHigh)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataSection
                    if let recorder = appState.packRecorder, recorder.micPermissionDenied {
                        micPermissionCard
                    }
                    statusSection
                    keyboardSection
                }
                .padding(20)
            }
            Divider().background(Color.klinkSurfaceHigh)
            footerBar
        }
        .frame(width: 720, height: 480)
        .background(Color.klinkBackground)
        .environment(\.colorScheme, .dark)
        .onDisappear {
            appState.closeRecordPackWindow()
        }
    }
}

// MARK: - Header

private extension RecordPackView {
    var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.accent)
            Text("Record Your Own Pack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.klinkText)
            Spacer()
            if let recorder = appState.packRecorder {
                Text("\(recorder.recordedKeys.count) key(s) recorded")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.klinkTextSecondary)
                autoRecordButton(recorder: recorder)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    func autoRecordButton(recorder: PackRecorder) -> some View {
        let isAuto = recorder.state == .autoRecording
        Button {
            if isAuto { recorder.stopAutoRecording() } else { recorder.startAutoRecording() }
        } label: {
            Label(isAuto ? "Stop Auto" : "Auto-Record",
                  systemImage: isAuto ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isAuto ? Color.red : theme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill((isAuto ? Color.red : theme.accent).opacity(0.12))
        )
    }
}

// MARK: - Metadata

private extension RecordPackView {
    var metadataSection: some View {
        HStack(spacing: 12) {
            metaField("PACK NAME", placeholder: "My Custom Pack", text: $packName)
            metaField("AUTHOR", placeholder: "Your name", text: $authorName)
                .frame(maxWidth: 180)
        }
    }

    func metaField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.klinkTextSecondary)
                .tracking(0.8)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.klinkText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.klinkSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.klinkSurfaceHigh, lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Status

private extension RecordPackView {
    var statusSection: some View {
        HStack(spacing: 10) {
            statusIcon
            Text(statusMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
            Spacer()
            if let recorder = appState.packRecorder,
               case .awaitingPress = recorder.state {
                Button("Cancel") { recorder.cancelListening() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.klinkTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statusBgColor)
        )
    }

    @ViewBuilder
    var statusIcon: some View {
        if let recorder = appState.packRecorder {
            switch recorder.state {
            case .idle:
                Image(systemName: "mic")
                    .foregroundStyle(Color.klinkTextSecondary)
            case .autoRecording:
                Image(systemName: "waveform.and.mic")
                    .foregroundStyle(theme.accent)
            case .awaitingPress:
                Image(systemName: "keyboard")
                    .foregroundStyle(theme.accent)
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundStyle(Color.red)
            }
        } else {
            Image(systemName: "mic")
                .foregroundStyle(Color.klinkTextSecondary)
        }
    }

    var statusMessage: String {
        guard let recorder = appState.packRecorder else { return "Opening recorder..." }
        switch recorder.state {
        case .idle:
            return recorder.recordedKeys.isEmpty
                ? "Click any key above to record it, or use Auto-Record"
                : "\(recorder.recordedKeys.count) key(s) recorded — click to re-record, or save"
        case .autoRecording:
            return recorder.recordedKeys.isEmpty
                ? "Type any key — it will be recorded automatically"
                : "\(recorder.recordedKeys.count) key(s) recorded — keep typing to add more"
        case .awaitingPress(_, let lbl):
            return "Press [\(lbl)] on your physical keyboard to record..."
        case .recording(_, let lbl):
            return "Holding \(lbl) — release to capture up sound too"
        }
    }

    var statusColor: Color {
        guard let recorder = appState.packRecorder else { return Color.klinkTextSecondary }
        switch recorder.state {
        case .idle:                          return Color.klinkTextSecondary
        case .autoRecording, .awaitingPress: return theme.accent
        case .recording:                     return Color.red
        }
    }

    var statusBgColor: Color {
        guard let recorder = appState.packRecorder else { return Color.klinkSurface }
        switch recorder.state {
        case .idle:                          return Color.klinkSurface
        case .autoRecording, .awaitingPress: return theme.accent.opacity(0.08)
        case .recording:                     return Color.red.opacity(0.08)
        }
    }
}

// MARK: - Keyboard + Mic permission

private extension RecordPackView {
    @ViewBuilder
    var keyboardSection: some View {
        if let recorder = appState.packRecorder {
            KeyboardLayoutView(
                recorder: recorder,
                onKeyTap: { keycode, lbl in
                    recorder.startListening(forKey: keycode, label: lbl)
                },
                onKeyPreview: { keycode, _ in
                    recorder.previewRecording(forKey: keycode)
                }
            )
        }
    }

    var micPermissionCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(Color.klinkWarning)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text("Microphone access denied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.klinkText)
                Text("System Settings → Privacy & Security → Microphone → enable KlinkMac")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.klinkTextSecondary)
            }
            Spacer()
            Button("Open Settings") {
                let privacyMicPath = "x-apple.systempreferences:" +
                    "com.apple.preference.security?Privacy_Microphone"
                // swiftlint:disable:next force_unwrapping
                NSWorkspace.shared.open(URL(string: privacyMicPath)!)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.klinkWarning)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.klinkWarning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.klinkWarning.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Footer + Actions

private extension RecordPackView {
    var footerBar: some View {
        HStack(spacing: 10) {
            if let msg = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.klinkWarning)
                    .font(.system(size: 12))
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.klinkWarning)
            }
            Spacer()
            Button("Cancel") {
                appState.closeRecordPackWindow()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color.klinkTextSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.klinkSurface, in: RoundedRectangle(cornerRadius: 8))

            Button(action: savePack) {
                let count = appState.packRecorder?.recordedKeys.count ?? 0
                Text(count > 0 ? "Save Pack (\(count) keys)" : "Save Pack")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(canSave ? Color.klinkText : Color.klinkTextSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(canSave ? theme.accent : Color.klinkSurface)
            )
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    var canSave: Bool {
        !packName.trimmingCharacters(in: .whitespaces).isEmpty
            && (appState.packRecorder?.recordedKeys.isEmpty == false)
    }

    func savePack() {
        guard let recorder = appState.packRecorder else { return }
        let name = packName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { errorMessage = "Pack name is required."; return }
        errorMessage = nil
        do {
            let url = try recorder.savePack(name: name, author: authorName)
            appState.discoverPacks()
            if let newPack = appState.installedPacks.first(where: { $0.url == url }) {
                appState.selectPack(newPack)
            }
            appState.closeRecordPackWindow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
