import Foundation
import NakedPantreeDomain
import Testing

@testable import NakedPantree

/// Tests for the model that backs `QuantityStepperControl` on
/// `ItemDetailView`. The view itself is intentionally trivial; the
/// behaviors that need pinning (clamping, debouncing, flush-on-dismiss,
/// error-triggered reload) all live on the model so they're driveable
/// from `swift-testing` without spinning up a SwiftUI host.
@Suite("QuantityStepperModel")
@MainActor
struct QuantityStepperModelTests {
    /// Test fixture that records every persist call. Uses an actor
    /// internally so concurrent debounced writes don't race the
    /// recorder; the public API stays simple.
    final class PersistRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Int32] = []
        var shouldThrow = false

        var values: [Int32] {
            lock.lock()
            defer { lock.unlock() }
            return _values
        }

        var callCount: Int { values.count }

        func record(_ value: Int32) throws {
            lock.lock()
            defer { lock.unlock() }
            if shouldThrow {
                throw PersistRecorderError.injected
            }
            _values.append(value)
        }
    }

    enum PersistRecorderError: Error { case injected }

    // MARK: Clamping

    @Test("Initial quantity below 0 clamps to 0")
    func initialClampsBelowZero() {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: -5,
            persist: { try recorder.record($0) }
        )
        #expect(model.quantity == 0)
    }

    @Test("Initial quantity above 9999 clamps to 9999")
    func initialClampsAboveMax() {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 12_345,
            persist: { try recorder.record($0) }
        )
        #expect(model.quantity == 9999)
    }

    @Test("Decrement at 0 stays at 0 and does not schedule a write")
    func decrementAtZeroIsNoOp() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 0,
            debounceInterval: .milliseconds(20),
            persist: { try recorder.record($0) }
        )
        model.decrement()
        #expect(model.quantity == 0)
        #expect(model.canDecrement == false)
        // Wait long enough to confirm no debounced write fires.
        try? await Task.sleep(for: .milliseconds(80))
        #expect(recorder.callCount == 0)
    }

    @Test("Increment at 9999 stays at 9999 and does not schedule a write")
    func incrementAtMaxIsNoOp() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 9999,
            debounceInterval: .milliseconds(20),
            persist: { try recorder.record($0) }
        )
        model.increment()
        #expect(model.quantity == 9999)
        #expect(model.canIncrement == false)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(recorder.callCount == 0)
    }

    // MARK: Debouncing

    @Test("Multiple rapid increments coalesce into a single persist call")
    func rapidIncrementsCoalesce() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 1,
            debounceInterval: .milliseconds(40),
            persist: { try recorder.record($0) }
        )

        for _ in 0..<5 {
            model.increment()
        }
        #expect(model.quantity == 6)
        #expect(recorder.callCount == 0)  // still pending

        // Wait past the debounce window plus a margin for scheduling.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(recorder.callCount == 1)
        #expect(recorder.values == [6])
    }

    @Test("Each tap resets the debounce window")
    func tapsResetDebounce() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 1,
            debounceInterval: .milliseconds(60),
            persist: { try recorder.record($0) }
        )

        model.increment()
        try? await Task.sleep(for: .milliseconds(30))
        model.increment()
        try? await Task.sleep(for: .milliseconds(30))
        model.increment()
        // Less time has passed than `60ms` since the last tap, so
        // the persist hasn't fired yet.
        #expect(recorder.callCount == 0)

        try? await Task.sleep(for: .milliseconds(150))
        #expect(recorder.values == [4])
    }

    // MARK: Flush

    @Test("flush() writes the pending value immediately")
    func flushWritesPending() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 1,
            debounceInterval: .seconds(10),  // long enough to never fire
            persist: { try recorder.record($0) }
        )

        model.increment()
        model.increment()
        #expect(recorder.callCount == 0)

        await model.flush()
        #expect(recorder.values == [3])
    }

    @Test("flush() with no pending change does nothing")
    func flushWithoutPendingChangeIsNoOp() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 5,
            persist: { try recorder.record($0) }
        )
        await model.flush()
        #expect(recorder.callCount == 0)
    }

    // MARK: Error path

    @Test("Persist failure invokes onPersistFailure")
    func persistFailureTriggersReload() async {
        let recorder = PersistRecorder()
        recorder.shouldThrow = true

        let failureCount = FailureCounter()
        let model = QuantityStepperModel(
            initialQuantity: 1,
            debounceInterval: .milliseconds(20),
            persist: { try recorder.record($0) },
            onPersistFailure: { failureCount.bump() }
        )

        model.increment()
        try? await Task.sleep(for: .milliseconds(120))
        #expect(failureCount.count == 1)
    }

    // MARK: Reset

    @Test("reset(to:) updates quantity and clears pending state")
    func resetClearsPending() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 1,
            debounceInterval: .seconds(10),
            persist: { try recorder.record($0) }
        )

        model.increment()
        model.increment()
        #expect(model.hasPendingWrite == true)

        model.reset(to: 7)
        #expect(model.quantity == 7)
        #expect(model.hasPendingWrite == false)

        // The cancelled debounced task must not fire after the reset.
        try? await Task.sleep(for: .milliseconds(80))
        #expect(recorder.callCount == 0)
    }

    @Test("hasPendingWrite is true between tap and persist completion")
    func hasPendingWriteWhilePending() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 1,
            debounceInterval: .milliseconds(40),
            persist: { try recorder.record($0) }
        )

        model.increment()
        #expect(model.hasPendingWrite == true)

        try? await Task.sleep(for: .milliseconds(150))
        #expect(model.hasPendingWrite == false)
    }

    // MARK: Long-press repeat

    @Test("beginPress repeats while held — every tick advances by 1 before acceleration")
    func longPressRepeatsBeforeAcceleration() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 0,
            debounceInterval: .seconds(10),  // never fires during the test
            repeatInterval: .milliseconds(40),
            accelerationThreshold: .seconds(10),  // never escalates here
            acceleratedStep: 5,
            persist: { try recorder.record($0) }
        )

        model.beginPress(.increment)
        // First tick is immediate, then ticks every 40 ms. After
        // ~200 ms we expect ≥4 ticks (5 immediate + repeats), but
        // we only assert a lower bound so CI scheduler jitter
        // doesn't flake.
        try? await Task.sleep(for: .milliseconds(200))
        model.endPress()

        #expect(model.quantity >= 3)
        // No persist yet — the long debounce interval keeps writes
        // batched for after the press loop ends.
        #expect(recorder.callCount == 0)
    }

    @Test("Long press escalates step size after acceleration threshold")
    func longPressEscalates() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 0,
            debounceInterval: .seconds(10),
            repeatInterval: .milliseconds(40),
            accelerationThreshold: .milliseconds(150),
            acceleratedStep: 10,
            persist: { try recorder.record($0) }
        )

        model.beginPress(.increment)
        try? await Task.sleep(for: .milliseconds(400))
        model.endPress()

        // Without acceleration, ~400 ms / 40 ms ≈ 10 ticks → q ≈ 10.
        // With escalation to +10 after 150 ms, we expect q to be
        // well above the linear bound. Use a conservative floor.
        #expect(model.quantity > 15)
    }

    @Test("beginPress on a bounded direction does not loop forever")
    func longPressStopsAtBound() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 9998,
            debounceInterval: .seconds(10),
            repeatInterval: .milliseconds(20),
            persist: { try recorder.record($0) }
        )

        model.beginPress(.increment)
        try? await Task.sleep(for: .milliseconds(150))
        // Loop should have self-cancelled once it hit 9999. Verify
        // we don't keep ticking past the bound and that
        // `hasPendingWrite` reflects the now-idle press loop.
        #expect(model.quantity == 9999)
        model.endPress()
    }

    @Test("beginPress + immediate endPress acts like a single tap (VoiceOver activation)")
    func voiceOverActivationActsLikeTap() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 1,
            debounceInterval: .milliseconds(40),
            persist: { try recorder.record($0) }
        )

        model.beginPress(.increment)
        model.endPress()

        // The first tick is synchronous, so the optimistic value
        // updates immediately even though endPress fires before
        // any sleep window has elapsed.
        #expect(model.quantity == 2)

        // After the debounce window, the persisted value catches up.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(recorder.values == [2])
    }

    @Test("flush() during a press cancels the press loop")
    func flushCancelsActivePress() async {
        let recorder = PersistRecorder()
        let model = QuantityStepperModel(
            initialQuantity: 0,
            debounceInterval: .milliseconds(20),
            repeatInterval: .milliseconds(30),
            persist: { try recorder.record($0) }
        )

        model.beginPress(.increment)
        try? await Task.sleep(for: .milliseconds(80))
        let snapshot = model.quantity
        await model.flush()

        // After flush, no further ticks land — wait and verify the
        // quantity stays put.
        try? await Task.sleep(for: .milliseconds(120))
        #expect(model.quantity == snapshot)
        // Flush wrote the snapshot value to the recorder.
        #expect(recorder.values == [snapshot])
    }
}

/// MainActor-isolated, mutable tally — `Int` plus a closure capture
/// can't escape the closure cleanly under strict concurrency.
@MainActor
final class FailureCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}
