import SwiftUI

struct CookingModeView: View {
    @Environment(\.dismiss) private var dismiss
    let note: CookingNote
    let onFinish: () -> Void
    @State private var checkedIngredients = Set<Int>()
    @State private var completedSteps = Set<Int>()
    @State private var timerMinutes = 5
    @State private var secondsRemaining = 0
    @State private var timerRunning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Serves \(note.servings)", systemImage: "person.2")
                        Spacer()
                        if note.totalMinutes > 0 { Label("\(note.totalMinutes) min", systemImage: "clock") }
                    }
                    .foregroundStyle(.secondary)
                }

                if !note.ingredients.isEmpty {
                    Section("Ingredients") {
                        ForEach(Array(note.ingredients.enumerated()), id: \.offset) { index, ingredient in
                            ChecklistRow(text: ingredient, checked: checkedIngredients.contains(index)) {
                                toggle(index, in: &checkedIngredients)
                            }
                        }
                    }
                }

                if !note.steps.isEmpty {
                    Section("Directions") {
                        ForEach(Array(note.steps.enumerated()), id: \.offset) { index, step in
                            Button {
                                toggle(index, in: &completedSteps)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)").font(.headline).frame(width: 28, height: 28)
                                        .background(completedSteps.contains(index) ? Color.green : Color.orange.opacity(0.16), in: Circle())
                                    Text(step).strikethrough(completedSteps.contains(index)).foregroundStyle(completedSteps.contains(index) ? .secondary : .primary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Section("Kitchen timer") {
                    HStack {
                        Stepper("\(timerMinutes) minutes", value: $timerMinutes, in: 1...180)
                        Text(timeText).font(.title3.monospacedDigit()).foregroundStyle(timerRunning ? .orange : .primary)
                    }
                    HStack {
                        Button(timerRunning ? "Pause" : (secondsRemaining > 0 ? "Resume" : "Start"), systemImage: timerRunning ? "pause.fill" : "play.fill") {
                            if secondsRemaining == 0 { secondsRemaining = timerMinutes * 60 }
                            timerRunning.toggle()
                        }
                        Spacer()
                        Button("Reset", systemImage: "arrow.counterclockwise") { timerRunning = false; secondsRemaining = 0 }
                    }
                }
            }
            .navigationTitle(note.title.isEmpty ? "Cook mode" : note.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finished", systemImage: "checkmark.circle.fill") { onFinish(); dismiss() }
                }
            }
            .task(id: timerRunning) {
                guard timerRunning else { return }
                while timerRunning && secondsRemaining > 0 && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard timerRunning, !Task.isCancelled else { return }
                    secondsRemaining -= 1
                    if secondsRemaining == 0 { timerRunning = false }
                }
            }
        }
    }

    private var timeText: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    private func toggle(_ value: Int, in set: inout Set<Int>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

private struct ChecklistRow: View {
    let text: String
    let checked: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(text, systemImage: checked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checked ? .secondary : .primary)
                .strikethrough(checked)
        }.buttonStyle(.plain)
    }
}
