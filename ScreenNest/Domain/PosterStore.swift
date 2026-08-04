//  PosterStore.swift
//  Screen Nest
//
//  Posters are files beside the document, referenced by name — the JSON never
//  carries image data, so a large library still loads instantly.

import UIKit

final class PosterStore {

    static let shared = PosterStore()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

    private var directory: URL { DataStore.shared.postersDirectory }

    private init() {
        cache.countLimit = 80
    }

    func image(named name: String?) -> UIImage? {
        guard let name = name, !name.isEmpty else { return nil }
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Stores a downscaled JPEG and returns the file name to keep on the title.
    @discardableResult
    func save(_ image: UIImage, replacing existing: String? = nil) -> String? {
        if let existing = existing { remove(named: existing) }
        let resized = downscale(image, maxDimension: 900)
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let name = "poster-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(name)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            cache.setObject(resized, forKey: name as NSString)
            return name
        } catch {
            return nil
        }
    }

    func remove(named name: String?) {
        guard let name = name, !name.isEmpty else { return }
        cache.removeObject(forKey: name as NSString)
        try? fileManager.removeItem(at: directory.appendingPathComponent(name))
    }

    private func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
