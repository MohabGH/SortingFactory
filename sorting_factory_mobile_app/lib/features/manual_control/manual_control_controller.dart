import 'package:flutter/widgets.dart';

import '../../core/communication/robot_command.dart';
import '../../core/robot/servo_config.dart';

/// UI-independent logic for the manual control mode: owns the text field
/// controllers, validates input and builds [RobotCommand]s.
class ManualControlController {
  ManualControlController({required List<ServoConfig> servos})
      : servos = List.unmodifiable(servos),
        _fields = {
          for (final servo in servos)
            servo.id: TextEditingController(text: '${servo.initialAngle}'),
        };

  final List<ServoConfig> servos;
  final Map<int, TextEditingController> _fields;

  TextEditingController fieldFor(ServoConfig servo) => _fields[servo.id]!;

  /// Returns an error message, or `null` if [raw] is a valid angle.
  String? validate(ServoConfig servo, String? raw) {
    final value = int.tryParse(raw?.trim() ?? '');
    if (value == null) return 'Required';
    if (!servo.isValidAngle(value)) {
      return '${servo.minAngle}–${servo.maxAngle}°';
    }
    return null;
  }

  /// Builds a command for one servo. Call only after validating its field.
  SetServoAngleCommand commandFor(ServoConfig servo) => SetServoAngleCommand(
        servoId: servo.id,
        angle: _angleOf(servo),
      );

  /// Builds a command for all servos. Call only after validating the form.
  SetServoAnglesCommand commandForAll() => SetServoAnglesCommand({
        for (final servo in servos) servo.id: _angleOf(servo),
      });

  /// Restores every field to its servo's initial angle.
  void resetToInitial() {
    for (final servo in servos) {
      fieldFor(servo).text = '${servo.initialAngle}';
    }
  }

  int _angleOf(ServoConfig servo) => int.parse(fieldFor(servo).text.trim());

  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
  }
}
