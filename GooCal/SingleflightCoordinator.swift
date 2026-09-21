//
//  SingleflightCoordinator.swift
//  GooCal
//

import Foundation

/// Defines how a caller participates in singleflight execution when an operation
/// is already in flight for the target key.
public enum SingleflightStrategy: Sendable {
    /// Joins the active in-flight task and returns its result when completed.
    /// No trailing execution pass is scheduled.
    case deduplicate

    /// If an operation is already in flight, registers for a trailing coalesced pass.
    /// The caller awaits and receives the result of that trailing pass once it concludes.
    case awaitTrailing

    /// Joins the active in-flight task to return immediately upon its conclusion,
    /// while also scheduling a trailing pass to run after to capture state updates.
    case joinAndScheduleTrailing
}

/// A generic concurrency coordinator that deduplicates concurrent asynchronous operations
/// by key and coalesces rapid subsequent execution triggers into at most one trailing pass.
///
/// Under burst conditions (e.g. system calendar notifications, popover presentation, manual
/// refresh clicks), multiple concurrent callers requesting work for the same key share
/// the single in-flight `Task`. If additional requests arrive while that pass is executing,
/// the coordinator schedules exactly one trailing execution pass to guarantee that any
/// state changes requested during the initial pass are accurately reflected.
public actor SingleflightCoordinator<Key: Hashable & Sendable, Value: Sendable> {

    private final class InFlightEntry {
        let taskID: UInt64
        let task: Task<Value, Error>
        var callerIDs: Set<UInt64>
        var continuations: [UInt64: CheckedContinuation<Value, Error>]
        var result: Result<Value, Error>?

        init(
            taskID: UInt64,
            task: Task<Value, Error>,
            callerIDs: Set<UInt64> = [],
            continuations: [UInt64: CheckedContinuation<Value, Error>] = [:]
        ) {
            self.taskID = taskID
            self.task = task
            self.callerIDs = callerIDs
            self.continuations = continuations
            self.result = nil
        }
    }

    private final class PendingTrailingEntry {
        var operation: @Sendable () async throws -> Value
        var callerIDs: Set<UInt64>
        var inFlightRequestorIDs: Set<UInt64>
        var continuations: [UInt64: CheckedContinuation<Value, Error>]

        var hasActiveWaiters: Bool {
            !callerIDs.isEmpty || !continuations.isEmpty || !inFlightRequestorIDs.isEmpty
        }

        init(
            operation: @Sendable @escaping () async throws -> Value,
            callerID: UInt64? = nil,
            inFlightRequestorID: UInt64? = nil,
            continuation: CheckedContinuation<Value, Error>? = nil
        ) {
            self.operation = operation
            if let callerID {
                self.callerIDs = [callerID]
                if let continuation {
                    self.continuations = [callerID: continuation]
                } else {
                    self.continuations = [:]
                }
            } else {
                self.callerIDs = []
                self.continuations = [:]
            }
            if let inFlightRequestorID {
                self.inFlightRequestorIDs = [inFlightRequestorID]
            } else {
                self.inFlightRequestorIDs = []
            }
        }
    }

    private var inFlight: [Key: InFlightEntry] = [:]
    private var pendingTrailing: [Key: PendingTrailingEntry] = [:]
    private var nextTaskID: UInt64 = 1
    private var nextCallerID: UInt64 = 1

    public init() {}

    /// Executes an operation for the specified key with deduplication.
    ///
    /// If an operation for this key is already running, the caller joins the existing task
    /// and shares its result without launching parallel work.
    @discardableResult
    public func execute(
        key: Key,
        operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        try await execute(key: key, strategy: .deduplicate, operation: operation)
    }

    /// Executes an operation for the specified key, coalescing concurrent mid-flight calls
    /// into a trailing execution pass.
    ///
    /// If an operation for this key is already in flight, the caller awaits the completion
    /// of a trailing pass rather than returning stale in-flight state.
    @discardableResult
    public func executeCoalescing(
        key: Key,
        operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        try await execute(key: key, strategy: .awaitTrailing, operation: operation)
    }

    /// Executes an operation for the specified key using the specified singleflight strategy.
    @discardableResult
    public func execute(
        key: Key,
        strategy: SingleflightStrategy,
        operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        let callerID = nextCallerID
        nextCallerID += 1

        if let existing = inFlight[key] {
            switch strategy {
            case .deduplicate:
                existing.callerIDs.insert(callerID)
                return try await awaitInFlightTask(key: key, callerID: callerID)

            case .joinAndScheduleTrailing:
                existing.callerIDs.insert(callerID)
                if let trailing = pendingTrailing[key] {
                    trailing.operation = operation
                    trailing.inFlightRequestorIDs.insert(callerID)
                } else {
                    pendingTrailing[key] = PendingTrailingEntry(
                        operation: operation,
                        inFlightRequestorID: callerID
                    )
                }
                return try await awaitInFlightTask(key: key, callerID: callerID)

            case .awaitTrailing:
                return try await registerAndAwaitTrailing(key: key, callerID: callerID, operation: operation)
            }
        }

        // No task is currently in flight for this key. Start a new initial pass.
        let taskID = nextTaskID
        nextTaskID += 1

        let task = Task { [weak self] () -> Value in
            do {
                let result = try await operation()
                if let self {
                    await self.handlePassCompletion(key: key, taskID: taskID, outcome: .success(result))
                }
                return result
            } catch {
                if let self {
                    await self.handlePassCompletion(key: key, taskID: taskID, outcome: .failure(error))
                }
                throw error
            }
        }

        let entry = InFlightEntry(taskID: taskID, task: task, callerIDs: [callerID])
        inFlight[key] = entry

        return try await awaitInFlightTask(key: key, callerID: callerID)
    }

    private func awaitInFlightTask(key: Key, callerID: UInt64) async throws -> Value {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard let entry = inFlight[key] else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let outcome = entry.result {
                    continuation.resume(with: outcome)
                } else {
                    entry.continuations[callerID] = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancelCaller(key: key, callerID: callerID)
            }
        }
    }

    private func registerAndAwaitTrailing(
        key: Key,
        callerID: UInt64,
        operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if let trailing = pendingTrailing[key] {
                    trailing.operation = operation
                    trailing.callerIDs.insert(callerID)
                    trailing.continuations[callerID] = continuation
                } else {
                    let entry = PendingTrailingEntry(
                        operation: operation,
                        callerID: callerID,
                        continuation: continuation
                    )
                    pendingTrailing[key] = entry
                }
            }
        } onCancel: {
            Task {
                await self.cancelCaller(key: key, callerID: callerID)
            }
        }
    }

    private func cancelCaller(key: Key, callerID: UInt64) {
        if let entry = inFlight[key] {
            entry.callerIDs.remove(callerID)
            if let cont = entry.continuations.removeValue(forKey: callerID) {
                cont.resume(throwing: CancellationError())
            }
            if let trailing = pendingTrailing[key] {
                trailing.inFlightRequestorIDs.remove(callerID)
                if !trailing.hasActiveWaiters {
                    pendingTrailing.removeValue(forKey: key)
                }
            }
            if entry.callerIDs.isEmpty {
                let hasTrailingCallers = pendingTrailing[key]?.hasActiveWaiters == true
                if !hasTrailingCallers {
                    entry.task.cancel()
                    inFlight.removeValue(forKey: key)
                    pendingTrailing.removeValue(forKey: key)
                } else {
                    entry.task.cancel()
                }
            }
        }

        if let trailing = pendingTrailing[key] {
            trailing.callerIDs.remove(callerID)
            trailing.inFlightRequestorIDs.remove(callerID)
            if let cont = trailing.continuations.removeValue(forKey: callerID) {
                cont.resume(throwing: CancellationError())
            }
            if !trailing.hasActiveWaiters {
                pendingTrailing.removeValue(forKey: key)
            }
        }
    }

    private func handlePassCompletion(key: Key, taskID: UInt64, outcome: Result<Value, Error>) {
        guard let currentEntry = inFlight[key], currentEntry.taskID == taskID else {
            return
        }

        currentEntry.result = outcome
        for continuation in currentEntry.continuations.values {
            continuation.resume(with: outcome)
        }
        currentEntry.continuations.removeAll()

        if let trailing = pendingTrailing.removeValue(forKey: key), trailing.hasActiveWaiters {
            let newTaskID = nextTaskID
            nextTaskID += 1

            let trailingTask = Task { [weak self, trailingOp = trailing.operation] () -> Value in
                do {
                    let res = try await trailingOp()
                    if let self {
                        await self.handlePassCompletion(key: key, taskID: newTaskID, outcome: .success(res))
                    }
                    return res
                } catch {
                    if let self {
                        await self.handlePassCompletion(key: key, taskID: newTaskID, outcome: .failure(error))
                    }
                    throw error
                }
            }

            let newEntry = InFlightEntry(
                taskID: newTaskID,
                task: trailingTask,
                callerIDs: trailing.callerIDs,
                continuations: trailing.continuations
            )
            inFlight[key] = newEntry
        } else {
            inFlight.removeValue(forKey: key)
        }
    }

    // MARK: - Lifecycle & Diagnostics Inspection

    /// Returns `true` if an operation is currently executing for the specified key.
    public func isInFlight(key: Key) -> Bool {
        inFlight[key] != nil
    }

    /// Returns `true` if a trailing pass is pending for the specified key.
    public func hasPendingTrailing(key: Key) -> Bool {
        pendingTrailing[key] != nil
    }

    /// Returns the keys of all operations currently in flight.
    public func activeInFlightKeys() -> Set<Key> {
        Set(inFlight.keys)
    }

    /// Awaits until all active in-flight and pending trailing operations for the key have settled.
    public func waitForIdle(key: Key) async {
        while let entry = inFlight[key] {
            _ = try? await entry.task.value
        }
    }

    /// Resets coordinator state by cancelling all in-flight tasks and clearing pending entries.
    public func reset() {
        for entry in inFlight.values {
            entry.task.cancel()
            for cont in entry.continuations.values {
                cont.resume(throwing: CancellationError())
            }
        }
        for trailing in pendingTrailing.values {
            for cont in trailing.continuations.values {
                cont.resume(throwing: CancellationError())
            }
        }
        inFlight.removeAll()
        pendingTrailing.removeAll()
    }
}
