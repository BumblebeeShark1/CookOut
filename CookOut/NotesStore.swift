import Foundation
import Combine

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [CookingNote] = []
    private let fileURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CookOut", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("notes.json")
        load()
    }

    func save(_ note: CookingNote) {
        var updated = note
        updated.updatedAt = .now
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = updated }
        else { notes.append(updated) }
        persist()
    }

    func delete(_ note: CookingNote) { notes.removeAll { $0.id == note.id }; persist() }

    func duplicate(_ note: CookingNote) {
        var copy = note
        copy.id = UUID()
        copy.title = note.title.isEmpty ? "Copy" : "\(note.title) Copy"
        copy.isPinned = false
        copy.updatedAt = .now
        notes.append(copy)
        persist()
    }

    func togglePin(_ note: CookingNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isPinned.toggle()
        notes[index].updatedAt = .now
        persist()
    }

    func toggleFavorite(_ note: CookingNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isFavorite.toggle()
        notes[index].updatedAt = .now
        persist()
    }

    func markCooked(_ note: CookingNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].cookCount += 1
        notes[index].lastCookedAt = .now
        notes[index].updatedAt = .now
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CookingNote].self, from: data) else { return }
        notes = decoded
        sort()
    }

    private func persist() {
        sort()
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func sort() {
        notes.sort { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
    }
}
