import 'communication_log.dart';
import 'connection_status.dart';
import 'robot_command.dart';
import 'robot_communication_service.dart';

/// Fallback used when no transport is available (tests, unsupported
/// platforms). Sending always fails with a [CommunicationException].
class UnconfiguredCommunicationService extends RobotCommunicationService {
  @override
  final CommunicationLog log = CommunicationLog();

  @override
  String get transportName => 'None';

  @override
  ConnectionStatus get status => ConnectionStatus.notConfigured;

  @override
  RobotActivity get activity => RobotActivity.offline;

  @override
  ConnectedDeviceInfo? get connectedDevice => null;

  @override
  Future<void> connect() async {
    log.error('No communication transport is configured.');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(RobotCommand command) async {
    const message = 'No communication transport is configured.';
    log.error(message);
    throw const CommunicationException(message);
  }

  @override
  void dispose() {
    log.dispose();
    super.dispose();
  }
}
