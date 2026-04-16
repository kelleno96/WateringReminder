//
//  PlantCameraView.swift
//  WateringReminder
//
//  Custom camera UI that previews the live feed full-screen with a circular
//  viewfinder in the center. The area outside the circle is dimmed so the
//  user sees exactly what the final icon will look like.
//
//  Captured photos are cropped to the circle's square bounding box and
//  downscaled in-memory. No data ever leaves the device.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Public SwiftUI view

struct PlantCameraView: View {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var model = CameraModel()

    private static let circleDiameterFraction: CGFloat = 0.75

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                content(in: geo.size)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch model.status {
        case .configuring:
            ProgressView().tint(.white)

        case .authorized:
            ZStack {
                CameraPreview(session: model.session).ignoresSafeArea()
                dimOverlay(in: size)
                viewfinderRing(in: size)
                topBar
                captureControls(in: size)
            }

        case .denied:
            messageView(
                title: "Camera access is denied",
                body: "Allow camera access in Settings to add a plant photo.",
                showOpenSettings: true
            )

        case .unavailable:
            messageView(
                title: "Camera not available",
                body: "This device doesn't have a camera we can use. (The simulator has no camera — run on a real device.)",
                showOpenSettings: false
            )
        }
    }

    // MARK: Overlay

    private func dimOverlay(in size: CGSize) -> some View {
        let diameter = min(size.width, size.height) * Self.circleDiameterFraction
        let rect = CGRect(origin: .zero, size: size)
        let circleRect = CGRect(
            x: (size.width - diameter) / 2,
            y: (size.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        return Path { p in
            p.addRect(rect)
            p.addEllipse(in: circleRect)
        }
        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func viewfinderRing(in size: CGSize) -> some View {
        let diameter = min(size.width, size.height) * Self.circleDiameterFraction
        return Circle()
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding(.leading, 16)
                Spacer()
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private func captureControls(in size: CGSize) -> some View {
        VStack {
            Spacer()
            Button {
                Task { await performCapture(previewSize: size) }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 3)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func performCapture(previewSize: CGSize) async {
        guard let image = await model.capture(
            previewSize: previewSize,
            circleDiameterFraction: Self.circleDiameterFraction
        ) else { return }
        onCapture(image)
    }

    private func messageView(title: String, body: String, showOpenSettings: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if showOpenSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Cancel", action: onCancel)
                .foregroundStyle(.white)
                .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - Live camera preview (UIViewRepresentable)

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Camera model (owns AVFoundation plumbing)

@Observable
@MainActor
final class CameraModel: @unchecked Sendable {

    enum Status {
        case configuring
        case authorized
        case denied
        case unavailable
    }

    var status: Status = .configuring

    // AVFoundation resources are reference-typed and only touched from
    // `sessionQueue`. Marked nonisolated so they can cross into the queue's
    // closures without main-actor isolation errors.
    @ObservationIgnored nonisolated let session = AVCaptureSession()
    @ObservationIgnored nonisolated let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored nonisolated let sessionQueue = DispatchQueue(label: "plant.camera.session")

    // Hold a strong reference to the photo delegate for the duration of a capture.
    @ObservationIgnored private var activeDelegate: PhotoCaptureDelegate?

    private var didConfigure = false

    // MARK: Lifecycle

    func start() async {
        if status == .authorized { return }
        let granted = await requestPermission()
        guard granted else {
            status = .denied
            return
        }
        if didConfigure {
            startRunning()
            status = .authorized
            return
        }
        let ok = await configureSession()
        didConfigure = ok
        status = ok ? .authorized : .unavailable
    }

    func stop() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: Capture

    func capture(previewSize: CGSize, circleDiameterFraction: CGFloat) async -> UIImage? {
        guard status == .authorized else { return nil }
        let photoOutput = self.photoOutput

        return await withCheckedContinuation { [weak self] continuation in
            let delegate = PhotoCaptureDelegate { data in
                guard let data = data else {
                    continuation.resume(returning: nil)
                    return
                }
                let cropped = cropToCircle(
                    photoData: data,
                    previewSize: previewSize,
                    circleDiameterFraction: circleDiameterFraction,
                    targetSize: 300
                )
                continuation.resume(returning: cropped)
            }
            // Retain the delegate across the async callback boundary.
            Task { @MainActor in
                self?.activeDelegate = delegate
            }
            self?.sessionQueue.async {
                photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }

    // MARK: Internals

    private func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func configureSession() async -> Bool {
        let session = self.session
        let photoOutput = self.photoOutput
        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard
                    let device = AVCaptureDevice.default(
                        .builtInWideAngleCamera, for: .video, position: .back),
                    let input = try? AVCaptureDeviceInput(device: device)
                else {
                    continuation.resume(returning: false)
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)
                session.addOutput(photoOutput)
                session.commitConfiguration()
                session.startRunning()
                continuation.resume(returning: true)
            }
        }
    }

    private func startRunning() {
        let session = self.session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }
}

// MARK: - Photo delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let onFinish: (Data?) -> Void

    init(onFinish: @escaping (Data?) -> Void) {
        self.onFinish = onFinish
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            onFinish(nil)
            return
        }
        onFinish(photo.fileDataRepresentation())
    }
}

// MARK: - Cropping (pure, testable)

/// Crops the captured JPEG data to the square bounding box of the on-screen
/// circular viewfinder and downscales to `targetSize × targetSize`.
///
/// The preview layer uses `.resizeAspectFill`, so we reproduce the same
/// center-crop mapping (preview size → image coordinates) before taking the
/// square crop around the circle.
func cropToCircle(photoData: Data,
                  previewSize: CGSize,
                  circleDiameterFraction: CGFloat,
                  targetSize: CGFloat) -> UIImage? {
    guard let source = UIImage(data: photoData) else { return nil }

    // 1. Normalize EXIF orientation so pixel coords match visual layout.
    let normalized = normalizedOrientation(source)
    guard let cg = normalized.cgImage else { return nil }

    let imgW = CGFloat(cg.width)
    let imgH = CGFloat(cg.height)
    guard imgW > 0, imgH > 0, previewSize.width > 0, previewSize.height > 0 else {
        return nil
    }

    // 2. resizeAspectFill: image is scaled so it fills the preview, then
    //    center-cropped. The visible region inside the image is:
    let scale = max(previewSize.width / imgW, previewSize.height / imgH)
    let visibleW = previewSize.width / scale
    let visibleH = previewSize.height / scale
    let visibleX = (imgW - visibleW) / 2
    let visibleY = (imgH - visibleH) / 2

    // 3. Circle diameter on screen → pixels in the source image.
    let screenDiameter = min(previewSize.width, previewSize.height) * circleDiameterFraction
    let imgDiameter = screenDiameter / scale

    // 4. Square crop centered within the visible rect.
    let cropX = visibleX + (visibleW - imgDiameter) / 2
    let cropY = visibleY + (visibleH - imgDiameter) / 2
    let cropRect = CGRect(
        x: cropX.rounded(),
        y: cropY.rounded(),
        width: imgDiameter.rounded(),
        height: imgDiameter.rounded()
    )
    .integral
    .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

    guard !cropRect.isEmpty, let cropped = cg.cropping(to: cropRect) else { return nil }
    let croppedImage = UIImage(cgImage: cropped)

    // 5. Downscale to targetSize × targetSize.
    let outSize = CGSize(width: targetSize, height: targetSize)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
    return renderer.image { _ in
        croppedImage.draw(in: CGRect(origin: .zero, size: outSize))
    }
}

/// Redraws an image to have `.up` orientation so pixel coords match the
/// visual layout — required before doing pixel-space cropping.
private func normalizedOrientation(_ image: UIImage) -> UIImage {
    if image.imageOrientation == .up { return image }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}
