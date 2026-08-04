//  SystemBridges.swift
//  Screen Nest
//
//  Thin UIKit bridges for the three things SwiftUI cannot do on the iOS 15
//  floor without a dependency: pick a photo, share a file, open Settings.

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Photo picker

struct PhotoPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked) { presentationMode.wrappedValue.dismiss() }
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onPicked: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [onPicked] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { onPicked(image) }
            }
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Document import (Import Backup)

struct DocumentPicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked) { presentationMode.wrappedValue.dismiss() }
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPicked: (URL) -> Void
        private let dismiss: () -> Void

        init(onPicked: @escaping (URL) -> Void, dismiss: @escaping () -> Void) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            dismiss()
            guard let url = urls.first else { return }
            onPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }
    }
}

// MARK: - System settings

enum SystemSettings {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Keep the screen awake during Watch Mode

enum ScreenIdle {
    static func disableSleep(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}
