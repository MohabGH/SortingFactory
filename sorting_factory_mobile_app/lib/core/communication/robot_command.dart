import 'package:flutter/foundation.dart';

/// Protocol-agnostic commands the app can send to the microcontroller.
///
/// Features build these objects; the concrete [RobotCommunicationService]
/// is responsible for encoding them into whatever wire format is chosen
/// later. Add new command types as subclasses (e.g. `HomeCommand`,
/// `RunSequenceCommand`). Because the class is `sealed`, `switch`
/// statements over commands will report any unhandled new type.
@immutable
sealed class RobotCommand {
  const RobotCommand();
}

/// Moves a single servo to [angle] degrees.
final class SetServoAngleCommand extends RobotCommand {
  const SetServoAngleCommand({required this.servoId, required this.angle});

  final int servoId;
  final int angle;

  @override
  String toString() => 'SetServoAngleCommand(servo: $servoId, angle: $angle)';
}

/// Moves several servos at once. Keys are servo ids, values are angles.
final class SetServoAnglesCommand extends RobotCommand {
  SetServoAnglesCommand(Map<int, int> angles)
      : angles = Map.unmodifiable(angles);

  final Map<int, int> angles;

  @override
  String toString() => 'SetServoAnglesCommand($angles)';
}
