import Foundation
import UIKit

@MainActor
final class BlueprintService: ObservableObject {
    @Published var scans: [HomeScan] = []
    @Published var utilities: [BuriedUtility] = []

    private let scansKey = "prvio.blueprints.scans"
    private let utilsKey = "prvio.blueprints.utilities"

    init() { load() }

    // MARK: - Storage directory

    static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Blueprints", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    func fileURL(_ name: String) -> URL { Self.dir.appendingPathComponent(name) }

    // MARK: - Load / Save

    func load() {
        if let d = UserDefaults.standard.data(forKey: scansKey),
           let v = try? JSONDecoder().decode([HomeScan].self, from: d) {
            scans = v.sorted { $0.createdAt > $1.createdAt }
        }
        if let d = UserDefaults.standard.data(forKey: utilsKey),
           let v = try? JSONDecoder().decode([BuriedUtility].self, from: d) {
            utilities = v.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func saveScans() {
        if let d = try? JSONEncoder().encode(scans) { UserDefaults.standard.set(d, forKey: scansKey) }
    }
    private func saveUtils() {
        if let d = try? JSONEncoder().encode(utilities) { UserDefaults.standard.set(d, forKey: utilsKey) }
    }

    // MARK: - Scans / plans

    @discardableResult
    func addScanData(name: String, kind: String, data: Data, ext: String, format: String, notes: String = "") -> HomeScan {
        let fileName = "\(UUID().uuidString).\(ext)"
        try? data.write(to: fileURL(fileName))
        let scan = HomeScan(name: name, kind: kind, fileName: fileName, fileFormat: format, notes: notes)
        scans.insert(scan, at: 0)
        saveScans()
        return scan
    }

    @discardableResult
    func addScanFile(name: String, kind: String, sourceURL: URL, format: String, notes: String = "") -> HomeScan? {
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let dest = fileURL(fileName)
        // Handle security-scoped URLs from the file importer.
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            // Fall back to reading the bytes directly.
            guard let data = try? Data(contentsOf: sourceURL) else { return nil }
            try? data.write(to: dest)
        }
        let scan = HomeScan(name: name, kind: kind, fileName: fileName, fileFormat: format, notes: notes)
        scans.insert(scan, at: 0)
        saveScans()
        return scan
    }

    func deleteScan(_ s: HomeScan) {
        try? FileManager.default.removeItem(at: fileURL(s.fileName))
        scans.removeAll { $0.id == s.id }
        saveScans()
    }

    func renameScan(_ s: HomeScan, to newName: String) {
        guard let idx = scans.firstIndex(where: { $0.id == s.id }) else { return }
        scans[idx].name = newName
        saveScans()
    }

    func image(for scan: HomeScan) -> UIImage? {
        guard scan.fileFormat == "image" else { return nil }
        return UIImage(contentsOfFile: fileURL(scan.fileName).path)
    }

    // MARK: - Buried utilities

    func addUtility(_ u: BuriedUtility, photo: Data?) {
        var item = u
        if let photo {
            let pn = "\(UUID().uuidString).jpg"
            try? photo.write(to: fileURL(pn))
            item.photoName = pn
        }
        utilities.insert(item, at: 0)
        saveUtils()
    }

    func updateUtility(_ u: BuriedUtility) {
        guard let idx = utilities.firstIndex(where: { $0.id == u.id }) else { return }
        utilities[idx] = u
        saveUtils()
    }

    func deleteUtility(_ u: BuriedUtility) {
        if let pn = u.photoName { try? FileManager.default.removeItem(at: fileURL(pn)) }
        utilities.removeAll { $0.id == u.id }
        saveUtils()
    }

    func utilityPhoto(_ u: BuriedUtility) -> UIImage? {
        guard let pn = u.photoName else { return nil }
        return UIImage(contentsOfFile: fileURL(pn).path)
    }
}
