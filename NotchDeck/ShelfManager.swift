import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let added: Date
    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var size: String {
        let v = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: v, countStyle: .file)
    }
    static func == (a: ShelfItem, b: ShelfItem) -> Bool { a.id == b.id }
}

final class ShelfManager: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var isDragTarget = false
    @Published var status: String?

    private let storageKey = "shelfItems"
    private let defaults = UserDefaults.standard

    init() {
        restore()
    }

    func add(urls: [URL]) {
        for u in urls where !items.contains(where: { $0.url == u }) {
            items.insert(ShelfItem(url: u, added: Date()), at: 0)
        }
        persist()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }

    func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
        flash("Path copied")
    }

    func copyFiles() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
        flash("\(items.count) file\(items.count == 1 ? "" : "s") copied")
    }

    func airdrop() {
        guard !items.isEmpty, let svc = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        svc.perform(withItems: items.map { $0.url })
    }

    func compress() {
        guard let first = items.first else { return }
        let dir = first.url.deletingLastPathComponent()
        let name = items.count == 1 ? first.url.deletingPathExtension().lastPathComponent : "Archive"
        var out = dir.appendingPathComponent(name + ".zip")
        var n = 2
        while FileManager.default.fileExists(atPath: out.path) { out = dir.appendingPathComponent("\(name) \(n).zip"); n += 1 }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-r", "-q", out.lastPathComponent] + items.map { $0.url.lastPathComponent }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.add(urls: [out])
                self?.flash("Zipped to \(out.lastPathComponent)")
            }
        }
        try? p.run()
    }

    func moveToDownloads() {
        let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var moved = 0
        for it in items {
            let dest = dl.appendingPathComponent(it.name)
            if (try? FileManager.default.moveItem(at: it.url, to: dest)) != nil { moved += 1 }
        }
        items.removeAll()
        persist()
        flash("Moved \(moved) to Downloads")
    }

    /// Re-check the files on disk; anything the user deleted or moved away drops off the shelf.
    func refresh() {
        let before = items.count
        items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        if items.count != before { persist() }
    }

    // MARK: - Persistence

    /// Bookmarks rather than paths, so a file that gets renamed or moved is still found.
    private func persist() {
        let payload: [[String: Any]] = items.compactMap { item in
            guard let data = try? item.url.bookmarkData(options: [],
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) else { return nil }
            return ["bookmark": data, "added": item.added.timeIntervalSince1970]
        }
        defaults.set(payload, forKey: storageKey)
    }

    private func restore() {
        guard let raw = defaults.array(forKey: storageKey) as? [[String: Any]] else { return }
        var restored: [ShelfItem] = []
        var changed = false
        for entry in raw {
            guard let data = entry["bookmark"] as? Data else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else {
                changed = true
                continue
            }
            if stale { changed = true }
            let added = entry["added"] as? TimeInterval ?? Date().timeIntervalSince1970
            restored.append(ShelfItem(url: url, added: Date(timeIntervalSince1970: added)))
        }
        items = restored
        if changed { persist() }
    }

    private func flash(_ s: String) {
        status = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in if self?.status == s { self?.status = nil } }
    }
}
