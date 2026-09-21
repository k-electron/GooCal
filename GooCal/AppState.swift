//
//  AppState.swift
//  GooCal
//

import AppKit
import SwiftUI
import Observation

/// Central state store for GooCal menu bar and settings presentation.
///
/// Marked `@MainActor` and `@Observable` to guarantee thread-safe UI binding updates
/// with fine-grained view invalidation under Swift concurrency.
@Observable
@MainActor
public final class AppState {
    public var menuBarTitle: String
    public var menuBarIconName: String
    public var isLaunchAtLoginEnabled: Bool
    public var statusMessage: String
    public private(set) var lastError: (any Error)?

    public private(set) var events: [CalendarEvent] = []
    public private(set) var placedEvents: [PlacedEvent] = []
    public private(set) var calendarAuthorizationStatus: CalendarAuthorizationStatus
    public var selectedDate: Date = Date()
    public var isTrackingToday: Bool = true
    public private(set) var isLoadingEvents: Bool = false
    public private(set) var isSyncingRemote: Bool = false
    public private(set) var syncError: (any Error)? = nil

    public let calendarService: any CalendarServiceManaging
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let localQueryCoordinator: SingleflightCoordinator<Date, [CalendarEvent]>
    private let remoteSyncCoordinator: SingleflightCoordinator<String, Void>
    private let notificationCenter: NotificationCenter
    private let debounceDuration: Duration
    private let heartbeatInterval: TimeInterval
    private let heartbeatTolerance: TimeInterval

    private nonisolated(unsafe) var storeChangeObserverTask: Task<Void, Never>?
    private nonisolated(unsafe) var storeChangeDebounceTask: Task<Void, Never>?
    private nonisolated(unsafe) var heartbeatTimer: Timer?
    private nonisolated(unsafe) var wakeObserver: (any NSObjectProtocol)?

    private var inFlightLoadingCount: Int = 0
    private var inFlightRemoteSyncCount: Int = 0

    /// Creates an application state instance.
    ///
    /// Accepts custom `LaunchAtLoginManaging`, `CalendarServiceManaging`, and coordinators to enable
    /// deterministic unit testing without mutating system-wide login items or relying on live TCC permissions.
    public init(
        launchAtLoginManager: (any LaunchAtLoginManaging)? = nil,
        calendarService: any CalendarServiceManaging = EventKitCalendarService(),
        menuBarTitle: String = "GooCal: No Upcoming Meetings",
        menuBarIconName: String = "calendar",
        statusMessage: String = "No upcoming meetings",
        selectedDate: Date = Date(),
        isTrackingToday: Bool? = nil,
        localQueryCoordinator: SingleflightCoordinator<Date, [CalendarEvent]> = SingleflightCoordinator(),
        remoteSyncCoordinator: SingleflightCoordinator<String, Void> = SingleflightCoordinator(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        debounceDuration: Duration = .milliseconds(250),
        heartbeatInterval: TimeInterval = 60.0,
        heartbeatTolerance: TimeInterval = 10.0,
        startMonitoring: Bool = true
    ) {
        let manager = launchAtLoginManager ?? SMAppServiceLaunchAtLoginManager()
        self.launchAtLoginManager = manager
        self.calendarService = calendarService
        self.menuBarTitle = menuBarTitle
        self.menuBarIconName = menuBarIconName
        self.statusMessage = statusMessage
        self.selectedDate = selectedDate
        self.isTrackingToday = isTrackingToday ?? Calendar.current.isDateInToday(selectedDate)
        self.isLaunchAtLoginEnabled = manager.isEnabled
        self.calendarAuthorizationStatus = calendarService.authorizationStatus()
        self.events = []
        self.placedEvents = []
        self.isLoadingEvents = false
        self.isSyncingRemote = false
        self.syncError = nil
        self.lastError = nil
        self.localQueryCoordinator = localQueryCoordinator
        self.remoteSyncCoordinator = remoteSyncCoordinator
        self.notificationCenter = notificationCenter
        self.debounceDuration = debounceDuration
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTolerance = heartbeatTolerance

        if startMonitoring {
            startObservingStoreChanges()
            startHeartbeat()
            startObservingWakeNotification()
        }
    }

    /// Two-way SwiftUI binding bridging toggle controls directly to managed login registration.
    public var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { self.isLaunchAtLoginEnabled },
            set: { self.setLaunchAtLogin(enabled: $0) }
        )
    }

    /// Synchronizes login item registration with macOS ServiceManagement.
    ///
    /// If registration or unregistration throws (e.g. system authorization failure),
    /// the error is captured, user status is updated, and `isLaunchAtLoginEnabled`
    /// stays synchronized with the manager's actual state to prevent misleading UI indicators.
    public func setLaunchAtLogin(enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
            statusMessage = enabled ? "Launch at login enabled" : "Launch at login disabled"
            lastError = nil
        } catch {
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
            statusMessage = "Failed to update launch at login: \(error.localizedDescription)"
            lastError = error
        }
    }

    /// Explicitly requests calendar access and triggers an events refresh.
    public func requestCalendarAccess() async {
        do {
            _ = try await calendarService.requestAccess()
            await refreshEvents()
        } catch {
            self.lastError = error
            self.calendarAuthorizationStatus = calendarService.authorizationStatus()
            self.statusMessage = "Failed to request calendar access: \(error.localizedDescription)"
        }
    }

    /// Updates the selected active date and queries calendar events for the new 24-hour day.
    public func setSelectedDate(_ date: Date) async {
        self.selectedDate = date
        self.isTrackingToday = Calendar.current.isDateInToday(date)
        await refreshEvents()
    }

    /// Refreshes calendar authorization and queries calendar events for the active date,
    /// optionally initiating remote source synchronization.
    ///
    /// Coalesces concurrent queries through `SingleflightCoordinator` with `.awaitTrailing`
    /// and precomputes layout placement off the main actor into `placedEvents`.
    public func refreshEvents(pullRemote: Bool = false) async {
        if pullRemote {
            inFlightRemoteSyncCount += 1
            isSyncingRemote = true
            defer {
                inFlightRemoteSyncCount -= 1
                if inFlightRemoteSyncCount == 0 {
                    isSyncingRemote = false
                }
            }

            do {
                try await remoteSyncCoordinator.execute(key: "remote_sync", strategy: .deduplicate) { [calendarService] in
                    try await calendarService.refreshSources()
                }
                syncError = nil
            } catch {
                syncError = error
            }

            if syncError == nil {
                await refreshEvents(pullRemote: false)
            }
            return
        }

        inFlightLoadingCount += 1
        isLoadingEvents = true
        defer {
            inFlightLoadingCount -= 1
            if inFlightLoadingCount == 0 {
                isLoadingEvents = false
            }
        }

        calendarAuthorizationStatus = calendarService.authorizationStatus()
        if calendarAuthorizationStatus == .notDetermined {
            do {
                _ = try await calendarService.requestAccess()
                calendarAuthorizationStatus = calendarService.authorizationStatus()
            } catch {
                self.lastError = error
                self.statusMessage = "Failed to request calendar access: \(error.localizedDescription)"
                return
            }
        }

        switch calendarAuthorizationStatus {
        case .authorized:
            let targetDate = selectedDate
            let dayKey = Calendar.current.startOfDay(for: targetDate)
            do {
                let fetchedEvents = try await localQueryCoordinator.execute(
                    key: dayKey,
                    strategy: .awaitTrailing
                ) { [calendarService] in
                    try await calendarService.events(for: targetDate)
                }

                // Offload geometry placement and cluster computation from @MainActor
                let placed = await Task.detached(priority: .userInitiated) {
                    TimelineLayoutEngine.layout(events: fetchedEvents, for: targetDate)
                }.value

                if Calendar.current.isDate(self.selectedDate, inSameDayAs: targetDate) {
                    self.events = fetchedEvents
                    self.placedEvents = placed
                    self.lastError = nil
                    updatePresentationForLoadedEvents(with: fetchedEvents)
                }
            } catch {
                self.lastError = error
                self.statusMessage = "Failed to load events: \(error.localizedDescription)"
            }

        case .denied, .restricted:
            self.events = []
            self.placedEvents = []
            self.menuBarTitle = "GooCal: Calendar Access Required"
            self.statusMessage = "Calendar access is denied or restricted"

        case .notDetermined:
            self.events = []
            self.placedEvents = []
        }
    }

    // MARK: - Store Change Observation & Debounce

    private func startObservingStoreChanges() {
        storeChangeObserverTask?.cancel()
        storeChangeObserverTask = Task { [weak self, calendarService] in
            for await _ in calendarService.storeChanges {
                guard !Task.isCancelled else { break }
                await self?.handleStoreChange()
            }
        }
    }

    private func handleStoreChange() {
        storeChangeDebounceTask?.cancel()
        storeChangeDebounceTask = Task { [weak self, debounceDuration] in
            do {
                try await Task.sleep(for: debounceDuration)
                guard !Task.isCancelled else { return }
                await self?.refreshEvents(pullRemote: false)
            } catch {
                // Cancelled due to rapid successive store change or teardown
            }
        }
    }

    // MARK: - Sleep-Safe Background Heartbeat & Wake Recovery

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleHeartbeatTick()
            }
        }
        timer.tolerance = heartbeatTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.heartbeatTimer = timer
    }

    private func startObservingWakeNotification() {
        if let wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleWakeNotification()
            }
        }
    }

    /// Handles periodic background tick: updates meeting status and manages midnight rollover.
    public func handleHeartbeatTick(referenceDate: Date = .now) async {
        if isTrackingToday && !Calendar.current.isDateInToday(selectedDate) {
            selectedDate = referenceDate
            await refreshEvents(pullRemote: false)
        } else {
            updatePresentationForLoadedEvents(with: events, referenceDate: referenceDate)
        }
    }

    /// Handles system wake from sleep: instantly advances time context, handles midnight rollover,
    /// and triggers catch-up remote synchronization.
    public func handleWakeNotification() async {
        let now = Date.now
        if isTrackingToday && !Calendar.current.isDateInToday(selectedDate) {
            selectedDate = now
        }
        updatePresentationForLoadedEvents(with: events, referenceDate: now)
        await refreshEvents(pullRemote: true)
    }

    /// Updates menu bar title and status message based on queried events and current time context.
    private func updatePresentationForLoadedEvents(with events: [CalendarEvent], referenceDate: Date = .now) {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(selectedDate)
        let activeEvents = events.filter { !$0.isAllDay && $0.participantStatus != .declined }

        if isToday {
            let now = referenceDate
            let upcoming = activeEvents
                .filter { $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }

            if let nextEvent = upcoming.first {
                menuBarTitle = "GooCal: \(nextEvent.title)"
                if nextEvent.startDate <= now {
                    statusMessage = "Current meeting: \(nextEvent.title)"
                } else {
                    let timeStr = nextEvent.startDate.formatted(date: .omitted, time: .shortened)
                    statusMessage = "Next at \(timeStr): \(nextEvent.title)"
                }
            } else {
                menuBarTitle = "GooCal: No Upcoming Meetings"
                statusMessage = events.isEmpty ? "No upcoming meetings" : "\(events.count) event\(events.count == 1 ? "" : "s") today"
            }
        } else {
            let count = events.count
            let dateStr = selectedDate.formatted(.dateTime.month().day())
            statusMessage = "\(count) event\(count == 1 ? "" : "s") on \(dateStr)"
        }
    }

    // MARK: - Teardown

    /// Cancels all background tasks, timers, and notification observers.
    public func cleanup() {
        storeChangeObserverTask?.cancel()
        storeChangeObserverTask = nil
        storeChangeDebounceTask?.cancel()
        storeChangeDebounceTask = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if let wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    deinit {
        storeChangeObserverTask?.cancel()
        storeChangeDebounceTask?.cancel()
        heartbeatTimer?.invalidate()
        if let wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
        }
    }
}
