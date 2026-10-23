import 'package:flutter/foundation.dart';

/// Static description of one servo of the robotic arm.
@immutable
class ServoConfig {
  const ServoConfig({
    required this.id,
    required this.name,
    this.minAngle = 0,
    this.maxAngle = 180,
    this.initialAngle = 90,
  }) : assert(minAngle <= initialAngle && initialAngle <= maxAngle);

  /// Identifier sent to the microcontroller.
  final int id;
  final String name;
  final int minAngle;
  final int maxAngle;
  final int initialAngle;

  bool isValidAngle(int angle) => angle >= minAngle && angle <= maxAngle;
}
