import AppKit
import Combine

struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let text: String?
    let image: NSImage?
    let fileURL: URL?
    var pinned = false

    var kind: String {
        if fileURL != nil { return "doc" }
        if image != nil { return "photo" }
        if let t = text, t.hasPrefix("http://") || t.hasPrefix("https://") { return "link" }
        return "text.alignleft"
    }

    var title: String {
        if let u = fileURL { return u.lastPathComponent }
        if image != nil { return "Image" }
        return (text ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    static func == (a: ClipItem, b: ClipItem) -> Bool { a.id == b.id && a.pinned == b.pinned }
}

final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    private var timer: Timer?
    private var lastCount = NSPasteboard.general.changeCount
    private var ignoreNext = false
    private let maxItems = 30
    private let pinnedKey = "clipPinned"
    private let defaults = UserDefaults.standard

    func start() {
        restorePinned()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Pinned entries are the ones worth keeping across restarts; the rolling history is not.
    private func persistPinned() {
        let payload: [[String: Any]] = items.filter(\.pinned).prefix(20).compactMap { item in
            if let u = item.fileURL { return ["kind": "file", "value": u.path, "date": item.date.timeIntervalSince1970] }
            if let t = item.text { return ["kind": "text", "value": t, "date": item.date.timeIntervalSince1970] }
            return nil
        }
        defaults.set(payload, forKey: pinnedKey)
    }

    private func restorePinned() {
        guard let raw = defaults.array(forKey: pinnedKey) as? [[String: Any]] else { return }
        var restored: [ClipItem] = []
        for entry in raw {
            guard let kind = entry["kind"] as? String, let value = entry["value"] as? String else { continue }
            let date = Date(timeIntervalSince1970: entry["date"] as? TimeInterval ?? Date().timeIntervalSince1970)
            if kind == "file" {
                guard FileManager.default.fileExists(atPath: value) else { continue }
                restored.append(ClipItem(date: date, text: nil, image: nil, fileURL: URL(fileURLWithPath: value), pinned: true))
            } else {
                restored.append(ClipItem(date: date, text: value, image: nil, fileURL: nil, pinned: true))
            }
        }
        items = restored
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        if ignoreNext { ignoreNext = false; return }
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true { return }
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) == true { return }

        var item: ClipItem?
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let u = urls.first {
            item = ClipItem(date: Date(), text: nil, image: nil, fileURL: u)
        } else if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item = ClipItem(date: Date(), text: String(s.prefix(4000)), image: nil, fileURL: nil)
        } else if let img = NSImage(pasteboard: pb) {
            item = ClipItem(date: Date(), text: nil, image: img, fileURL: nil)
        }
        guard let new = item else { return }
        if let first = items.first(where: { !$0.pinned }), first.title == new.title, first.kind == new.kind { return }
        items.insert(new, at: 0)
        trim()
    }

    private func trim() {
        var unpinned = 0
        items = items.filter { it in
            if it.pinned { return true }
            unpinned += 1
            return unpinned <= maxItems
        }
    }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        ignoreNext = true
        if let u = item.fileURL { pb.writeObjects([u as NSURL]) }
        else if let img = item.image { pb.writeObjects([img]) }
        else if let t = item.text { pb.setString(t, forType: .string) }
        lastCount = pb.changeCount
    }

    func paste(_ item: ClipItem) {
        copy(item)
        SoundKit.play(.paste)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            KeyPoster.postCommandV()
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        SoundKit.play(.pin)
        persistPinned()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        persistPinned()
    }

    func clear() {
        items.removeAll { !$0.pinned }
    }
}
