# Spec Delta

## MODIFIED Requirements

### Requirement: Menu bar item displays status and expands on click
The application SHALL display an icon and status text in the menu bar and present an interactive popover window containing the daily timeline view when clicked.

#### Scenario: Clicking menu bar item opens popover
- **WHEN** the user clicks the menu bar item
- **THEN** a popover window opens adjacent to the status item containing the scrollable daily timeline, status information, and a Settings button

#### Scenario: Clicking outside closes popover
- **WHEN** the popover window is open and the user clicks outside the window
- **THEN** the popover window dismisses
