import AVFoundation
import SwiftUI

/// Shows the live camera feed. The feed is not mirrored, so the text on a page reads the right way round.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    /// Turns the feed upside down, for a camera that sees the book upside down.
    var rotated180 = false

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        if let connection = view.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        let angle: CGFloat = rotated180 ? 180 : 0
        if let connection = nsView.previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        } else {
            nsView.frameCenterRotation = angle
        }
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            previewLayer.videoGravity = .resizeAspect
            layer = previewLayer
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
