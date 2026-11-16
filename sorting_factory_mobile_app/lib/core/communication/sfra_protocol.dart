import 'robot_command.dart';

/// Kind of message received from the ESP32.
enum DeviceResponse {
  /// `Moving...` – the command was valid and the servos started moving.
  moving,

  /// `DONE` – every servo reached its target angle.
  done,

  /// `ERROR, Try again` – the command was rejected by the parser.
  error,

  /// Anything else (future firmware messages, debug output, ...).
  unknown,
}

/// Wire protocol spoken by the `SFRA_ESP` firmware
/// (`microcontrollers/microcontrollers.ino`).
///
/// Transport: BLE, Nordic-UART-style service.
///  * The app **writes** UTF-8/ASCII text to the RX characteristic.
///  * The ESP32 **notifies** text lines terminated by `\r\n` on the TX
///    characteristic.
///
/// Command grammar (one command per write, whitespace around tokens is
/// ignored, a single trailing comma is tolerated):
///
/// ```text
/// command := pair ("," pair)*
/// pair    := servo ":" angle        servo 0–5, angle 0–180 (digits only)
/// ```
///
/// A command is applied atomically: if any pair is invalid nothing moves and
/// the ESP32 answers `ERROR, Try again`. Servos not mentioned keep their
/// current target. While the arm is moving, newly received commands are not
/// queued: only the most recent one is executed after `DONE`.
abstract final class SfraProtocol {
  /// Advertised BLE name ("Sorting Factory Robotic Arm ESP32-S").
  static const String deviceName = 'SFRA_ESP';

  static const String serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// App → ESP32. Supports write and write-without-response.
  static const String rxCharacteristicUuid =
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  /// ESP32 → App. Notify only.
  static const String txCharacteristicUuid =
      '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  /// Number of PCA9685 channels driven by the firmware (`NUM_SERVO`).
  static const int servoCount = 6;
  static const int minAngle = 0;
  static const int maxAngle = 180;

  /// Time the firmware waits between two 1° steps (`SERVO_STEP_INTERVAL`).
  static const Duration servoStepInterval = Duration(milliseconds: 15);

  static const String responseMoving = 'Moving...';
  static const String responseDone = 'DONE';
  static const String responseError = 'ERROR, Try again';

  static const String formatHint = 'servo:angle[,servo:angle…]';
  static const String example = '0:90,1:45';

  /// Encodes [command] into the text expected by the firmware.
  static String encode(RobotCommand command) => switch (command) {
    SetServoAngleCommand(:final servoId, :final angle) => '$servoId:$angle',
    SetServoAnglesCommand(:final angles) =>
      (angles.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key}:${e.value}')
          .join(','),
    RawTextCommand(:final text) => text.trim(),
  };

  /// Mirrors the firmware's `parseCommand()`.
  ///
  /// Returns `null` when the ESP32 would accept [raw], otherwise a short
  /// explanation of why it would answer `ERROR, Try again`.
  static String? validate(String raw) {
    final cmd = raw.trim();
    if (cmd.isEmpty) return 'Empty command';

    final first = cmd.codeUnitAt(0);
    if (first < 32 || first > 126) {
      return 'Must start with a printable character';
    }

    final pairs = cmd.split(',');
    // The firmware stops when the cursor reaches the end of the text, so one
    // trailing comma is harmless ("0:90," is accepted).
    if (pairs.length > 1 && pairs.last.isEmpty) pairs.removeLast();

    for (final rawPair in pairs) {
      final pair = rawPair.trim();
      final colon = pair.indexOf(':');
      if (colon == -1) {
        return pair.isEmpty
            ? 'Empty pair between commas'
            : 'Missing ":" in "$pair"';
      }
      final servoStr = pair.substring(0, colon).trim();
      final angleStr = pair.substring(colon + 1).trim();
      if (servoStr.isEmpty || angleStr.isEmpty) {
        return 'Incomplete pair "$pair"';
      }
      if (!_isDigits(servoStr)) return 'Servo must be a number: "$servoStr"';
      if (!_isDigits(angleStr)) return 'Angle must be a number: "$angleStr"';

      final servo = int.tryParse(servoStr);
      final angle = int.tryParse(angleStr);
      if (servo == null || servo < 0 || servo >= servoCount) {
        return 'Servo must be 0–${servoCount - 1}';
      }
      if (angle == null || angle < minAngle || angle > maxAngle) {
        return 'Angle must be $minAngle–$maxAngle';
      }
    }
    return null;
  }

  /// Classifies one line received from the ESP32 (line endings stripped).
  static DeviceResponse parseResponse(String line) {
    final text = line.trim();
    if (text == responseDone) return DeviceResponse.done;
    if (text.startsWith('Moving')) return DeviceResponse.moving;
    if (text.startsWith('ERROR')) return DeviceResponse.error;
    return DeviceResponse.unknown;
  }

  static bool _isDigits(String s) {
    for (final unit in s.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }
}
