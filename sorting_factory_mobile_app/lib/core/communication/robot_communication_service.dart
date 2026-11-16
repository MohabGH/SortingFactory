import 'package:flutter/foundation.dart';

import 'communication_log.dart';
import 'connection_status.dart';
import 'robot_command.dart';

/// Thrown by [RobotCommunicationService.send] when a command cannot be
/// delivered. [message] is suitable for display to the user.
class CommunicationException implements Exception {
  const CommunicationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Contract for talking to the robotic arm's microcontroller.
///
/// UI code only depends on this interface, so a transport can be swapped
/// (BLE today, see `BleCommunicationService`) without touching features.
abstract class RobotCommunicationService extends ChangeNotifier {
  /// Human readable name of the transport, e.g. "Bluetooth Low Energy".
  String get transportName;

  ConnectionStatus get status;

  /// Extra detail about [status] (e.g. why it is unavailable), if any.
  String? get statusMessage => null;

  bool get isConnected => status == ConnectionStatus.connected;

  /// What the robot is doing, inferred from its replies.
  RobotActivity get activity;

  /// The device currently linked, or `null` when not connected.
  ConnectedDeviceInfo? get connectedDevice;

  /// Every message sent and received, plus connection events.
  CommunicationLog get log;

  /// Connects to the robot (finding it first if necessary).
  Future<void> connect();

  Future<void> disconnect();

  /// Sends [command] to the microcontroller.
  ///
  /// Throws a [CommunicationException] if it could not be delivered.
  Future<void> send(RobotCommand command);
}

/// A device found while scanning.
@immutable
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isRobot,
  });

  /// Platform identifier (MAC address on Android, UUID on iOS).
  final String id;

  /// Advertised name, empty when the device did not advertise one.
  final String name;

  /// Signal strength in dBm.
  final int rssi;

  /// Whether the device looks like the SFRA_ESP firmware (matching name or
  /// advertised service).
  final bool isRobot;

  String get displayName => name.isEmpty ? 'Unknown device' : name;
}

/// A transport that must discover devices before connecting (e.g. BLE).
abstract class ScanningCommunicationService extends RobotCommunicationService {
  bool get isScanning;

  /// Results of the current/last scan, robots first then by signal strength.
  List<DiscoveredDevice> get discoveredDevices;

  /// Starts a time-limited scan. With [onlyRobots] only devices advertising
  /// the SFRA service or name are reported.
  Future<void> startScan({bool onlyRobots = true});

  Future<void> stopScan();

  Future<void> connectTo(DiscoveredDevice device);

  /// Whether the app can switch the radio on itself (Android only).
  bool get canEnableAdapter;

  Future<void> enableAdapter();
}
