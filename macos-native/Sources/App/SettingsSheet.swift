import SwiftUI

public struct SettingsSheet: View {
    @ObservedObject var settings = SettingsStore.shared
    @Environment(\.presentationMode) var presentationMode

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Google Gemini API Key:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                SecureField("Enter GEMINI_API_KEY", text: $settings.apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                HStack {
                    Text("Stored locally in application preferences.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Link("Get an API key ↗", destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Browser Cookies (Bypass Bot Verification):")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Picker("", selection: $settings.browserCookies) {
                    Text("None (Default)").tag("none")
                    Text("Chrome").tag("chrome")
                    Text("Brave").tag("brave")
                    Text("Safari").tag("safari")
                    Text("Firefox").tag("firefox")
                    Text("Edge").tag("edge")
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 180)

                Text("If YouTube shows 'Sign in to confirm you're not a bot', select your browser to borrow your active login session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Files Base Directory:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("Base Directory", text: $settings.saveDirectoryPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Choose...") {
                        selectFolder()
                    }
                }
                Text("Summaries are saved to base/summaries, transcripts to base/transcriptions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred Caption Languages:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g. en or pl,en", text: $settings.languagePreferences)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("Comma-separated list in priority order. Defaults to English first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 460)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}
