import Foundation

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct AppleNoteSource: Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
    let folderName: String
}

enum AppleNotesImportError: LocalizedError {
    case unavailable
    case permissionDenied(String)
    case noTextOnPasteboard

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Notes could not be opened."
        case .permissionDenied(let detail):
            "CookOut could not read Apple Notes. Allow Notes access in System Settings > Privacy & Security > Automation, then try again. \(detail)"
        case .noTextOnPasteboard:
            "Copy a recipe note in Apple Notes first, then return to CookOut and tap Paste."
        }
    }
}

@MainActor
struct AppleNotesService {
#if os(macOS)
    func loadNotes() throws -> [AppleNoteSource] {
        let source = """
        tell application "Notes"
            set noteRows to {}
            repeat with aFolder in every folder
                set folderName to "Notes"
                try
                    set folderName to name of aFolder as text
                end try
                repeat with aNote in every note of aFolder
                    try
                        set noteID to id of aNote as text
                        set noteName to name of aNote as text
                        set noteText to plaintext of aNote as text
                        set end of noteRows to {noteID, noteName, noteText, folderName}
                    end try
                end repeat
            end repeat
            return noteRows
        end tell
        """
        guard let script = NSAppleScript(source: source) else { throw AppleNotesImportError.unavailable }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let detail = (errorInfo[NSAppleScript.errorMessage] as? String) ?? ""
            throw AppleNotesImportError.permissionDenied(detail)
        }

        guard result.numberOfItems > 0 else { return [] }
        var notes: [AppleNoteSource] = []
        for index in 1...result.numberOfItems {
            guard let row = result.atIndex(index), row.numberOfItems >= 3 else { continue }
            let id = row.atIndex(1)?.stringValue ?? UUID().uuidString
            let title = row.atIndex(2)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Note"
            let text = row.atIndex(3)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let folder = row.atIndex(4)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Notes"
            guard !text.isEmpty else { continue }
            notes.append(AppleNoteSource(id: id, title: title.isEmpty ? "Untitled Note" : title, text: text, folderName: folder))
        }
        return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
#else
    func pastedNote() throws -> AppleNoteSource {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw AppleNotesImportError.noTextOnPasteboard
        }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Apple Notes Recipe"
        return AppleNoteSource(id: UUID().uuidString, title: firstLine, text: text, folderName: "Apple Notes")
    }
#endif
}
