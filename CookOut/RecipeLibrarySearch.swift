import Foundation

enum RecipeFolderScope: Hashable {
    case all, unfiled, folder(UUID)
}

/// Shared tag identity keeps imported spellings and editor suggestions consistent.
enum RecipeTags {
    nonisolated static func key(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { value in
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(key(tag)).inserted else { return nil }
            return tag
        }
    }

    nonisolated static func parse(_ text: String) -> [String] {
        normalized(text.components(separatedBy: CharacterSet(charactersIn: ",\n\r")))
    }

    static func available(in notes: [CookingNote]) -> [String] {
        normalized(notes.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

enum RecipeLibrarySearch {
    static func isActive(query: String, tags: Set<String>) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tags.isEmpty
    }

    static func filter(_ notes: [CookingNote], folders: [RecipeFolder], query: String,
                       tags: Set<String>, folderScope: RecipeFolderScope,
                       searchAllFolders: Bool, favoritesOnly: Bool) -> [CookingNote] {
        let terms = query.split(whereSeparator: \.isWhitespace).map { RecipeTags.key(String($0)) }
        let tagKeys = Set(RecipeTags.normalized(Array(tags)).map(RecipeTags.key))
        let crossesFolders = searchAllFolders && isActive(query: query, tags: tags)
        // A malformed duplicate folder ID must not crash a library search.
        let folderNames = Dictionary(folders.map { ($0.id, RecipeFolders.path(for: $0.id, in: folders)) }, uniquingKeysWith: { first, _ in first })
        let scopedIDs: Set<UUID>
        if case .folder(let id) = folderScope { scopedIDs = RecipeFolders.descendants(of: id, in: folders) }
        else { scopedIDs = [] }
        return notes.filter { note in
            if favoritesOnly && !note.isFavorite { return false }
            if !crossesFolders {
                switch folderScope {
                case .all: break
                case .unfiled: if note.folderID != nil { return false }
                case .folder: if !(note.folderID.map(scopedIDs.contains) ?? false) { return false }
                }
            }
            let recipeTags = Set(RecipeTags.normalized(note.tags).map(RecipeTags.key))
            guard tagKeys.isSubset(of: recipeTags) else { return false }
            let folderName = note.folderID.flatMap { folderNames[$0] } ?? "Unfiled"
            let text = RecipeTags.key(([note.title, note.body, folderName] + note.ingredients + note.steps + note.tags).joined(separator: "\n"))
            return terms.allSatisfy { text.contains($0) }
        }
    }
}
