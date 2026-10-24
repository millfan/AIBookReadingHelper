import SwiftUI

/// The app's Settings window (Cmd+,), where the Google Cloud API key is entered.
struct SettingsView: View {
    @AppStorage(SettingsKey.googleAPIKey) private var apiKey = ""

    var body: some View {
        Form {
            SecureField("Google Cloud API key", text: $apiKey)
            Text("Used only when View > Google Translation is chosen. Create a key for the Cloud Translation API in the Google Cloud console. Apple Translation needs no key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 460)
    }
}
