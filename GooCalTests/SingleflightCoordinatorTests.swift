//
//  SingleflightCoordinatorTests.swift
//  GooCalTests
//

import Testing
import Foundation
@testable import GooCal

@Suite("SingleflightCoordinator Behavioral Contracts & Concurrency Guarantees")
struct SingleflightCoordinatorTests {

    private struct TestError: Error, Equatable {
        let message: String
    }

    /// Thread-safe test synchronization gate for deterministic mid-flight testing.
    private actor TestGate {
        private var isOpened = false
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpened { return }
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func open() {
            isOpened = true
            for continuation in continuations {
                continuation.resume()
            }
            continuations.removeAll()
        }
    }

    /// Thread-safe counter for operation invocations.
    private actor InvocationTracker {
        private(set) var count = 0
        private(set) var recordedValues: [String] = []

        func increment(value: String = "") -> Int {
            count += 1
            if !value.isEmpty {
                recordedValues.append(value)
            }
            return count
        }
    }

    // MARK: - 1. Deduplication & Result Sharing Contracts

    @Test("Concurrent callers for identical key execute operation exactly once and share the result")
    func concurrentCallersShareSingleExecution() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let tracker = InvocationTracker()
        let gate = TestGate()
        let callerCount = 20

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<callerCount {
                group.addTask {
                    try await coordinator.execute(key: "calendar-refresh") {
                        await gate.wait()
                        let count = await tracker.increment(value: "run-\(i)")
                        return "payload-v\(count)"
                    }
                }
            }

            // Yield briefly to let all tasks queue up at the coordinator
            try await Task.sleep(for: .milliseconds(20))
            await gate.open()

            var collected: [String] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(results.count == callerCount)
        let firstResult = try #require(results.first)
        #expect(results.allSatisfy { $0 == firstResult })
        #expect(firstResult == "payload-v1")

        let totalInvocations = await tracker.count
        #expect(totalInvocations == 1)

        #expect(await coordinator.isInFlight(key: "calendar-refresh") == false)
        #expect(await coordinator.hasPendingTrailing(key: "calendar-refresh") == false)
    }

    @Test("Distinct keys execute independently and concurrently without blocking")
    func independentKeysExecuteInParallel() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let tracker = InvocationTracker()

        let keys = ["calendar-1", "calendar-2", "calendar-3"]

        let results = try await withThrowingTaskGroup(of: (String, String).self) { group in
            for key in keys {
                group.addTask {
                    let value = try await coordinator.execute(key: key) {
                        try await Task.sleep(for: .milliseconds(15))
                        _ = await tracker.increment()
                        return "result-for-\(key)"
                    }
                    return (key, value)
                }
            }

            var dict: [String: String] = [:]
            for try await (k, v) in group {
                dict[k] = v
            }
            return dict
        }

        #expect(results.count == 3)
        for key in keys {
            #expect(results[key] == "result-for-\(key)")
        }

        let totalInvocations = await tracker.count
        #expect(totalInvocations == 3)
    }

    @Test("Sequential calls after completion execute fresh operations")
    func sequentialCallsExecuteFreshOperations() async throws {
        let coordinator = SingleflightCoordinator<String, Int>()
        let tracker = InvocationTracker()

        let first = try await coordinator.execute(key: "date-query") {
            await tracker.increment()
        }
        #expect(first == 1)

        let second = try await coordinator.execute(key: "date-query") {
            await tracker.increment()
        }
        #expect(second == 2)

        let totalInvocations = await tracker.count
        #expect(totalInvocations == 2)
    }

    // MARK: - 2. Trailing Coalescing Contracts

    @Test("Calls arriving mid-flight trigger exactly one coalesced trailing pass")
    func midFlightTriggerExecutesSingleTrailingPass() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let tracker = InvocationTracker()
        let firstPassGate = TestGate()

        // 1. Launch initial in-flight pass
        let initialTask = Task {
            try await coordinator.execute(key: "sync") {
                await firstPassGate.wait()
                let c = await tracker.increment()
                return "pass-\(c)"
            }
        }

        // Wait until task is registered in-flight
        while await !coordinator.isInFlight(key: "sync") {
            try await Task.sleep(for: .milliseconds(5))
        }

        // 2. Launch two concurrent mid-flight calls that coalesce into trailing pass
        let trailingCall1 = Task {
            try await coordinator.executeCoalescing(key: "sync") {
                let c = await tracker.increment()
                return "trailing-\(c)"
            }
        }

        let trailingCall2 = Task {
            try await coordinator.executeCoalescing(key: "sync") {
                let c = await tracker.increment()
                return "trailing-\(c)"
            }
        }

        // Wait until trailing pass is registered
        while await !coordinator.hasPendingTrailing(key: "sync") {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(await coordinator.hasPendingTrailing(key: "sync") == true)

        // 3. Allow initial pass to complete
        await firstPassGate.open()

        let initialResult = try await initialTask.value
        let trailingResult1 = try await trailingCall1.value
        let trailingResult2 = try await trailingCall2.value

        #expect(initialResult == "pass-1")
        #expect(trailingResult1 == "trailing-2")
        #expect(trailingResult2 == "trailing-2")

        let totalInvocations = await tracker.count
        #expect(totalInvocations == 2)

        #expect(await coordinator.isInFlight(key: "sync") == false)
        #expect(await coordinator.hasPendingTrailing(key: "sync") == false)
    }

    @Test("Trailing pass captures latest operation closure requested during flight")
    func trailingPassCapturesLatestOperation() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let gate = TestGate()

        let initialTask = Task {
            try await coordinator.execute(key: "layout") {
                await gate.wait()
                return "layout-v1"
            }
        }

        while await !coordinator.isInFlight(key: "layout") {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Mid-flight trigger 1
        let trailing1 = Task {
            try await coordinator.executeCoalescing(key: "layout") {
                "layout-v2-stale"
            }
        }

        while await !coordinator.hasPendingTrailing(key: "layout") {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Mid-flight trigger 2 overwriting with latest operation
        let trailing2 = Task {
            try await coordinator.executeCoalescing(key: "layout") {
                "layout-v2-latest"
            }
        }

        try await Task.sleep(for: .milliseconds(10))
        await gate.open()

        let initialRes = try await initialTask.value
        let trailingRes1 = try await trailing1.value
        let trailingRes2 = try await trailing2.value

        #expect(initialRes == "layout-v1")
        #expect(trailingRes1 == "layout-v2-latest")
        #expect(trailingRes2 == "layout-v2-latest")
    }

    @Test("Join and schedule trailing returns in-flight result immediately and executes trailing pass")
    func joinAndScheduleTrailingExecutesTrailingPass() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let tracker = InvocationTracker()
        let gate = TestGate()

        let task1 = Task {
            try await coordinator.execute(key: "events") {
                await gate.wait()
                let c = await tracker.increment()
                return "pass-\(c)"
            }
        }

        while await !coordinator.isInFlight(key: "events") {
            try await Task.sleep(for: .milliseconds(5))
        }

        let task2 = Task {
            try await coordinator.execute(key: "events", strategy: .joinAndScheduleTrailing) {
                let c = await tracker.increment()
                return "trailing-pass-\(c)"
            }
        }

        while await !coordinator.hasPendingTrailing(key: "events") {
            try await Task.sleep(for: .milliseconds(5))
        }

        await gate.open()

        let res1 = try await task1.value
        let res2 = try await task2.value

        // Both joined the first pass
        #expect(res1 == "pass-1")
        #expect(res2 == "pass-1")

        // Wait for the trailing pass to finish settling
        await coordinator.waitForIdle(key: "events")

        let count = await tracker.count
        #expect(count == 2)
        #expect(await coordinator.isInFlight(key: "events") == false)
    }

    @Test("Cascading triggers: call arriving during trailing pass triggers another subsequent trailing pass")
    func cascadingTrailingPassesExecuteSequentially() async throws {
        let coordinator = SingleflightCoordinator<String, Int>()
        let tracker = InvocationTracker()
        let gate1 = TestGate()
        let gate2 = TestGate()

        // Pass 1
        let task1 = Task {
            try await coordinator.execute(key: "cascade") {
                await gate1.wait()
                return await tracker.increment()
            }
        }

        while await !coordinator.isInFlight(key: "cascade") {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Pass 2 requested during pass 1
        let task2 = Task {
            try await coordinator.executeCoalescing(key: "cascade") {
                await gate2.wait()
                return await tracker.increment()
            }
        }

        while await !coordinator.hasPendingTrailing(key: "cascade") {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Complete pass 1 -> pass 2 begins
        await gate1.open()
        let res1 = try await task1.value
        #expect(res1 == 1)

        // Wait for pass 2 to become in-flight
        try await Task.sleep(for: .milliseconds(10))

        // Pass 3 requested during pass 2
        let task3 = Task {
            try await coordinator.executeCoalescing(key: "cascade") {
                return await tracker.increment()
            }
        }

        while await !coordinator.hasPendingTrailing(key: "cascade") {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Complete pass 2 -> pass 3 begins and completes
        await gate2.open()
        let res2 = try await task2.value
        let res3 = try await task3.value

        #expect(res2 == 2)
        #expect(res3 == 3)

        let totalInvocations = await tracker.count
        #expect(totalInvocations == 3)
    }

    // MARK: - 3. Error Propagation Contracts

    @Test("Operation error propagates to all concurrent callers sharing the in-flight pass")
    func operationErrorPropagatesToAllSharingCallers() async {
        let coordinator = SingleflightCoordinator<String, String>()
        let expectedError = TestError(message: "Database connection failed")
        let gate = TestGate()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await #expect(throws: TestError.self) {
                        try await coordinator.execute(key: "error-key") {
                            await gate.wait()
                            throw expectedError
                        }
                    }
                }
            }

            try? await Task.sleep(for: .milliseconds(10))
            await gate.open()
        }

        #expect(await coordinator.isInFlight(key: "error-key") == false)
        #expect(await coordinator.hasPendingTrailing(key: "error-key") == false)
    }

    @Test("Trailing pass error propagates to trailing callers without affecting completed first pass")
    func trailingPassErrorPropagatesCleanly() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let expectedError = TestError(message: "Remote sync throttled")
        let gate = TestGate()

        let task1 = Task {
            try await coordinator.execute(key: "fail-trailing") {
                await gate.wait()
                return "initial-success"
            }
        }

        while await !coordinator.isInFlight(key: "fail-trailing") {
            try await Task.sleep(for: .milliseconds(5))
        }

        let task2 = Task {
            try await coordinator.executeCoalescing(key: "fail-trailing") {
                throw expectedError
            }
        }

        while await !coordinator.hasPendingTrailing(key: "fail-trailing") {
            try await Task.sleep(for: .milliseconds(5))
        }

        await gate.open()

        let res1 = try await task1.value
        #expect(res1 == "initial-success")

        do {
            _ = try await task2.value
            Issue.record("Expected task2 to throw TestError")
        } catch let error as TestError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }

        #expect(await coordinator.isInFlight(key: "fail-trailing") == false)
        #expect(await coordinator.hasPendingTrailing(key: "fail-trailing") == false)
    }

    @Test("Subsequent calls succeed after previous in-flight pass threw error")
    func subsequentCallSucceedsAfterError() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let error = TestError(message: "Transient failure")

        await #expect(throws: TestError.self) {
            try await coordinator.execute(key: "recovery") {
                throw error
            }
        }

        let recovery = try await coordinator.execute(key: "recovery") {
            "recovered-successfully"
        }

        #expect(recovery == "recovered-successfully")
    }

    // MARK: - 4. Task Cancellation Contracts

    @Test("Cancelling one caller does not cancel in-flight operation when other callers remain")
    func cancellingOneCallerDoesNotCancelSharedOperation() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let gate = TestGate()

        let caller1 = Task {
            try await coordinator.execute(key: "cancel-test") {
                await gate.wait()
                return "completed-work"
            }
        }

        while await !coordinator.isInFlight(key: "cancel-test") {
            try await Task.sleep(for: .milliseconds(5))
        }

        let caller2 = Task {
            try await coordinator.execute(key: "cancel-test") {
                await gate.wait()
                return "completed-work"
            }
        }

        try await Task.sleep(for: .milliseconds(10))

        // Cancel caller 1 while caller 2 continues awaiting
        caller1.cancel()

        await #expect(throws: CancellationError.self) {
            try await caller1.value
        }

        await gate.open()

        let caller2Result = try await caller2.value
        #expect(caller2Result == "completed-work")

        #expect(await coordinator.isInFlight(key: "cancel-test") == false)
    }

    @Test("Cancelling all shared callers cancels the underlying operation task")
    func cancellingAllCallersCancelsUnderlyingTask() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let gate = TestGate()

        let caller1 = Task {
            try await coordinator.execute(key: "cancel-all") {
                await gate.wait()
                try Task.checkCancellation()
                return "finished"
            }
        }

        while await !coordinator.isInFlight(key: "cancel-all") {
            try await Task.sleep(for: .milliseconds(5))
        }

        let caller2 = Task {
            try await coordinator.execute(key: "cancel-all") {
                await gate.wait()
                try Task.checkCancellation()
                return "finished"
            }
        }

        try await Task.sleep(for: .milliseconds(10))

        caller1.cancel()
        caller2.cancel()

        await #expect(throws: CancellationError.self) {
            try await caller1.value
        }

        await #expect(throws: CancellationError.self) {
            try await caller2.value
        }

        await gate.open()

        // Verify coordinator has cleaned up
        #expect(await coordinator.isInFlight(key: "cancel-all") == false)
    }

    @Test("Cancelling trailing caller removes waiter and cleans up pending state")
    func cancellingTrailingCallerRemovesWaiter() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let gate = TestGate()
        let tracker = InvocationTracker()

        let task1 = Task {
            try await coordinator.execute(key: "trailing-cancel") {
                await gate.wait()
                _ = await tracker.increment()
                return "pass-1"
            }
        }

        while await !coordinator.isInFlight(key: "trailing-cancel") {
            try await Task.sleep(for: .milliseconds(5))
        }

        let trailingTask = Task {
            try await coordinator.executeCoalescing(key: "trailing-cancel") {
                _ = await tracker.increment()
                return "pass-2"
            }
        }

        while await !coordinator.hasPendingTrailing(key: "trailing-cancel") {
            try await Task.sleep(for: .milliseconds(5))
        }

        // Cancel trailing caller before initial pass opens
        trailingTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await trailingTask.value
        }

        await gate.open()

        let res1 = try await task1.value
        #expect(res1 == "pass-1")

        await coordinator.waitForIdle(key: "trailing-cancel")

        let count = await tracker.count
        #expect(count == 1)
        #expect(await coordinator.isInFlight(key: "trailing-cancel") == false)
        #expect(await coordinator.hasPendingTrailing(key: "trailing-cancel") == false)
    }

    // MARK: - 5. Lifecycle & Memory Invariants

    @Test("Coordinator cleans up inFlight and pendingTrailing dictionaries upon completion")
    func cleanStateResetAfterSuccessfulExecution() async throws {
        let coordinator = SingleflightCoordinator<String, Int>()

        let val = try await coordinator.execute(key: "cleanup") {
            42
        }

        #expect(val == 42)
        #expect(await coordinator.isInFlight(key: "cleanup") == false)
        #expect(await coordinator.hasPendingTrailing(key: "cleanup") == false)
        #expect(await coordinator.activeInFlightKeys().isEmpty)
    }

    @Test("Coordinator cleans up inFlight and pendingTrailing dictionaries upon failure")
    func cleanStateResetAfterFailure() async {
        let coordinator = SingleflightCoordinator<String, Int>()

        await #expect(throws: TestError.self) {
            try await coordinator.execute(key: "cleanup-err") {
                throw TestError(message: "Bown")
            }
        }

        #expect(await coordinator.isInFlight(key: "cleanup-err") == false)
        #expect(await coordinator.hasPendingTrailing(key: "cleanup-err") == false)
        #expect(await coordinator.activeInFlightKeys().isEmpty)
    }

    @Test("Reset method cancels in-flight tasks and resets all internal state")
    func resetMethodClearsAllState() async throws {
        let coordinator = SingleflightCoordinator<String, String>()
        let gate = TestGate()

        let task1 = Task {
            try await coordinator.execute(key: "reset-1") {
                await gate.wait()
                return "r1"
            }
        }

        while await !coordinator.isInFlight(key: "reset-1") {
            try await Task.sleep(for: .milliseconds(5))
        }

        await coordinator.reset()

        #expect(await coordinator.isInFlight(key: "reset-1") == false)
        #expect(await coordinator.activeInFlightKeys().isEmpty)

        await gate.open()
        _ = try? await task1.value
    }
}
