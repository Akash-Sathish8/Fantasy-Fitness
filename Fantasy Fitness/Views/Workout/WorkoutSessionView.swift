//
//  WorkoutSessionView.swift
//  Fantasy Fitness
//
//  Full-screen workout logger: pick an exercise, log weight × reps per set, rest with
//  the timer, then finish to send the sets to the server, which awards XP, stats and
//  quest progress. The title follows the current exercise.
//

import SwiftUI

struct WorkoutSessionView: View {
    let quest: Quest?
    let onClose: () -> Void

    @Environment(GameStore.self) private var store
    @State private var session: WorkoutSession
    @State private var weight: Double = 0
    @State private var reps: Int = 8
    @State private var showingAddExercise = false
    @State private var newExerciseName = ""
    @State private var confirmingDiscard = false
    @State private var isSubmitting = false
    @State private var result: WorkoutResult?

    init(quest: Quest?, onClose: @escaping () -> Void) {
        self.quest = quest
        self.onClose = onClose
        _session = State(initialValue: WorkoutSession(quest: quest))
    }

    var body: some View {
        Group {
            if let result {
                WorkoutCompleteView(result: result, quest: store.quests[.daily].flatMap { $0.id == quest?.id ? $0 : nil },
                                    onDone: onClose)
            } else {
                logger
            }
        }
        .background(WoodBackground())
        .alert("Add exercise", isPresented: $showingAddExercise) {
            TextField("Exercise name", text: $newExerciseName)
                .textInputAutocapitalization(.sentences)
            Button("Add") {
                session.addExercise(named: newExerciseName)
                newExerciseName = ""
            }
            Button("Cancel", role: .cancel) { newExerciseName = "" }
        } message: {
            Text("Sets for exercises outside the quest still count toward your weekly workouts and Strength.")
        }
        .confirmationDialog("Leave this workout?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard \(session.sets.count) logged sets", role: .destructive, action: onClose)
        } message: {
            Text("Sets are only saved when you finish the workout.")
        }
        .onChange(of: session.currentName, initial: true) { _, name in
            weight = session.suggestedWeight(for: name)
            reps = session.suggestedReps(for: name)
        }
        .sensoryFeedback(.success, trigger: session.sets.count) { old, new in new > old }
    }

    // MARK: - Logger

    private var logger: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    if session.exercises.isEmpty {
                        emptyState
                    } else {
                        exercisePicker
                        RestTimerCard(timer: session.restTimer)
                        if let exercise = session.current {
                            setEntry(for: exercise)
                            loggedSets(for: exercise)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            finishBar
        }
    }

    /// Close button and the title, which switches to the current exercise.
    private var header: some View {
        HStack(spacing: 12) {
            WoodIconButton(systemImage: "xmark", accessibilityLabel: "Close workout") {
                if session.hasSets { confirmingDiscard = true } else { onClose() }
            }
            VStack(spacing: 0) {
                // KickerText's ink is for parchment; on wood the label needs cream.
                Text((quest.map { "\($0.title) · \(progressText)" } ?? "Free workout · \(progressText)").uppercased())
                    .font(.alegreyaSans(12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.cream.opacity(0.85))
                    .lineLimit(1)
                Text(session.current?.name ?? "Workout")
                    .font(.pirata(34))
                    .foregroundStyle(Theme.gold)
                    .shadow(color: Theme.darkestWood, radius: 0, x: 0, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .id(session.currentName)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .animation(.snappy(duration: 0.3), value: session.currentName)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var progressText: String {
        let planned = session.exercises.filter { $0.target != nil }
        guard !planned.isEmpty else { return "\(session.sets.count) sets" }
        return "\(planned.filter(session.isDone).count) of \(planned.count) lifts"
    }

    /// Chips for every exercise; tapping one makes it current.
    private var exercisePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(session.exercises) { exercise in
                        exerciseChip(exercise).id(exercise.id)
                    }
                    Button {
                        showingAddExercise = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.alegreyaSans(16, weight: .bold))
                            .foregroundStyle(Theme.cream)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Capsule().strokeBorder(Theme.cream.opacity(0.6),
                                                               style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.currentName) { _, name in
                withAnimation { proxy.scrollTo(name.lowercased(), anchor: .center) }
            }
        }
    }

    private func exerciseChip(_ exercise: WorkoutSession.Exercise) -> some View {
        let isCurrent = exercise.name == session.currentName
        let done = session.isDone(exercise)
        return Button {
            session.select(exercise.name)
        } label: {
            HStack(spacing: 6) {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(isCurrent ? Theme.positiveText : Theme.progressGreen)
                }
                Text(exercise.name)
                    .font(.alegreyaSans(16, weight: .bold))
                if let target = exercise.target {
                    Text("\(min(session.countingSets(for: exercise), target.sets))/\(target.sets)")
                        .font(.alegreyaSans(14, weight: .bold))
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isCurrent ? Theme.ink : Theme.cream)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .cartoonBackground(Capsule(), fill: isCurrent ? Theme.gold : Theme.darkWood,
                               outline: Theme.darkestWood, shadowOffset: 3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: - Set entry

    private func setEntry(for exercise: WorkoutSession.Exercise) -> some View {
        let counts = exercise.target?.counts(reps: reps, weightLb: weight) ?? true
        return ParchmentCard(padding: 16) {
            if let target = exercise.target {
                KickerText("Quest: \(target.sets) sets × \(target.minReps)+ reps"
                           + (target.minWeightLb > 0 ? " @ \(target.minWeightLb.formatted()) lb" : ""))
            } else {
                KickerText("Your own exercise")
            }

            HStack(spacing: 12) {
                ValueStepper(title: "Weight (lb)", value: weightText, step: "5") {
                    weight = max(weight - 5, 0)
                } onIncrement: {
                    weight += 5
                }
                ValueStepper(title: "Reps", value: "\(reps)", step: "1") {
                    reps = max(reps - 1, 1)
                } onIncrement: {
                    reps = min(reps + 1, 100)
                }
            }
            .padding(.top, 10)

            if !counts, let target = exercise.target {
                Text("This set won't count toward the quest (needs \(target.minReps)+ reps"
                     + (target.minWeightLb > 0 ? " at \(target.minWeightLb.formatted())+ lb" : "") + "), but it's still logged.")
                    .font(.alegreyaSans(14, weight: .medium))
                    .foregroundStyle(Theme.waxRed)
                    .padding(.top, 8)
            }

            Button {
                withAnimation(.snappy) { session.logSet(weightLb: weight, reps: reps) }
            } label: {
                Label("Log set \(session.sets(for: exercise.name).count + 1)", systemImage: "checkmark")
            }
            .buttonStyle(.chunky(.wax))
            .padding(.top, 14)
        }
    }

    private var weightText: String {
        weight.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func loggedSets(for exercise: WorkoutSession.Exercise) -> some View {
        let logged = session.sets(for: exercise.name)
        return Group {
            if !logged.isEmpty {
                ParchmentCard(padding: 16) {
                    NoteHeading(title: "Logged sets")
                    ForEach(Array(logged.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .font(.alegreyaSans(16, weight: .bold))
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(width: 56, alignment: .leading)
                            Text("\(set.weightLb.formatted()) lb × \(set.reps)")
                                .font(.alegreyaSans(18, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                            if let target = exercise.target, target.counts(reps: set.reps, weightLb: set.weightLb) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Theme.progressGreen)
                                    .accessibilityLabel("Counts toward quest")
                            }
                            Spacer()
                            Button {
                                withAnimation(.snappy) { session.removeSet(set) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.waxRed)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete set \(index + 1)")
                        }
                        if index < logged.count - 1 { DashedDivider() }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        ParchmentCard {
            NoteHeading(title: "Free workout", subtitle: "Add the exercises you're doing today.")
            Button {
                showingAddExercise = true
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
            .buttonStyle(.chunky(.wax))
            .padding(.top, 14)
        }
        .padding(.top, 24)
    }

    // MARK: - Finish

    private var finishBar: some View {
        Button {
            Task { await finish() }
        } label: {
            if isSubmitting {
                ProgressView().tint(Theme.cream)
            } else {
                Label(session.hasSets ? "Finish workout · \(session.sets.count) sets" : "Log a set to finish",
                      systemImage: "flag.checkered")
            }
        }
        .buttonStyle(.chunky(.emerald, minHeight: 58))
        .disabled(!session.hasSets || isSubmitting)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func finish() async {
        isSubmitting = true
        defer { isSubmitting = false }
        session.restTimer.stop()
        if let payout = await store.submitWorkout(sets: session.sets, questID: session.questID) {
            withAnimation(.snappy) { result = payout }
        }
    }
}

/// − value + control with 44 pt buttons.
private struct ValueStepper: View {
    let title: String
    let value: String
    let step: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.alegreyaSans(14, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
            HStack(spacing: 0) {
                stepButton("minus", label: "Decrease \(title.lowercased()) by \(step)", action: onDecrement)
                Text(value)
                    .font(.alegreyaSans(24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                stepButton("plus", label: "Increase \(title.lowercased()) by \(step)", action: onIncrement)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.checkboxFill))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.outline, lineWidth: 2.5))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(value)")
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}

/// Summary after the server accepts the workout.
private struct WorkoutCompleteView: View {
    let result: WorkoutResult
    /// The refreshed quest, if this workout was for one.
    let quest: Quest?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(quest?.progress == 1 ? "Quest complete" : "Workout logged")
                .font(.pirata(44))
                .foregroundStyle(Theme.gold)
                .shadow(color: Theme.darkestWood, radius: 0, x: 0, y: 3)
                .accessibilityAddTraits(.isHeader)
            ParchmentCard {
                HStack {
                    NoteHeading(title: "\(result.sets) sets logged", subtitle: "XP and stats are worked out by the guild.")
                    Spacer()
                    TagChip(label: "+\(result.xpGained) XP", systemImage: "star.fill")
                }
                if let quest {
                    DashedDivider().padding(.vertical, 12)
                    KickerText(quest.title)
                    ParchmentProgressBar(progress: quest.progress)
                        .padding(.top, 6)
                    Text("\(quest.completedCount) of \(quest.objectives.count) objectives done"
                         + (quest.progress == 1 ? " · reward chest added to your inventory" : ""))
                        .font(.alegreyaSans(15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 6)
                }
            }
            Button("Back to the board", action: onDone)
                .buttonStyle(.chunky(.emerald))
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    WorkoutSessionView(quest: .sampleDaily, onClose: {})
        .environment(GameStore.preview)
}

/// Presents a Workout session full screen (tab bar hidden). `quest` nil = free workout.
struct ActiveWorkout: Identifiable {
    let id = UUID()
    let quest: Quest?
}

extension View {
    func workoutSessionCover(_ workout: Binding<ActiveWorkout?>) -> some View {
        fullScreenCover(item: workout) { active in
            WorkoutSessionView(quest: active.quest) { workout.wrappedValue = nil }
        }
    }
}
