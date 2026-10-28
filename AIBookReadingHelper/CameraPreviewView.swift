import AVFoundation
import SwiftUI

/// Shows the live camera feed, using the camera's one preview layer.
struct CameraPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    /// Turns the feed upside down, for a camera that sees the book upside down.
    var rotated180 = false

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.host(previewLayer)
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        let angle: CGFloat = rotated180 ? 180 : 0
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            if connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        } else {
            nsView.frameCenterRotation = angle
        }
    }

    final class PreviewView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func host(_ previewLayer: AVCaptureVideoPreviewLayer) {
            previewLayer.removeFromSuperlayer()
            previewLayer.frame = bounds
            previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer?.addSublayer(previewLayer)
        }
    }
}
