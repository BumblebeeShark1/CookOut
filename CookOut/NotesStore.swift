import Foundation
import Combine

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [CookingNote] = []
    @Published private(set) var folders: [RecipeFolder] = []
    private let fileURL: URL
    private let foldersURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CookOut", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("notes.json")
        foldersURL = folder.appendingPathComponent("folders.json")
        load()
        loadFolders()
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

    func markPerfected(_ note: CookingNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }), notes[index].status != .perfected else { return }
        notes[index].status = .perfected
        notes[index].updatedAt = .now
        persist()
    }

    func createFolder(name: String, symbol: String, color: FolderColor) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        folders.append(RecipeFolder(name: cleanName, symbol: symbol, color: color))
        persistFolders()
    }

    func updateFolder(_ folder: RecipeFolder, name: String, symbol: String, color: FolderColor) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        folders[index].name = cleanName
        folders[index].symbol = symbol
        folders[index].color = color
        persistFolders()
    }

    func deleteFolder(_ folder: RecipeFolder) {
        folders.removeAll { $0.id == folder.id }
        for index in notes.indices where notes[index].folderID == folder.id {
            notes[index].folderID = nil
            notes[index].updatedAt = .now
        }
        persistFolders()
        persist()
    }

    func move(_ note: CookingNote, to folderID: UUID?) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].folderID = folderID
        notes[index].updatedAt = .now
        persist()
    }

    func count(in folderID: UUID?) -> Int {
        folderID == nil ? notes.filter { $0.folderID == nil }.count : notes.filter { $0.folderID == folderID }.count
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

    private func loadFolders() {
        guard let data = try? Data(contentsOf: foldersURL),
              let decoded = try? JSONDecoder().decode([RecipeFolder].self, from: data) else { return }
        folders = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persistFolders() {
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: foldersURL, options: .atomic)
    }

    private func sort() {
        notes.sort { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
    }
}
