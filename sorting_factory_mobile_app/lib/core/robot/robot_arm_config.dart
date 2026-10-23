import 'servo_config.dart';

/// Hardware description of the robotic arm.
///
/// Edit this list to match the real arm (number of servos, names and
/// mechanical limits). Every control mode reads from here.
abstract final class RobotArmConfig {
  static const List<ServoConfig> servos = [
    ServoConfig(id: 0, name: 'Base'),
    ServoConfig(id: 1, name: 'Shoulder'),
    ServoConfig(id: 2, name: 'Elbow'),
    ServoConfig(id: 3, name: 'Wrist pitch'),
    ServoConfig(id: 4, name: 'Wrist roll'),
    ServoConfig(id: 5, name: 'Gripper'),
  ];
}
