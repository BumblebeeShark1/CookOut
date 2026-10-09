import SwiftUI

struct CookingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: CookingNote
    let onFinish: () -> Void
    @State private var checkedIngredients = Set<Int>()
    @State private var completedSteps = Set<Int>()
    @State private var servings: Double
    @State private var recipeUnits: RecipeMeasurementSystem = .original
    @State private var timerMinutes = 5
    @State private var secondsRemaining = 0
    @State private var timerRunning = false

    init(note: CookingNote, initialServings: Double? = nil, onFinish: @escaping () -> Void) {
        self.note = note
        self.onFinish = onFinish
        let requested = initialServings ?? Double(max(1, note.servings))
        _servings = State(initialValue: requested.isFinite && (0.25...1000).contains(requested) ? requested : Double(max(1, note.servings)))
    }
    private var portionFactor: Double { servings / Double(max(1, note.servings)) }
    private var validPortions: Bool { note.canScaleQuantities && servings.isFinite && (0.25...1000).contains(servings) && portionFactor <= 1000 }

    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "At the stove", title: note.title.isEmpty ? "Let’s cook." : note.title,
                                  subtitle: "One ingredient, one step, one delicious meal at a time.")
                HStack(spacing: 20) {
                    Label(note.canScaleQuantities ? "Serves \(RecipeQuantity.format(servings))" : "Check source yield", systemImage: "person.2")
                    if note.totalMinutes > 0 { Label("\(note.totalMinutes) minutes", systemImage: "clock") }
                }.font(.subheadline).foregroundStyle(.secondary)
                CookOutPanel(title: "Make it your portion", symbol: "person.2") {
                    if note.canScaleQuantities {
                        RecipePortionControls(originalServings: note.servings, servings: $servings)
                    } else {
                        Text("The source yield is unclear. Ingredients stay as written. Confirm the original serving yield in your recipe editor before scaling.").font(.subheadline)
                    }
                    RecipeConversionControls(system: $recipeUnits)
                    Text("Ingredient quantities update below. Your saved recipe stays unchanged. Cooking times stay as written; adjust to the size of your batch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let source = note.sourceURL, let url = RecipeSourceURL.valid(source) {
                    CookOutPanel(title: "Original recipe", symbol: "safari") {
                        Link("Open \(note.sourcePublisher ?? "original") directions", destination: url).buttonStyle(.borderedProminent)
                        Text("This source-linked recipe keeps its cooking directions at the publisher.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !note.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Your progress").font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(completedSteps.count) of \(note.steps.count) steps").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(completedSteps.count), total: Double(note.steps.count)).tint(CookOutTheme.olive)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 22, alignment: .top)], alignment: .leading, spacing: 22) {
                    if !note.ingredients.isEmpty {
                        CookOutPanel(title: "On the counter", subtitle: "Leading quantities scale with your portions. Unrecognized amounts stay as written.", symbol: "basket") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(note.ingredients.enumerated()), id: \.offset) { index, ingredient in
                                    ChecklistRow(text: RecipeQuantity.convertMeasurements(in: validPortions ? RecipeQuantity.scale(ingredient, by: portionFactor) : ingredient, to: recipeUnits), checked: checkedIngredients.contains(index)) {
                                        toggle(index, in: &checkedIngredients)
                                    }
                                    if index < note.ingredients.count - 1 { Divider().padding(.leading, 34) }
                                }
                            }
                        }
                    }
                    if !note.steps.isEmpty {
                        CookOutPanel(title: "Make it happen", subtitle: "Take your time. Enjoy the process.", symbol: "list.number") {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(Array(note.steps.enumerated()), id: \.offset) { index, step in
                                    Button { toggle(index, in: &completedSteps) } label: {
                                        HStack(alignment: .top, spacing: 14) {
                                            ZStack {
                                                Circle().fill(completedSteps.contains(index) ? CookOutTheme.olive : Color.primary.opacity(0.05))
                                                if completedSteps.contains(index) {
                                                    Image(systemName: "checkmark").foregroundStyle(.white)
                                                } else {
                                                    Text("\(index + 1)").foregroundStyle(.primary)
                                                }
                                            }.font(.caption.weight(.medium)).frame(width: 30, height: 30)
                                            Text(RecipeQuantity.convertMeasurements(in: step, to: recipeUnits)).font(.body).strikethrough(completedSteps.contains(index))
                                                .foregroundStyle(completedSteps.contains(index) ? .secondary : .primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(CookOutPressStyle())
                                        .accessibilityLabel("Step \(index + 1): \(RecipeQuantity.convertMeasurements(in: step, to: recipeUnits))")
                                        .accessibilityValue(completedSteps.contains(index) ? "Complete" : "Incomplete")
                                }
                            }
                        }
                    }
                }
                if !note.body.isEmpty {
                    CookOutPanel(title: "Chef’s notes", symbol: "note.text") {
                        Text(RecipeQuantity.convertMeasurements(in: note.body, to: recipeUnits)).textSelection(.enabled)
                    }
                }
                CookOutPanel(title: "A little time", subtitle: "Keep an eye on the simmer, bake, or rest.", symbol: "timer") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 30) { timerDisplay; timerControls }
                        VStack(alignment: .leading, spacing: 24) { timerDisplay; timerControls }
                    }
                }
            }
            .onChange(of: servings) { _, _ in checkedIngredients.removeAll() }
            .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: checkedIngredients)
            .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: completedSteps)
            .navigationTitle("Cooking mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finished cooking", systemImage: "checkmark") { onFinish(); dismiss() }
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
#if os(macOS)
        .frame(minWidth: 740, minHeight: 740)
#endif
    }

    private var timerDisplay: some View {
        Text(timeText).font(CookOutTypography.display(50, relativeTo: .largeTitle)).monospacedDigit()
            .frame(minWidth: 155, alignment: .leading)
            .accessibilityLabel("Timer, \(secondsRemaining / 60) minutes, \(secondsRemaining % 60) seconds remaining")
    }

    private var timerControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Stepper("\(timerMinutes) minutes", value: $timerMinutes, in: 1...180)
            HStack(spacing: 12) {
                Button(timerRunning ? "Pause" : (secondsRemaining > 0 ? "Resume" : "Start timer"), systemImage: timerRunning ? "pause" : "play") {
                    if secondsRemaining == 0 { secondsRemaining = timerMinutes * 60 }
                    timerRunning.toggle()
                }.buttonStyle(.borderedProminent)
                Button("Reset", systemImage: "arrow.counterclockwise") { timerRunning = false; secondsRemaining = 0 }
                    .buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeText: String { String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60) }
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(checked ? CookOutTheme.olive : .secondary)
                Text(text).strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(CookOutPressStyle()).accessibilityValue(checked ? "Checked" : "Unchecked")
    }
}
