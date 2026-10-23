import 'connection_status.dart';
import 'robot_command.dart';
import 'robot_communication_service.dart';

/// Placeholder used until the communication protocol is specified.
///
/// Every operation intentionally does nothing.
class UnconfiguredCommunicationService extends RobotCommunicationService {
  @override
  ConnectionStatus get status => ConnectionStatus.notConfigured;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(RobotCommand command) async {}
}
