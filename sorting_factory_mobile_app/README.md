# Robot Arm Controller (Flutter)

Mobile app for controlling a robotic arm from a microcontroller.

## Project structure

```
lib/
├── main.dart                     # Entry point
├── app/                          # App-level wiring
│   ├── app.dart                  # RobotArmApp: theme + scopes (navigation, communication)
│   ├── app_shell.dart            # Single Scaffold whose body is swapped (no Navigator routes)
│   ├── app_destinations.dart     # Registry of every page (drawer + home cards read from here)
│   ├── theme/app_theme.dart
│   └── widgets/app_drawer.dart   # Hamburger menu
├── core/                         # Feature-agnostic building blocks
│   ├── constants/                # App name, version, ...
│   ├── navigation/               # AppPageId, AppDestination, NavigationController/Scope
│   ├── communication/            # RobotCommand, RobotCommunicationService (+ no-op placeholder)
│   └── robot/                    # ServoConfig, RobotArmConfig (servo list & limits)
├── features/                     # One folder per feature / control mode
│   ├── home/
│   ├── manual_control/
│   └── settings/
└── shared/widgets/               # Reusable UI pieces used by several features
```

## Navigation

There is only one page (`AppShell`). Selecting an item in the drawer or a
card on the home page calls `NavigationController.goTo(...)`, which swaps the
shell body. Selecting the page that is already visible only closes the drawer.
The Android back button returns to Home (or closes the drawer if open).

## Adding a new feature (e.g. a joystick control mode)

1. Create `lib/features/joystick_control/joystick_control_page.dart`
   (return the page body only; no `Scaffold`/`AppBar` — the shell provides them).
2. Add `joystickControl` to `AppPageId` in `lib/core/navigation/app_page_id.dart`.
3. Register an `AppDestination` in `lib/app/app_destinations.dart`
   (use `group: DestinationGroup.controlModes, showOnHome: true`).

The drawer, home page and app bar title update automatically.

## Plugging in the communication protocol

Features only build protocol-agnostic `RobotCommand` objects and call
`CommunicationScope.read(context).send(command)`. Today the active service is
`UnconfiguredCommunicationService`, which does nothing. When the protocol is
chosen:

1. Implement `RobotCommunicationService` (e.g. `BluetoothCommunicationService`)
   in `lib/core/communication/`, encoding each `RobotCommand` into bytes.
2. Pass it to `RobotArmApp(communicationService: ...)` in `main.dart`.

## Adjusting the arm

Edit `lib/core/robot/robot_arm_config.dart` to change the number of servos,
their names, or angle limits.
