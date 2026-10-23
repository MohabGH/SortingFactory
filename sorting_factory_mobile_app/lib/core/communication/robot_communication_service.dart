import 'package:flutter/foundation.dart';

import 'connection_status.dart';
import 'robot_command.dart';

/// Contract for talking to the robotic arm's microcontroller.
///
/// The protocol (Bluetooth, BLE, Wi-Fi, USB serial, ...) is not decided yet.
/// When it is, create a new implementation of this class (for example
/// `BluetoothCommunicationService`) and pass it to `RobotArmApp`.
/// UI code only depends on this interface, so no feature needs to change.
abstract class RobotCommunicationService extends ChangeNotifier {
  ConnectionStatus get status;

  bool get isConnected => status == ConnectionStatus.connected;

  Future<void> connect();

  Future<void> disconnect();

  /// Sends [command] to the microcontroller.
  Future<void> send(RobotCommand command);
}
