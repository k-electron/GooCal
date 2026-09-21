# menu-bar-app Specification

## Purpose

Provides a lightweight macOS menu bar presence that runs as an accessory, displays upcoming status in the menu bar, opens an interactive popover window on click, and supports automatic launch at login.

## Requirements

### Requirement: Application operates as a menu bar accessory
The application SHALL run as an accessory application (`LSUIElement = true`), remaining active in the macOS menu bar without appearing in the macOS Dock or application switcher.

#### Scenario: Application launch
- **WHEN** the application is launched
- **THEN** an icon and status text appear in the macOS menu bar and no icon appears in the macOS Dock

### Requirement: Menu bar item displays status and expands on click
The application SHALL display an icon and status text in the menu bar and present an interactive popover window containing the daily timeline view when clicked.

#### Scenario: Clicking menu bar item opens popover
- **WHEN** the user clicks the menu bar item
- **THEN** a popover window opens adjacent to the status item containing the scrollable daily timeline, status information, and a Settings button

#### Scenario: Clicking outside closes popover
- **WHEN** the popover window is open and the user clicks outside the window
- **THEN** the popover window dismisses

### Requirement: Popover provides access to application settings
The popover window SHALL contain a Settings button that triggers the application's Settings window.

#### Scenario: User opens settings from popover
- **WHEN** the user clicks the Settings button in the popover window
- **THEN** the application opens the Settings window

### Requirement: User can toggle launch at login
The application SHALL provide a setting allowing the user to enable or disable automatic launching when logging into macOS.

#### Scenario: Enable launch at login
- **WHEN** the user toggles the "Launch at Login" setting to enabled
- **THEN** the application registers itself with macOS ServiceManagement to launch upon user login

#### Scenario: Disable launch at login
- **WHEN** the user toggles the "Launch at Login" setting to disabled
- **THEN** the application unregisters itself from macOS ServiceManagement login items
