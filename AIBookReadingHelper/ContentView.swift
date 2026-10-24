import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraController()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let image = camera.capturedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    switch camera.status {
                    case .idle, .running:
                        CameraPreviewView(session: camera.session)
                    case .unauthorized:
                        notice("Camera access is turned off. Turn it on in System Settings > Privacy & Security > Camera, then reopen the app.")
                    case .unavailable:
                        notice("No camera was found.")
                    }
                }
            }

            Divider()

            HStack {
                if let errorMessage = camera.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Spacer()
                if camera.capturedImage == nil {
                    Button("Capture page", systemImage: "camera") {
                        camera.capturePage()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(camera.status != .running)
                } else {
                    Button("Retake", systemImage: "arrow.counterclockwise") {
                        camera.retake()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 520)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
    }
}
