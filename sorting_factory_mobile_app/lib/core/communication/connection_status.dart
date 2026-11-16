/// Connection state between the app and the microcontroller.
enum ConnectionStatus {
  /// No communication protocol/transport is available in this build.
  notConfigured('Not configured'),

  /// The transport exists but cannot be used right now (e.g. Bluetooth is
  /// turned off, permission was denied or the phone has no BLE radio).
  unavailable('Unavailable'),

  disconnected('Disconnected'),

  /// Searching for the robot (BLE scan in progress).
  scanning('Scanning…'),

  /// Link being established / services being discovered.
  connecting('Connecting…'),

  /// Link up and ready to exchange commands.
  connected('Connected');

  const ConnectionStatus(this.label);

  final String label;

  /// Whether a connection attempt or a scan is in progress.
  bool get isBusy => this == scanning || this == connecting;
}

/// What the robot is doing, as inferred from the messages it sends back.
///
/// The ESP32 firmware runs a small state machine:
/// `IDLE → PARSE_CMD → MOVING → FEEDBACK → IDLE`. It answers every command
/// with `Moving...` (valid) or `ERROR, Try again` (invalid) and sends `DONE`
/// once every servo has reached its target.
enum RobotActivity {
  /// Not connected, nothing can be said about the robot.
  offline('Offline'),

  /// Connected and waiting for a command.
  idle('Ready'),

  /// A command was sent; no acknowledgement received yet.
  awaitingResponse('Waiting…'),

  /// The ESP32 acknowledged the command and the servos are moving.
  moving('Moving…');

  const RobotActivity(this.label);

  final String label;

  bool get isBusy => this == awaitingResponse || this == moving;
}

/// Information about the device the app is currently linked to.
class ConnectedDeviceInfo {
  const ConnectedDeviceInfo({required this.name, required this.id, this.mtu});

  final String name;

  /// Platform identifier (MAC address on Android, UUID on iOS).
  final String id;

  /// Negotiated ATT MTU, when known.
  final int? mtu;
}
