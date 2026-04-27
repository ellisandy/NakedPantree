import NakedPantreeDomain
import SwiftUI

/// Inline +/- controls used on `ItemDetailView` so users can adjust an
/// item's quantity in one tap without entering the edit form.
///
/// The view is a thin SwiftUI shell over `QuantityStepperModel`; all of
/// the interesting logic (clamping at the 0...9999 bounds, debouncing
/// rapid taps, flushing on dismiss, reloading on save error) lives in
/// the model so it stays unit-testable without instantiating a view
/// hierarchy.
struct QuantityStepperControl: View {
    @Bindable var model: QuantityStepperModel
    let unit: NakedPantreeDomain.Unit

    var body: some View {
        HStack(spacing: 12) {
            stepButton(
                systemImage: "minus",
                identifier: "itemDetail.qty.decrement",
                accessibilityLabel: "Decrease quantity",
                direction: .decrement,
                isEnabled: model.canDecrement
            )

            // Tabular figures keep the digit column from jittering as
            // the count changes — `DESIGN_GUIDELINES.md` §5.
            Text("\(model.quantity) \(unit.displayLabel)")
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("itemDetail.qty.value")

            stepButton(
                systemImage: "plus",
                identifier: "itemDetail.qty.increment",
                accessibilityLabel: "Increase quantity",
                direction: .increment,
                isEnabled: model.canIncrement
            )
        }
    }

    @ViewBuilder
    private func stepButton(
        systemImage: String,
        identifier: String,
        accessibilityLabel: String,
        direction: QuantityStepperModel.PressDirection,
        isEnabled: Bool
    ) -> some View {
        // Fixed 44-pt square hit target — `DESIGN_GUIDELINES.md`
        // §10 / Apple HIG. We use a plain shape with a press gesture
        // rather than `Button(action:)` because SwiftUI's `Button`
        // only fires on release, and we need press-down /
        // press-release callbacks to drive the long-press repeat
        // loop in the model.
        PressableStepButton(
            isEnabled: isEnabled,
            onPressBegan: { model.beginPress(direction) },
            onPressEnded: { model.endPress() }
        ) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        // VoiceOver double-tap doesn't fire `DragGesture`, so without
        // an explicit `.accessibilityAction` the button would
        // announce as activatable but never increment. Pair
        // begin/end so a single VO activation triggers exactly one
        // ±1 step plus the debounced save (same as a sighted tap).
        .accessibilityAction {
            guard isEnabled else { return }
            model.beginPress(direction)
            model.endPress()
        }
    }
}

/// SwiftUI shim that exposes press-began / press-ended callbacks via a
/// `DragGesture(minimumDistance: 0)`. `Button` won't do — it only
/// fires on release, and we need to start a repeat loop the moment
/// the finger lands on the +/- button. Disabled state suppresses the
/// gesture entirely so neither callback fires when the model has
/// already hit a bound.
private struct PressableStepButton<Label: View>: View {
    let isEnabled: Bool
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressing = false

    var body: some View {
        label()
            .opacity(isEnabled ? (isPressing ? 0.5 : 1) : 0.3)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !isPressing else { return }
                        isPressing = true
                        onPressBegan()
                    }
                    .onEnded { _ in
                        guard isPressing else { return }
                        isPressing = false
                        onPressEnded()
                    },
                isEnabled: isEnabled
            )
    }
}

/// Drives `QuantityStepperControl`: holds the optimistic in-flight
/// `quantity`, clamps to 0...9999, and coalesces rapid taps into a
/// single repository write.
///
/// **Persistence model.** Every increment/decrement updates `quantity`
/// immediately so the UI feels instant; the actual `repositories.item
/// .update(...)` call is debounced behind ~500 ms of idle. This avoids
/// hammering Core Data / CloudKit during a long-press repeat. The view
/// is expected to call `flush()` from `.onDisappear` so any pending
/// write lands before the detail screen tears down.
///
/// **Long-press repeat.** Holding a button calls `beginPress(_:)` and
/// the model spins a loop that ticks every `repeatInterval`. After
/// `accelerationThreshold` of held time, each tick advances by
/// `acceleratedStep` instead of `1` — same idea as a native `Stepper`
/// but with bigger tap targets and a slightly more aggressive
/// acceleration so big restocks aren't tedious.
///
/// **Error recovery.** If the persist closure throws, the model invokes
/// `onPersistFailure()` so the view can reload from the repository —
/// optimistic state gets thrown away and the canonical record wins.
@MainActor
@Observable
final class QuantityStepperModel {
    /// Lower bound. The issue text reserves quantity = 0 for the
    /// "Add to grocery list" affordance landing in a follow-up; keep
    /// the floor here, no negative quantities.
    static let minimumQuantity: Int32 = 0

    /// Upper bound matches the form's `Stepper` range so the two
    /// surfaces don't disagree on what's a valid count.
    static let maximumQuantity: Int32 = 9999

    /// Default debounce window. Long enough to coalesce a long-press
    /// burst, short enough that release-then-walk-away still saves
    /// before the user leaves the screen.
    static let defaultDebounce: Duration = .milliseconds(500)

    /// Default tick rate while a button is held — roughly 8 Hz, in
    /// line with Apple's native `Stepper`.
    static let defaultRepeatInterval: Duration = .milliseconds(120)

    /// Default delay before the per-tick step size escalates from
    /// `1` to `acceleratedStep`. Hold "for about a second" matches
    /// the issue text.
    static let defaultAccelerationThreshold: Duration = .seconds(1)

    /// Default escalated step size once the acceleration threshold
    /// is crossed. Five is a comfortable middle ground — issue text
    /// suggests 5–10.
    static let defaultAcceleratedStep: Int32 = 5

    /// Direction passed to `beginPress(_:)`. `+1` for the increment
    /// button, `-1` for the decrement button.
    enum PressDirection: Sendable {
        case increment
        case decrement

        var sign: Int32 {
            switch self {
            case .increment: 1
            case .decrement: -1
            }
        }
    }

    /// Current displayed quantity. Mutating this directly bypasses the
    /// debouncer — internal use only; tap handlers should call
    /// `increment()` / `decrement()` / `set(_:)` instead.
    private(set) var quantity: Int32

    private var pendingTask: Task<Void, Never>?
    private var pendingDebounceToken: UUID?
    private var pressTask: Task<Void, Never>?
    private var lastPersistedQuantity: Int32
    private let debounceInterval: Duration
    private let repeatInterval: Duration
    private let accelerationThreshold: Duration
    private let acceleratedStep: Int32
    private let persist: @Sendable (Int32) async throws -> Void
    private let onPersistFailure: @MainActor () -> Void

    init(
        initialQuantity: Int32,
        debounceInterval: Duration = QuantityStepperModel.defaultDebounce,
        repeatInterval: Duration = QuantityStepperModel.defaultRepeatInterval,
        accelerationThreshold: Duration = QuantityStepperModel.defaultAccelerationThreshold,
        acceleratedStep: Int32 = QuantityStepperModel.defaultAcceleratedStep,
        persist: @escaping @Sendable (Int32) async throws -> Void,
        onPersistFailure: @MainActor @escaping () -> Void = {}
    ) {
        let clamped = QuantityStepperModel.clamp(initialQuantity)
        self.quantity = clamped
        self.lastPersistedQuantity = clamped
        self.debounceInterval = debounceInterval
        self.repeatInterval = repeatInterval
        self.accelerationThreshold = accelerationThreshold
        self.acceleratedStep = acceleratedStep
        self.persist = persist
        self.onPersistFailure = onPersistFailure
    }

    var canIncrement: Bool { quantity < QuantityStepperModel.maximumQuantity }
    var canDecrement: Bool { quantity > QuantityStepperModel.minimumQuantity }

    /// True if there's a debounced write pending, an active press
    /// loop, or the in-memory value disagrees with what we last
    /// persisted. Lets the view avoid clobbering the user's
    /// in-flight tap when an unrelated remote change reload happens.
    var hasPendingWrite: Bool {
        pendingTask != nil || pressTask != nil || quantity != lastPersistedQuantity
    }

    func increment() {
        set(quantity &+ 1)
    }

    func decrement() {
        set(quantity &- 1)
    }

    /// Sets `quantity` (clamped) and schedules a debounced persist. A
    /// no-op if the clamped value matches what's already on screen,
    /// since a single +/- tap that hits a bound shouldn't reset the
    /// debouncer.
    func set(_ proposed: Int32) {
        let next = QuantityStepperModel.clamp(proposed)
        guard next != quantity else { return }
        quantity = next
        scheduleSave()
    }

    /// Cancels any in-flight debounce and writes the current value
    /// immediately. Also stops a press-loop if one's running — the
    /// view-disappear path needs to make sure neither task outlives
    /// the screen.
    func flush() async {
        pressTask?.cancel()
        pressTask = nil
        pendingTask?.cancel()
        pendingTask = nil
        await persistIfChanged()
    }

    /// Starts the long-press repeat loop. The first tick fires
    /// immediately so the press feels responsive; subsequent ticks
    /// fire every `repeatInterval`, and after `accelerationThreshold`
    /// elapses each tick advances by `acceleratedStep` instead of 1.
    /// `endPress()` cancels the loop. Calling `beginPress` while
    /// another press is already running cancels it first.
    func beginPress(_ direction: PressDirection) {
        pressTask?.cancel()
        let interval = repeatInterval
        let threshold = accelerationThreshold
        let big = acceleratedStep
        let sign = direction.sign

        // Fire the first tick *synchronously*. Without this, a
        // press-then-immediate-release pair (the VoiceOver
        // activation pattern, or just a very short tap) would
        // cancel the press Task before its first iteration ever
        // gets scheduled — the user would tap and nothing would
        // happen.
        applyPressTick(sign: sign, accelerated: false)
        let start = ContinuousClock.now

        pressTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                guard let self else { return }
                let elapsed = ContinuousClock.now - start
                let accelerated = elapsed >= threshold
                let stepMagnitude: Int32 = accelerated ? big : 1
                self.applyPressTick(sign: sign, magnitude: stepMagnitude, accelerated: accelerated)
            }
        }
    }

    /// Cancels the press-loop and schedules a debounced save for
    /// whatever quantity the user landed on. Safe to call even if no
    /// press is active — used from `.onEnded` of the press gesture.
    func endPress() {
        pressTask?.cancel()
        pressTask = nil
        // After a press settles, kick off the normal debounced save.
        // We didn't schedule per-tick during the press to avoid
        // flooding the actor with `Task` create/cancel pairs at the
        // tick rate.
        if quantity != lastPersistedQuantity {
            scheduleSave()
        }
    }

    private func applyPressTick(sign: Int32, magnitude: Int32 = 1, accelerated: Bool) {
        let proposed = quantity &+ (sign &* magnitude)
        let next = QuantityStepperModel.clamp(proposed)
        if next == quantity {
            // Bounded out — there's no more to do, no point spinning.
            pressTask?.cancel()
            pressTask = nil
            return
        }
        quantity = next
        _ = accelerated  // surfaced for future haptics; not used yet
    }

    /// External hook for the parent reload path — keeps the model's
    /// `lastPersistedQuantity` in sync when the underlying record
    /// changes from outside (e.g. CloudKit push, edit form save).
    func reset(to quantity: Int32) {
        let clamped = QuantityStepperModel.clamp(quantity)
        pendingTask?.cancel()
        pendingTask = nil
        self.quantity = clamped
        lastPersistedQuantity = clamped
    }

    private func scheduleSave() {
        pendingTask?.cancel()
        let interval = debounceInterval
        let token = UUID()
        pendingDebounceToken = token
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self?.persistIfChanged()
            await self?.clearPendingTask(matching: token)
        }
    }

    private func clearPendingTask(matching token: UUID) {
        // Only clear `pendingTask` if no newer tap re-armed the
        // slot. The fresh task will clear itself when it finishes.
        guard pendingDebounceToken == token else { return }
        pendingTask = nil
        pendingDebounceToken = nil
    }

    private func persistIfChanged() async {
        let target = quantity
        guard target != lastPersistedQuantity else { return }
        do {
            try await persist(target)
            // Only mark as persisted if the user hasn't tapped again
            // mid-flight. If they have, `quantity` will have moved on
            // and the next debounce cycle will pick up the delta.
            lastPersistedQuantity = target
        } catch {
            onPersistFailure()
        }
    }

    private static func clamp(_ value: Int32) -> Int32 {
        min(max(value, minimumQuantity), maximumQuantity)
    }
}
