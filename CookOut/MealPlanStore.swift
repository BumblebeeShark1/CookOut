import Foundation
import Combine

struct PlannedMeal: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var day: String
    var meal: MealType
    var recipeID: UUID
    var recipeTitle: String
    var servings: Double
    var recipeSnapshot: CookingNote?
    var notes: String?
    var isLocked: Bool?
    var isCompleted: Bool?
    var leftoversFromID: UUID?
    var preparedServings: Double?
}

struct MealPlanDocument: Codable {
    var version = 1
    var entries: [PlannedMeal] = []
    var preferences: PlanningPreferences?
    var checkedGroceryKeys: [String]?
    var prepNotesByWeek: [String: [String]]?

    func validate() throws {
        guard version == 1, entries.count <= 10_000, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ MealPlanDate.date($0.day) != nil && !$0.recipeTitle.isEmpty && $0.recipeTitle.count <= 500 && $0.servings.isFinite && (0.25...1000).contains($0.servings) }) else {
            throw MealPlanError.invalidFile
        }
        try preferences?.validate()
        guard (checkedGroceryKeys?.count ?? 0) <= 10_000,
              checkedGroceryKeys?.allSatisfy({ !$0.isEmpty && $0.count <= 2000 }) != false else { throw MealPlanError.invalidFile }
        guard (prepNotesByWeek?.count ?? 0) <= 1000, prepNotesByWeek?.allSatisfy({ day, notes in
            MealPlanDate.date(day) != nil && notes.count <= 12 && notes.allSatisfy { $0.count <= 1000 }
        }) != false else { throw MealPlanError.invalidFile }
        for entry in entries {
            guard (entry.notes?.count ?? 0) <= 2000 else { throw MealPlanError.invalidFile }
            if let portions = entry.preparedServings, !portions.isFinite || portions < entry.servings || portions > 1000 { throw MealPlanError.invalidFile }
            if let note = entry.recipeSnapshot {
                guard note.id == entry.recipeID, note.title.count <= 2000, note.ingredients.count <= 500,
                      note.steps.count <= 500, (note.sourceURL == nil || RecipeSourceURL.valid(note.sourceURL!) != nil) else { throw MealPlanError.invalidFile }
            }
            if let parent = entry.leftoversFromID {
                guard parent != entry.id, let source = entries.first(where: { $0.id == parent }),
                      source.recipeID == entry.recipeID, source.day < entry.day else { throw MealPlanError.invalidFile }
            }
        }
    }
}

enum MealPlanDate {
    static func key(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }
    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              key.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }),
              let year = Int(parts[0]), (1900...9999).contains(year), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)), self.key(date) == key else { return nil }
        return date
    }
}

enum MealPlanError: LocalizedError {
    case invalidFile, tooManyEntries
    var errorDescription: String? {
        switch self {
        case .invalidFile: "The saved meal plan could not be read. It has been kept untouched. Try reloading, or restore a valid copy of meal-plan.json."
        case .tooManyEntries: "The meal planner has reached its limit. Remove an older meal before adding another."
        }
    }
}

@MainActor
final class MealPlanStore: ObservableObject {
    @Published private(set) var entries: [PlannedMeal] = []
    @Published private(set) var isAvailable = true
    @Published private(set) var preferences = PlanningPreferences()
    @Published private(set) var checkedGroceryKeys: Set<String> = []
    @Published private(set) var prepNotesByWeek: [String: [String]] = [:]
    @Published var errorMessage: String?
    private let fileURL: URL
    private let writeData: (Data, URL) throws -> Void

    init(fileURL: URL? = nil, writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CookOut", isDirectory: true).appendingPathComponent("meal-plan.json")
        self.writeData = writeData
        reload()
    }

    func reload() {
        do {
            let document = try read(fileURL)
            publish(document)
            isAvailable = true
            errorMessage = nil
        } catch {
            isAvailable = false
            errorMessage = message(for: error, saving: false)
        }
    }

    @discardableResult func save(_ meal: PlannedMeal) -> Bool {
        mutate { document in
            if let index = document.entries.firstIndex(where: { $0.id == meal.id }) {
                guard document.entries[index].isLocked != true || document.entries[index] == meal else { throw MealPlanningError.planChanged }
                document.entries[index] = meal
            }
            else {
                guard document.entries.count < 10_000 else { throw MealPlanError.tooManyEntries }
                document.entries.append(meal)
            }
        }
    }

    @discardableResult func remove(_ meal: PlannedMeal) -> Bool {
        mutate { document in
            guard document.entries.first(where: { $0.id == meal.id })?.isLocked != true else { throw MealPlanningError.planChanged }
            document.entries.removeAll { $0.id == meal.id }
            for index in document.entries.indices where document.entries[index].leftoversFromID == meal.id {
                document.entries[index].leftoversFromID = nil
                document.entries[index].notes = "Original cooking entry removed. Prepare this meal separately."
            }
            Self.reconcilePreparedServings(&document)
        }
    }

    @discardableResult func savePreferences(_ preferences: PlanningPreferences) -> Bool {
        mutate { document in try preferences.validate(); document.preferences = preferences }
    }

    @discardableResult func toggleGrocery(_ key: String) -> Bool {
        mutate { document in
            var checked = Set(document.checkedGroceryKeys ?? [])
            if !checked.insert(key).inserted { checked.remove(key) }
            document.checkedGroceryKeys = checked.sorted()
        }
    }

    @discardableResult func apply(_ draft: MealPlanDraft) -> Bool {
        mutate { document in
            let current = document.entries.filter { draft.days.contains($0.day) }.sorted { $0.id.uuidString < $1.id.uuidString }
            let original = draft.baseline.sorted { $0.id.uuidString < $1.id.uuidString }
            guard current == original, (document.preferences ?? PlanningPreferences()) == draft.preferences else { throw MealPlanningError.planChanged }
            // The draft only fills empty slots. Applying it is a single atomic
            // write, preserving every existing or locked meal.
            let occupied = Set(current.map { MealPlanningEngine.slot($0.day, $0.meal) })
            var added = Set<String>()
            guard draft.entries.allSatisfy({ draft.days.contains($0.day) && !occupied.contains(MealPlanningEngine.slot($0.day, $0.meal)) && added.insert(MealPlanningEngine.slot($0.day, $0.meal)).inserted }) else { throw MealPlanningError.invalidDraft }
            let candidates = draft.entries.compactMap { entry -> PlanningCandidate? in
                guard let note = entry.recipeSnapshot else { return nil }
                return PlanningCandidate(note: note, foodGroups: RecipeFoodGroups.infer(note.ingredients), cuisine: "", minutes: note.totalMinutes > 0 ? note.totalMinutes : nil)
            }
            try MealPlanningEngine.validateDraft(draft.entries, days: draft.days, candidates: candidates, preferences: draft.preferences, occupied: current)
            document.entries += draft.entries
            document.preferences = draft.preferences
            if let day = draft.days.sorted().first {
                var notes = document.prepNotesByWeek ?? [:]; notes[day] = draft.prepNotes; document.prepNotesByWeek = notes
            }
        }
    }

    @discardableResult func move(_ meal: PlannedMeal, to day: String, mealType: MealType) -> Bool {
        mutate { document in
            guard let index = document.entries.firstIndex(where: { $0.id == meal.id }), document.entries[index].isLocked != true,
                  MealPlanDate.date(day) != nil else { throw MealPlanningError.invalidDraft }
            guard !document.entries.contains(where: { $0.id != meal.id && $0.day == day && $0.meal == mealType }) else { throw MealPlanningError.invalidDraft }
            document.entries[index].day = day
            document.entries[index].meal = mealType
            Self.detachInvalidLeftovers(&document)
        }
    }

    @discardableResult func setLocked(_ id: UUID, locked: Bool) -> Bool {
        mutate { document in
            if let index = document.entries.firstIndex(where: { $0.id == id }) { document.entries[index].isLocked = locked }
        }
    }

    @discardableResult func setCompleted(_ id: UUID, completed: Bool) -> Bool {
        mutate { document in
            if let index = document.entries.firstIndex(where: { $0.id == id }) { document.entries[index].isCompleted = completed }
        }
    }

    @discardableResult func copyWeek(from days: [String], offset: Int = 7) -> Bool {
        mutate { document in
            let source = document.entries.filter { days.contains($0.day) }
            var idMap: [UUID: UUID] = [:]
            for meal in source { idMap[meal.id] = UUID() }
            var copies: [PlannedMeal] = []
            for meal in source {
                guard let date = MealPlanDate.date(meal.day), let target = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: date) else { throw MealPlanningError.invalidDraft }
                let day = MealPlanDate.key(target)
                // Refuse the whole copy when a slot is occupied; never quietly
                // replace part of an existing week or orphan a leftover link.
                guard !document.entries.contains(where: { $0.day == day && $0.meal == meal.meal }) else { throw MealPlanningError.planChanged }
                var copy = meal
                copy.id = idMap[meal.id]!
                copy.day = day
                copy.isCompleted = false
                copy.leftoversFromID = meal.leftoversFromID.flatMap { idMap[$0] }
                copies.append(copy)
            }
            document.entries += copies
        }
    }

    private static func detachInvalidLeftovers(_ document: inout MealPlanDocument) {
        for index in document.entries.indices {
            if let parent = document.entries[index].leftoversFromID,
               !document.entries.contains(where: { $0.id == parent && $0.recipeID == document.entries[index].recipeID && $0.day < document.entries[index].day }) {
                document.entries[index].leftoversFromID = nil
                document.entries[index].notes = "Plan changed. Prepare this meal separately."
            }
        }
        reconcilePreparedServings(&document)
    }

    private static func reconcilePreparedServings(_ document: inout MealPlanDocument) {
        for index in document.entries.indices where document.entries[index].preparedServings != nil {
            let id = document.entries[index].id
            document.entries[index].preparedServings = document.entries[index].servings + document.entries.filter { $0.leftoversFromID == id }.reduce(0) { $0 + $1.servings }
        }
    }

    private func publish(_ document: MealPlanDocument) {
        entries = document.entries
        preferences = document.preferences ?? PlanningPreferences()
        checkedGroceryKeys = Set(document.checkedGroceryKeys ?? [])
        prepNotesByWeek = document.prepNotesByWeek ?? [:]
    }

    // Coordinated read-modify-write merges changes from other windows. A failed
    // read or atomic write leaves the current view and existing file intact.
    private func mutate(_ change: (inout MealPlanDocument) throws -> Void) -> Bool {
        guard isAvailable else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var operationError: Error?
            var saved: MealPlanDocument?
            coordinator.coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
                do {
                    var document = try read(url)
                    try change(&document)
                    Self.detachInvalidLeftovers(&document)
                    try document.validate()
                    let data = try JSONEncoder().encode(document)
                    guard data.count <= 20_000_000 else { throw MealPlanError.tooManyEntries }
                    try writeData(data, url)
                    saved = document
                } catch { operationError = error }
            }
            if let operationError { throw operationError }
            if let coordinationError { throw coordinationError }
            guard let saved else { throw MealPlanError.invalidFile }
            publish(saved)
            errorMessage = nil
            return true
        } catch {
            errorMessage = message(for: error, saving: true)
            return false
        }
    }

    private func read(_ url: URL) throws -> MealPlanDocument {
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20_000_000 else { throw MealPlanError.invalidFile }
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
            return MealPlanDocument()
        }
        guard data.count <= 20_000_000 else { throw MealPlanError.invalidFile }
        let document: MealPlanDocument
        do { document = try JSONDecoder().decode(MealPlanDocument.self, from: data) }
        catch { throw MealPlanError.invalidFile }
        try document.validate()
        return document
    }

    private func message(for error: Error, saving: Bool) -> String {
        if let error = error as? MealPlanError { return error.localizedDescription }
        if let error = error as? MealPlanningError { return error.localizedDescription }
        return saving ? "Your meal plan could not be saved. No changes were applied. Check available storage and try again." : "Your meal plan could not be loaded. Check access to its saved file and try reloading."
    }
}
