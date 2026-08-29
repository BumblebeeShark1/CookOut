//
//  ContentView.swift
//  CookOut
//
//  Created by Bumblebee on 8/29/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    private enum NoteSort: String, CaseIterable, Identifiable {
        case updated = "Recently edited"
        case title = "Title"
        case rating = "Highest rated"
        case cooked = "Most cooked"
        case quickest = "Quickest"
        var id: Self { self }
    }

    @StateObject private var store = NotesStore()
    @State private var query = ""
    @State private var selectedNote: CookingNote?
    @State private var showingEditor = false
    @State private var selectedTag: String?
    @State private var sort: NoteSort = .updated
    @State private var favoritesOnly = false
    @State private var cookingNote: CookingNote?
    @State private var showingChat = false
    @State private var showingAppearance = false

    private var allTags: [String] {
        Array(Set(store.notes.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredNotes: [CookingNote] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.notes.filter { note in
            let matchesTag = selectedTag == nil || note.tags.contains { $0.caseInsensitiveCompare(selectedTag!) == .orderedSame }
            let matchesFavorite = !favoritesOnly || note.isFavorite
            let matchesSearch = search.isEmpty || note.title.localizedCaseInsensitiveContains(search) ||
                note.body.localizedCaseInsensitiveContains(search) ||
                note.tags.joined(separator: " ").localizedCaseInsensitiveContains(search)
            return matchesTag && matchesFavorite && matchesSearch
        }
        return filtered.sorted { first, second in
            if first.isPinned != second.isPinned { return first.isPinned }
            switch sort {
            case .updated: return first.updatedAt > second.updatedAt
            case .title: return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            case .rating: return first.rating > second.rating
            case .cooked: return first.cookCount > second.cookCount
            case .quickest:
                if first.totalMinutes == 0 { return false }
                if second.totalMinutes == 0 { return true }
                return first.totalMinutes < second.totalMinutes
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredNotes.isEmpty {
                    ContentUnavailableView(
                        store.notes.isEmpty ? "Start your cookbook" : "No matching recipes",
                        systemImage: store.notes.isEmpty ? "fork.knife.circle" : "line.3.horizontal.decrease.circle",
                        description: Text(store.notes.isEmpty ? "Save an idea, recipe, or kitchen experiment." : "Clear a search, tag, or favorites filter.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            LibrarySummary(notes: store.notes)
                            if !allTags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        FilterChip(title: "All", isSelected: selectedTag == nil) { selectedTag = nil }
                                        ForEach(allTags, id: \.self) { tag in
                                            FilterChip(title: tag, isSelected: selectedTag == tag) { selectedTag = tag }
                                        }
                                    }
                                }
                            }
                            ForEach(filteredNotes) { note in
                                Button {
                                    selectedNote = note
                                    showingEditor = true
                                } label: {
                                    NoteCard(note: note)
                                }
                                .buttonStyle(.plain)
                                    .accessibilityLabel("Edit \(note.title.isEmpty ? "untitled recipe" : note.title)")
                                    .contextMenu {
                                        Button("Edit", systemImage: "pencil") {
                                        selectedNote = note
                                        showingEditor = true
                                        }
                                        if !note.steps.isEmpty || !note.ingredients.isEmpty {
                                            Button("Start cooking", systemImage: "play.fill") { cookingNote = note }
                                        }
                                        Button(note.isFavorite ? "Remove Favorite" : "Favorite", systemImage: note.isFavorite ? "heart.slash" : "heart") { store.toggleFavorite(note) }
                                        Button(note.isPinned ? "Unpin" : "Pin", systemImage: "pin") { store.togglePin(note) }
                                        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(note) }
                                        ShareLink(item: shareText(for: note)) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button("Delete", systemImage: "trash", role: .destructive) { store.delete(note) }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background {
                ZStack { palette.background(for: colorScheme); palette.softGradient }.ignoresSafeArea()
            }
            .navigationTitle("CookOut")
            .searchable(text: $query, prompt: "Search your kitchen notes")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { showingAppearance = true } label: { Label("Appearance", systemImage: "paintpalette.fill") }
                }
                ToolbarItem {
                    Menu {
                        Toggle("Favorites only", isOn: $favoritesOnly)
                        Divider()
                        Picker("Sort", selection: $sort) {
                            ForEach(NoteSort.allCases) { option in Text(option.rawValue).tag(option) }
                        }
                    } label: { Label("Sort notes", systemImage: "arrow.up.arrow.down") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedNote = nil
                        showingEditor = true
                    } label: { Label("New recipe", systemImage: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { showingChat = true } label: {
                    Label("Ask the Cooking ChatBot", systemImage: "bubble.left.and.sparkles")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal).padding(.top, 8)
                .background(.bar)
            }
            .sheet(isPresented: $showingEditor, onDismiss: { selectedNote = nil }) {
                NoteEditor(note: selectedNote, onSave: store.save)
            }
            .sheet(item: $cookingNote) { note in
                CookingModeView(note: note) { store.markCooked(note) }
            }
            .sheet(isPresented: $showingChat) {
                CookingChatView(cookbook: store.notes)
            }
            .sheet(isPresented: $showingAppearance) { AppearanceSettingsView() }
        }
        .tint(palette.accent)
    }

    private func shareText(for note: CookingNote) -> String {
        let ingredients = note.ingredients.isEmpty ? "" : "\n\nIngredients\n" + note.ingredients.map { "• \($0)" }.joined(separator: "\n")
        let steps = note.steps.isEmpty ? "" : "\n\nDirections\n" + note.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let tags = note.tags.isEmpty ? "" : "\n\nTags: " + note.tags.joined(separator: ", ")
        return "\(note.title)\n\n\(note.body)\(ingredients)\(steps)\(tags)"
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.medium)) }
            .buttonStyle(.borderedProminent)
            .tint(isSelected ? .orange : .secondary.opacity(0.35))
    }
}

private struct LibrarySummary: View {
    @Environment(\.cookOutPalette) private var palette
    let notes: [CookingNote]
    private var favorites: Int { notes.filter(\.isFavorite).count }
    private var timesCooked: Int { notes.reduce(0) { $0 + $1.cookCount } }

    var body: some View {
        HStack(spacing: 0) {
            metric("\(notes.count)", "Recipes", "book.closed")
            Divider().frame(height: 36)
            metric("\(favorites)", "Favorites", "heart.fill")
            Divider().frame(height: 36)
            metric("\(timesCooked)", "Cooked", "flame.fill")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .top) {
            Capsule().fill(palette.gradient).frame(height: 3).padding(.horizontal, 16)
        }
    }

    private func metric(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Label(value, systemImage: symbol).font(.headline).foregroundStyle(.orange)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct NoteCard: View {
    let note: CookingNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: note.mealType.symbol)
                    .font(.headline).foregroundStyle(.white).padding(8)
                    .background(note.mealType.tint.gradient, in: RoundedRectangle(cornerRadius: 10))
                Text(note.title.isEmpty ? "Untitled note" : note.title).font(.headline)
                Spacer()
                if note.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.red) }
                if note.isPinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
            }
            Text(note.body.isEmpty ? "No details yet" : note.body)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            HStack(spacing: 14) {
                Label(note.mealType.rawValue, systemImage: note.mealType.symbol)
                if note.totalMinutes > 0 { Label("\(note.totalMinutes) min", systemImage: "clock") }
                Label("Serves \(note.servings)", systemImage: "person.2")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(note.status.rawValue)
                .font(.caption2.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(note.status == .perfected ? .green : .secondary)
            if note.rating > 0 {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { value in
                        Image(systemName: value <= note.rating ? "star.fill" : "star").foregroundStyle(.orange)
                    }
                }.font(.caption)
            }
            HStack {
                ForEach(note.tags.prefix(3), id: \.self) { tag in
                    Text(tag).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(note.updatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(note.mealType.tint).frame(width: 5).padding(.vertical, 12)
        }
        .shadow(color: note.mealType.tint.opacity(0.10), radius: 10, y: 4)
    }
}

#Preview { ContentView() }
