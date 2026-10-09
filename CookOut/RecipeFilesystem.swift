import Foundation

struct RecipeFolderNode: Identifiable {
    let folder: RecipeFolder
    var children: [RecipeFolderNode]?
    var id: UUID { folder.id }
}

enum RecipeFolders {
    static func children(of parentID: UUID?, in folders: [RecipeFolder]) -> [RecipeFolder] {
        folders.filter { $0.parentID == parentID }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func ancestors(of id: UUID, in folders: [RecipeFolder]) -> [RecipeFolder] {
        let lookup = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var path: [RecipeFolder] = []
        var seen = Set<UUID>()
        var current: UUID? = id
        while let next = current, seen.insert(next).inserted, let folder = lookup[next] {
            path.insert(folder, at: 0)
            current = folder.parentID
        }
        return path
    }

    static func path(for id: UUID, in folders: [RecipeFolder]) -> String {
        ancestors(of: id, in: folders).map(\.name).joined(separator: " / ")
    }

    static func descendants(of id: UUID, in folders: [RecipeFolder]) -> Set<UUID> {
        var found: Set<UUID> = [id]
        var pending = [id]
        while let parent = pending.popLast() {
            for child in folders where child.parentID == parent {
                if found.insert(child.id).inserted { pending.append(child.id) }
            }
        }
        return found
    }

    static func tree(in folders: [RecipeFolder], parentID: UUID? = nil) -> [RecipeFolderNode] {
        func nodes(_ parent: UUID?, visited: Set<UUID>) -> [RecipeFolderNode] {
            children(of: parent, in: folders).compactMap { folder in
                guard !visited.contains(folder.id) else { return nil }
                let children = nodes(folder.id, visited: visited.union([folder.id]))
                return RecipeFolderNode(folder: folder, children: children.isEmpty ? nil : children)
            }
        }
        return nodes(parentID, visited: [])
    }

    /// Invalid links are detached, never allowed to hide recipes or loop navigation.
    static func repaired(_ folders: [RecipeFolder]) -> [RecipeFolder] {
        var seen = Set<UUID>()
        var result = folders.filter { seen.insert($0.id).inserted }
        let ids = Set(result.map(\.id))
        for index in result.indices {
            if let parent = result[index].parentID,
               !ids.contains(parent) || descendants(of: result[index].id, in: result).contains(parent) || ancestors(of: parent, in: result).count >= 64 {
                result[index].parentID = nil
            }
        }
        return result
    }

    static func starterFolders() -> [RecipeFolder] {
        var folders: [RecipeFolder] = []
        func add(_ name: String, _ symbol: String, _ color: FolderColor, _ children: [String]) {
            let root = RecipeFolder(name: name, symbol: symbol, color: color)
            folders.append(root)
            folders += children.map { RecipeFolder(name: $0, symbol: "folder.fill", color: color, parentID: root.id) }
        }
        add("Bread", "oven.fill", .mango, ["Sourdough", "Yeast breads", "Quick breads", "Flatbreads & rolls"])
        add("Sauces", "drop.fill", .coral, ["Pasta sauces", "Dressings", "Dips & spreads", "Marinades"])
        add("Desserts", "birthday.cake", .berry, ["Cakes", "Cookies", "Pies & tarts", "Frozen desserts"])
        add("Entrées", "fork.knife", .orange, ["Meat & poultry", "Seafood", "Vegetarian", "Pasta & noodles"])
        add("Cuisines", "globe.americas", .indigo, ["Italian", "Mexican", "Indian", "Chinese", "Japanese", "Thai", "Mediterranean", "Middle Eastern"])
        add("Breakfast", "sunrise", .mango, [])
        add("Soups & stews", "mug", .coral, [])
        add("Salads & sides", "carrot", .mint, [])
        add("Drinks", "cup.and.saucer", .cyan, [])
        return folders
    }
}

enum RecipeLibraryError: LocalizedError {
    case invalidArchive, unavailable, invalidFolder, duplicateName
    var errorDescription: String? {
        switch self {
        case .invalidArchive: "This cookbook file is damaged or uses an unsupported format. Your existing recipes have been kept unchanged."
        case .unavailable: "Your saved library could not be opened. The original files have been kept untouched. Reload the library after restoring access."
        case .invalidFolder: "That folder no longer exists, or this move would put a folder inside itself."
        case .duplicateName: "A folder with that name already exists here. Choose another name."
        }
    }
}

struct RecipeLibraryArchive: Codable {
    var version = 1
    var notes: [CookingNote]
    var folders: [RecipeFolder]
    var smartCollections: [RecipeSmartCollection]? = nil

    func validate() throws {
        guard (smartCollections?.count ?? 0) <= 500,
              Set((smartCollections ?? []).map(\.id)).count == (smartCollections?.count ?? 0) else { throw RecipeLibraryError.invalidArchive }
        for collection in smartCollections ?? [] { try collection.validate() }
        guard version == 1, notes.count <= 100_000, folders.count <= 10_000,
              Set(notes.map(\.id)).count == notes.count,
              Set(folders.map(\.id)).count == folders.count,
              folders.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 }),
              notes.allSatisfy({ (0...100_000).contains($0.servings) && (0...5_256_000).contains($0.prepMinutes) &&
                  (0...5_256_000).contains($0.cookMinutes) && (0...5).contains($0.rating) &&
                  (0..<Int.max).contains($0.cookCount) && $0.createdAt.timeIntervalSince1970.isFinite &&
                  $0.updatedAt.timeIntervalSince1970.isFinite }) else {
            throw RecipeLibraryError.invalidArchive
        }
    }

    func reconciled() -> RecipeLibraryArchive {
        let repaired = RecipeFolders.repaired(folders)
        let ids = Set(repaired.map(\.id))
        return RecipeLibraryArchive(notes: notes.map { note in
            var copy = note
            if let folderID = copy.folderID, !ids.contains(folderID) { copy.folderID = nil }
            return copy
        }, folders: repaired, smartCollections: smartCollections)
    }
}
