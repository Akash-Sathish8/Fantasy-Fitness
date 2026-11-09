//
//  MealPhotoPicker.swift
//  Fantasy Fitness
//
//  Getting a photo of a meal for the plate reader: the camera or the photo library, and
//  shrinking the photo before it's sent.
//

import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI

/// A meal photo the player picked: just taken with the camera, or from their library.
enum MealPhotoSource {
    case camera(UIImage)
    case library(PhotosPickerItem)
}

/// A meal photo ready for the plate reader: a JPEG at most 1280 px on its long edge (the
/// model reads no finer detail than that), redrawn from the pixels, so it carries no
/// location or other metadata. It's never saved, on the phone or on the server.
nonisolated struct MealPhoto: Equatable, Sendable {
    let jpeg: Data
    let preview: UIImage

    static let longEdge: CGFloat = 1280
    /// scan-meal refuses anything larger.
    static let maxBytes = 3_000_000

    /// Opens, shrinks and re-encodes the photo off the main thread. Nil when it can't be read.
    @concurrent
    static func prepare(_ source: MealPhotoSource) async -> MealPhoto? {
        switch source {
        case .camera(let image):
            return redrawn(image)
        case .library(let item):
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            return decoded(data)
        }
    }

    /// Library photos can be 48 MP: decode straight to the small size instead of whole.
    private static func decoded(_ data: Data) -> MealPhoto? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,  // upright, as the player sees it
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: longEdge,
              ] as CFDictionary)
        else { return nil }
        return encoded(UIImage(cgImage: image))
    }

    private static func redrawn(_ image: UIImage) -> MealPhoto? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard pixels.width > 0, pixels.height > 0 else { return nil }
        let factor = min(1, longEdge / max(pixels.width, pixels.height))
        let size = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))  // applies the photo's orientation
        }
        return encoded(small)
    }

    private static func encoded(_ image: UIImage) -> MealPhoto? {
        for quality in [0.7, 0.5, 0.3] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return MealPhoto(jpeg: jpeg, preview: image)
            }
        }
        return nil
    }
}

/// "Snap a photo": asks camera or library, then hands the photo to `onPick` once the
/// picker has closed, so the caller can present a sheet straight away. Without a camera
/// it opens the library directly. The library needs no permission; the
/// camera asks once (NSCameraUsageDescription) and, if it was turned off, offers Settings.
/// The first time, it says where the photo goes and asks to continue: photos are sent to
/// a third-party AI (App Review guideline 5.1.2).
struct MealPhotoButton: View {
    let onPick: (MealPhotoSource) -> Void

    @AppStorage("allowsMealPhotoReading") private var allowsPhotoReading = false
    @State private var askingConsent = false

    @State private var choosingSource = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var picked: MealPhotoSource?
    @State private var cameraOff = false

    var body: some View {
        Button(action: start) {
            Label(CameraPicker.isAvailable ? "Snap a photo" : "Choose a photo",
                  systemImage: CameraPicker.isAvailable ? "camera" : "photo")
        }
        .buttonStyle(.chunky(.wood, minHeight: 48, fontSize: 17))
        .alert("Meal photos go to Claude", isPresented: $askingConsent) {
            Button("Continue") {
                allowsPhotoReading = true
                chooseSource()
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To list what's on your plate, each photo is sent to Anthropic's Claude AI. Fantasy Fitness doesn't keep your photos.")
        }
        .confirmationDialog("Photo of your meal", isPresented: $choosingSource) {
            Button("Take photo") { Task { await openCamera() } }
            Button("Choose from Photos") { showingLibrary = true }
        }
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            picked = .library(item)
            deliver()
        }
        .onChange(of: showingLibrary) { deliver() }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: deliver) {
            CameraPicker { picked = .camera($0) }
                .ignoresSafeArea()
        }
        .alert("Camera is off", isPresented: $cameraOff) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Choose a photo") { showingLibrary = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To snap your meals, turn on Camera for Fantasy Fitness in Settings. You can also choose a photo you've taken.")
        }
    }

    private func start() {
        UIApplication.shared.endEditing()  // or the grams keyboard comes back afterwards
        if allowsPhotoReading { chooseSource() } else { askingConsent = true }
    }

    private func chooseSource() {
        if CameraPicker.isAvailable { choosingSource = true } else { showingLibrary = true }
    }

    private func openCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { showingCamera = true } else { cameraOff = true }
        default:
            cameraOff = true
        }
    }

    /// Hands the photo over once its picker has closed.
    private func deliver() {
        guard !showingLibrary, !showingCamera, let photo = picked else { return }
        picked = nil
        onPick(photo)
    }
}

/// The system camera, for one photo. Only where there is a camera (not the simulator).
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
